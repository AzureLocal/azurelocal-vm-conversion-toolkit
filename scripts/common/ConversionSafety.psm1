<#
.SYNOPSIS
    Safety gates shared by the Gen 1 to Gen 2 conversion scripts (02 and 03, Hyper-V and Azure Local paths).
.DESCRIPTION
    Pure functions that decide "is it safe to continue". They are kept out of the scripts so Pester can test
    them with mocks. Nothing here deletes or changes a VM, a disk or a cluster resource, and the copy helper
    never overwrites an existing file.
#>

#region MBR2GPT availability

# Learn (https://learn.microsoft.com/windows/deployment/mbr-to-gpt): mbr2gpt.exe is in the box on supported
# Windows client (Windows 10 1703 = build 15063 and later) and Windows Server 2019 (build 17763) and later.
# Windows Server 2016 does not include it. Offline conversion of Windows 7, 8 and 8.1 is not supported.
$script:MinClientBuild = 15063
$script:MinServerBuild = 17763

function Test-Mbr2GptOsSupport {
    <#
    .SYNOPSIS
        Decides from the OS caption, build number and bitness whether mbr2gpt.exe can be expected in the guest.
    .OUTPUTS
        PSCustomObject with Supported (bool) and Reason (string).
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$Caption,
        [Parameter(Mandatory)][int]$BuildNumber,
        [int]$AddressWidth = 64
    )

    $isServer = $Caption -match 'Server'

    if ($AddressWidth -ne 64) {
        return [pscustomobject]@{ Supported = $false; Reason = "Gen 2 needs a 64-bit OS; this one is ${AddressWidth}-bit." }
    }
    if ($isServer -and $BuildNumber -lt $script:MinServerBuild) {
        $name = if ($BuildNumber -eq 14393) { 'Windows Server 2016 does not include mbr2gpt.exe.' } else { "Server build $BuildNumber predates Windows Server 2019 and does not include mbr2gpt.exe." }
        return [pscustomobject]@{ Supported = $false; Reason = "$name Windows Server 2019 or later is required. Upgrade the guest first, then convert." }
    }
    if (-not $isServer -and $BuildNumber -lt $script:MinClientBuild) {
        $name = if ($BuildNumber -lt 10240) { 'Offline conversion of Windows 7, 8 and 8.1 is not supported.' } else { "Windows 10 build $BuildNumber predates version 1703." }
        return [pscustomobject]@{ Supported = $false; Reason = "$name Windows 10 1703 (build $script:MinClientBuild) or later is required. Upgrade the guest first, then convert." }
    }
    [pscustomobject]@{ Supported = $true; Reason = "Build $BuildNumber ($Caption) ships mbr2gpt.exe." }
}

function Get-Mbr2GptPath {
    <# Returns the expected path of mbr2gpt.exe, using Sysnative when a 32-bit host runs on 64-bit Windows. #>
    [CmdletBinding()]
    [OutputType([string])]
    param([string]$SystemRoot = $env:SystemRoot)
    $dir = 'System32'
    if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) { $dir = 'Sysnative' }
    [IO.Path]::Combine($SystemRoot, $dir, 'mbr2gpt.exe')
}

function Test-Mbr2GptAvailable {
    <# True only when the file is really there and not empty. The build number alone is not proof. #>
    [CmdletBinding()]
    [OutputType([bool])]
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
    return ((Get-Item -LiteralPath $Path).Length -gt 0)
}

#endregion

#region BitLocker

function Get-BitLockerConversionState {
    <#
    .SYNOPSIS
        Classifies a Get-BitLockerVolume result for MBR2GPT.
    .DESCRIPTION
        MBR2GPT converts BitLocker volumes only while protection is suspended
        (Learn: "as long as protection is suspended"). Ready is true for NotEncrypted and Suspended only.
    .OUTPUTS
        PSCustomObject with State (NotEncrypted, Suspended, Protected, Unknown) and Ready (bool).
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param($Volume)

    if ($null -eq $Volume) { return [pscustomobject]@{ State = 'Unknown'; Ready = $false } }
    $vs = "$($Volume.VolumeStatus)"
    $ps = "$($Volume.ProtectionStatus)"
    if ($vs -eq 'FullyDecrypted') { return [pscustomobject]@{ State = 'NotEncrypted'; Ready = $true } }
    # Protection can read Off while encryption or decryption is still running or paused; that is not safe to convert.
    if ($vs -match 'InProgress|Paused') { return [pscustomobject]@{ State = 'InProgress'; Ready = $false } }
    switch ($ps) {
        'Off'   { return [pscustomobject]@{ State = 'Suspended'; Ready = $true } }
        '0'     { return [pscustomobject]@{ State = 'Suspended'; Ready = $true } }
        'On'    { return [pscustomobject]@{ State = 'Protected'; Ready = $false } }
        '1'     { return [pscustomobject]@{ State = 'Protected'; Ready = $false } }
        default { return [pscustomobject]@{ State = 'Unknown'; Ready = $false } }
    }
}

