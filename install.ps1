# ============================================================================
# install.ps1 - Point d'entree public consomme via `irm | iex`.
#
# Tout le code est encapsule dans la fonction Invoke-WslDevSetup pour trois
# raisons imposees par le canal `irm | iex` :
#
#   1. `exit N` execute au top-level d'un script consomme via `iex` ferme la
#      console PowerShell entiere (car iex n'introduit pas de scope script).
#      `return` dans une fonction sort uniquement de la fonction, la console
#      reste ouverte pour lire les messages.
#
#   2. Sans encapsulation, une exception attrapee par try/catch au top-level
#      ne peut pas stopper les commandes suivantes dans iex sans provoquer
#      soit une stack trace laide (throw) soit la fermeture de la console
#      (exit). La fonction wrapper donne un scope propre a stopper via return.
#
#   3. Les variables definies dans la fonction ne polluent pas la session
#      utilisateur apres l'execution.
#
# Ce pattern est utilise par tous les installeurs Windows publics du meme
# type : chocolatey, oh-my-posh, starship, uv, rustup-init.ps1, etc.
#
# Contraintes de format (verifiees par tests/install.Tests.ps1) :
#   - Pas de BOM UTF-8 (sinon iex plante sur la premiere commande).
#   - ASCII pur (sinon PS 5.1 lit le fichier en Windows-1252 sans BOM et
#     produit du mojibake).
# ============================================================================

function Invoke-WslListOnline {
    [CmdletBinding()]
    [OutputType([string])]
    param()

    # Wrapper bas niveau autour de `wsl --list --online`, isole pour :
    #   - Etre mockable par Pester avec des fixtures multi-langues, comme
    #     Get-WslVersionOutput dans check-prerequisites.ps1.
    #   - Centraliser le forcage WSL_UTF8 qui evite le probleme d'encoding
    #     UTF-16 sur PowerShell 5.1 (voir Get-WslOnlineDistros pour details).
    $env:WSL_UTF8 = "1"
    return (wsl --list --online | Out-String)
}

function Get-WslOnlineDistros {
    # Nom au pluriel volontaire : la fonction agrege plusieurs distros
    # dans un tableau. Meme convention que Test-Prerequisites.
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '',
        Justification = 'Function aggregates multiple distros into an array; plural noun is intentional.')]
    [CmdletBinding()]
    [OutputType([object[]])]
    param()

    # Retourne la liste des noms de distros disponibles a l'installation via
    # `wsl --install --name <Distro>`.
    #
    # Parsing language-agnostic : on ne teste AUCUN mot-cle localise
    # (name/nom/voici/installez) mais uniquement la structure tabulaire de la
    # sortie wsl :
    #   - Identifiant de distro : alphanumerique + . _ - (3 caracteres min)
    #   - Suivi d'au moins 2 espaces (les colonnes wsl sont bien espacees)
    #   - Suivi d'un autre non-blanc (colonne FRIENDLY NAME)
    # Cela filtre naturellement :
    #   - Les lignes de prose FR/EN (un seul espace apres le premier mot)
    #   - Les lignes vides
    # Filtre supplementaire pour l'en-tete "NAME" ou "NOM" (seul token isole
    # qui aurait pu matcher accidentellement dans une sortie inhabituelle).
    #
    # WSL_UTF8 (defini dans Invoke-WslListOnline) force wsl.exe a sortir en
    # UTF-8 au lieu d'UTF-16 LE (defaut) depuis WSL 0.64.0 (avril 2022).
    # Sans ca, PowerShell 5.1 capture les octets bruts et se retrouve avec un
    # caractere NUL entre chaque caractere reel, cassant le parsing.
    $raw = Invoke-WslListOnline
    return @(
        $raw -split "`n" |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ -match '^([A-Za-z0-9][A-Za-z0-9_.-]{2,})\s{2,}\S' } |
            ForEach-Object { $matches[1] } |
            Where-Object { $_ -notmatch '^(?i:name|nom)$' }
    )
}

