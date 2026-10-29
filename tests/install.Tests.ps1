# ============================================================================
# Pester tests for install.ps1
#
# But : garantir que install.ps1 reste consommable via le flux
#       `irm https://.../install.ps1 | iex`
#       et via `[scriptblock]::Create()` (utilisé en fallback quand le contenu
#       téléchargé contient un BOM ou d'autres subtilités non gérées par iex).
#
# Contexte de la régression détectée le 2026-09-21 :
#   - Le commit c236258 avait ajouté un attribut
#     [Diagnostics.CodeAnalysis.SuppressMessageAttribute(...)]
#     accolé à un `param()` vide au top-level du script. Cette syntaxe n'est
#     pas valide en top-level de script (elle l'est uniquement à l'intérieur
#     d'une fonction ou classe), ce qui cassait totalement install.ps1 :
#     `irm | iex`, `[scriptblock]::Create()` ET l'exécution locale
#     `.\install.ps1` échouaient toutes trois avec la même ParseException.
#   - En parallèle, Invoke-Expression sur du contenu téléchargé conservant un
#     BOM UTF-8 (U+FEFF) échouait avec CommandNotFoundException sur "﻿#..."
#     (le BOM devient le premier caractère de la première commande).
#
# Ces tests protègent contre la récidive de ces deux classes de bugs.
# ============================================================================

BeforeAll {
    $script:InstallScriptPath = Join-Path -Path $PSScriptRoot -ChildPath '../install.ps1'
    $script:InstallScriptRaw = Get-Content -Path $script:InstallScriptPath -Raw
}

Describe "install.ps1 - Parsing" {

    It "Est parsable via [scriptblock]::Create() (flux irm | iex)" {
        # Ce test aurait attrapé la régression c236258 : l'attribut top-level
        # [SuppressMessageAttribute()]param() faisait échouer Create() avec une
        # ParseException.
        { [scriptblock]::Create($script:InstallScriptRaw) } | Should -Not -Throw
    }

    It "Ne contient pas d'attribut [Diagnostics.CodeAnalysis.SuppressMessage] au top-level" {
        # Sécurité belt-and-suspenders : même si un futur PowerShell l'acceptait
        # au top-level, on le refuse ici parce que le pattern casse `iex` avec
        # BOM et augmente la surface d'erreur pour un simple hint PSSA. Les
        # exclusions doivent passer par tests/PSScriptAnalyzerSettings.psd1.
        $firstNonEmptyLines = ($script:InstallScriptRaw -split "`r?`n" |
            Where-Object { $_ -notmatch '^\s*(#|$)' } |
            Select-Object -First 5) -join "`n"
        $firstNonEmptyLines | Should -Not -Match 'Diagnostics\.CodeAnalysis\.SuppressMessageAttribute'
    }
}

Describe "install.ps1 - Robustesse Invoke-Expression sur contenu téléchargé" {

    It "Neutralise le BOM UTF-8 avant Invoke-Expression du script de check" {
        # Le script doit strip le BOM (U+FEFF) sur $checkScriptContent avant
        # de le passer à Invoke-Expression. Sans ça, PS 5.1 déclenche un
        # CommandNotFoundException sur "﻿#..." (le BOM devient le premier
        # caractère de la première commande).
        $script:InstallScriptRaw | Should -Match '\$checkScriptContent\s*=\s*\$checkScriptContent\s*-replace\s*"\^\\uFEFF"'
    }

    It "Fait le strip du BOM avant d'appeler Invoke-Expression" {
        # Vérifie l'ordre : le -replace doit précéder le Invoke-Expression.
        $bomStripIndex = $script:InstallScriptRaw.IndexOf('$checkScriptContent = $checkScriptContent -replace "^\uFEFF"')
        $iexIndex = $script:InstallScriptRaw.IndexOf('Invoke-Expression $checkScriptContent')
        $bomStripIndex | Should -BeGreaterThan -1
        $iexIndex | Should -BeGreaterThan -1
        $bomStripIndex | Should -BeLessThan $iexIndex
    }
}

