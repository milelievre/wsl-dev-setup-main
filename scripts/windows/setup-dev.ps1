param(
    [Parameter(Mandatory = $true)]
    [string]$DistroName,

    [string]$InstanceName = $DistroName
)

# 1. Activation et installation de WSL (Ubuntu par défaut)
if ($InstanceName -eq $DistroName) {
    wsl --install -d $DistroName --no-launch
} else {
    wsl --install -d $DistroName --name $InstanceName --no-launch
}

# 2. Installation de VS Code
winget install -e --id Microsoft.VisualStudioCode --accept-package-agreements --accept-source-agreements

# 3. Rafraîchissement de l'environnement pour la commande code
$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")

# 4. Extensions hôte indispensables
code --install-extension ms-vscode-remote.remote-wsl --force
code --install-extension ms-vscode-remote.remote-containers --force

Write-Host "Socle Windows prêt. Redémarre si WSL vient d'être activé pour la première fois." -ForegroundColor Green
