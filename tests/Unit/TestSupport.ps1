# Shared helpers for the unit tests. Nothing here touches a VM, a cluster, Azure or a real disk layout:
# every Hyper-V, FailoverClusters, Storage, BitLocker and az command is a stub function that the tests mock.

$script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path

function Import-SafetyModule {
    Get-Module ConversionSafety | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module (Join-Path $script:RepoRoot 'scripts\common\ConversionSafety.psd1') -Force -ErrorAction Stop
}

$script:StubNames = @(
    'Get-VM', 'Get-VMReplication', 'Get-VMCheckpoint', 'Get-VMHardDiskDrive', 'Get-VHD', 'Get-VMNetworkAdapter', 'Get-VMNetworkAdapterVlan',
    'Get-ClusterGroup', 'Convert-VHD', 'Remove-ClusterGroup', 'Remove-VM', 'New-VM', 'Set-VMProcessor', 'Set-VMMemory',
    'Set-VMFirmware', 'Add-VMHardDiskDrive', 'Set-VMNetworkAdapterVlan', 'Set-VMNetworkAdapter', 'Add-VMNetworkAdapter',
    'Set-VM', 'New-HgsGuardian', 'New-HgsKeyProtector', 'Set-VMKeyProtector', 'Enable-VMTPM', 'Add-ClusterVirtualMachineRole',
    'Start-VM', 'Get-Disk', 'Get-Partition', 'Get-BitLockerVolume', 'Suspend-BitLocker', 'az'
)

function Install-ConversionStubs {
    foreach ($n in $script:StubNames) {
        if ($n -eq 'az') {
            # No param block: a mock of a native-style command reads $args.
            Set-Item -Path "Function:\global:az" -Value { }
            continue
        }
        # ValueFromRemainingArguments lets the stub accept any named parameters the scripts pass.
        Set-Item -Path "Function:\global:$n" -Value { param($Path, $Name, $VM, $VMName, [Parameter(ValueFromRemainingArguments)]$Rest) }
    }
}

function Uninstall-ConversionStubs {
    foreach ($n in $script:StubNames) { Remove-Item "Function:\global:$n" -ErrorAction SilentlyContinue }
}

function Resolve-ScriptCopy {
    <#
    Returns the path of a copy of a repository script that can run on a build agent:
    #Requires lines are dropped (no Hyper-V, no elevation there), $PSScriptRoot points at the real folder,
    and the Import-Module of the safety module is dropped because the test imports it already (a re-import
    would throw away the mocks).
    #>
    param([Parameter(Mandatory)][string]$RelativePath)
    $src = Join-Path $script:RepoRoot $RelativePath
    $dir = Split-Path $src -Parent
    $text = [IO.File]::ReadAllText($src)
    $text = [regex]::Replace($text, '(?m)^#Requires .*\r?\n', '')
    $text = [regex]::Replace($text, '(?m)^Import-Module \(Join-Path \$PSScriptRoot .*ConversionSafety.*\r?\n', '')
    $text = $text.Replace('$PSScriptRoot', "'" + $dir.Replace("'", "''") + "'")
    $out = Join-Path ([IO.Path]::GetTempPath()) ('copy-' + [guid]::NewGuid().ToString('N') + '-' + (Split-Path $src -Leaf))
    [IO.File]::WriteAllText($out, $text, [Text.UTF8Encoding]::new($true))
    return $out
}

function Initialize-TestDisk {
    param([Parameter(Mandatory)][string]$Directory, [string]$Name = 'os.vhdx', [int]$Bytes = 4096)
    if (-not (Test-Path $Directory)) { New-Item -Path $Directory -ItemType Directory -Force | Out-Null }
    $p = Join-Path $Directory $Name
    $buf = [byte[]]::new($Bytes)
    [Random]::new(42).NextBytes($buf)
    [IO.File]::WriteAllBytes($p, $buf)
    return $p
}
