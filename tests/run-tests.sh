#!/usr/bin/env bash
# ============================================================================
# Analyse statique des scripts PowerShell du projet.
#
# Étapes :
#   1. Build (idempotent) de l'image PowerShell + PSScriptAnalyzer.
#   2. Analyse syntaxique via [System.Management.Automation.Language.Parser].
#   3. Analyse bonnes pratiques via Invoke-ScriptAnalyzer.
#
# Politique d'échec : toute Error ou Warning fait sortir avec code != 0.
#                     Les Information sont affichés mais n'échouent pas.
#
# Usage :
#   ./tests/run-tests.sh
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
COMPOSE_FILE="$REPO_ROOT/images/docker-compose.yml"

# Codes couleurs terminal
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m'

log()  { printf "${CYAN}==>${NC} %s\n" "$*"; }
ok()   { printf "${GREEN}[OK]${NC} %s\n" "$*"; }
warn() { printf "${YELLOW}[WARN]${NC} %s\n" "$*"; }
err()  { printf "${RED}[ERR]${NC} %s\n" "$*" >&2; }

# ----------------------------------------------------------------------------
# 1. Build de l'image (rapide si déjà construite grâce au cache Docker)
# ----------------------------------------------------------------------------
log "Build de l'image PowerShell (cache Docker si déjà présente)..."
docker compose -f "$COMPOSE_FILE" build powershell >/dev/null

# ----------------------------------------------------------------------------
# 2. Détection des fichiers .ps1 (relatifs au repo, hors répertoires ignorés)
# ----------------------------------------------------------------------------
mapfile -t PS_FILES < <(
    find "$REPO_ROOT" -type f -name "*.ps1" \
        -not -path "*/.git/*" \
        -not -path "*/.kilo/*" \
        -not -path "*/node_modules/*" \
        -printf "%P\n" | sort
)

