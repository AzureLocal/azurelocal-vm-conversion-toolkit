#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

# Script 03 removes the Gen 1 VM. These tests prove the safety order: no verified backup, no removal.
# Hyper-V, FailoverClusters and the file copy are mocked or run against small temp files; no VM exists.

BeforeAll {
    . $PSScriptRoot/TestSupport.ps1
    Install-ConversionStubs
    Import-SafetyModule
    $script:Root = Join-Path ([IO.Path]::GetTempPath()) ('s03-' + [guid]::NewGuid().ToString('N'))
    New-Item $script:Root -ItemType Directory | Out-Null

    function script:Initialize-Scenario {
        $global:T_Journal = [System.Collections.Generic.List[string]]::new()
        $global:T_Gen = 1; $global:T_State = 'Off'; $global:T_Checkpoints = @(); $global:T_Nics = 1; $global:T_Clustered = $true
        $global:T_NewVmFails = $false; $global:T_ClusterRemoveFails = $false; $global:T_Replication = $null
        $script:Work = Join-Path $script:Root ([guid]::NewGuid().ToString('N'))
        $script:DiskDir = Join-Path $script:Work 'disks'
        $script:Boot = Initialize-TestDisk -Directory $script:DiskDir -Name 'os.vhdx' -Bytes 6000
        $script:Data = Initialize-TestDisk -Directory $script:DiskDir -Name 'data.vhdx' -Bytes 3000
        $global:T_Disks = @(
            [pscustomobject]@{ Path = $script:Boot; ControllerType = 'IDE'; ControllerNumber = 0; ControllerLocation = 0 }
            [pscustomobject]@{ Path = $script:Data; ControllerType = 'SCSI'; ControllerNumber = 0; ControllerLocation = 1 }
        )
        New-Item (Join-Path $script:Work 'Logs') -ItemType Directory -Force | Out-Null
    }

    function script:Install-Mocks {
        Mock Write-Host {}
        Mock Start-Sleep {}
        Mock Get-VM {
            [pscustomobject]@{ Name = 'VM1'; State = $global:T_State; Generation = $global:T_Gen; ComputerName = 'node01'
                ProcessorCount = 2; MemoryStartup = 2GB; MemoryMinimum = 1GB; MemoryMaximum = 4GB; DynamicMemoryEnabled = $false
                AutomaticStartAction = 'Nothing'; AutomaticStopAction = 'Save'; AutomaticStartDelay = 0; Notes = ''
                Heartbeat = 'OkApplicationsHealthy'; MemoryAssigned = 2GB }
        }
        Mock Get-VMCheckpoint { $global:T_Checkpoints }
        Mock Get-VMHardDiskDrive { $global:T_Disks }
        Mock Get-VHD { [pscustomobject]@{ VhdFormat = 'VHDX'; Size = 10GB; ParentPath = $null } }
        Mock Get-VHD { [pscustomobject]@{ VhdFormat = 'VHDX'; Size = 10GB; ParentPath = $null } } -ModuleName ConversionSafety
        Mock Get-PathFreeBytes { [long]100GB } -ModuleName ConversionSafety
        Mock Get-VMNetworkAdapter {
            @(1..$global:T_Nics | ForEach-Object { [pscustomobject]@{ Name = "NIC$_"; SwitchName = 'ConvergedSwitch'; MacAddress = '00155D000001'; IsLegacy = $false } })
        }
        Mock Get-VMNetworkAdapterVlan { [pscustomobject]@{ AccessVlanId = 0 } }
        Mock Get-ClusterGroup { if ($global:T_Clustered) { [pscustomobject]@{ Name = 'VM1'; State = 'Online'; OwnerNode = 'node01' } } }
        Mock Remove-ClusterGroup {
            if ($global:T_ClusterRemoveFails) { throw 'cluster busy' }
            $global:T_Journal.Add('Remove-ClusterGroup'); $global:T_Clustered = $false
        }
        Mock Get-VMReplication { $global:T_Replication }
        Mock Remove-VM { $global:T_Journal.Add('Remove-VM') }
        Mock Remove-Item { $global:T_Journal.Add('Remove-Item') }
        Mock Convert-VHD { $global:T_Journal.Add('Convert-VHD') }
        Mock New-VM {
            $global:T_Journal.Add('New-VM')
            if ($global:T_NewVmFails) { throw 'simulated New-VM failure' }
            [pscustomobject]@{ Name = 'VM1' }
        }
        Mock Set-VMProcessor {}; Mock Set-VMMemory {}; Mock Set-VMFirmware {}; Mock Add-VMHardDiskDrive {}
        Mock Set-VMNetworkAdapterVlan {}; Mock Set-VMNetworkAdapter {}; Mock Add-VMNetworkAdapter {}; Mock Set-VM {}
        Mock New-HgsGuardian {}; Mock New-HgsKeyProtector {}; Mock Set-VMKeyProtector {}; Mock Enable-VMTPM {}
        Mock Add-ClusterVirtualMachineRole { $global:T_Journal.Add('Add-ClusterVirtualMachineRole') }
        Mock Start-VM { $global:T_Journal.Add('Start-VM') }
    }

    function script:Invoke-Script03 {
        param([string]$Path, [hashtable]$Extra = @{})
        $p = @{ VMName = 'VM1'; WorkingDirectory = $script:Work; Confirm = $false } + $Extra
        # Only the Azure Local variant takes the Azure parameters.
        if ($Path -match 'azurelocal' -or $script:Variant -eq 'azurelocal') { $p.ResourceGroup = 'rg-example'; $p.SubscriptionId = '00000000-0000-0000-0000-000000000000' }
        & $Path @p
    }
}