Describe "install.ps1 - Compatibilité irm | iex (BOM et ASCII)" {

    It "Ne commence PAS par un BOM UTF-8 (U+FEFF)" {
        # Régression 2026-09-21 : le BOM en tête de install.ps1 lui-même
        # rendait le flux `irm | iex` cassé, car Invoke-Expression traitait
        # le BOM comme le premier caractère de la première commande
        # ("$ErrorActionPreference" devenait "﻿$ErrorActionPreference").
        # On garantit ici l'absence de BOM sur le point d'entrée public.
        $bytes = [System.IO.File]::ReadAllBytes($script:InstallScriptPath)
        $bytes.Length | Should -BeGreaterThan 3
        # BOM UTF-8 = EF BB BF
        (($bytes[0] -eq 0xEF) -and ($bytes[1] -eq 0xBB) -and ($bytes[2] -eq 0xBF)) `
            | Should -BeFalse -Because "install.ps1 doit rester sans BOM pour supporter `irm | iex` sur PowerShell 5.1."
    }

    It "Ne contient AUCUN caractère non-ASCII" {
        # Sans BOM, PowerShell 5.1 interprète les fichiers .ps1 en ANSI
        # (Windows-1252 en France), ce qui déclenche du mojibake sur tout
        # caractère non-ASCII (accents, guillemets typographiques, tirets
        # cadratins). On garantit ici que le fichier reste 100 % ASCII pour
        # rester lisible identiquement sur PS 5.1 et PS 7+.
        $bytes = [System.IO.File]::ReadAllBytes($script:InstallScriptPath)
        $nonAscii = $bytes | Where-Object { $_ -gt 0x7F }
        $nonAscii.Count | Should -Be 0 -Because "install.ps1 doit rester ASCII pur pour éviter le mojibake PS 5.1 sans BOM."
    }
}

Describe "install.ps1 - Gestion propre de l'échec Test-Prerequisites" {

    It "Enveloppe Test-Prerequisites dans un try/catch avec return" {
        # Régression UX 2026-09-21 (première itération) : quand
        # Test-Prerequisites lève, PowerShell affichait la stack trace complète
        # (Au caractère Ligne:163 ...) juste après le récap [KO] déjà lisible.
        # Un try/catch attrape l'exception et réaffiche seulement le message.
        # Régression UX 2026-09-21 (seconde itération) : `exit 1` dans le catch
        # fermait la console PowerShell entière quand le script était consommé
        # via `irm | iex` (iex n'introduit pas de scope script). On utilise
        # `return` désormais, ce qui sort seulement de la fonction wrapper.
        $script:InstallScriptRaw | Should -Match '(?s)try\s*\{[^}]*Invoke-Expression\s+\$checkScriptContent[^}]*Test-Prerequisites[^}]*\}\s*catch\s*\{[^}]*\breturn\b[^}]*\}'
    }

    It "N'utilise PAS exit dans le catch (fermerait la console via iex)" {
        # Garde-fou contre la régression 'fenêtre PowerShell qui se ferme
        # automatiquement' : `exit N` au top-level d'un script consommé via
        # `iex` ferme la console. Le catch doit utiliser `return` uniquement.
        $catchBlock = [regex]::Match($script:InstallScriptRaw, '(?s)catch\s*\{(.*?)\}').Groups[1].Value
        $catchBlock | Should -Not -Match '\bexit\s+\d'
    }

    It "Ne réécrit pas Exception.Message avec du texte accentué" {
        # Le catch doit rester ASCII pour ne pas réintroduire du non-ASCII
        # dans install.ps1 (invariant du Describe précédent).
        $catchBlock = [regex]::Match($script:InstallScriptRaw, '(?s)catch\s*\{(.*?)\}').Groups[1].Value
        $catchBlock | Should -Not -Match '[^\x00-\x7F]'
    }
}

Describe "install.ps1 - Encapsulation en fonction (pattern irm | iex)" {

    It "Définit une fonction wrapper Invoke-WslDevSetup" {
        # Le contenu doit être encapsulé dans une fonction plutôt qu'exécuté
        # au top-level. Sans cette fonction, `return` et `exit` n'ont pas le
        # comportement voulu dans le canal `irm | iex` :
        #   - `exit N` ferme la console entière
        #   - `return` au top-level ne stoppe pas les commandes suivantes
        # La fonction wrapper donne un scope propre à stopper via `return`.
        $script:InstallScriptRaw | Should -Match '(?m)^\s*function\s+Invoke-WslDevSetup\b'
    }

    It "Appelle Invoke-WslDevSetup à la fin du fichier" {
        # Sans cet appel, `irm | iex` ne ferait que définir la fonction dans
        # le scope de l'utilisateur sans exécuter le setup. L'appel doit être
        # en dehors de la définition de la fonction.
        # On vérifie qu'une ligne "Invoke-WslDevSetup" (sans indentation, hors
        # commentaire) existe après la définition de fonction.
        $lines = $script:InstallScriptRaw -split "`r?`n"
        $callLines = $lines | Where-Object { $_ -match '^\s*Invoke-WslDevSetup\s*$' }
        $callLines.Count | Should -BeGreaterOrEqual 1 -Because "l'appel Invoke-WslDevSetup doit exister en tant que ligne à part."
    }

    It "N'utilise PAS exit au top-level (fermerait la console via iex)" {
        # Toutes les sorties d'erreur doivent passer par `return` dans la
        # fonction, jamais par `exit` (qui fermerait la console PowerShell
        # de l'utilisateur quand le script est consommé via `irm | iex`).
        $script:InstallScriptRaw | Should -Not -Match '(?m)^\s*exit\s+\d'
    }
}

Describe "install.ps1 - Transmission du bootstrap.sh a WSL" {

    It "N'utilise PAS 'bash -c' pour executer bootstrap.sh (regression 2026-09-21)" {
        # Passer un script bash entier comme argument -c a bash via PowerShell
        # est cassé : les guillemets, $(), heredocs et continuations de ligne
        # sont mangles par le quoting PowerShell, ce qui provoque des erreurs
        # bash en cascade (variables vides, unexpected EOF, unary operator,
        # etc.). Il faut passer par le filesystem via `bash /mnt/c/.../bootstrap.sh`.
        $script:InstallScriptRaw | Should -Not -Match 'wsl[^\r\n]*bash\s+-c\s+"?\$bootstrap'
    }

    It "Convertit le chemin Windows en chemin WSL /mnt/<lettre>/" {
        # Le script doit convertir le chemin Windows du bootstrap.sh en un
        # chemin utilisable depuis WSL (/mnt/c/... ou similaire) avant de le
        # passer a bash. Sans cette conversion, bash ne trouvera pas le fichier.
        $script:InstallScriptRaw | Should -Match '/mnt/'
    }

    It "Passe TargetUser comme argument positionnel de bash, pas via -c" {
        # `bash <script> <arg>` transmet correctement l'argument comme $1 au
        # script, sans mecanisme complique. On verifie la presence du pattern.
        $script:InstallScriptRaw | Should -Match 'bash\s+"?\$bootstrapWslPath"?\s+"?\$TargetUser"?'
    }

    It "Force [Console]::OutputEncoding en UTF-8 pour eviter le mojibake" {
        # Sans ce reglage, PS 5.1 en locale FR decode les sorties UTF-8 des
        # sous-processus (bash, wsl.exe) en Windows-1252, produisant du
        # mojibake sur tous les messages accentues de bootstrap.sh.
        $script:InstallScriptRaw | Should -Match '\[Console\]::OutputEncoding\s*=\s*\[System\.Text\.Encoding\]::UTF8'
    }
}

Describe "install.ps1 - Compatibilité PS 5.1 (patterns interdits)" {

    It "N'utilise PAS de scriptblock replacement -replace 'pattern', { ... }" {
        # Régression 2026-09-21 : les scriptblock replacements (`-replace
        # 'pattern', { $_.Groups[1] }`) sont une feature PowerShell 7+.
        # Sur PS 5.1 (cible de compatibilité), la syntaxe est acceptée mais
        # le scriptblock est traité comme une string littérale, ce qui insère
        # "$($_.Groups[1].Value.ToLower())" tel quel dans le résultat.
        # Utiliser plutôt une variable temporaire + if ($x -match ...) { ... }.
        $script:InstallScriptRaw | Should -Not -Match "-replace\s+'[^']+'\s*,\s*\{"
        $script:InstallScriptRaw | Should -Not -Match '-replace\s+"[^"]+"\s*,\s*\{'
    }
}