if [[ ${#PS_FILES[@]} -eq 0 ]]; then
    warn "Aucun fichier .ps1 trouvé dans le repo."
    exit 0
fi

log "Fichiers analysés (${#PS_FILES[@]}) :"
printf '    - %s\n' "${PS_FILES[@]}"

# ----------------------------------------------------------------------------
# 3. Lancement combiné parse + PSScriptAnalyzer dans le conteneur
# ----------------------------------------------------------------------------
# On construit une liste PowerShell des fichiers à passer au script inline.
PS_FILES_JOINED=$(printf "'%s'," "${PS_FILES[@]}")
PS_FILES_JOINED="${PS_FILES_JOINED%,}"

log "Analyse dans le conteneur..."

# Le heredoc contient uniquement du PowerShell : pas d'expansion bash à part
# la substitution de $PS_FILES_JOINED faite ci-dessus.
PS_SCRIPT=$(cat <<PWSH
\$ErrorActionPreference = 'Stop'
\$files = @($PS_FILES_JOINED)

\$parseErrors = 0
\$analyzerErrors = 0
\$analyzerWarnings = 0
\$analyzerInfos = 0
\$pesterFailed = 0
\$pesterPassed = 0
\$pesterSkipped = 0

Write-Host ''
Write-Host '========================================' -ForegroundColor Cyan
Write-Host ' 1) Analyse syntaxique (Parser)' -ForegroundColor Cyan
Write-Host '========================================' -ForegroundColor Cyan

foreach (\$f in \$files) {
    \$tokens = \$null
    \$errors = \$null
    [System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path \$f), [ref]\$tokens, [ref]\$errors) | Out-Null
    if (\$errors -and \$errors.Count -gt 0) {
        Write-Host ("[FAIL] {0}" -f \$f) -ForegroundColor Red
        foreach (\$e in \$errors) {
            Write-Host ("       L{0}:C{1} {2}" -f \$e.Extent.StartLineNumber, \$e.Extent.StartColumnNumber, \$e.Message) -ForegroundColor Red
            \$parseErrors++
        }
    } else {
        Write-Host ("[OK]   {0} ({1} tokens)" -f \$f, \$tokens.Count) -ForegroundColor Green
    }
}

Write-Host ''
Write-Host '========================================' -ForegroundColor Cyan
Write-Host ' 2) Bonnes pratiques (PSScriptAnalyzer)' -ForegroundColor Cyan
Write-Host '========================================' -ForegroundColor Cyan

Import-Module PSScriptAnalyzer

\$settingsPath = Join-Path (Get-Location) 'tests/PSScriptAnalyzerSettings.psd1'
\$hasSettings = Test-Path \$settingsPath
if (\$hasSettings) {
    Write-Host ("Using settings: {0}" -f \$settingsPath) -ForegroundColor Gray
}

foreach (\$f in \$files) {
    if (\$hasSettings) {
        \$results = Invoke-ScriptAnalyzer -Path \$f -Settings \$settingsPath
    } else {
        \$results = Invoke-ScriptAnalyzer -Path \$f -Severity Error,Warning,Information
    }
    if (\$null -eq \$results -or \$results.Count -eq 0) {
        Write-Host ("[OK]   {0}" -f \$f) -ForegroundColor Green
        continue
    }
    Write-Host ("[HITS] {0} ({1} entrees)" -f \$f, \$results.Count) -ForegroundColor Yellow
    foreach (\$r in \$results) {
        \$color = switch (\$r.Severity) {
            'Error'       { 'Red' }
            'Warning'     { 'Yellow' }
            'Information' { 'Gray' }
            default       { 'White' }
        }
        Write-Host ("       [{0}] L{1} {2} : {3}" -f \$r.Severity, \$r.Line, \$r.RuleName, \$r.Message) -ForegroundColor \$color
        switch (\$r.Severity) {
            'Error'       { \$analyzerErrors++ }
            'Warning'     { \$analyzerWarnings++ }
            'Information' { \$analyzerInfos++ }
        }
    }
}

Write-Host ''
Write-Host '========================================' -ForegroundColor Cyan
Write-Host ' 3) Tests unitaires (Pester)' -ForegroundColor Cyan
Write-Host '========================================' -ForegroundColor Cyan

Import-Module Pester
\$pesterTestsPath = Join-Path (Get-Location) 'tests'
if (Test-Path \$pesterTestsPath) {
    \$pesterConfig = New-PesterConfiguration
    \$pesterConfig.Run.Path = \$pesterTestsPath
    \$pesterConfig.Run.PassThru = \$true
    \$pesterConfig.Output.Verbosity = 'Detailed'
    \$pesterResult = Invoke-Pester -Configuration \$pesterConfig
    \$pesterFailed = \$pesterResult.FailedCount
    \$pesterPassed = \$pesterResult.PassedCount
    \$pesterSkipped = \$pesterResult.SkippedCount
} else {
    Write-Host 'Aucun repertoire tests/ trouve, passe Pester ignoree.' -ForegroundColor Gray
}

Write-Host ''
Write-Host '========================================' -ForegroundColor Cyan
Write-Host ' Recapitulatif' -ForegroundColor Cyan
Write-Host '========================================' -ForegroundColor Cyan
Write-Host ("  Erreurs de parsing        : {0}" -f \$parseErrors)
Write-Host ("  PSScriptAnalyzer Error    : {0}" -f \$analyzerErrors)
Write-Host ("  PSScriptAnalyzer Warning  : {0}" -f \$analyzerWarnings)
Write-Host ("  PSScriptAnalyzer Info     : {0} (non bloquant)" -f \$analyzerInfos)
Write-Host ("  Pester tests passed       : {0}" -f \$pesterPassed)
Write-Host ("  Pester tests failed       : {0}" -f \$pesterFailed)
Write-Host ("  Pester tests skipped      : {0} (non bloquant)" -f \$pesterSkipped)

\$blocking = \$parseErrors + \$analyzerErrors + \$analyzerWarnings + \$pesterFailed
if (\$blocking -gt 0) {
    Write-Host ''
    Write-Host ("ECHEC : {0} probleme(s) bloquant(s)" -f \$blocking) -ForegroundColor Red
    exit 1
}
Write-Host ''
Write-Host 'SUCCES : tous les scripts passent l analyse.' -ForegroundColor Green
exit 0
PWSH
)

# Exécution : on passe le script inline via -Command.
# Le service powershell monte déjà le repo en /repo (working_dir).
if docker compose -f "$COMPOSE_FILE" run --rm --no-TTY powershell -Command "$PS_SCRIPT"; then
    ok "Analyse terminée sans problème bloquant."
    exit 0
else
    err "Analyse échouée (voir sortie ci-dessus)."
    exit 1
fi