#endregion

#region Backup policy and verification

function Assert-BackupPolicy {
    <#
    .SYNOPSIS
        Refuses to continue without a backup unless the operator explicitly accepted that risk.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][bool]$BackupVHDX,
        [switch]$IUnderstandNoBackup
    )
    if (-not $BackupVHDX -and -not $IUnderstandNoBackup) {
        throw "-BackupVHDX:`$false removes the only safety net before the VM is deleted. Add -IUnderstandNoBackup to proceed without a backup, or keep the backup."
    }
}

function Get-VhdChain {
    <#
    .SYNOPSIS
        Returns the file and every parent of a differencing disk (leaf first).
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param([Parameter(Mandatory)][string]$Path)

    $chain = [System.Collections.Generic.List[string]]::new()
    $current = $Path
    while ($current) {
        if ($chain.Contains($current)) { throw "Loop in the parent chain at '$current'." }
        $chain.Add($current)
        $vhd = Get-VHD -Path $current -ErrorAction Stop
        $current = if ($vhd.ParentPath) { $vhd.ParentPath } else { $null }
    }
    return , $chain.ToArray()
}

function Get-PathFreeBytes {
    <# Free bytes on the volume that holds $Path, mount points (cluster shared volumes) included. #>
    [CmdletBinding()]
    [OutputType([long])]
    param([Parameter(Mandatory)][string]$Path)
    $full = [IO.Path]::GetFullPath($Path)
    $vol = Get-CimInstance -ClassName Win32_Volume |
        Where-Object { $_.Name -and $full.StartsWith($_.Name, [StringComparison]::OrdinalIgnoreCase) } |
        Sort-Object { $_.Name.Length } -Descending | Select-Object -First 1
    if (-not $vol) { throw "Could not find the volume that holds '$Path'." }
    return [long]$vol.FreeSpace
}

function Test-FileIntegrity {
    <#
    .SYNOPSIS
        Compares a copy with its source by size and SHA256.
    .OUTPUTS
        PSCustomObject: Ok, Reason, Source, Destination, SourceSize, DestinationSize, SourceHash, DestinationHash.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Destination
    )
    $r = [ordered]@{ Ok = $false; Reason = ''; Source = $Source; Destination = $Destination
                     SourceSize = $null; DestinationSize = $null; SourceHash = $null; DestinationHash = $null }
    if (-not (Test-Path -LiteralPath $Source -PathType Leaf)) { $r.Reason = 'source file is missing'; return [pscustomobject]$r }
    if (-not (Test-Path -LiteralPath $Destination -PathType Leaf)) { $r.Reason = 'copy is missing'; return [pscustomobject]$r }
    $r.SourceSize = (Get-Item -LiteralPath $Source).Length
    $r.DestinationSize = (Get-Item -LiteralPath $Destination).Length
    if ($r.SourceSize -ne $r.DestinationSize) { $r.Reason = "size differs ($($r.SourceSize) vs $($r.DestinationSize) bytes)"; return [pscustomobject]$r }
    if ($r.SourceSize -eq 0) { $r.Reason = 'source file is empty'; return [pscustomobject]$r }
    $r.SourceHash = (Get-FileHash -LiteralPath $Source -Algorithm SHA256 -ErrorAction Stop).Hash
    $r.DestinationHash = (Get-FileHash -LiteralPath $Destination -Algorithm SHA256 -ErrorAction Stop).Hash
    if (-not $r.SourceHash -or -not $r.DestinationHash) { $r.Reason = 'could not compute a SHA256'; return [pscustomobject]$r }
    if ($r.SourceHash -ne $r.DestinationHash) { $r.Reason = 'SHA256 differs'; return [pscustomobject]$r }
    $r.Ok = $true
    $r.Reason = 'size and SHA256 match'
    [pscustomobject]$r
}