# ============================================================================
# Tests fonctionnels de ConvertTo-WslPath.
# ============================================================================

Describe "ConvertTo-WslPath - Conversion chemin Windows vers WSL" {

    BeforeAll {
        # Charge uniquement les définitions de fonctions de install.ps1
        # (on retire la dernière ligne d'appel `Invoke-WslDevSetup` qui
        # déclencherait le vrai setup).
        $scriptContent = $script:InstallScriptRaw
        $scriptContent = $scriptContent -replace '(?m)^\s*Invoke-WslDevSetup\s*$', ''
        . ([scriptblock]::Create($scriptContent))
    }

    Context "Chemins Windows classiques (backslash)" {

        It "Convertit C:\Users\foo -> /mnt/c/Users/foo" {
            ConvertTo-WslPath -WindowsPath 'C:\Users\foo' | Should -Be '/mnt/c/Users/foo'
        }

        It "Convertit D:\Projects\bar\baz.sh -> /mnt/d/Projects/bar/baz.sh" {
            ConvertTo-WslPath -WindowsPath 'D:\Projects\bar\baz.sh' | Should -Be '/mnt/d/Projects/bar/baz.sh'
        }

        It "Met la lettre de lecteur en minuscule" {
            ConvertTo-WslPath -WindowsPath 'E:\foo' | Should -Be '/mnt/e/foo'
        }
    }

    Context "Chemins Windows avec forward slash (PS 7 style)" {

        It "Convertit C:/Users/foo -> /mnt/c/Users/foo" {
            # PS 7+ et certains Join-Path produisent des chemins avec `/`.
            # Le helper doit accepter les deux séparateurs.
            ConvertTo-WslPath -WindowsPath 'C:/Users/foo' | Should -Be '/mnt/c/Users/foo'
        }

        It "Convertit un chemin réel typique du temp WSL setup" {
            $realPath = 'C:/Users/DDVV3817/AppData/Local/Temp/wsl-setup-123/wsl-dev-setup-main/scripts/linux/bootstrap.sh'
            $expected = '/mnt/c/Users/DDVV3817/AppData/Local/Temp/wsl-setup-123/wsl-dev-setup-main/scripts/linux/bootstrap.sh'
            ConvertTo-WslPath -WindowsPath $realPath | Should -Be $expected
        }
    }

    Context "Chemins mixtes ou pathologiques" {

        It "Convertit un chemin mixte C:\Users/foo\bar -> /mnt/c/Users/foo/bar" {
            ConvertTo-WslPath -WindowsPath 'C:\Users/foo\bar' | Should -Be '/mnt/c/Users/foo/bar'
        }

        It "Rejette un chemin sans lettre de lecteur" {
            { ConvertTo-WslPath -WindowsPath '/etc/foo' } | Should -Throw -ExpectedMessage "*Chemin Windows attendu*"
        }

        It "Rejette une chaîne vide" {
            { ConvertTo-WslPath -WindowsPath '' } | Should -Throw
        }
    }
}

