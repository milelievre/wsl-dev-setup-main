# ============================================================================
# check-prerequisites.ps1
#
# Fonction publique : Test-Prerequisites
#   - Exécute une série de checks bloquants avant tout téléchargement lourd.
#   - Affiche un récapitulatif [OK]/[KO] par ligne.
#   - Lève une exception (throw) en cas d'échec d'au moins un prérequis.
#
# Fonction interne : Get-WslVersionOutput
#   - Wrapper isolé autour de "wsl.exe --version" pour être mockable par Pester
#     (Pester ne peut pas mocker l'opérateur d'appel `&` sur un exécutable).
#   - Nettoie les octets nuls issus de la sortie UTF-16 native de wsl.exe.
# ============================================================================

function Get-WslVersionOutput {
    [CmdletBinding()]
    param()

    # `wsl --version` renvoie de l'UTF-16 avec des octets nuls (comportement
    # identique à `wsl --list --online`). On force en string puis on retire
    # les \0 pour que le regex de parsing fonctionne correctement.
    $raw = & wsl.exe --version 2>&1 | Out-String
    return ($raw -replace "`0", '')
}

function Test-IsAdministrator {
    [CmdletBinding()]
    param()

    # Wrapper autour du check administrateur. Isolé dans une fonction dédiée
    # pour être mockable par Pester (les appels statiques .NET ne le sont pas).
    return ([Security.Principal.WindowsPrincipal] `
            [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-WindowsBuildNumber {
    [CmdletBinding()]
    [OutputType([int])]
    param()

    # Wrapper autour de Get-CimInstance pour rester mockable en environnement
    # Linux/pwsh (où Get-CimInstance n'existe pas). Renvoie un [int].
    return [int](Get-CimInstance -ClassName Win32_OperatingSystem).BuildNumber
}

function Get-PowerShellVersion {
    [CmdletBinding()]
    param()

    # Wrapper autour de $PSVersionTable.PSVersion pour permettre le mock Pester.
    return $PSVersionTable.PSVersion
}

function Test-Prerequisites {
    # Nom au pluriel volontaire : reflète l'agrégation de plusieurs checks
    # (spécifié par le plan `.kilo/plans/1790022007682-prerequisites-check-plan.md`).
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '',
        Justification = 'Function orchestrates multiple prerequisite checks; plural noun is intentional.')]
    [CmdletBinding()]
    param()

    $checks = @()

    # ------------------------------------------------------------------------
    # 1. Session administrateur
    # ------------------------------------------------------------------------
    $isAdmin = Test-IsAdministrator
    $checks += [PSCustomObject]@{
        Name   = "Session administrateur"
        Ok     = $isAdmin
        Detail = if ($isAdmin) { "OK" } else { "Relancez PowerShell en tant qu'administrateur" }
    }

    # ------------------------------------------------------------------------
    # 2. Version PowerShell >= 5.1
    # ------------------------------------------------------------------------
    $psVer = Get-PowerShellVersion
    $psOk = ($psVer.Major -gt 5) -or ($psVer.Major -eq 5 -and $psVer.Minor -ge 1)
    $checks += [PSCustomObject]@{
        Name   = "PowerShell >= 5.1"
        Ok     = $psOk
        Detail = "Détecté : $psVer"
    }

    # ------------------------------------------------------------------------
    # 3. Windows build >= 19041 (version 2004+, requis par WSL 2 moderne)
    # ------------------------------------------------------------------------
    $build = Get-WindowsBuildNumber
    $buildOk = $build -ge 19041
    $checks += [PSCustomObject]@{
        Name   = "Windows build >= 19041 (2004+)"
        Ok     = $buildOk
        Detail = "Détecté : build $build"
    }

    # ------------------------------------------------------------------------
    # 4. wsl.exe présent dans le PATH
    # ------------------------------------------------------------------------
    $wslCmd = Get-Command wsl.exe -ErrorAction SilentlyContinue
    $wslPresent = $null -ne $wslCmd
    $checks += [PSCustomObject]@{
        Name   = "wsl.exe présent"
        Ok     = $wslPresent
        Detail = if ($wslPresent) { $wslCmd.Path } else { "Installez WSL : https://aka.ms/wsl" }
    }

    # ------------------------------------------------------------------------
    # 5. WSL >= 2.4.4 (requis pour `wsl --install --name`)
    #    Uniquement testé si wsl.exe est présent, sinon on marque "Non testé".
    # ------------------------------------------------------------------------
    $wslVerOk = $false
    $wslVerDetail = "Non testé (wsl.exe absent)"
    if ($wslPresent) {
        try {
            $wslVerRaw = Get-WslVersionOutput
            # Parsing FR/EN : "WSL version: 2.4.13.0" ou "Version WSL : 2.4.13.0"
            if ($wslVerRaw -match '(?im)^\s*(?:WSL version|Version WSL)\s*[:=]\s*(\d+)\.(\d+)\.(\d+)') {
                $maj = [int]$matches[1]
                $min = [int]$matches[2]
                $patch = [int]$matches[3]
                $wslVerOk = ($maj -gt 2) -or
                            ($maj -eq 2 -and $min -gt 4) -or
                            ($maj -eq 2 -and $min -eq 4 -and $patch -ge 4)
                $wslVerDetail = "Détecté : $maj.$min.$patch"
            } else {
                $wslVerDetail = "Version non parsée. Lancez : wsl --update"
            }
        } catch {
            $wslVerDetail = "Erreur wsl --version. Lancez : wsl --update"
        }
    }
    $checks += [PSCustomObject]@{
        Name   = "WSL >= 2.4.4 (support --name)"
        Ok     = $wslVerOk
        Detail = $wslVerDetail
    }

    # ------------------------------------------------------------------------
    # 6. winget présent (pas de version min)
    # ------------------------------------------------------------------------
    $wingetOk = $null -ne (Get-Command winget -ErrorAction SilentlyContinue)
    $checks += [PSCustomObject]@{
        Name   = "winget présent"
        Ok     = $wingetOk
        Detail = if ($wingetOk) { "OK" } else { "Installez App Installer : https://apps.microsoft.com/detail/9nblggh4nns1" }
    }

    # ------------------------------------------------------------------------
    # Affichage récapitulatif
    # ------------------------------------------------------------------------
    Write-Host ""
    Write-Host "=== Vérification des prérequis ===" -ForegroundColor Cyan
    foreach ($c in $checks) {
        $tag = if ($c.Ok) { "[OK]" } else { "[KO]" }
        $color = if ($c.Ok) { "Green" } else { "Red" }
        Write-Host ("  {0} {1,-45} {2}" -f $tag, $c.Name, $c.Detail) -ForegroundColor $color
    }
    Write-Host ""

    $failed = @($checks | Where-Object { -not $_.Ok })
    if ($failed.Count -gt 0) {
        throw "Prérequis manquants ($($failed.Count)). Corrigez les points [KO] ci-dessus puis relancez."
    }
    Write-Host "Tous les prérequis sont satisfaits." -ForegroundColor Green
}
