# AGENTS.md

Instructions pour les assistants IA travaillant sur ce dépôt.

## Le projet

Vigilius est un script PowerShell, `Check-OpenPullRequests.ps1`, qui recense les pull requests ouvertes des dépôts GitHub personnels de l'utilisateur authentifié et de plusieurs organisations, puis propose de fusionner celles de Dependabot. Il s'appuie sur le CLI `gh`.

## Structure

```
Check-OpenPullRequests.ps1   le script (fichier unique)
config.psd1.sample           modèle de configuration (clé Organizations) ; config.psd1 est local et ignoré par Git
.github/workflows/           ci.yml (syntaxe + PSScriptAnalyzer) et release.yml (publication sur tag vX.Y.Z)
```

## Commandes

```powershell
.\Check-OpenPullRequests.ps1 -Help          # aide du script
.\Check-OpenPullRequests.ps1 -IgnoreCache   # exécution sans le cache
Invoke-ScriptAnalyzer -Path .\Check-OpenPullRequests.ps1 -Severity Error
```

Il n'y a pas de tests automatisés : la CI vérifie la syntaxe et PSScriptAnalyzer (erreurs seulement).

## Comportements à préserver

- Cache de 30 minutes par dépôt (`%LOCALAPPDATA%\Vigilius\open-pull-requests.json`, ou `~/.cache/vigilius/` ailleurs) ; toute tentative de fusion invalide le cache du dépôt concerné.
- La méthode de fusion suit les réglages du dépôt : squash, puis merge, puis rebase. Les protections de branche ne sont jamais contournées.
- Une PR dont la CI est en cours est ignorée, sans tentative de fusion.
- Ne jamais committer `config.psd1`.

## Style

`.editorconfig` fait foi. Messages, aide et documentation sont en français. Commits au format `type(portée): résumé`, PR mergées en squash. Garder le `README.md` à jour quand une option ou un comportement change.
