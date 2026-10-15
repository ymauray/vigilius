<#
.SYNOPSIS
    Vérifie les pull requests ouvertes sur tous les dépôts GitHub dont l'utilisateur est propriétaire,
    ainsi que sur les dépôts d'une liste d'organisations données.

.DESCRIPTION
    Utilise le CLI `gh` pour lister les dépôts appartenant à l'utilisateur authentifié et aux
    organisations listées dans config.psd1, puis interroge chaque dépôt pour récupérer ses
    pull requests ouvertes. Les résultats sont mis en cache pendant 30 minutes par dépôt.

.PARAMETER IncludeForks
    Inclut également les dépôts qui sont des forks (exclus par défaut).

.PARAMETER Owner
    Nom du propriétaire (utilisateur ou organisation) à interroger, au lieu de la liste par défaut.

.PARAMETER MergeDependabot
    Tente de merger automatiquement les pull requests ouvertes créées par Dependabot, sans demander confirmation.

.PARAMETER ClearCache
    Supprime le cache local avant de lancer l'analyse.

.PARAMETER IgnoreCache
    Ignore le cache local pendant l'analyse sans le supprimer.

.PARAMETER Help
    Affiche l'aide et les options disponibles.

.EXAMPLE
    ./Check-OpenPullRequests.ps1

.EXAMPLE
    ./Check-OpenPullRequests.ps1 -Owner "mon-organisation" -IncludeForks

.EXAMPLE
    ./Check-OpenPullRequests.ps1 -MergeDependabot

.EXAMPLE
    ./Check-OpenPullRequests.ps1 -IgnoreCache
#>

[CmdletBinding()]
param(
    [switch]$IncludeForks,
    [string]$Owner,
    [switch]$MergeDependabot,
    [switch]$ClearCache,
    [switch]$IgnoreCache,
    [switch]$Help
)

if ($Help) {
    Get-Help $PSCommandPath -Detailed
    exit 0
}

$ErrorActionPreference = 'Stop'
$DependabotAuthors = @(
    'dependabot',
    'dependabot[bot]',
    'app/dependabot'
)
$CacheDuration = [TimeSpan]::FromMinutes(30)
$configFile = Join-Path $PSScriptRoot 'config.psd1'

if (-not (Test-Path $configFile)) {
    Write-Error "Le fichier de configuration '$configFile' est introuvable. Copiez config.psd1.sample vers config.psd1 et adaptez la liste des organisations."
    exit 1
}

try {
    $config = Import-PowerShellDataFile -Path $configFile
    $OrgsToCheck = @($config.Organizations)
}
catch {
    Write-Error "Impossible de charger le fichier de configuration '$configFile' : $_"
    exit 1
}

if ($env:LOCALAPPDATA) {
    $cacheDirectory = Join-Path $env:LOCALAPPDATA 'Vigilius'
}
else {
    $cacheDirectory = Join-Path (Join-Path $HOME '.cache') 'vigilius'
}

$cacheFile = Join-Path $cacheDirectory 'open-pull-requests.json'

if ($ClearCache -and (Test-Path $cacheFile)) {
    Remove-Item -Path $cacheFile
    Write-Host "Cache local supprimé." -ForegroundColor Yellow
}

function Get-PullRequestCache {
    if (-not (Test-Path $cacheFile)) {
        return @{}
    }

    try {
        $cacheContent = Get-Content -Raw $cacheFile
        if ([string]::IsNullOrWhiteSpace($cacheContent)) {
            return @{}
        }

        $cachedRepositories = $cacheContent | ConvertFrom-Json
        $cache = @{}
        foreach ($property in $cachedRepositories.PSObject.Properties) {
            $cache[$property.Name] = $property.Value
        }

        return $cache
    }
    catch {
        Write-Warning "Le cache '$cacheFile' est illisible et sera remplacé : $_"
        return @{}
    }
}

