# Image PowerShell + PSScriptAnalyzer pour l'analyse statique
# des scripts .ps1 du projet.
#
# Base : image officielle Microsoft PowerShell (Ubuntu LTS).
# Ajout : module PSScriptAnalyzer installé depuis la PSGallery.

FROM mcr.microsoft.com/powershell:latest

# Installation de PSScriptAnalyzer (linter PowerShell officiel).
# Version pinnée : 1.22.0 est compatible PowerShell Core 7.4.x.
# Les versions >= 1.23 exigent 7.4.6+ (au-delà de l'image mcr:latest actuelle).
RUN pwsh -NoProfile -Command "Set-PSRepository -Name PSGallery -InstallationPolicy Trusted; Install-Module -Name PSScriptAnalyzer -RequiredVersion 1.22.0 -Force -Scope AllUsers"

# Installation de Pester (framework de test PowerShell) pour les tests unitaires.
# Version pinnée : 5.5.0 est compatible PowerShell Core 7.4.x.
RUN pwsh -NoProfile -Command "Install-Module -Name Pester -RequiredVersion 5.5.0 -Force -SkipPublisherCheck -Scope AllUsers"

# Vérification
RUN pwsh -NoProfile -Command "Import-Module PSScriptAnalyzer; Import-Module Pester; Get-Module PSScriptAnalyzer, Pester | Select-Object Name, Version"

WORKDIR /repo

# Point d'entrée neutre : on lance des commandes ad hoc via docker compose run
ENTRYPOINT ["pwsh", "-NoProfile"]
CMD ["-Command", "Write-Host 'Image PowerShell + PSScriptAnalyzer prête. Utilisez tests/run-tests.sh.'"]