function Copy-VhdChainWithVerification {
    <#
    .SYNOPSIS
        Copies every file of each disk chain into a new folder and verifies each copy (size and SHA256).
    .DESCRIPTION
        Checks free space first, never overwrites an existing file, never touches the source, and throws on
        the first copy that does not verify. The return value is the proof the conversion script requires
        before it removes anything.
    .OUTPUTS
        One verification record per copied file (see Test-FileIntegrity).
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject[]])]
    param(
        [Parameter(Mandatory)][string[]]$DiskPath,
        [Parameter(Mandatory)][string]$DestinationDirectory,
        [Parameter(Mandatory)][scriptblock]$Log
    )

    $files = [System.Collections.Generic.List[string]]::new()
    foreach ($d in $DiskPath) {
        foreach ($f in (Get-VhdChain -Path $d)) { if (-not $files.Contains($f)) { $files.Add($f) } }
    }

    $needed = ($files | ForEach-Object { (Get-Item -LiteralPath $_).Length } | Measure-Object -Sum).Sum
    if (-not (Test-Path -LiteralPath $DestinationDirectory)) { New-Item -Path $DestinationDirectory -ItemType Directory -Force | Out-Null }
    $free = Get-PathFreeBytes -Path $DestinationDirectory
    if ($free -lt ($needed * 1.05)) {
        throw ("Not enough free space for the backup: need about {0:N1} GB, {1:N1} GB free on the destination volume. Nothing was copied." -f ($needed / 1GB), ($free / 1GB))
    }

    $records = [System.Collections.Generic.List[object]]::new()
    $names = @{}
    foreach ($f in $files) {
        $leaf = Split-Path $f -Leaf
        # Two disks can share a file name in different folders; keep both.
        if ($names.ContainsKey($leaf)) { $leaf = '{0}_{1}' -f ($names[$leaf]++), $leaf } else { $names[$leaf] = 1 }
        $dest = Join-Path $DestinationDirectory $leaf
        if (Test-Path -LiteralPath $dest) { throw "Backup target '$dest' already exists; refusing to overwrite it." }
        & $Log "  Backing up: $f -> $dest"
        Copy-Item -LiteralPath $f -Destination $dest -ErrorAction Stop
        & $Log "  Verifying (size and SHA256)..."
        $check = Test-FileIntegrity -Source $f -Destination $dest
        if (-not $check.Ok) { throw "Backup of '$f' did not verify: $($check.Reason). The source was not touched; remove '$dest' and fix the cause." }
        & $Log ("    Verified: {0:N2} GB, SHA256 {1}" -f ($check.SourceSize / 1GB), $check.SourceHash)
        $records.Add($check)
    }
    return , $records.ToArray()
}

function Assert-VerifiedBackup {
    <#
    .SYNOPSIS
        Throws unless every file of every disk has a verified backup record. Call it directly before any removal.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$DiskPath,
        [AllowNull()][object[]]$Record
    )
    if (@($DiskPath).Count -eq 0) { throw 'No disks were supplied to check; refusing to remove the VM.' }
    # Trust the proof only while the copy it describes is still there.
    $ok = @($Record | Where-Object { $_ -and $_.Ok -and $_.Destination -and (Test-Path -LiteralPath $_.Destination -PathType Leaf) })
    if ($ok.Count -eq 0) { throw 'No verified backup exists. Refusing to remove the VM.' }
    foreach ($d in $DiskPath) {
        foreach ($f in (Get-VhdChain -Path $d)) {
            if (-not ($ok | Where-Object { $_.Source -eq $f })) { throw "No verified backup of '$f'. Refusing to remove the VM." }
        }
    }
}

#endregion

Export-ModuleMember -Function Test-Mbr2GptOsSupport, Get-Mbr2GptPath, Test-Mbr2GptAvailable, Get-BitLockerConversionState,
    Assert-BackupPolicy, Get-VhdChain, Get-PathFreeBytes, Test-FileIntegrity, Copy-VhdChainWithVerification, Assert-VerifiedBackup
