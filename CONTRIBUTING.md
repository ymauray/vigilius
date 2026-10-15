# Contribuer à Vigilius

Merci de vous intéresser à Vigilius ! C'est un petit projet personnel, mais les contributions externes sont bienvenues.

## Avant de commencer

Pour une nouvelle fonctionnalité ou un changement important, ouvrez d'abord une [issue](https://github.com/ymauray/vigilius/issues/new/choose) ou une [discussion](https://github.com/ymauray/vigilius/discussions) pour en parler avec le mainteneur.

## Environnement de développement

Il faut PowerShell 7 (`pwsh`) et le [CLI GitHub](https://cli.github.com/) authentifié (`gh auth login`). Le script est un fichier unique, `Check-OpenPullRequests.ps1`, et il n'y a pas de suite de tests : la CI vérifie la syntaxe et lance PSScriptAnalyzer. Pour reproduire ces contrôles en local :

```powershell
Install-Module PSScriptAnalyzer -Scope CurrentUser
Invoke-ScriptAnalyzer -Path .\Check-OpenPullRequests.ps1 -Severity Error
```

Vérifiez aussi le comportement à la main sur vos propres dépôts (`.\Check-OpenPullRequests.ps1 -IgnoreCache`).

## Proposer une modification

1. Forkez le dépôt et créez une branche dédiée depuis `main` (ex. `fix/...`, `feat/...`).
2. Faites des commits atomiques, avec des messages clairs (convention `type(portée): résumé`).
3. Vérifiez que l'analyse PSScriptAnalyzer ne remonte aucune erreur, et mettez le `README.md` à jour si une option ou un comportement change.
4. Ouvrez une pull request vers `main` en remplissant le modèle fourni. Les PR sont mergées en squash.

## Style

Le fichier `.editorconfig` à la racine fait foi. Messages, aide et documentation sont en français.
