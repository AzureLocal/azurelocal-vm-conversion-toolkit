#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Converts the MBR boot disk to GPT inside a running Windows Gen 1 VM (pre-conversion step).

.DESCRIPTION
    This script runs INSIDE the guest VM (Gen 1) to:
    - Confirm the guest OS ships mbr2gpt.exe and that the file is actually present
    - Validate the disk layout for mbr2gpt
    - Make sure BitLocker protection is suspended (MBR2GPT only converts BitLocker volumes while it is)
    - Run mbr2gpt to convert the boot disk from MBR to GPT

    OS support (Microsoft Learn, mbr2gpt): mbr2gpt.exe is in the box on Windows 10 version 1703
    (build 15063) and later and on Windows Server 2019 (build 17763) and later. Windows Server 2016
    does not include it. Offline conversion of Windows 7, 8 and 8.1 is not supported: upgrade the
    guest first. https://learn.microsoft.com/windows/deployment/mbr-to-gpt

    IMPORTANT: Run this script inside the guest OS of each Gen 1 VM BEFORE running the Gen 2
    conversion script, and take a backup or checkpoint-free copy of the VM first. The conversion
    cannot be undone. The VM should still be running as Gen 1 when this script executes.

    After conversion, BitLocker protectors must be deleted and recreated before protection is resumed.

.PARAMETER ValidateOnly
    Only validate. Nothing is changed (BitLocker is not suspended either).

.PARAMETER LogPath
    Path to write the log file. Defaults to C:\Temp\MBR2GPT_Conversion.log

.EXAMPLE
    # Validate only (dry run)
    .\02-Convert-MBRtoGPT.ps1 -ValidateOnly

    # Perform the conversion
    .\02-Convert-MBRtoGPT.ps1
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [Parameter()]
    [switch]$ValidateOnly,

    [Parameter()]
    [string]$LogPath = "C:\Temp\MBR2GPT_Conversion.log"
)

$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot '..\common\ConversionSafety.psd1') -Force -ErrorAction Stop

# Ensure log directory exists
$logDir = Split-Path $LogPath -Parent
if (-not (Test-Path $logDir)) { New-Item -Path $logDir -ItemType Directory -Force -WhatIf:$false | Out-Null }

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $entry = "[$timestamp] [$Level] $Message"
    Write-Host $entry -ForegroundColor $(switch ($Level) { "ERROR" { "Red" } "WARN" { "Yellow" } "SUCCESS" { "Green" } "FAIL" { "Red" } default { "Cyan" } })
    Add-Content -Path $LogPath -Value $entry -WhatIf:$false
}

Write-Log "═══════════════════════════════════════════════════════════════"
Write-Log "  MBR → GPT Conversion Script (Runs Inside Guest VM)"
Write-Log "═══════════════════════════════════════════════════════════════"

# ── Step 1: System Validation ────────────────────────────────────────────────
Write-Log "Performing system validation checks..."

$os = Get-CimInstance -ClassName Win32_OperatingSystem
$arch = (Get-CimInstance -ClassName Win32_Processor | Select-Object -First 1).AddressWidth
$buildNumber = [int]$os.BuildNumber
Write-Log "  OS: $($os.Caption) $($os.Version)"
Write-Log "  Build Number: $buildNumber"
Write-Log "  Architecture: ${arch}-bit"

# OS gate: mbr2gpt.exe is in the box on Windows 10 1703+ (build 15063) and Windows Server 2019+ (build 17763).
$support = Test-Mbr2GptOsSupport -Caption $os.Caption -BuildNumber $buildNumber -AddressWidth $arch
if (-not $support.Supported) {
    Write-Log "FATAL: $($support.Reason)" -Level "ERROR"
    throw "OS not supported for in-guest MBR to GPT conversion."
}
Write-Log "  $($support.Reason)" -Level "SUCCESS"

