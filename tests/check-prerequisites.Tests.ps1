# ============================================================================
# Pester tests for scripts/windows/check-prerequisites.ps1
#
# Ces tests s'exécutent dans un conteneur Linux/pwsh 7.4.x. On mocke donc
# systématiquement les wrappers dépendants de Windows (Get-CimInstance,
# Test-IsAdministrator, Get-WslVersionOutput) plutôt que d'essayer de mocker
# les appels statiques .NET ou les exécutables externes.
# ============================================================================

BeforeAll {
    . "$PSScriptRoot/../scripts/windows/check-prerequisites.ps1"
}

Describe "Test-Prerequisites" {

    Context "Quand tous les checks passent" {
        BeforeAll {
            Mock Test-IsAdministrator { $true }
            Mock Get-PowerShellVersion { [Version]'7.4.2' }
            Mock Get-WindowsBuildNumber { 22631 }
            Mock Get-Command { [PSCustomObject]@{ Path = "C:\Windows\System32\wsl.exe" } } -ParameterFilter { $Name -eq 'wsl.exe' }
            Mock Get-Command { [PSCustomObject]@{ Path = "C:\Users\me\AppData\Local\Microsoft\WindowsApps\winget.exe" } } -ParameterFilter { $Name -eq 'winget' }
            Mock Get-WslVersionOutput { "WSL version: 2.4.13.0`nKernel version: 5.15.153.1-2" }
        }

        It "Ne lève pas d'exception" {
            { Test-Prerequisites } | Should -Not -Throw
        }
    }

    Context "Quand la session n'est pas administrateur" {
        BeforeAll {
            Mock Test-IsAdministrator { $false }
            Mock Get-PowerShellVersion { [Version]'7.4.2' }
            Mock Get-WindowsBuildNumber { 22631 }
            Mock Get-Command { [PSCustomObject]@{ Path = "C:\Windows\System32\wsl.exe" } } -ParameterFilter { $Name -eq 'wsl.exe' }
            Mock Get-Command { [PSCustomObject]@{ Path = "C:\winget.exe" } } -ParameterFilter { $Name -eq 'winget' }
            Mock Get-WslVersionOutput { "WSL version: 2.4.13.0" }
        }

        It "Throw avec un message mentionnant les prérequis manquants" {
            { Test-Prerequisites } | Should -Throw -ExpectedMessage "*Prérequis manquants*"
        }
    }

    Context "Quand la build Windows est trop ancienne" {
        BeforeAll {
            Mock Test-IsAdministrator { $true }
            Mock Get-PowerShellVersion { [Version]'7.4.2' }
            Mock Get-WindowsBuildNumber { 18363 }
            Mock Get-Command { [PSCustomObject]@{ Path = "C:\Windows\System32\wsl.exe" } } -ParameterFilter { $Name -eq 'wsl.exe' }
            Mock Get-Command { [PSCustomObject]@{ Path = "C:\winget.exe" } } -ParameterFilter { $Name -eq 'winget' }
            Mock Get-WslVersionOutput { "WSL version: 2.4.13.0" }
        }

        It "Throw car la build est < 19041" {
            { Test-Prerequisites } | Should -Throw -ExpectedMessage "*Prérequis manquants*"
        }
    }

    Context "Quand PowerShell est trop ancien (4.0)" {
        BeforeAll {
            Mock Test-IsAdministrator { $true }
            Mock Get-PowerShellVersion { [Version]'4.0' }
            Mock Get-WindowsBuildNumber { 22631 }
            Mock Get-Command { [PSCustomObject]@{ Path = "C:\Windows\System32\wsl.exe" } } -ParameterFilter { $Name -eq 'wsl.exe' }
            Mock Get-Command { [PSCustomObject]@{ Path = "C:\winget.exe" } } -ParameterFilter { $Name -eq 'winget' }
            Mock Get-WslVersionOutput { "WSL version: 2.4.13.0" }
        }

        It "Throw car PowerShell < 5.1" {
            { Test-Prerequisites } | Should -Throw -ExpectedMessage "*Prérequis manquants*"
        }
    }

    Context "Quand wsl.exe est absent" {
        BeforeAll {
            Mock Test-IsAdministrator { $true }
            Mock Get-PowerShellVersion { [Version]'7.4.2' }
            Mock Get-WindowsBuildNumber { 22631 }
            Mock Get-Command { $null } -ParameterFilter { $Name -eq 'wsl.exe' }
            Mock Get-Command { [PSCustomObject]@{ Path = "C:\winget.exe" } } -ParameterFilter { $Name -eq 'winget' }
            # Get-WslVersionOutput ne devrait pas être appelé, mais on le mocke
            # par sécurité pour éviter un appel réel à wsl.exe.
            Mock Get-WslVersionOutput { "" }
        }

        It "Throw avec un message mentionnant les prérequis manquants" {
            { Test-Prerequisites } | Should -Throw -ExpectedMessage "*Prérequis manquants*"
        }

        It "N'appelle pas Get-WslVersionOutput quand wsl.exe est absent" {
            # L'exception est attendue ici (wsl.exe absent), on l'absorbe
            # volontairement puisque le but du test est de vérifier l'appel.
            try {
                Test-Prerequisites
            } catch {
                $null = $_
            }
            Should -Invoke Get-WslVersionOutput -Times 0 -Exactly
        }
    }

    Context "Quand WSL est présent mais trop ancien (2.0.5)" {
        BeforeAll {
            Mock Test-IsAdministrator { $true }
            Mock Get-PowerShellVersion { [Version]'7.4.2' }
            Mock Get-WindowsBuildNumber { 22631 }
            Mock Get-Command { [PSCustomObject]@{ Path = "C:\Windows\System32\wsl.exe" } } -ParameterFilter { $Name -eq 'wsl.exe' }
            Mock Get-Command { [PSCustomObject]@{ Path = "C:\winget.exe" } } -ParameterFilter { $Name -eq 'winget' }
            Mock Get-WslVersionOutput { "WSL version: 2.0.5.0" }
        }

        It "Throw car WSL < 2.4.4" {
            { Test-Prerequisites } | Should -Throw -ExpectedMessage "*Prérequis manquants*"
        }
    }

    Context "Quand winget est absent" {
        BeforeAll {
            Mock Test-IsAdministrator { $true }
            Mock Get-PowerShellVersion { [Version]'7.4.2' }
            Mock Get-WindowsBuildNumber { 22631 }
            Mock Get-Command { [PSCustomObject]@{ Path = "C:\Windows\System32\wsl.exe" } } -ParameterFilter { $Name -eq 'wsl.exe' }
            Mock Get-Command { $null } -ParameterFilter { $Name -eq 'winget' }
            Mock Get-WslVersionOutput { "WSL version: 2.4.13.0" }
        }

        It "Throw avec un message mentionnant les prérequis manquants" {
            { Test-Prerequisites } | Should -Throw -ExpectedMessage "*Prérequis manquants*"
        }
    }

    Context "Parsing FR de wsl --version" {
        BeforeAll {
            Mock Test-IsAdministrator { $true }
            Mock Get-PowerShellVersion { [Version]'7.4.2' }
            Mock Get-WindowsBuildNumber { 22631 }
            Mock Get-Command { [PSCustomObject]@{ Path = "C:\Windows\System32\wsl.exe" } } -ParameterFilter { $Name -eq 'wsl.exe' }
            Mock Get-Command { [PSCustomObject]@{ Path = "C:\winget.exe" } } -ParameterFilter { $Name -eq 'winget' }
            Mock Get-WslVersionOutput { "Version WSL : 2.4.13.0`nVersion du noyau : 5.15" }
        }

        It "Accepte la locale FR (Version WSL : X.Y.Z)" {
            { Test-Prerequisites } | Should -Not -Throw
        }
    }
}