function ConvertTo-WslPath {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$WindowsPath
    )

    # Convertit un chemin Windows ("C:\Users\..." ou "C:/Users/...") en chemin
    # WSL ("/mnt/c/Users/..."). Compatible PS 5.1 : n'utilise PAS de scriptblock
    # replacement (feature PS 7+ only) qui, en PS 5.1, insere silencieusement
    # la chaine litterale du scriptblock dans le resultat.
    #
    # Accepte les deux separateurs (\ et /) car Join-Path et les proprietes
    # .FullName peuvent produire l'un ou l'autre selon la version PowerShell.
    if ($WindowsPath -notmatch '^([A-Za-z]):[\\/](.*)$') {
        throw "Chemin Windows attendu avec lettre de lecteur, recu : '$WindowsPath'"
    }
    $driveLetter = $matches[1].ToLower()
    $pathTail = $matches[2] -replace '\\', '/'
    return "/mnt/$driveLetter/$pathTail"
}

function Invoke-WslDevSetup {
    [CmdletBinding()]
    param()

    $ErrorActionPreference = "Stop"

    # Force la console PowerShell a decoder les sorties des sous-processus en
    # UTF-8. Sans ca, sur PS 5.1 avec locale FR (Windows-1252 par defaut),
    # les caracteres accentues renvoyes par wsl.exe et bash apparaissent en
    # mojibake (les caracteres UTF-8 multi-octets deviennent 2 caracteres
    # Windows-1252 : par exemple e-accent devient A-tilde + copyright).
    # bootstrap.sh utilise systematiquement des accents dans ses messages.
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8

    # ========================================================
    # VERIFICATION DES PREREQUIS
    # ========================================================
    # Telechargement isole du script de check AVANT toute autre action (le ZIP
    # complet et l'installation lourde ne sont declenches qu'apres validation).
    $CheckScriptUrl = "https://raw.githubusercontent.com/milelievre/wsl-dev-setup-main/refs/heads/main/scripts/windows/check-prerequisites.ps1"

    Write-Host "==> Telechargement du script de verification des prerequis..." -ForegroundColor Cyan
    $checkScriptContent = (Invoke-WebRequest -Uri $CheckScriptUrl -UseBasicParsing).Content

    # Le contenu peut commencer par un BOM UTF-8 (U+FEFF) que PowerShell 5.1
    # n'ignore pas quand la string est passee a Invoke-Expression : le BOM
    # devient alors le premier caractere de la premiere commande et declenche
    # un CommandNotFoundException. On le retire explicitement ici.
    $checkScriptContent = $checkScriptContent -replace "^\uFEFF", ''

    # Invoke-Expression definit Test-Prerequisites dans le scope courant, ce
    # qui permet l'appel juste apres. Necessaire pour rester 100 % compatible
    # avec le flux `irm | iex` (pas de fichier local disponible).
    # Le try/catch evite la stack trace PowerShell brute apres le recap [KO]
    # deja produit par Test-Prerequisites : on ne montre que le message clair
    # puis on sort de la fonction (return, PAS exit qui fermerait la console).
    try {
        Invoke-Expression $checkScriptContent
        Test-Prerequisites
    } catch {
        Write-Host $_.Exception.Message -ForegroundColor Red
        return
    }

    # ========================================================
    # SELECTION DE LA DISTRIBUTION WSL
    # ========================================================
    Write-Host "==> Recuperation des distributions WSL disponibles..." -ForegroundColor Cyan

    # Filtres de compatibilite apt (bootstrap.sh actuel)
    $CompatiblePatterns = @('^Ubuntu', '^Debian', '^kali-linux')
    $DefaultDistro = 'Ubuntu-26.04'

    # Recuperation via helper mockable (voir Get-WslOnlineDistros pour details
    # sur le parsing language-agnostic et le forcage WSL_UTF8).
    $allDistros = Get-WslOnlineDistros

    $compatibleDistros = $allDistros | Where-Object {
        $name = $_
        $CompatiblePatterns | Where-Object { $name -match $_ }
    }

    if (-not $compatibleDistros -or $compatibleDistros.Count -eq 0) {
        Write-Host "Aucune distribution compatible detectee. Verifiez votre version de WSL." -ForegroundColor Red
        return
    }

    Write-Host ""
    Write-Host "Distributions disponibles (filtrees pour compatibilite apt - Ubuntu / Debian / Kali) :" -ForegroundColor Yellow
    for ($i = 0; $i -lt $compatibleDistros.Count; $i++) {
        $marker = if ($compatibleDistros[$i] -eq $DefaultDistro) { " (defaut)" } else { "" }
        Write-Host ("  [{0}] {1}{2}" -f ($i + 1), $compatibleDistros[$i], $marker)
    }

    $defaultIndex = [Array]::IndexOf($compatibleDistros, $DefaultDistro) + 1
    if ($defaultIndex -eq 0) { $defaultIndex = 1 }

    $choice = Read-Host "Numero de la distribution [$defaultIndex]"
    if ([string]::IsNullOrWhiteSpace($choice)) { $choice = $defaultIndex }

    if (-not ($choice -as [int]) -or [int]$choice -lt 1 -or [int]$choice -gt $compatibleDistros.Count) {
        Write-Host "Choix invalide : '$choice'." -ForegroundColor Red
        return
    }

    $DistroName = $compatibleDistros[[int]$choice - 1]
    Write-Host "==> Distribution selectionnee : $DistroName" -ForegroundColor Green

    # ========================================================
    # NOM D'INSTANCE WSL
    # ========================================================
    $InstanceName = Read-Host "Nom de l'instance WSL [$DistroName]"
    if ([string]::IsNullOrWhiteSpace($InstanceName)) { $InstanceName = $DistroName }

    # Validation du nom
    if ($InstanceName -notmatch '^[a-zA-Z0-9._-]+$') {
        Write-Host "Nom d'instance invalide : '$InstanceName'. Utilisez uniquement lettres, chiffres, '.', '_', '-'." -ForegroundColor Red
        return
    }

    # Verification de collision (fresh install uniquement)
    $existingInstances = (wsl -l -q) -split "`n" | ForEach-Object { $_.Trim() -replace "`0", '' } | Where-Object { $_ }
    if ($existingInstances -contains $InstanceName) {
        Write-Host "L'instance WSL '$InstanceName' existe deja. Ce script ne gere que les installations fraiches." -ForegroundColor Red
        Write-Host "Supprimez-la manuellement avec : wsl --unregister $InstanceName" -ForegroundColor Yellow
        return
    }

    Write-Host "==> Instance a creer : $InstanceName (source : $DistroName)" -ForegroundColor Green

    # ========================================================
    # CONFIGURATION DU DEPOT GIT
    # ========================================================
    $RepoZipUrl = https://github.com/milelievre/wsl-dev-setup-main/archive/refs/heads/main.zip"

    # Demande de l'utilisateur Linux
    $TargetUser = Read-Host "Entrez le nom d'utilisateur Linux souhaite (ex: mallain)"
    if ([string]::IsNullOrWhiteSpace($TargetUser)) {
        Write-Host "Le nom d'utilisateur ne peut pas etre vide." -ForegroundColor Red
        return
    }

    # ========================================================
    # 1. PREPARATION DU DOSSIER TEMPORAIRE & TELECHARGEMENT
    # ========================================================
    $tempDir = Join-Path $env:TEMP "wsl-setup-$((Get-Random))"
    $zipFile = "$tempDir\repo.zip"
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

    Write-Host "==> [1/5] Telechargement des scripts..." -ForegroundColor Cyan
    Invoke-WebRequest -Uri $RepoZipUrl -OutFile $zipFile
    Expand-Archive -Path $zipFile -DestinationPath $tempDir

    # Detection du dossier extrait (generalement wsl-dev-setup-main)
    $extractedFolder = Get-ChildItem -Path $tempDir -Directory | Select-Object -First 1
    $scriptsLinuxDir = Join-Path $extractedFolder.FullName "scripts\linux"

    # ========================================================
    # 2. SOCLE WINDOWS (WSL + VS CODE)
    # ========================================================
    Write-Host "==> [2/5] Deploiement du socle Windows..." -ForegroundColor Cyan
    $setupWinScript = Join-Path $extractedFolder.FullName "scripts\windows\setup-dev.ps1"
    if (Test-Path $setupWinScript) {
        & $setupWinScript -DistroName $DistroName -InstanceName $InstanceName
    }

    # ========================================================
    # 3. EXECUTION DU BOOTSTRAP DANS WSL
    # ========================================================
    Write-Host "==> [3/5] Configuration interne de WSL via root..." -ForegroundColor Cyan

    # ATTENTION - Regression 2026-09-21 :
    # NE PAS utiliser `bash -c "$bootstrapContent"` pour transmettre un script
    # inline via PowerShell. Le script bash contient des guillemets, des `$(...)`,
    # des heredocs et des continuations de ligne que PowerShell reinterprete
    # avant de les passer a wsl.exe, ce qui casse le parsing bash (variables
    # vides, `unexpected EOF`, `unary operator expected`, etc.).
    #
    # Solution : faire lire le script directement par bash depuis le systeme
    # de fichiers monte, en convertissant le chemin Windows en chemin WSL
    # (`C:\Users\...` -> `/mnt/c/Users/...`). WSL fait cette conversion via
    # wslpath, mais on peut aussi la faire cote PowerShell pour rester simple.
    $bootstrapWinPath = Join-Path $scriptsLinuxDir "bootstrap.sh"

    # Conversion "C:\Users\..." -> "/mnt/c/Users/..." via helper testable.
    $bootstrapWslPath = ConvertTo-WslPath -WindowsPath $bootstrapWinPath

    # Normalisation CRLF -> LF sur le fichier lui-meme (Get-Content de PS 5.1
    # peut renvoyer CRLF meme si le fichier est LF selon l'origine du checkout
    # git ; on force en LF pour bash).
    $bootstrapRaw = [System.IO.File]::ReadAllText($bootstrapWinPath) -replace "`r`n", "`n"
    [System.IO.File]::WriteAllText($bootstrapWinPath, $bootstrapRaw, [System.Text.UTF8Encoding]::new($false))

    # Execution : bash lit le fichier depuis /mnt/c/... et recoit TargetUser
    # comme $1. Zero quoting cote PowerShell, encoding UTF-8 preserve.
    wsl -d $InstanceName -u root -- bash "$bootstrapWslPath" "$TargetUser"

    # ========================================================
    # 4. REDEMARRAGE WSL
    # ========================================================
    Write-Host "==> [4/5] Redemarrage de WSL..." -ForegroundColor Cyan
    wsl --shutdown
    Start-Sleep -Seconds 2

    # Nettoyage des fichiers temporaires Windows
    Remove-Item -Recurse -Force $tempDir

    # ========================================================
    # 5. DEMARRAGE DE VS CODE
    # ========================================================
    Write-Host "==> [5/5] Lancement de VS Code connecte a WSL..." -ForegroundColor Cyan
    code --remote "wsl+$InstanceName" "/home/$TargetUser"

    Write-Host "Machine initialisee avec succes !" -ForegroundColor Green
}

# ----------------------------------------------------------------------------
# Point d'entree : appel unique de la fonction wrapper.
# Necessaire pour que le flux `irm | iex` execute effectivement le contenu
# (sans cet appel, on ne ferait que definir la fonction dans le scope courant).
# ----------------------------------------------------------------------------
Invoke-WslDevSetup