# The file must really be there; the build number alone is not proof.
$mbr2gptPath = Get-Mbr2GptPath
if (-not (Test-Mbr2GptAvailable -Path $mbr2gptPath)) {
    Write-Log "FATAL: mbr2gpt.exe not found at $mbr2gptPath" -Level "ERROR"
    Write-Log "  It ships with Windows 10 1703+ and Windows Server 2019+. Repair or upgrade the guest, then retry." -Level "ERROR"
    throw "mbr2gpt.exe not available."
}
Write-Log "  mbr2gpt.exe present: $mbr2gptPath" -Level "SUCCESS"

# Check current partition style
$bootDisk = Get-Disk | Where-Object { $_.IsBoot -eq $true }
Write-Log "  Boot Disk Number: $($bootDisk.Number)"
Write-Log "  Partition Style:  $($bootDisk.PartitionStyle)"
Write-Log "  Disk Size:        $([math]::Round($bootDisk.Size / 1GB, 2)) GB"

if ($bootDisk.PartitionStyle -eq "GPT") {
    Write-Log "Boot disk is ALREADY GPT. No conversion needed!" -Level "SUCCESS"
    Write-Log "  This VM may already be ready for Gen 2 conversion."
    exit 0
}

if ($bootDisk.PartitionStyle -ne "MBR") {
    Write-Log "Unexpected partition style: $($bootDisk.PartitionStyle)" -Level "ERROR"
    throw "Cannot proceed with unexpected partition style."
}

# Check partition count (mbr2gpt supports max 3 primary partitions)
$partitions = Get-Partition -DiskNumber $bootDisk.Number
$primaryPartitions = $partitions | Where-Object { $_.Type -ne "Reserved" -and $_.Type -ne "Unknown" }
Write-Log "  Total Partitions:   $($partitions.Count)"
Write-Log "  Primary Partitions: $($primaryPartitions.Count)"

if ($primaryPartitions.Count -gt 3) {
    Write-Log "WARNING: mbr2gpt requires 3 or fewer primary partitions. Found $($primaryPartitions.Count)." -Level "ERROR"
    Write-Log "  You may need to manually merge or delete partitions before conversion." -Level "ERROR"
    throw "Too many primary partitions for mbr2gpt."
}

Write-Log ""
Write-Log "── Partition Layout ──"
foreach ($part in $partitions) {
    Write-Log "  Partition $($part.PartitionNumber): Drive=$($part.DriveLetter) | Type=$($part.Type) | Size=$([math]::Round($part.Size / 1GB, 2))GB | Offset=$($part.Offset)"
}

# ── BitLocker: protection must be suspended before MBR2GPT ──────────────────
Write-Log ""
Write-Log "Checking BitLocker status on $env:SystemDrive ..."
$blVolume = $null
if (Get-Command Get-BitLockerVolume -ErrorAction SilentlyContinue) {
    try { $blVolume = Get-BitLockerVolume -MountPoint $env:SystemDrive -ErrorAction Stop }
    catch { Write-Log "Could not read BitLocker state: $_" -Level "ERROR"; throw "BitLocker state unknown; refusing to convert." }
    $bl = Get-BitLockerConversionState -Volume $blVolume
}
else {
    # No BitLocker cmdlets means the feature is not installed, so the volume cannot be BitLocker-encrypted.
    $bl = [pscustomobject]@{ State = 'NotEncrypted'; Ready = $true }
    Write-Log "  BitLocker cmdlets not present on this OS; treating the volume as not encrypted." -Level "INFO"
}
Write-Log "  BitLocker state: $($bl.State)"

if ($bl.State -eq 'Unknown') {
    throw "BitLocker state of $env:SystemDrive could not be determined; refusing to convert."
}
if (-not $bl.Ready) {
    # Protected
    if ($ValidateOnly) {
        Write-Log "  BitLocker protection is ON. The real run would suspend it first (Suspend-BitLocker -RebootCount 0)." -Level "WARN"
    }
    else {
        Write-Log "  BitLocker protection is ON; MBR2GPT only converts while it is suspended." -Level "WARN"
        if (-not $PSCmdlet.ShouldProcess("BitLocker on $env:SystemDrive", "Suspend protection (RebootCount 0) so mbr2gpt can run")) {
            Write-Log "BitLocker suspension declined. Nothing was changed." -Level "WARN"
            exit 1
        }
        Suspend-BitLocker -MountPoint $env:SystemDrive -RebootCount 0
        $bl = Get-BitLockerConversionState -Volume (Get-BitLockerVolume -MountPoint $env:SystemDrive)
        if (-not $bl.Ready) {
            Write-Log "BitLocker protection is still $($bl.State) after Suspend-BitLocker." -Level "ERROR"
            throw "BitLocker is not suspended; refusing to convert."
        }
        Write-Log "  BitLocker suspended (verified)." -Level "SUCCESS"
    }
}