function Save-PullRequestCache([hashtable]$Cache) {
    if (-not (Test-Path $cacheDirectory)) {
        New-Item -ItemType Directory -Path $cacheDirectory | Out-Null
    }

    $Cache | ConvertTo-Json -Depth 5 | Set-Content -Path $cacheFile -Encoding utf8
}

function Test-CacheEntryIsValid($CacheEntry) {
    try {
        $checkedAt = [DateTimeOffset]$CacheEntry.CheckedAt
        return (([DateTimeOffset]::UtcNow - $checkedAt) -lt $CacheDuration)
    }
    catch {
        return $false
    }
}

# Vérifie que gh est installé et authentifié
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    Write-Error "Le CLI 'gh' est introuvable. Installez-le depuis https://cli.github.com/ puis exécutez 'gh auth login'."
    exit 1
}

try {
    gh auth status *> $null
}
catch {
    Write-Error "Vous n'êtes pas authentifié avec 'gh'. Exécutez 'gh auth login' avant de relancer ce script."
    exit 1
}

if ($Owner) {
    $owners = @($Owner)
}
else {
    $currentUser = gh api user --jq '.login'
    $owners = @($currentUser) + $OrgsToCheck
}

Write-Host "Récupération des dépôts pour : $($owners -join ', ')..." -ForegroundColor Cyan

# Liste tous les dépôts de chaque propriétaire (dépôts propres, pas ceux où on est simple collaborateur)
$repos = @()
foreach ($ownerName in $owners) {
    $repoJson = gh repo list $ownerName --limit 1000 --json nameWithOwner,isFork,isArchived
    $repos += $repoJson | ConvertFrom-Json
}

if (-not $IncludeForks) {
    $repos = $repos | Where-Object { -not $_.isFork }
}

$repos = $repos | Where-Object { -not $_.isArchived }

if (-not $repos -or $repos.Count -eq 0) {
    Write-Host "Aucun dépôt trouvé pour : $($owners -join ', ')." -ForegroundColor Yellow
    exit 0
}

Write-Host "Analyse de $($repos.Count) dépôt(s)...`n" -ForegroundColor Cyan

$results = @()
$cache = Get-PullRequestCache

foreach ($repo in $repos) {
    $repoName = $repo.nameWithOwner
    $pullRequests = @()

    if (-not $IgnoreCache -and $cache.ContainsKey($repoName) -and (Test-CacheEntryIsValid $cache[$repoName])) {
        Write-Host "Utilisation du cache pour $repoName..." -ForegroundColor DarkGray
        $pullRequests = @($cache[$repoName].PullRequests)
    }
    else {
        Write-Host "Vérification de $repoName..." -ForegroundColor DarkGray

        try {
            $prJson = gh pr list --repo $repoName --state open --json number,title,author,createdAt --limit 100
            $prs = $prJson | ConvertFrom-Json
        }
        catch {
            Write-Warning "Impossible de récupérer les PR pour $repoName : $_"
            continue
        }

        $pullRequests = @($prs | ForEach-Object {
            [PSCustomObject]@{
                Repo = $repoName
                Number = $_.number
                Title = $_.title
                Author = $_.author.login
                CreatedAt = $_.createdAt
            }
        })

        $cache[$repoName] = [PSCustomObject]@{
            CheckedAt = [DateTimeOffset]::UtcNow.ToString('O')
            PullRequests = $pullRequests
        }
        Save-PullRequestCache $cache
    }

    $results += $pullRequests
}

Write-Host ""

if ($results.Count -eq 0) {
    Write-Host "Aucune pull request ouverte trouvée sur l'ensemble des dépôts." -ForegroundColor Green
}
else {
    Write-Host "$($results.Count) pull request(s) ouverte(s) trouvée(s) :`n" -ForegroundColor Green
    $results | Sort-Object Repo, Number | Format-Table Repo, Number, Title, Author, CreatedAt -AutoSize
}

$dependabotPullRequests = @($results | Where-Object { $_.Author -in $DependabotAuthors })