Describe "install.ps1 - Structure du parser WSL (helpers)" {

    It "Définit une fonction Invoke-WslListOnline (wrapper mockable)" {
        # Le wrapper bas niveau autour de `wsl --list --online` doit être
        # extrait en fonction dédiée pour être mockable par Pester (comme
        # Get-WslVersionOutput dans check-prerequisites.ps1).
        $script:InstallScriptRaw | Should -Match '(?m)^\s*function\s+Invoke-WslListOnline\b'
    }

    It "Définit une fonction Get-WslOnlineDistros (parser)" {
        # Le parser doit être extrait en fonction dédiée pour être testable
        # indépendamment (fixtures multi-langues, avec/sans NULs UTF-16).
        $script:InstallScriptRaw | Should -Match '(?m)^\s*function\s+Get-WslOnlineDistros\b'
    }

    It "Force WSL_UTF8=1 pour éviter l'encoding UTF-16 sur PS 5.1" {
        # WSL_UTF8=1 force wsl.exe à sortir en UTF-8 au lieu d'UTF-16 LE
        # depuis WSL 0.64.0 (avril 2022). Sans ça, PowerShell 5.1 capture
        # les octets bruts et se retrouve avec un caractère NUL entre
        # chaque caractère réel, cassant le parsing.
        $script:InstallScriptRaw | Should -Match '\$env:WSL_UTF8\s*=\s*"1"'
    }
}

# ============================================================================
# Tests fonctionnels du parser Get-WslOnlineDistros avec fixtures multi-langues.
#
# On dot-source install.ps1 dans un scriptblock qui neutralise l'appel final
# `Invoke-WslDevSetup` (sinon Pester déclencherait le vrai setup pendant le
# discovery). On peut ensuite mocker Invoke-WslListOnline avec des fixtures
# textuelles et vérifier que Get-WslOnlineDistros retourne les bons noms.
# ============================================================================

