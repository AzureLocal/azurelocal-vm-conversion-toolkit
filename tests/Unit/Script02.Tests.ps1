#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

# Script 02 runs inside the guest. Disk, BitLocker, CIM and mbr2gpt.exe are all mocked: no disk is converted.

BeforeAll {
    . $PSScriptRoot/TestSupport.ps1
    Install-ConversionStubs
    Import-SafetyModule
    $script:Root = Join-Path ([IO.Path]::GetTempPath()) ('s02-' + [guid]::NewGuid().ToString('N'))
    New-Item $script:Root -ItemType Directory | Out-Null
    $script:RealSystemRoot = $env:SystemRoot

    function script:Initialize-Guest {
        param([string]$Caption = 'Microsoft Windows Server 2019 Standard', [int]$Build = 17763, [bool]$HasMbr2Gpt = $true)
        $global:T_Journal = [System.Collections.Generic.List[string]]::new()
        $global:T_Caption = $Caption; $global:T_Build = $Build
        $global:T_BitLocker = [pscustomobject]@{ VolumeStatus = 'FullyDecrypted'; ProtectionStatus = 'Off' }
        $global:T_BitLockerAfterSuspend = $null      # when set, what Get-BitLockerVolume returns after Suspend-BitLocker
        $global:T_BitLockerThrows = $false
        $global:T_ValidateExit = 0; $global:T_ConvertExit = 0
        $sys = Join-Path $script:Root ([guid]::NewGuid().ToString('N'))
        New-Item (Join-Path $sys 'System32') -ItemType Directory -Force | Out-Null
        if ($HasMbr2Gpt) { [IO.File]::WriteAllBytes((Join-Path $sys 'System32\mbr2gpt.exe'), [byte[]](1..32)) }
        $env:SystemRoot = $sys
        $script:Log = Join-Path $sys 'log\run.log'
    }

    function script:Install-Mocks {
        Mock Write-Host {}
        Mock Get-CimInstance {
            if ($ClassName -eq 'Win32_OperatingSystem') { [pscustomobject]@{ Caption = $global:T_Caption; Version = "10.0.$($global:T_Build)"; BuildNumber = "$($global:T_Build)" } }
            else { [pscustomobject]@{ AddressWidth = 64 } }
        }
        Mock Get-Disk { [pscustomobject]@{ Number = 0; IsBoot = $true; PartitionStyle = 'MBR'; Size = 60GB } }
        Mock Get-Partition { @([pscustomobject]@{ PartitionNumber = 1; DriveLetter = 'C'; Type = 'IFS'; Size = 59GB; Offset = 1MB; GptType = $null }) }
        Mock Get-BitLockerVolume {
            if ($global:T_BitLockerThrows) { throw 'access denied' }
            if ($global:T_BitLockerAfterSuspend -and $global:T_Journal.Contains('Suspend-BitLocker')) { $global:T_BitLockerAfterSuspend } else { $global:T_BitLocker }
        }
        Mock Suspend-BitLocker { $global:T_Journal.Add('Suspend-BitLocker') }
        Mock Start-Process {
            $mode = if ("$ArgumentList" -match '/convert') { 'convert' } else { 'validate' }
            $global:T_Journal.Add("mbr2gpt $mode")
            [pscustomobject]@{ ExitCode = $(if ($mode -eq 'convert') { $global:T_ConvertExit } else { $global:T_ValidateExit }) }
        }
    }

    function script:Invoke-Script02 {
        param([string]$Path, [hashtable]$Extra = @{})
        $p = @{ LogPath = $script:Log; Confirm = $false } + $Extra
        & $Path @p
    }
}

AfterAll {
    $env:SystemRoot = $script:RealSystemRoot
    Uninstall-ConversionStubs
    Get-Module ConversionSafety | Remove-Module -Force
    Remove-Item $script:Root -Recurse -Force -ErrorAction SilentlyContinue
}

