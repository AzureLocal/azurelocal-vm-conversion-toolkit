@{
    RootModule        = 'ConversionSafety.psm1'
    ModuleVersion     = '0.1.0'   # x-release-please-version
    GUID              = '5b0e9f0e-3a43-4c63-9a53-0d6f6a8d7c21'
    Author            = 'Azure Local Cloud'
    CompanyName       = 'Azure Local Cloud'
    Copyright         = '(c) 2026 Azure Local Cloud. All rights reserved.'
    Description       = 'Safety gates shared by the Gen 1 to Gen 2 conversion scripts: mbr2gpt OS and availability checks, BitLocker state, backup policy and backup verification.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @(
        'Test-Mbr2GptOsSupport', 'Get-Mbr2GptPath', 'Test-Mbr2GptAvailable', 'Get-BitLockerConversionState',
        'Assert-BackupPolicy', 'Get-VhdChain', 'Get-PathFreeBytes', 'Test-FileIntegrity',
        'Copy-VhdChainWithVerification', 'Assert-VerifiedBackup'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
}
