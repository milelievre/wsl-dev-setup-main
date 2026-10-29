# tests/

Tests statiques du projet, exécutés dans des conteneurs Docker isolés (voir `images/`).

## Prérequis

- Docker Engine avec le plugin Compose v2 (`docker compose ...`).
- Aucune installation locale de PowerShell : tout tourne dans l'image `images/powershell/`.

## Lancer tous les tests

Depuis la racine du repo :

```bash
./tests/run-tests.sh
```

Le script :

1. Build (ou réutilise le cache) l'image `wsl-dev-setup/powershell`.
2. Découvre tous les fichiers `*.ps1` du repo (hors `.git/`, `.kilo/`, `node_modules/`).
3. Exécute trois passes :
   - **Analyse syntaxique** via `[System.Management.Automation.Language.Parser]::ParseFile` (détecte les erreurs de parsing).
   - **Bonnes pratiques** via `Invoke-ScriptAnalyzer` de PSScriptAnalyzer, configuré par `tests/PSScriptAnalyzerSettings.psd1` (exclusions justifiées, ex. `PSAvoidUsingWriteHost` pour un script CLI interactif).
   - **Tests unitaires Pester** sur tous les fichiers `tests/*.Tests.ps1` (mocks des dépendances Windows pour valider la logique côté Linux).

## Politique de sortie

| Sévérité PSScriptAnalyzer | Comportement                        |
|---------------------------|-------------------------------------|
| `Error`                   | Bloquant : exit code 1              |
| `Warning`                 | Bloquant : exit code 1              |
| `Information`             | Affiché mais **non bloquant**       |

Toute erreur de parsing est également bloquante. Tout test Pester en échec (`FailedCount > 0`) est également bloquant.

## Sortie type

```
==> Build de l'image PowerShell...
==> Fichiers analysés (2) :
    - install.ps1
    - scripts/windows/setup-dev.ps1
==> Analyse dans le conteneur...

========================================
 1) Analyse syntaxique (Parser)
========================================
[OK]   install.ps1 (312 tokens)
[OK]   scripts/windows/setup-dev.ps1 (58 tokens)

========================================
 2) Bonnes pratiques (PSScriptAnalyzer)
========================================
[OK]   install.ps1
[OK]   scripts/windows/setup-dev.ps1

========================================
 Recapitulatif
========================================
  Erreurs de parsing        : 0
  PSScriptAnalyzer Error    : 0
  PSScriptAnalyzer Warning  : 0
  PSScriptAnalyzer Info     : 0 (non bloquant)

SUCCES : tous les scripts passent l analyse.
```

## Ajouter un test

Pour un nouveau linter ou une autre couche d'analyse :

1. Ajouter l'outil dans une image (soit `images/powershell/Dockerfile`, soit une nouvelle image dans `images/`).
2. Ajouter le service dans `images/docker-compose.yml` si c'est une nouvelle image.
3. Étendre `tests/run-tests.sh` avec un nouveau bloc.

## Limites connues

- Pas de tests **runtime** : impossible d'exécuter `wsl --install` ou `winget` depuis un conteneur Linux. La validation end-to-end reste manuelle sur poste Windows (checklist dans le plan `.kilo/plans/1790020793229-distro-selection-plan.md`).
- Pas encore de tests pour `scripts/linux/bootstrap.sh` (shellcheck à ajouter dans une future image).