Describe 'Script 02 (<variant>)' -ForEach @(
    @{ variant = 'hyperv'; rel = 'scripts\hyperv\02-Convert-MBRtoGPT.ps1' }
    @{ variant = 'azurelocal'; rel = 'scripts\azurelocal\02-Convert-MBRtoGPT.ps1' }
) {
    BeforeAll { $script:Copy = Resolve-ScriptCopy -RelativePath $rel }
    AfterAll { Remove-Item $script:Copy -ErrorAction SilentlyContinue }
    AfterEach { $env:SystemRoot = $script:RealSystemRoot }
    BeforeEach { Initialize-Guest; Install-Mocks }

    Context 'OS gate' {
        It 'refuses <caption> (build <build>) and never calls mbr2gpt' -ForEach @(
            @{ caption = 'Microsoft Windows Server 2016 Standard'; build = 14393 }
            @{ caption = 'Microsoft Windows Server 2012 R2 Standard'; build = 9600 }
            @{ caption = 'Microsoft Windows 8.1 Pro'; build = 9600 }
        ) {
            Initialize-Guest -Caption $caption -Build $build
            { Invoke-Script02 -Path $script:Copy } | Should -Throw '*not supported*'
            $global:T_Journal | Should -BeNullOrEmpty
        }
        It 'accepts Windows Server 2019 and Windows 10 1703' -ForEach @(
            @{ caption = 'Microsoft Windows Server 2019 Standard'; build = 17763 }
            @{ caption = 'Microsoft Windows 10 Pro'; build = 15063 }
        ) {
            Initialize-Guest -Caption $caption -Build $build
            { Invoke-Script02 -Path $script:Copy -Extra @{ ValidateOnly = $true } } | Should -Not -Throw
            $global:T_Journal | Should -Contain 'mbr2gpt validate'
        }
        It 'refuses a supported build when mbr2gpt.exe is not actually there' {
            Initialize-Guest -HasMbr2Gpt $false
            { Invoke-Script02 -Path $script:Copy } | Should -Throw '*mbr2gpt.exe not available*'
            $global:T_Journal | Should -BeNullOrEmpty
        }
        It 'the error text names Windows Server 2019 and Windows 10 1703, not 2012 R2 or 2016+' {
            $t = Get-Content (Join-Path $script:RepoRoot $rel) -Raw
            $t | Should -Match '2019'
            $t | Should -Match '1703'
            $t | Should -Not -Match '2012 R2'
            $t | Should -Not -Match 'Server 2016\+'
        }
    }

    Context 'BitLocker' {
        It 'suspends protection (RebootCount 0), re-checks, then converts' {
            $global:T_BitLocker = [pscustomobject]@{ VolumeStatus = 'FullyEncrypted'; ProtectionStatus = 'On' }
            $global:T_BitLockerAfterSuspend = [pscustomobject]@{ VolumeStatus = 'FullyEncrypted'; ProtectionStatus = 'Off' }
            Invoke-Script02 -Path $script:Copy
            Should -Invoke Suspend-BitLocker -Times 1 -ParameterFilter { "$Rest" -match '-RebootCount 0' }
            $global:T_Journal.IndexOf('Suspend-BitLocker') | Should -BeLessThan $global:T_Journal.IndexOf('mbr2gpt convert')
        }
        It 'does not convert when protection is still on after the suspend attempt' {
            $global:T_BitLocker = [pscustomobject]@{ VolumeStatus = 'FullyEncrypted'; ProtectionStatus = 'On' }
            $global:T_BitLockerAfterSuspend = $null
            { Invoke-Script02 -Path $script:Copy } | Should -Throw '*not suspended*'
            $global:T_Journal | Should -Not -Contain 'mbr2gpt convert'
        }
        It 'does not suspend or convert in -ValidateOnly, and says protection is on' {
            $global:T_BitLocker = [pscustomobject]@{ VolumeStatus = 'FullyEncrypted'; ProtectionStatus = 'On' }
            Invoke-Script02 -Path $script:Copy -Extra @{ ValidateOnly = $true }
            $global:T_Journal | Should -Not -Contain 'Suspend-BitLocker'
            $global:T_Journal | Should -Not -Contain 'mbr2gpt convert'
            Should -Invoke Write-Host -ParameterFilter { "$Object" -match 'BitLocker protection is ON' }
        }
        It 'converts an already suspended volume without suspending again' {
            $global:T_BitLocker = [pscustomobject]@{ VolumeStatus = 'FullyEncrypted'; ProtectionStatus = 'Off' }
            Invoke-Script02 -Path $script:Copy
            $global:T_Journal | Should -Not -Contain 'Suspend-BitLocker'
            $global:T_Journal | Should -Contain 'mbr2gpt convert'
        }
        It 'refuses to convert when the BitLocker state cannot be read' {
            $global:T_BitLockerThrows = $true
            { Invoke-Script02 -Path $script:Copy } | Should -Throw '*BitLocker state unknown*'
            $global:T_Journal | Should -Not -Contain 'mbr2gpt convert'
        }
    }

    Context 'validation and conversion' {
        It 'does not convert when mbr2gpt /validate fails' {
            $global:T_ValidateExit = 7
            { Invoke-Script02 -Path $script:Copy } | Should -Throw '*validation failed*'
            $global:T_Journal | Should -Not -Contain 'mbr2gpt convert'
        }
        It 'treats convert exit code 100 as a warning, not a failure' {
            $global:T_ConvertExit = 100
            { Invoke-Script02 -Path $script:Copy } | Should -Not -Throw
            Should -Invoke Write-Host -ParameterFilter { "$Object" -match 'CONVERTED WITH WARNINGS' }
        }
        It 'throws on any other convert failure' {
            $global:T_ConvertExit = 9
            { Invoke-Script02 -Path $script:Copy } | Should -Throw '*conversion failed*'
        }
        It '-ValidateOnly runs /validate only' {
            Invoke-Script02 -Path $script:Copy -Extra @{ ValidateOnly = $true }
            $global:T_Journal | Should -Be @('mbr2gpt validate')
        }
        It '-WhatIf never runs /convert' {
            Invoke-Script02 -Path $script:Copy -Extra @{ WhatIf = $true }
            $global:T_Journal | Should -Not -Contain 'mbr2gpt convert'
        }
    }
}
