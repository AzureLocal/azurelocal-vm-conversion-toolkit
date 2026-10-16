#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    . $PSScriptRoot/TestSupport.ps1
    Install-ConversionStubs
    Import-SafetyModule
    $script:Copy05 = Resolve-ScriptCopy -RelativePath 'scripts\azurelocal\05-Reconnect-AzureLocalVM.ps1'

    function script:Install-Mocks {
        $global:T_Az = [System.Collections.Generic.List[string]]::new()
        $global:T_AzFail = @()
        $global:T_Gen = 2
        Mock Write-Host {}
        Mock Get-Module { [pscustomobject]@{ Name = 'Hyper-V' } } -ParameterFilter { $ListAvailable }
        Mock Get-VM { [pscustomobject]@{ Name = 'VM1'; Generation = $global:T_Gen; State = 'Running' } }
        Mock az {
            $cmd = ($args | ForEach-Object { "$_" }) -join ' '
            $global:T_Az.Add($cmd)
            $global:LASTEXITCODE = 0
            foreach ($rx in $global:T_AzFail) { if ($cmd -match $rx) { $global:LASTEXITCODE = 1; return 'ERROR: simulated' } }
            if ($cmd -match 'network nic create') { return '{"id":"/nics/nic-VM1","provisioningState":"Succeeded"}' }
            if ($cmd -match 'reconnect-to-azure --help') { return 'Command usage' }
            return '{"id":"/vms/VM1"}'
        }
    }
    function script:Invoke-05 {
        param([hashtable]$Extra = @{})
        $p = @{ VMName = 'VM1'; ResourceGroup = 'rg-example'; SubscriptionId = '00000000-0000-0000-0000-000000000000'
                CustomLocationId = '/subscriptions/s/customLocations/cl-example'; LogicalNetworkId = '/subscriptions/s/logicalNetworks/lnet-example'; Confirm = $false } + $Extra
        & $script:Copy05 @p
    }
}
AfterAll {
    Remove-Item $script:Copy05 -ErrorAction SilentlyContinue
    Uninstall-ConversionStubs
    Get-Module ConversionSafety | Remove-Module -Force
}

Describe 'Script 05 reconnect (azurelocal)' {
    BeforeEach { Install-Mocks }

    It 'creates the NIC and then reconnects with the expected arguments' {
        Invoke-05
        $nic = @($global:T_Az | Where-Object { $_ -match 'network nic create' })
        $rc = @($global:T_Az | Where-Object { $_ -match '^stack-hci-vm reconnect-to-azure ' -and $_ -notmatch '--help' })
        $nic.Count | Should -Be 1
        $rc.Count | Should -Be 1
        $nic[0] | Should -Match '--name nic-VM1'
        $nic[0] | Should -Match '--subnet-id /subscriptions/s/logicalNetworks/lnet-example'
        $rc[0] | Should -Match '--name VM1'
        $rc[0] | Should -Match '--local-vm-name VM1'
        $rc[0] | Should -Match '--nics /nics/nic-VM1'
        $rc[0] | Should -Match '--custom-location /subscriptions/s/customLocations/cl-example'
        $rc[0] | Should -Not -Match '--yes'
        $global:T_Az.IndexOf($nic[0]) | Should -BeLessThan $global:T_Az.IndexOf($rc[0])
    }
    It 'uses -AzureVMName for the Azure resource and the NIC name' {
        Invoke-05 -Extra @{ AzureVMName = 'web-01' }
        (@($global:T_Az | Where-Object { $_ -match 'network nic create' })[0]) | Should -Match '--name nic-web-01'
        (@($global:T_Az | Where-Object { $_ -match '^stack-hci-vm reconnect-to-azure --name web-01' })).Count | Should -Be 1
    }
    It 'refuses a Gen 1 VM before any Azure change' {
        $global:T_Gen = 1
        Invoke-05
        @($global:T_Az | Where-Object { $_ -match 'nic create|reconnect-to-azure ' -and $_ -notmatch '--help' }).Count | Should -Be 0
    }
    It 'refuses when reconnect-to-azure is missing from the extension (extension too old)' {
        Mock az {
            $cmd = ($args | ForEach-Object { "$_" }) -join ' '
            $global:T_Az.Add($cmd); $global:LASTEXITCODE = 0
            if ($cmd -match 'reconnect-to-azure --help') { $global:LASTEXITCODE = 2; return "'reconnect-to-azure' is not in the 'az stack-hci-vm' command group" }
            return '{}'
        }
        Invoke-05
        @($global:T_Az | Where-Object { $_ -match 'nic create' }).Count | Should -Be 0
    }
    It 'does not reconnect when NIC creation fails' {
        $global:T_AzFail = @('network nic create')
        { Invoke-05 } | Should -Throw '*nic create*failed*'
        @($global:T_Az | Where-Object { $_ -match '^stack-hci-vm reconnect-to-azure ' -and $_ -notmatch '--help' }).Count | Should -Be 0
    }
    It 'creates and reconnects nothing under -WhatIf' {
        Invoke-05 -Extra @{ WhatIf = $true }
        @($global:T_Az | Where-Object { $_ -match 'nic create|^stack-hci-vm reconnect-to-azure ' -and $_ -notmatch '--help' }).Count | Should -Be 0
    }
    It 'carries the work-in-progress warning and the no-copy explanation' {
        $t = Get-Content (Join-Path $script:RepoRoot 'scripts\azurelocal\05-Reconnect-AzureLocalVM.ps1') -Raw
        $t | Should -Match 'WORK IN PROGRESS'
        $t | Should -Match 'unsupported operation'
    }
}