if ($dependabotPullRequests.Count -eq 0) {
    Write-Host "Aucune pull request Dependabot ouverte trouvée." -ForegroundColor Yellow
    exit 0
}

if (-not $MergeDependabot) {
    $answer = Read-Host "`nTenter de merger automatiquement les $($dependabotPullRequests.Count) pull request(s) Dependabot ? (o/N)"
    if ($answer.Trim().ToLowerInvariant() -notin @('o', 'oui')) {
        Write-Host "Aucune pull request Dependabot n'a été mergée." -ForegroundColor Yellow
        exit 0
    }
}

function Get-MergeMethod {
    param([Parameter(Mandatory)][string]$Repo)

    # Squash en priorité, puis merge standard, puis rebase, selon ce que le dépôt autorise.
    $json = & gh repo view $Repo --json squashMergeAllowed,mergeCommitAllowed,rebaseMergeAllowed 2>$null | Out-String
    if ($LASTEXITCODE -eq 0 -and $json.Trim()) {
        $settings = $json | ConvertFrom-Json
        if ($settings.squashMergeAllowed) { return '--squash' }
        if ($settings.mergeCommitAllowed) { return '--merge' }
        if ($settings.rebaseMergeAllowed) { return '--rebase' }
    }

    return '--merge'
}

function Test-ChecksRunning {
    param(
        [Parameter(Mandatory)][string]$Repo,
        [Parameter(Mandatory)][int]$Number
    )

    $json = & gh pr view $Number --repo $Repo --json statusCheckRollup 2>$null | Out-String
    if ($LASTEXITCODE -ne 0 -or -not $json.Trim()) { return $false }

    $checks = @(($json | ConvertFrom-Json).statusCheckRollup)
    foreach ($check in $checks) {
        # CheckRun : status != COMPLETED ; StatusContext : state PENDING/EXPECTED
        if ($check.status -and $check.status -ne 'COMPLETED') { return $true }
        if ($check.state -in @('PENDING', 'EXPECTED')) { return $true }
    }

    return $false
}

$mergeResults = @()

foreach ($repository in ($dependabotPullRequests | Group-Object Repo | Sort-Object Name)) {
    $mergeMethod = Get-MergeMethod -Repo $repository.Name

    foreach ($pullRequest in ($repository.Group | Sort-Object CreatedAt)) {
        if (Test-ChecksRunning -Repo $pullRequest.Repo -Number $pullRequest.Number) {
            Write-Host "Ignorée (CI en cours) : $($pullRequest.Repo)#$($pullRequest.Number)" -ForegroundColor Yellow
            $mergeResults += [PSCustomObject]@{
                Repo = $pullRequest.Repo
                Number = $pullRequest.Number
                Status = 'Ignorée'
                Details = 'CI en cours'
            }
            continue
        }

        Write-Host "Tentative de fusion de $($pullRequest.Repo)#$($pullRequest.Number)..." -ForegroundColor DarkGray
        $mergeOutput = (& gh pr merge $pullRequest.Number --repo $pullRequest.Repo $mergeMethod 2>&1 | Out-String).Trim()

        if ($LASTEXITCODE -eq 0) {
            Write-Host "Fusionnée : $($pullRequest.Repo)#$($pullRequest.Number)" -ForegroundColor Green
            $mergeResults += [PSCustomObject]@{
                Repo = $pullRequest.Repo
                Number = $pullRequest.Number
                Status = 'Fusionnée'
                Details = ''
            }
        }
        else {
            Write-Warning "Impossible de merger $($pullRequest.Repo)#$($pullRequest.Number) : $mergeOutput"
            $mergeResults += [PSCustomObject]@{
                Repo = $pullRequest.Repo
                Number = $pullRequest.Number
                Status = 'Échec'
                Details = $mergeOutput
            }
        }

        $null = $cache.Remove($pullRequest.Repo)
        Save-PullRequestCache $cache
    }
}

Write-Host "`nBilan des fusions Dependabot :" -ForegroundColor Cyan
$mergeResults | Format-Table Repo, Number, Status, Details -AutoSize
