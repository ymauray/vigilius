# Vigilius

`Check-OpenPullRequests.ps1` recense les pull requests ouvertes des dépôts personnels GitHub de l'utilisateur authentifié ainsi que de plusieurs organisations configurées.

## Configuration

Copiez le modèle de configuration, puis remplacez les organisations d'exemple par celles à vérifier :

```powershell
Copy-Item config.psd1.sample config.psd1
```

Le fichier `config.psd1` n'est pas suivi par Git. Il contient la clé `Organizations`, une liste de noms d'organisations GitHub :

```powershell
@{
  Organizations = @(
    'mon-organisation'
  )
}
```

## Prérequis

- PowerShell
- [GitHub CLI](https://cli.github.com/) installé et authentifié :

  ```powershell
  gh auth login
  ```

## Utilisation

Analyser les dépôts personnels et les organisations configurées :

```powershell
.\Check-OpenPullRequests.ps1
```

Analyser les dépôts d'un propriétaire précis :

```powershell
.\Check-OpenPullRequests.ps1 -Owner mon-organisation
```

Inclure les forks :

```powershell
.\Check-OpenPullRequests.ps1 -IncludeForks
```

Afficher l'aide complète :

```powershell
.\Check-OpenPullRequests.ps1 -Help
```

## Cache

Les résultats sont conservés pendant 30 minutes par dépôt afin de limiter les appels à GitHub. Le cache contient l'horodatage de vérification et les pull requests ouvertes.

- Windows : `%LOCALAPPDATA%\Vigilius\open-pull-requests.json`
- autres plateformes : `~/.cache/vigilius/open-pull-requests.json`

Forcer une interrogation GitHub sans supprimer le cache :

```powershell
.\Check-OpenPullRequests.ps1 -IgnoreCache
```

Supprimer le cache avant l'analyse :

```powershell
.\Check-OpenPullRequests.ps1 -ClearCache
```

## Pull requests Dependabot

Après l'analyse, le script propose de fusionner les pull requests ouvertes créées par Dependabot. Les PR sont traitées dépôt par dépôt, dans l'ordre de leur ouverture.

Chaque fusion utilise la méthode autorisée par le dépôt, par ordre de préférence : squash, merge standard, rebase. Les protections de branche, les vérifications, les approbations et les conflits ne sont pas contournés ; les échecs sont signalés dans le bilan final pour traitement manuel. Les PR dont des vérifications (CI) sont encore en cours sont ignorées et signalées comme telles dans le bilan, sans tentative de fusion ni invalidation du cache. Toute tentative de fusion, réussie ou non, invalide le cache du dépôt concerné.

Pour ne pas demander confirmation :

```powershell
.\Check-OpenPullRequests.ps1 -MergeDependabot
```
