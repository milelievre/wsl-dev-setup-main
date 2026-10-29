@{
    # Configuration PSScriptAnalyzer pour wsl-dev-setup.
    # Chargée explicitement par tests/run-tests.sh via
    # Invoke-ScriptAnalyzer -Settings tests/PSScriptAnalyzerSettings.psd1

    # Règles exclues (avec justification).
    ExcludeRules = @(
        # PSAvoidUsingWriteHost : justifié pour un script CLI interactif dont
        # le rôle est d'afficher des messages colorés à l'utilisateur.
        # Depuis PS 5+, Write-Host écrit sur le flux Information et n'est plus
        # bloquant. Write-Output polluerait le pipeline, Write-Information est
        # muet par défaut.
        'PSAvoidUsingWriteHost',

        # PSAvoidUsingInvokeExpression : justifié dans install.ps1, où
        # Invoke-Expression définit Test-Prerequisites dans le scope courant
        # depuis un contenu téléchargé (flux `irm | iex`, pas de fichier local
        # disponible). L'attribut inline SuppressMessageAttribute n'est pas
        # utilisable en top-level de script, on gère donc l'exclusion ici.
        'PSAvoidUsingInvokeExpression'
    )

    # Sévérités analysées (le script de test filtre ensuite ce qui est bloquant).
    Severity = @('Error', 'Warning', 'Information')
}
