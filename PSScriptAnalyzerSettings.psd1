@{
    # PSScriptAnalyzer settings for azurelocal-vm-conversion-toolkit.
    # Usage: Invoke-ScriptAnalyzer -Path ./Modules -Recurse -Settings ./PSScriptAnalyzerSettings.psd1
    # Error and Warning findings fail CI (tests/Invoke-Checks.ps1). Information findings are listed only.
    Severity            = @('Error', 'Warning', 'Information')
    IncludeDefaultRules = $true
    IncludeRules        = @(
        'PSUseShouldProcessForStateChangingFunctions'
        'PSAvoidUsingPlainTextForPassword'
        'PSAvoidUsingConvertToSecureStringWithPlainText'
        'PSAvoidUsingInvokeExpression'
        'PSUseCompatibleSyntax'
        'PSUseDeclaredVarsMoreThanAssignments'
    )
    # Excluded on purpose:
    #   PSAvoidUsingWriteHost: the commands are interactive admin tools that print a coloured progress
    #     log for the operator. Nothing is returned through Write-Host; results go to the pipeline.
    #   PSUseBOMForUnicodeEncodedFile: the repository standard (.editorconfig) is UTF-8 without BOM.
    # Unit tests are analysed with PSAvoidGlobalVars also excluded (mock bodies run in another scope and
    # share scenario state through globals); tests/Invoke-Checks.ps1 applies that for tests/ only.
    # The scripts under scripts/ target Windows PowerShell 5.1 inside guests, so the syntax check is 5.1.
    ExcludeRules        = @('PSAvoidUsingWriteHost', 'PSUseBOMForUnicodeEncodedFile')
    Rules               = @{
        PSUseCompatibleSyntax = @{
            Enable         = $true
            TargetVersions = @('5.1', '7.0')
        }
    }
}