AfterAll {
    Uninstall-ConversionStubs
    Get-Module ConversionSafety | Remove-Module -Force
    Remove-Item $script:Root -Recurse -Force -ErrorAction SilentlyContinue
}

Describe 'Script 03 (<variant>)' -ForEach @(
    @{ variant = 'hyperv'; rel = 'scripts\hyperv\03-Convert-Gen1toGen2.ps1' }
    @{ variant = 'azurelocal'; rel = 'scripts\azurelocal\03-Convert-Gen1toGen2.ps1' }
) {
    BeforeAll { $script:Copy = Resolve-ScriptCopy -RelativePath $rel; $script:Variant = $variant }
    AfterAll { Remove-Item $script:Copy -ErrorAction SilentlyContinue }
    BeforeEach { Initialize-Scenario; Install-Mocks }

    Context 'backup policy' {
        It 'refuses -BackupVHDX:$false without -IUnderstandNoBackup, before touching anything' {
            { Invoke-Script03 -Path $script:Copy -Extra @{ BackupVHDX = $false } } | Should -Throw '*-IUnderstandNoBackup*'
            Should -Invoke Get-VM -Times 0
            $global:T_Journal | Should -BeNullOrEmpty
        }
        It 'allows no backup with the acknowledgement, makes no backup folder, and warns' {
            Invoke-Script03 -Path $script:Copy -Extra @{ BackupVHDX = $false; IUnderstandNoBackup = $true }
            $global:T_Journal | Should -Contain 'Remove-VM'
            Test-Path (Join-Path $script:Work 'Backups') | Should -BeFalse
            Should -Invoke Write-Host -ParameterFilter { "$Object" -match 'NO BACKUP' }
        }
    }

    Context 'backup verification gates the removal' {
        It 'copies and verifies every disk, and only then removes the VM (cluster group first)' {
            Invoke-Script03 -Path $script:Copy
            $bk = Get-ChildItem (Join-Path $script:Work 'Backups\VM1') -Directory
            $bk.Count | Should -Be 1
            (Get-ChildItem $bk.FullName).Name | Should -Contain 'os.vhdx'
            (Get-FileHash (Join-Path $bk.FullName 'os.vhdx')).Hash | Should -Be (Get-FileHash $script:Boot).Hash
            $global:T_Journal.IndexOf('Remove-ClusterGroup') | Should -BeLessThan $global:T_Journal.IndexOf('Remove-VM')
            $global:T_Journal.IndexOf('Remove-VM') | Should -BeLessThan $global:T_Journal.IndexOf('New-VM')
            $global:T_Journal | Should -Not -Contain 'Remove-Item'
            (Test-Path $script:Boot) | Should -BeTrue
        }
        It 'does NOT remove the cluster group or the VM when a copy is corrupt' {
            Mock Copy-Item { [IO.File]::WriteAllBytes($Destination, [byte[]]::new(7)) } -ModuleName ConversionSafety
            { Invoke-Script03 -Path $script:Copy } | Should -Throw '*did not verify*'
            $global:T_Journal | Should -BeNullOrEmpty
            (Test-Path $script:Boot) | Should -BeTrue
        }
        It 'does NOT remove anything when the destination volume is too small' {
            Mock Get-PathFreeBytes { [long]1000 } -ModuleName ConversionSafety
            { Invoke-Script03 -Path $script:Copy } | Should -Throw '*Not enough free space*'
            $global:T_Journal | Should -BeNullOrEmpty
        }
        It 'does NOT remove anything when the final backup gate finds a file without a verified record' {
            # The script calls the exported function from outside the module, so mock it where the script sees it.
            Mock Copy-VhdChainWithVerification { , @() }
            { Invoke-Script03 -Path $script:Copy } | Should -Throw '*No verified backup*'
            $global:T_Journal | Should -BeNullOrEmpty
        }
    }

    Context 'pre-removal checks' {
        It 'exits without changes for a VM that is already Gen 2' {
            $global:T_Gen = 2
            Invoke-Script03 -Path $script:Copy
            $global:T_Journal | Should -BeNullOrEmpty
            Test-Path (Join-Path $script:Work 'Backups') | Should -BeFalse
        }
        It 'refuses a VM that is not Off' {
            $global:T_State = 'Running'
            { Invoke-Script03 -Path $script:Copy } | Should -Throw '*not shut down*'
            $global:T_Journal | Should -BeNullOrEmpty
        }
        It 'refuses a VM with checkpoints' {
            $global:T_Checkpoints = @([pscustomobject]@{ Name = 'cp'; CreationTime = Get-Date })
            { Invoke-Script03 -Path $script:Copy } | Should -Throw '*checkpoint*'
            $global:T_Journal | Should -BeNullOrEmpty
        }
        It 'refuses a VM with no network adapter before removing it' {
            $global:T_Nics = 0
            Mock Get-VMNetworkAdapter { @() }
            { Invoke-Script03 -Path $script:Copy } | Should -Throw '*no network adapter*'
            $global:T_Journal | Should -BeNullOrEmpty
            Test-Path (Join-Path $script:Work 'Backups') | Should -BeFalse
        }
    }

    Context 'more guards before anything is removed' {
        It 'stops, and removes the VM from nothing, when the cluster group cannot be removed' {
            $global:T_ClusterRemoveFails = $true
            { Invoke-Script03 -Path $script:Copy } | Should -Throw '*Could not remove cluster group*'
            $global:T_Journal | Should -Not -Contain 'Remove-VM'
            (Test-Path $script:Boot) | Should -BeTrue
        }
        It 'refuses a VM with Hyper-V Replica enabled' {
            $global:T_Replication = [pscustomobject]@{ ReplicationState = 'Replicating' }
            { Invoke-Script03 -Path $script:Copy } | Should -Throw '*Replica*'
            $global:T_Journal | Should -BeNullOrEmpty
        }
        It 'refuses a pass-through disk' {
            $global:T_Disks = @([pscustomobject]@{ Path = ''; DiskNumber = 3; ControllerType = 'SCSI'; ControllerNumber = 0; ControllerLocation = 0 })
            { Invoke-Script03 -Path $script:Copy } | Should -Throw '*pass-through*'
            $global:T_Journal | Should -BeNullOrEmpty
        }
        It 'refuses a shared disk / VHD Set' {
            $global:T_Disks = @([pscustomobject]@{ Path = (Join-Path $script:DiskDir 'set.vhds'); SupportPersistentReservations = $true; ControllerType = 'SCSI'; ControllerNumber = 0; ControllerLocation = 0 })
            { Invoke-Script03 -Path $script:Copy } | Should -Throw '*shared disk*'
            $global:T_Journal | Should -BeNullOrEmpty
        }
    }

    Context '-WhatIf' {
        It 'copies nothing, converts nothing and removes nothing' {
            Invoke-Script03 -Path $script:Copy -Extra @{ WhatIf = $true }
            $global:T_Journal | Should -BeNullOrEmpty
            Test-Path (Join-Path $script:Work 'Backups') | Should -BeFalse
        }
    }

    Context 'failure after the VM is removed' {
        It 'rethrows, prints where the disks and the verified backup are, and deletes no file' {
            $global:T_NewVmFails = $true
            { Invoke-Script03 -Path $script:Copy } | Should -Throw '*simulated New-VM failure*'
            Should -Invoke Write-Host -ParameterFilter { "$Object" -match 'STOPPED AFTER THE GEN 1 VM WAS REMOVED' }
            Should -Invoke Write-Host -ParameterFilter { "$Object" -match 'Verified backup' }
            $global:T_Journal | Should -Not -Contain 'Remove-Item'
            (Test-Path $script:Boot) | Should -BeTrue
            (Test-Path $script:Data) | Should -BeTrue
        }
    }

    Context 'source ordering (static)' {
        It 'puts the backup gate before any removal in the script text' {
            $t = Get-Content (Join-Path $script:RepoRoot $rel) -Raw
            $t.IndexOf('Assert-VerifiedBackup') | Should -BeGreaterThan 0
            $t.IndexOf('Assert-VerifiedBackup') | Should -BeLessThan $t.IndexOf('Remove-ClusterGroup -Name')
            $t.IndexOf('Remove-ClusterGroup -Name') | Should -BeLessThan $t.IndexOf('Remove-VM -Name')
        }
        It 'is a High-impact ShouldProcess script with -IUnderstandNoBackup' {
            $ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $script:RepoRoot $rel), [ref]$null, [ref]$null)
            $names = $ast.ParamBlock.Parameters.Name.VariablePath.UserPath
            $names | Should -Contain 'IUnderstandNoBackup'
            $attr = $ast.ParamBlock.Attributes | Where-Object TypeName -Like 'CmdletBinding'
            ($attr.NamedArguments | Where-Object ArgumentName -eq 'ConfirmImpact').Argument.Value | Should -Be 'High'
        }
    }
}