# ── Step 2: mbr2gpt Validation ──────────────────────────────────────────────
Write-Log ""
Write-Log "Running mbr2gpt /validate..."

$validateArgs = "/validate /disk:$($bootDisk.Number) /allowfullos"
Write-Log "  Command: mbr2gpt.exe $validateArgs"

$validateResult = Start-Process -FilePath $mbr2gptPath -ArgumentList $validateArgs -Wait -PassThru -NoNewWindow -RedirectStandardOutput "$logDir\mbr2gpt_validate_stdout.txt" -RedirectStandardError "$logDir\mbr2gpt_validate_stderr.txt"

$stdout = Get-Content "$logDir\mbr2gpt_validate_stdout.txt" -Raw -ErrorAction SilentlyContinue
$stderr = Get-Content "$logDir\mbr2gpt_validate_stderr.txt" -Raw -ErrorAction SilentlyContinue

if ($stdout) { Write-Log "  stdout: $stdout" }
if ($stderr) { Write-Log "  stderr: $stderr" -Level "WARN" }

# mbr2gpt also logs to C:\Windows\setupact.log and C:\Windows\setuperr.log
$mbr2gptLog = "$env:SystemRoot\setupact.log"
if (Test-Path $mbr2gptLog) {
    $recentEntries = Get-Content $mbr2gptLog -Tail 30 | Where-Object { $_ -match "MBR2GPT" }
    if ($recentEntries) {
        Write-Log "  mbr2gpt log entries:"
        $recentEntries | ForEach-Object { Write-Log "    $_" }
    }
}

if ($validateResult.ExitCode -ne 0) {
    Write-Log "VALIDATION FAILED (Exit Code: $($validateResult.ExitCode))" -Level "FAIL"
    if ($validateResult.ExitCode -eq 6) {
        Write-Log "  Exit code 6: a volume on the disk is encrypted. Suspend BitLocker protection and retry." -Level "INFO"
    }
    Write-Log "  Common causes:" -Level "INFO"
    Write-Log "    - More than 3 primary partitions, or an extended/logical partition" -Level "INFO"
    Write-Log "    - Unrecognized partition types" -Level "INFO"
    Write-Log "    - Not enough unallocated space for the GPT structures" -Level "INFO"
    Write-Log "  Check C:\Windows\setupact.log for detailed mbr2gpt diagnostics." -Level "INFO"
    throw "mbr2gpt validation failed."
}

Write-Log "  Validation PASSED" -Level "SUCCESS"

# ── Step 3: Perform Conversion (if not validate-only) ───────────────────────
if ($ValidateOnly) {
    Write-Log ""
    Write-Log "═══════════════════════════════════════════════════════════════"
    Write-Log "  VALIDATE ONLY MODE — No changes were made."
    if ($bl.Ready) {
        Write-Log "  This VM IS eligible for MBR → GPT conversion."
    }
    else {
        Write-Log "  Layout is eligible, but BitLocker protection is ON and must be suspended first."
    }
    Write-Log "  Re-run without -ValidateOnly to perform the conversion."
    Write-Log "═══════════════════════════════════════════════════════════════"
    exit 0
}

Write-Log ""
Write-Log "╔═══════════════════════════════════════════════════════════════╗"
Write-Log "║  PERFORMING MBR → GPT CONVERSION                            ║"
Write-Log "║  This modifies the boot disk partition table and cannot be   ║"
Write-Log "║  undone. Make sure the VM has been backed up.                ║"
Write-Log "╚═══════════════════════════════════════════════════════════════╝"

