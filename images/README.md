# images/

Images Docker utilitaires du projet, orchestrées via un Compose central. Toutes les dépendances lourdes (PowerShell, linters, etc.) sont isolées dans des conteneurs pour ne rien polluer sur l'hôte WSL.

## Contenu

| Service       | Base                                    | Ajouts             | Usage principal                              |
|---------------|-----------------------------------------|--------------------|----------------------------------------------|
| `powershell`  | `mcr.microsoft.com/powershell:latest`   | PSScriptAnalyzer   | Analyse statique des scripts `.ps1`          |

## Build

Depuis la racine du repo :

```bash
docker compose -f images/docker-compose.yml build
```

Le build est incrémental grâce au cache Docker. Un `--no-cache` est possible pour forcer une reconstruction complète.

## Utilisation directe

```bash
# Ouvrir un pwsh interactif dans le repo monté en lecture seule
docker compose -f images/docker-compose.yml run --rm powershell

# Exécuter une commande ponctuelle
docker compose -f images/docker-compose.yml run --rm powershell -Command 'Get-Module -ListAvailable PSScriptAnalyzer'
```

## Utilisation via tests/

La plupart du temps, on passe par le script `tests/run-tests.sh` qui encapsule le build + les commandes d'analyse. Voir `tests/README.md`.

## Ajouter une image

1. Créer `images/<nom>/Dockerfile`.
2. Ajouter un service dans `images/docker-compose.yml`.
3. Documenter dans le tableau ci-dessus.
4. Si utilisée pour les tests : brancher dans `tests/run-tests.sh`.