Describe 'Batch script 04 calls its siblings with parameters they have' -ForEach @(
    @{ variant = 'azurelocal' }
    @{ variant = 'hyperv' }
) {
    BeforeAll {
        function script:Get-ParamNames([string]$Path) {
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$null, [ref]$null)
            $ast.ParamBlock.Parameters.Name.VariablePath.UserPath
        }
        $script:Dir = Join-Path $script:RepoRoot "scripts\$variant"
        $script:Batch = Get-Content (Join-Path $script:Dir '04-Batch-ConvertVMs.ps1') -Raw
        # Common parameters every cmdlet-bound script accepts.
        $script:Common = 'Confirm', 'WhatIf', 'Verbose', 'Debug', 'ErrorAction'
    }
    It 'every key splatted into script 03 is a parameter of script 03' {
        $m = [regex]::Match($script:Batch, '\$params = @\{(?<b>.*?)\n\s*\}', 'Singleline')
        $keys = [regex]::Matches($m.Groups['b'].Value, '(?m)^\s*(\w+)\s*=') | ForEach-Object { $_.Groups[1].Value }
        $keys.Count | Should -BeGreaterThan 3
        $allowed = (Get-ParamNames (Join-Path $script:Dir '03-Convert-Gen1toGen2.ps1')) + $script:Common
        foreach ($k in $keys) { $allowed | Should -Contain $k }
    }
    It 'every key splatted into script 05 (azurelocal only) is a parameter of script 05' -Skip:($variant -ne 'azurelocal') {
        $m = [regex]::Match($script:Batch, '\$reconnectParams = @\{(?<b>.*?)\n\s*\}', 'Singleline')
        $keys = [regex]::Matches($m.Groups['b'].Value, '(?m)^\s*(\w+)\s*=') | ForEach-Object { $_.Groups[1].Value }
        $allowed = (Get-ParamNames (Join-Path $script:Dir '05-Reconnect-AzureLocalVM.ps1')) + $script:Common
        foreach ($k in $keys) { $allowed | Should -Contain $k }
    }
    It 'always asks script 03 for a backup' {
        $script:Batch | Should -Match 'BackupVHDX\s*=\s*\$true'
    }
}