if (-not $PSCmdlet.ShouldProcess("Boot Disk $($bootDisk.Number)", "Convert MBR to GPT")) {
    Write-Log "Conversion cancelled by user." -Level "WARN"
    exit 1
}

$convertArgs = "/convert /disk:$($bootDisk.Number) /allowfullos"
Write-Log "  Command: mbr2gpt.exe $convertArgs"

$convertResult = Start-Process -FilePath $mbr2gptPath -ArgumentList $convertArgs -Wait -PassThru -NoNewWindow -RedirectStandardOutput "$logDir\mbr2gpt_convert_stdout.txt" -RedirectStandardError "$logDir\mbr2gpt_convert_stderr.txt"

$stdout = Get-Content "$logDir\mbr2gpt_convert_stdout.txt" -Raw -ErrorAction SilentlyContinue
$stderr = Get-Content "$logDir\mbr2gpt_convert_stderr.txt" -Raw -ErrorAction SilentlyContinue

if ($stdout) { Write-Log "  stdout: $stdout" }
if ($stderr) { Write-Log "  stderr: $stderr" -Level "WARN" }

if ($convertResult.ExitCode -eq 100) {
    Write-Log "CONVERTED WITH WARNINGS (Exit Code 100): the layout is GPT but some boot configuration entries could not be restored." -Level "WARN"
    Write-Log "  Check C:\Windows\setupact.log and verify the boot entries before powering the VM off." -Level "WARN"
}
elseif ($convertResult.ExitCode -ne 0) {
    Write-Log "CONVERSION FAILED (Exit Code: $($convertResult.ExitCode))" -Level "FAIL"
    Write-Log "  The disk may be in an inconsistent state!" -Level "ERROR"
    Write-Log "  Check C:\Windows\setupact.log immediately." -Level "ERROR"
    throw "mbr2gpt conversion failed!"
}
else {
    Write-Log "  MBR → GPT conversion SUCCEEDED" -Level "SUCCESS"
}

# ── Step 4: Post-Conversion Verification ─────────────────────────────────────
Write-Log ""
Write-Log "Verifying conversion..."

$bootDiskPost = Get-Disk | Where-Object { $_.IsBoot -eq $true }
Write-Log "  Partition Style: $($bootDiskPost.PartitionStyle)"

if ($bootDiskPost.PartitionStyle -eq "GPT") {
    Write-Log "  CONFIRMED: Boot disk is now GPT" -Level "SUCCESS"
}
else {
    Write-Log "  WARNING: Partition style still shows as $($bootDiskPost.PartitionStyle)" -Level "WARN"
    Write-Log "  This may require a reboot to refresh. The conversion log indicates success." -Level "WARN"
}

$efiPartition = Get-Partition -DiskNumber $bootDiskPost.Number | Where-Object { $_.GptType -eq "{c12a7328-f81f-11d2-ba4b-00a0c93ec93b}" }
if ($efiPartition) {
    Write-Log "  EFI System Partition found: Partition $($efiPartition.PartitionNumber), Size: $([math]::Round($efiPartition.Size / 1MB, 0))MB" -Level "SUCCESS"
}
else {
    Write-Log "  WARNING: EFI System Partition not detected (may need reboot to appear)" -Level "WARN"
}

# ── Summary ──────────────────────────────────────────────────────────────────
Write-Log ""
Write-Log "═══════════════════════════════════════════════════════════════"
Write-Log "  MBR → GPT Conversion Complete!"
Write-Log "═══════════════════════════════════════════════════════════════"
Write-Log "  IMPORTANT NEXT STEPS:"
Write-Log "  1. SHUT DOWN this VM (do NOT reboot — it won't boot as Gen 1 with GPT)"
Write-Log "  2. Run 03-Convert-Gen1toGen2.ps1 on the Hyper-V host / Azure Local node"
Write-Log "     to recreate this VM as Gen 2"
Write-Log "  3. If BitLocker was used: delete and recreate the protectors before resuming protection"
Write-Log ""
Write-Log "  ⚠️  DO NOT power on this VM as Gen 1 after conversion — it will fail to boot!"
Write-Log "═══════════════════════════════════════════════════════════════"
