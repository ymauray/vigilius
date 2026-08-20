<#
.SYNOPSIS
    Vérifie les pull requests ouvertes sur tous les dépôts GitHub dont l'utilisateur est propriétaire,
    ainsi que sur les dépôts d'une liste d'organisations données.

.DESCRIPTION
    Utilise le CLI `gh` pour lister les dépôts appartenant à l'utilisateur authentifié et aux
    organisations listées dans $OrgsToCheck, puis interroge chaque dépôt pour récupérer ses
    pull requests ouvertes.

.PARAMETER IncludeForks
    Inclut également les dépôts qui sont des forks (exclus par défaut).

.PARAMETER Owner
    Nom du propriétaire (utilisateur ou organisation) à interroger, au lieu de la liste par défaut.

.PARAMETER MergeDependabot
    Tente de merger automatiquement les pull requests ouvertes créées par Dependabot, sans demander confirmation.

.EXAMPLE
    ./Check-OpenPullRequests.ps1

.EXAMPLE
    ./Check-OpenPullRequests.ps1 -Owner "mon-organisation" -IncludeForks

.EXAMPLE
    ./Check-OpenPullRequests.ps1 -MergeDependabot
#>

[CmdletBinding()]
param(
    [switch]$IncludeForks,
    [string]$Owner,
    [switch]$MergeDependabot
)

# Organisations à vérifier en plus des dépôts personnels (pas toujours créées par moi, mais j'y suis admin)
$OrgsToCheck = @(
    'my-nanuq',
    'frenchguych',
    'euterpiaradio',
    'picaster',
    'tetrixel',
    'sandrinekohler',
    'amaurybennett'
)

$ErrorActionPreference = 'Stop'
$DependabotAuthors = @(
    'dependabot',
    'dependabot[bot]',
    'app/dependabot'
)

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

foreach ($repo in $repos) {
    $repoName = $repo.nameWithOwner
    Write-Host "Vérification de $repoName..." -ForegroundColor DarkGray

    try {
        $prJson = gh pr list --repo $repoName --state open --json number,title,author,createdAt --limit 100
        $prs = $prJson | ConvertFrom-Json
    }
    catch {
        Write-Warning "Impossible de récupérer les PR pour $repoName : $_"
        continue
    }

    foreach ($pr in $prs) {
        $results += [PSCustomObject]@{
            Repo      = $repoName
            Number    = $pr.number
            Title     = $pr.title
            Author    = $pr.author.login
            CreatedAt = $pr.createdAt
        }
    }
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

$mergeResults = @()

foreach ($repository in ($dependabotPullRequests | Group-Object Repo | Sort-Object Name)) {
    foreach ($pullRequest in ($repository.Group | Sort-Object CreatedAt)) {
        Write-Host "Tentative de fusion de $($pullRequest.Repo)#$($pullRequest.Number)..." -ForegroundColor DarkGray
        $mergeOutput = (& gh pr merge $pullRequest.Number --repo $pullRequest.Repo --merge 2>&1 | Out-String).Trim()

        if ($LASTEXITCODE -eq 0) {
            Write-Host "Fusionnée : $($pullRequest.Repo)#$($pullRequest.Number)" -ForegroundColor Green
            $mergeResults += [PSCustomObject]@{
                Repo = $pullRequest.Repo
                Number = $pullRequest.Number
                Status = 'Fusionnée'
                Details = ''
            }
            continue
        }

        Write-Warning "Impossible de merger $($pullRequest.Repo)#$($pullRequest.Number) : $mergeOutput"
        $mergeResults += [PSCustomObject]@{
            Repo = $pullRequest.Repo
            Number = $pullRequest.Number
            Status = 'Échec'
            Details = $mergeOutput
        }
    }
}

Write-Host "`nBilan des fusions Dependabot :" -ForegroundColor Cyan
$mergeResults | Format-Table Repo, Number, Status, Details -AutoSize