Describe "Get-WslOnlineDistros - Parser language-agnostic" {

    BeforeAll {
        # Charge uniquement les définitions de fonctions de install.ps1
        # (on retire la dernière ligne d'appel `Invoke-WslDevSetup` qui
        # déclencherait le vrai setup).
        $scriptContent = $script:InstallScriptRaw
        $scriptContent = $scriptContent -replace '(?m)^\s*Invoke-WslDevSetup\s*$', ''
        . ([scriptblock]::Create($scriptContent))
    }

    Context "Sortie EN réelle (celle de la machine de dev)" {

        BeforeAll {
            $fixture = @"
Voici la liste des distributions valides qui peuvent etre installees.
Installez a l'aide de 'wsl.exe --install <Distro>'.

NAME                            FRIENDLY NAME
Ubuntu                          Ubuntu
Ubuntu-26.04                    Ubuntu 26.04 LTS
Ubuntu-24.04                    Ubuntu 24.04 LTS
Ubuntu-22.04                    Ubuntu 22.04 LTS
openSUSE-Tumbleweed             openSUSE Tumbleweed
kali-linux                      Kali Linux Rolling
Debian                          Debian GNU/Linux
AlmaLinux-9                     AlmaLinux OS 9
archlinux                       Arch Linux
"@
            Mock Invoke-WslListOnline { return $fixture }
        }

        It "Détecte Ubuntu, Ubuntu-26.04, Debian, kali-linux" {
            $distros = Get-WslOnlineDistros
            $distros | Should -Contain 'Ubuntu'
            $distros | Should -Contain 'Ubuntu-26.04'
            $distros | Should -Contain 'Debian'
            $distros | Should -Contain 'kali-linux'
        }

        It "Détecte aussi les distros non-Ubuntu (Alma, Arch, openSUSE)" {
            $distros = Get-WslOnlineDistros
            $distros | Should -Contain 'openSUSE-Tumbleweed'
            $distros | Should -Contain 'AlmaLinux-9'
            $distros | Should -Contain 'archlinux'
        }

        It "Ne détecte PAS les lignes de prose FR" {
            $distros = Get-WslOnlineDistros
            $distros | Should -Not -Contain 'Voici'
            $distros | Should -Not -Contain 'Installez'
        }

        It "Ne détecte PAS l'en-tête de colonne NAME" {
            $distros = Get-WslOnlineDistros
            $distros | Should -Not -Contain 'NAME'
            $distros | Should -Not -Contain 'FRIENDLY'
        }
    }

    Context "Sortie FR pure (en-tête NOM/NOM CONVIVIAL)" {

        BeforeAll {
            $fixture = @"
Voici la liste des distributions valides qui peuvent etre installees.
Installez a l'aide de 'wsl.exe --install <Distro>'.

NOM                             NOM CONVIVIAL
Ubuntu                          Ubuntu
Ubuntu-26.04                    Ubuntu 26.04 LTS
Debian                          Debian GNU/Linux
kali-linux                      Kali Linux Rolling
"@
            Mock Invoke-WslListOnline { return $fixture }
        }

        It "Détecte les distros malgré l'en-tête localisé FR" {
            $distros = Get-WslOnlineDistros
            $distros | Should -Contain 'Ubuntu-26.04'
            $distros | Should -Contain 'Debian'
            $distros | Should -Contain 'kali-linux'
        }

        It "Ne détecte PAS l'en-tête FR (NOM, CONVIVIAL)" {
            $distros = Get-WslOnlineDistros
            $distros | Should -Not -Contain 'NOM'
            $distros | Should -Not -Contain 'CONVIVIAL'
        }
    }

    Context "Sortie vide (WSL non installé ou erreur)" {

        BeforeAll {
            Mock Invoke-WslListOnline { return '' }
        }

        It "Retourne un tableau vide" {
            $distros = Get-WslOnlineDistros
            $distros.Count | Should -Be 0
        }
    }

    Context "Sortie avec espaces simples entre colonnes (résilience)" {

        BeforeAll {
            # Cas dégénéré : si un jour WSL change de format et met un seul
            # espace, le parser doit rejeter (pattern exige 2+ espaces).
            # Ce test documente le comportement voulu : on préfère un faux
            # négatif (aucune distro) à un faux positif (parse la prose).
            $fixture = @"
NAME FRIENDLY NAME
Ubuntu Ubuntu
"@
            Mock Invoke-WslListOnline { return $fixture }
        }

        It "Ne détecte rien si les colonnes sont mal espacées" {
            $distros = Get-WslOnlineDistros
            $distros.Count | Should -Be 0
        }
    }
}
