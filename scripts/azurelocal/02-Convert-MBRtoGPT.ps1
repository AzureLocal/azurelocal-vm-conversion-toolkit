#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Converts MBR boot disk to GPT inside a running Windows Gen 1 VM (pre-conversion step).

.DESCRIPTION
    This script runs INSIDE the guest VM (Gen 1) to:
    - Validate the OS supports UEFI/Gen 2
    - Validate disk layout for mbr2gpt compatibility
    - Run mbr2gpt to convert the boot disk from MBR to GPT
    - Create a conversion readiness report

    IMPORTANT: Run this script inside the guest OS of each Gen 1 VM BEFORE
    running the Gen 2 conversion script. The VM should still be running as Gen 1
    when this script executes.

.PARAMETER ValidateOnly
    Only validate — do not perform the actual conversion.

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

# Ensure log directory exists
$logDir = Split-Path $LogPath -Parent
if (-not (Test-Path $logDir)) { New-Item -Path $logDir -ItemType Directory -Force | Out-Null }

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $entry = "[$timestamp] [$Level] $Message"
    Write-Host $entry -ForegroundColor $(switch ($Level) { "ERROR" { "Red" } "WARN" { "Yellow" } "SUCCESS" { "Green" } "FAIL" { "Red" } default { "Cyan" } })
    Add-Content -Path $LogPath -Value $entry
}

Write-Log "═══════════════════════════════════════════════════════════════"
Write-Log "  MBR → GPT Conversion Script (Runs Inside Guest VM)"
Write-Log "═══════════════════════════════════════════════════════════════"

# ── Step 1: System Validation ────────────────────────────────────────────────
Write-Log "Performing system validation checks..."

# Check OS architecture
$os = Get-CimInstance -ClassName Win32_OperatingSystem
$arch = (Get-CimInstance -ClassName Win32_Processor).AddressWidth
Write-Log "  OS: $($os.Caption) $($os.Version)"
Write-Log "  Architecture: ${arch}-bit"

if ($arch -ne 64) {
    Write-Log "FATAL: Gen 2 VMs require 64-bit OS. This system is ${arch}-bit." -Level "ERROR"
    throw "Cannot proceed: 32-bit OS detected."
}

# Check OS version (must be Server 2012 R2+ or Windows 8.1+)
$buildNumber = [int]$os.BuildNumber
$isServer = $os.Caption -match "Server"
Write-Log "  Build Number: $buildNumber"
Write-Log "  Is Server OS: $isServer"

if ($buildNumber -lt 9600) {
    Write-Log "FATAL: OS build $buildNumber is too old. Need Server 2012 R2+ / Win 8.1+ for Gen 2." -Level "ERROR"
    throw "OS version not supported for Gen 2."
}

# Check if mbr2gpt exists
$mbr2gptPath = "$env:SystemRoot\System32\mbr2gpt.exe"
if (-not (Test-Path $mbr2gptPath)) {
    Write-Log "FATAL: mbr2gpt.exe not found at $mbr2gptPath" -Level "ERROR"
    Write-Log "  mbr2gpt is available on Windows 10 1703+ and Server 2016+." -Level "ERROR"
    Write-Log "  For older OS, you will need to manually convert the disk." -Level "ERROR"
    throw "mbr2gpt.exe not available."
}

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

# Partition detail dump
Write-Log ""
Write-Log "── Partition Layout ──"
foreach ($part in $partitions) {
    Write-Log "  Partition $($part.PartitionNumber): Drive=$($part.DriveLetter) | Type=$($part.Type) | Size=$([math]::Round($part.Size / 1GB, 2))GB | Offset=$($part.Offset)"
}

# Check for BitLocker
Write-Log ""
Write-Log "Checking BitLocker status..."
try {
    $blStatus = Get-BitLockerVolume -MountPoint "C:" -ErrorAction SilentlyContinue
    if ($blStatus -and $blStatus.ProtectionStatus -eq "On") {
        Write-Log "WARNING: BitLocker is ENABLED on C:. Suspend BitLocker before conversion." -Level "WARN"
        Write-Log "  Run: Suspend-BitLocker -MountPoint 'C:' -RebootCount 0" -Level "WARN"

        if (-not $ValidateOnly) {
            Write-Log "Suspending BitLocker automatically..." -Level "WARN"
            Suspend-BitLocker -MountPoint "C:" -RebootCount 0
            Write-Log "  BitLocker suspended." -Level "SUCCESS"
        }
    }
    else {
        Write-Log "  BitLocker: Not active or not enabled" -Level "SUCCESS"
    }
}
catch {
    Write-Log "  BitLocker check skipped (not available on this OS edition)" -Level "INFO"
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
    Write-Log "  Common causes:" -Level "INFO"
    Write-Log "    - More than 3 primary partitions" -Level "INFO"
    Write-Log "    - Unrecognized partition types" -Level "INFO"
    Write-Log "    - Disk layout incompatible with UEFI boot" -Level "INFO"
    Write-Log "  Check C:\Windows\setupact.log for detailed mbr2gpt diagnostics." -Level "INFO"
    throw "mbr2gpt validation failed."
}

Write-Log "  Validation PASSED" -Level "SUCCESS"

# ── Step 3: Perform Conversion (if not validate-only) ───────────────────────
if ($ValidateOnly) {
    Write-Log ""
    Write-Log "═══════════════════════════════════════════════════════════════"
    Write-Log "  VALIDATE ONLY MODE — No changes were made."
    Write-Log "  This VM IS eligible for MBR → GPT conversion."
    Write-Log "  Re-run without -ValidateOnly to perform the conversion."
    Write-Log "═══════════════════════════════════════════════════════════════"
    exit 0
}

Write-Log ""
Write-Log "╔═══════════════════════════════════════════════════════════════╗"
Write-Log "║  PERFORMING MBR → GPT CONVERSION                            ║"
Write-Log "║  This modifies the boot disk partition table!                ║"
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

if ($convertResult.ExitCode -ne 0) {
    Write-Log "CONVERSION FAILED (Exit Code: $($convertResult.ExitCode))" -Level "FAIL"
    Write-Log "  The disk may be in an inconsistent state!" -Level "ERROR"
    Write-Log "  Check C:\Windows\setupact.log immediately." -Level "ERROR"
    throw "mbr2gpt conversion failed!"
}

Write-Log "  MBR → GPT conversion SUCCEEDED" -Level "SUCCESS"

# ── Step 4: Post-Conversion Verification ─────────────────────────────────────
Write-Log ""
Write-Log "Verifying conversion..."

# Refresh disk info
$bootDiskPost = Get-Disk | Where-Object { $_.IsBoot -eq $true }
Write-Log "  Partition Style: $($bootDiskPost.PartitionStyle)"

if ($bootDiskPost.PartitionStyle -eq "GPT") {
    Write-Log "  CONFIRMED: Boot disk is now GPT" -Level "SUCCESS"
}
else {
    Write-Log "  WARNING: Partition style still shows as $($bootDiskPost.PartitionStyle)" -Level "WARN"
    Write-Log "  This may require a reboot to refresh. The conversion log indicates success." -Level "WARN"
}

# Check for EFI System Partition
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
Write-Log ""
Write-Log "  ⚠️  DO NOT power on this VM as Gen 1 after conversion — it will fail to boot!"
Write-Log "═══════════════════════════════════════════════════════════════"
