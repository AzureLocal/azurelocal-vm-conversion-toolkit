#Requires -RunAsAdministrator
#Requires -Modules Hyper-V, FailoverClusters

<#
.SYNOPSIS
    Converts a Gen 1 VM to Gen 2 on a Hyper-V failover cluster.

.DESCRIPTION
    This script runs on a Hyper-V cluster node and:
    1. Exports the Gen 1 VM configuration (NICs, memory, CPU, disks, etc.)
    2. Backs up the VHDX files
    3. Removes the Gen 1 VM from the cluster and Hyper-V (preserving VHDXs)
    4. Creates a new Gen 2 VM with the same configuration
    5. Attaches the existing VHDX disks (already converted to GPT via Script 02)
    6. Adds the VM back to the failover cluster
    7. Starts the VM and validates the boot

    No Azure connectivity, Arc registration, or Azure resource management is performed.
    This script is for the Hyper-V path only. If you need the VM managed in the Azure
    portal, use the Azure Local path (scripts/azurelocal/).

    PREREQUISITES:
    - Script 01 has been run (environment setup, config exports exist)
    - Script 02 has been run inside the guest (MBR → GPT conversion done)
    - The VM is SHUT DOWN

.PARAMETER VMName
    Name of the VM to convert.

.PARAMETER WorkingDirectory
    Path to the conversion working directory (created by Script 01).

.PARAMETER BackupVHDX
    Copy every disk file (and any parent of a differencing disk) to Backups\<VM>\<timestamp> before the VM
    is removed, and verify each copy by size and SHA256. The VM is NOT removed unless every file verified.
    Default: $true. Setting it to $false is refused unless -IUnderstandNoBackup is also given.

.PARAMETER SecureBootTemplate
    Secure Boot template for the new Gen 2 VM. Default MicrosoftWindows. Linux guests usually need
    MicrosoftUEFICertificateAuthority; a wrong template means the VM does not boot.

.PARAMETER IUnderstandNoBackup
    Required together with -BackupVHDX:$false. Removing the VM without a verified copy of its disks is
    your decision and your risk.

.EXAMPLE
    .\03-Convert-Gen1toGen2.ps1 `
        -VMName "WebServer01" `
        -WorkingDirectory "C:\ClusterStorage\Volume01\Gen2Conversion"
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory = $true)]
    [string]$VMName,

    [Parameter(Mandatory = $true)]
    [string]$WorkingDirectory,

    [Parameter()]
    [bool]$BackupVHDX = $true,

    [Parameter()]
    [ValidateSet('MicrosoftWindows', 'MicrosoftUEFICertificateAuthority', 'OpenSourceShieldedVM')]
    [string]$SecureBootTemplate = 'MicrosoftWindows',

    [Parameter()]
    [switch]$IUnderstandNoBackup
)

# ── Global Settings ──────────────────────────────────────────────────────────
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot '..\common\ConversionSafety.psd1') -Force -ErrorAction Stop

# Refuse to run without a backup unless the operator explicitly accepted that.
Assert-BackupPolicy -BackupVHDX $BackupVHDX -IUnderstandNoBackup:$IUnderstandNoBackup
$LogFile = Join-Path $WorkingDirectory "Logs\Gen2Convert_${VMName}_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
$logDirectory = Split-Path $LogFile -Parent
if (-not (Test-Path $logDirectory)) { New-Item -Path $logDirectory -ItemType Directory -Force -WhatIf:$false | Out-Null }
$backupDir = $null

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $entry = "[$timestamp] [$Level] $Message"
    Write-Host $entry -ForegroundColor $(switch ($Level) { "ERROR" { "Red" } "WARN" { "Yellow" } "SUCCESS" { "Green" } default { "Cyan" } })
    Add-Content -Path $LogFile -Value $entry -WhatIf:$false
}

Write-Log "═══════════════════════════════════════════════════════════════"
Write-Log "  Hyper-V Gen 1 → Gen 2 VM Conversion"
Write-Log "  VM: $VMName"
Write-Log "═══════════════════════════════════════════════════════════════"

# ── Step 1: Load and Validate VM Configuration ──────────────────────────────
Write-Log "Step 1: Loading VM configuration..."

# Check for config file from Script 01
$configPath = Join-Path $WorkingDirectory "Configs\${VMName}_config.json"
if (Test-Path $configPath) {
    $null = Get-Content $configPath -Raw | ConvertFrom-Json   # fails early if the saved config is corrupt
    Write-Log "  Loaded saved config from: $configPath" -Level "SUCCESS"
}

# Get live VM state
$vm = Get-VM -Name $VMName -ErrorAction Stop
Write-Log "  VM State:   $($vm.State)"
Write-Log "  Generation: $($vm.Generation)"
Write-Log "  Host:       $($vm.ComputerName)"

if ($vm.Generation -ne 1) {
    Write-Log "VM '$VMName' is already Generation $($vm.Generation). Nothing to do." -Level "WARN"
    exit 0
}

if ($vm.State -ne 'Off') {
    Write-Log "VM must be in 'Off' state. Current state: $($vm.State)" -Level "ERROR"
    Write-Log "  Please shut down the VM first (after running Script 02 inside the guest)." -Level "ERROR"
    throw "VM is not shut down."
}

# Check for checkpoints
$checkpoints = Get-VMCheckpoint -VM $vm
if ($checkpoints.Count -gt 0) {
    Write-Log "VM has $($checkpoints.Count) checkpoint(s). These MUST be removed before conversion." -Level "ERROR"
    $checkpoints | ForEach-Object { Write-Log "    - $($_.Name) (Created: $($_.CreationTime))" -Level "ERROR" }
    throw "Remove all checkpoints before proceeding."
}

# Replica, shared and pass-through disks cannot be rebuilt safely by this script.
$vmId = $vm.Id
$replication = Get-VMReplication -VMName $VMName -ErrorAction SilentlyContinue
if ($replication -and "$($replication.ReplicationState)" -notin @('', 'Disabled')) {
    throw "VM '$VMName' has Hyper-V Replica enabled (state $($replication.ReplicationState)). Remove the replication relationship first; nothing was changed."
}

# ── Step 2: Capture Full VM Configuration ────────────────────────────────────
Write-Log ""
Write-Log "Step 2: Capturing VM configuration..."

# Processor
$processorCount = $vm.ProcessorCount
Write-Log "  Processors: $processorCount"

# Memory
$memoryStartup = $vm.MemoryStartup
$memoryMin = $vm.MemoryMinimum
$memoryMax = $vm.MemoryMaximum
$dynamicMemory = $vm.DynamicMemoryEnabled
Write-Log "  Memory Startup: $($memoryStartup / 1MB) MB"
Write-Log "  Dynamic Memory: $dynamicMemory"
if ($dynamicMemory) {
    Write-Log "  Memory Min: $($memoryMin / 1MB) MB | Max: $($memoryMax / 1MB) MB"
}

# Hard disks
$hardDisks = Get-VMHardDiskDrive -VM $vm
$diskDetails = @()
foreach ($disk in $hardDisks) {
    if ($null -ne $disk.DiskNumber -or -not $disk.Path) {
        throw "VM '$VMName' has a pass-through (physical) disk attached. It cannot be copied or rebuilt by this script. Nothing was changed."
    }
    if ($disk.Path -match '\.vhds$' -or $disk.SupportPersistentReservations) {
        throw "VM '$VMName' uses a shared disk or VHD Set ($($disk.Path)). Other VMs may depend on it; this script refuses to continue. Nothing was changed."
    }
    $vhd = Get-VHD -Path $disk.Path -ErrorAction SilentlyContinue
    $detail = [PSCustomObject]@{
        Path               = $disk.Path
        ControllerType     = $disk.ControllerType.ToString()
        ControllerNumber   = $disk.ControllerNumber
        ControllerLocation = $disk.ControllerLocation
        VhdFormat          = if ($vhd) { $vhd.VhdFormat.ToString() } else { "Unknown" }
        SizeGB             = if ($vhd) { [math]::Round($vhd.Size / 1GB, 2) } else { 0 }
    }
    $diskDetails += $detail
    Write-Log "  Disk: $($disk.Path) | $($detail.ControllerType) $($detail.ControllerNumber):$($detail.ControllerLocation) | $($detail.VhdFormat) | $($detail.SizeGB) GB"
}

# Identify boot disk (first IDE disk is typically boot on Gen 1)
$bootDiskPath = ($hardDisks | Where-Object { $_.ControllerType -eq "IDE" -and $_.ControllerNumber -eq 0 -and $_.ControllerLocation -eq 0 }).Path
if (-not $bootDiskPath) {
    $bootDiskPath = $hardDisks[0].Path
    Write-Log "  Could not identify boot disk by IDE 0:0, using first disk: $bootDiskPath" -Level "WARN"
}
Write-Log "  Boot Disk: $bootDiskPath"

# Network adapters
$nics = Get-VMNetworkAdapter -VM $vm
$nicDetails = @()
foreach ($nic in $nics) {
    $vlan = Get-VMNetworkAdapterVlan -VMNetworkAdapter $nic -ErrorAction SilentlyContinue
    $detail = [PSCustomObject]@{
        Name       = $nic.Name
        SwitchName = $nic.SwitchName
        MacAddress = $nic.MacAddress
        VlanId     = if ($vlan) { $vlan.AccessVlanId } else { 0 }
        IsLegacy   = $nic.IsLegacy
    }
    $nicDetails += $detail
    Write-Log "  NIC: $($nic.Name) | Switch: $($nic.SwitchName) | MAC: $($nic.MacAddress) | VLAN: $($detail.VlanId) | Legacy: $($nic.IsLegacy)"
}

# Auto start/stop actions
$autoStart = $vm.AutomaticStartAction
$autoStop = $vm.AutomaticStopAction
$autoStartDelay = $vm.AutomaticStartDelay
Write-Log "  Auto Start: $autoStart (Delay: ${autoStartDelay}s) | Auto Stop: $autoStop"

# VM notes
$vmNotes = $vm.Notes

# Get cluster resource info
$clusterGroup = $null
try {
    $clusterGroup = Get-ClusterGroup -Name $VMName -ErrorAction SilentlyContinue
    if ($clusterGroup) {
        Write-Log "  Cluster Group: $($clusterGroup.Name) | State: $($clusterGroup.State) | Owner: $($clusterGroup.OwnerNode)" -Level "SUCCESS"
    }
}
catch {
    Write-Log "  VM is not in a cluster group (standalone)" -Level "WARN"
}

# Everything the rebuild needs must be known BEFORE anything is removed.
if (@($nicDetails).Count -lt 1) {
    throw "VM '$VMName' has no network adapter; the rebuild would fail after the VM was removed. Nothing was changed."
}
if (-not $bootDiskPath) {
    throw "No boot disk found for '$VMName'. Nothing was changed."
}

# -WhatIf stops here: everything above only read state. Copying disks and removing the VM are not simulated.
if ($WhatIfPreference) {
    Write-Log ""
    Write-Log "WHATIF: the checks above passed. A real run would now (1) convert any .vhd disk to .vhdx," -Level "WARN"
    Write-Log "  (2) copy every disk file to Backups\$VMName\<timestamp> and verify size and SHA256 (skipped only with" -Level "WARN"
    Write-Log "  -BackupVHDX:`$false -IUnderstandNoBackup), (3) remove '$VMName' from the cluster and Hyper-V, (4) rebuild it as Gen 2." -Level "WARN"
    Write-Log "  Nothing was copied, converted or removed." -Level "WARN"
    exit 0
}

# ── Step 3: VHD Format Check and Backup ─────────────────────────────────────
Write-Log ""
Write-Log "Step 3: VHD format validation and backup..."

foreach ($disk in $diskDetails) {
    if ($disk.VhdFormat -eq "VHD") {
        Write-Log "  CONVERTING VHD → VHDX: $($disk.Path)" -Level "WARN"
        $newPath = [System.IO.Path]::ChangeExtension($disk.Path, ".vhdx")

        if (-not $PSCmdlet.ShouldProcess($disk.Path, "Convert VHD to VHDX")) {
            throw "User cancelled VHD conversion."
        }

        Convert-VHD -Path $disk.Path -DestinationPath $newPath -VHDType Dynamic
        Write-Log "  Converted: $newPath" -Level "SUCCESS"

        if ($disk.Path -eq $bootDiskPath) { $bootDiskPath = $newPath }
        $disk.Path = $newPath
    }
}

$backupRecords = @()
if ($BackupVHDX) {
    $backupDir = Join-Path $WorkingDirectory ("Backups\$VMName\" + (Get-Date -Format 'yyyyMMdd_HHmmss'))
    Write-Log "  Backup folder: $backupDir"
    if ((("$backupDir" -split '[\x5C/]')[0..2] -join '|') -eq (("$bootDiskPath" -split '[\x5C/]')[0..2] -join '|')) {
        Write-Log "  NOTE: the backup is on the same volume as the VM. A volume failure would lose both; keep a copy elsewhere if you can." -Level "WARN"
    }
    Write-Log "  Each file is copied, then compared by size and SHA256. This takes a while for large disks."
    $backupRecords = Copy-VhdChainWithVerification -DiskPath @($diskDetails | ForEach-Object { $_.Path }) `
        -DestinationDirectory $backupDir -Log { param($m) Write-Log $m }
    Write-Log "  Backup verified: $($backupRecords.Count) file(s)" -Level "SUCCESS"
}
else {
    Write-Log "  NO BACKUP: -BackupVHDX:`$false with -IUnderstandNoBackup. The VM will be removed without a verified copy." -Level "WARN"
}

# ── Step 4: Remove Gen 1 VM (Preserve Disks) ────────────────────────────────
Write-Log ""
Write-Log "Step 4: Removing Gen 1 VM..."

# Hard gate: no verified copy of every disk file, no removal.
if ($BackupVHDX) {
    Assert-VerifiedBackup -DiskPath @($diskDetails | ForEach-Object { $_.Path }) -Record $backupRecords
    Write-Log "  Backup gate passed: every disk file has a verified copy." -Level "SUCCESS"
}

if (-not $PSCmdlet.ShouldProcess($VMName, "Remove Gen 1 VM (disks will be preserved)")) {
    throw "User cancelled VM removal."
}

# The VM must still be the same, powered-off VM that was backed up.
$recheck = Get-VM -Name $VMName -ErrorAction Stop
if ($recheck.Id -ne $vmId -or $recheck.State -ne 'Off') {
    throw "VM '$VMName' changed during the backup (identity or power state). It was NOT removed; re-run after checking it."
}

# Remove from cluster first if clustered. A failure stops the script: removing the VM while the cluster
# still owns it can leave a broken resource that the cluster restarts or fails over.
if ($clusterGroup) {
    Write-Log "  Removing from failover cluster..."
    try {
        Remove-ClusterGroup -Name $VMName -RemoveResources -Force -ErrorAction Stop
    }
    catch {
        throw "Could not remove cluster group '$VMName': $_. The VM was NOT removed; nothing was deleted."
    }
    Start-Sleep -Seconds 3
    if (Get-ClusterGroup -Name $VMName -ErrorAction SilentlyContinue) {
        throw "Cluster group '$VMName' is still present after removal. The VM was NOT removed; nothing was deleted."
    }
    Write-Log "  Removed from cluster" -Level "SUCCESS"
}

# Remove VM (without deleting VHDXs)
Write-Log "  Removing Hyper-V VM '$VMName' (preserving VHDXs)..."
Remove-VM -Name $VMName -Force
Write-Log "  Gen 1 VM removed" -Level "SUCCESS"

Start-Sleep -Seconds 3

try {
    # ── Step 5: Create Gen 2 VM ─────────────────────────────────────────────────
    Write-Log ""
    Write-Log "Step 5: Creating Gen 2 VM..."

    $vmPath = Split-Path (Split-Path $bootDiskPath -Parent) -Parent

    $newVMParams = @{
        Name               = $VMName
        Generation         = 2
        MemoryStartupBytes = $memoryStartup
        VHDPath            = $bootDiskPath
        Path               = $vmPath
        SwitchName         = $nicDetails[0].SwitchName
    }

    Write-Log "  Creating VM with params:"
    $newVMParams.GetEnumerator() | ForEach-Object { Write-Log "    $($_.Key): $($_.Value)" }

    $newVM = New-VM @newVMParams
    Write-Log "  Gen 2 VM created" -Level "SUCCESS"

    # ── Step 6: Configure VM Settings ───────────────────────────────────────────
    Write-Log ""
    Write-Log "Step 6: Applying VM configuration..."

    # Processor
    Set-VMProcessor -VM $newVM -Count $processorCount
    Write-Log "  Processors: $processorCount"

    # Memory
    if ($dynamicMemory) {
        Set-VMMemory -VM $newVM -DynamicMemoryEnabled $true -MinimumBytes $memoryMin -MaximumBytes $memoryMax -StartupBytes $memoryStartup
        Write-Log "  Dynamic Memory: $($memoryMin / 1MB)MB - $($memoryMax / 1MB)MB (Start: $($memoryStartup / 1MB)MB)"
    }

    # Secure Boot
    try {
        Set-VMFirmware -VM $newVM -EnableSecureBoot On -SecureBootTemplate $SecureBootTemplate
        Write-Log "  Secure Boot: Enabled ($SecureBootTemplate template)"
    }
    catch {
        Write-Log "  Secure Boot configuration issue: $_" -Level "WARN"
        try {
            Set-VMFirmware -VM $newVM -EnableSecureBoot Off
            Write-Log "  Secure Boot: Disabled (fallback)" -Level "WARN"
        }
        catch {
            Write-Log "  Could not configure Secure Boot: $_" -Level "WARN"
        }
    }

    # Attach additional data disks
    $additionalDisks = $diskDetails | Where-Object { $_.Path -ne $bootDiskPath }
    $scsiLocation = 1
    foreach ($disk in $additionalDisks) {
        Write-Log "  Attaching data disk: $($disk.Path) at SCSI 0:$scsiLocation"
        Add-VMHardDiskDrive -VM $newVM -ControllerType SCSI -ControllerNumber 0 -ControllerLocation $scsiLocation -Path $disk.Path
        $scsiLocation++
    }

    # Configure NICs
    $firstNic = Get-VMNetworkAdapter -VM $newVM | Select-Object -First 1
    if ($nicDetails[0].VlanId -and $nicDetails[0].VlanId -gt 0) {
        Set-VMNetworkAdapterVlan -VMNetworkAdapter $firstNic -Access -VlanId $nicDetails[0].VlanId
        Write-Log "  NIC 1 VLAN: $($nicDetails[0].VlanId)"
    }
    if ($nicDetails[0].MacAddress -and $nicDetails[0].MacAddress -ne "000000000000") {
        try {
            Set-VMNetworkAdapter -VMNetworkAdapter $firstNic -StaticMacAddress $nicDetails[0].MacAddress
            Write-Log "  NIC 1 MAC (static): $($nicDetails[0].MacAddress)"
        }
        catch {
            Write-Log "  Could not set static MAC (may be in use): $_" -Level "WARN"
        }
    }

    for ($i = 1; $i -lt $nicDetails.Count; $i++) {
        $nic = $nicDetails[$i]
        if ($nic.IsLegacy) {
            Write-Log "  Skipping legacy NIC '$($nic.Name)' — not supported on Gen 2" -Level "WARN"
            continue
        }
        Write-Log "  Adding NIC: $($nic.Name) on switch $($nic.SwitchName)"
        $newNic = Add-VMNetworkAdapter -VM $newVM -Name $nic.Name -SwitchName $nic.SwitchName -PassThru
        if ($nic.VlanId -and $nic.VlanId -gt 0) {
            Set-VMNetworkAdapterVlan -VMNetworkAdapter $newNic -Access -VlanId $nic.VlanId
        }
        if ($nic.MacAddress -and $nic.MacAddress -ne "000000000000") {
            try {
                Set-VMNetworkAdapter -VMNetworkAdapter $newNic -StaticMacAddress $nic.MacAddress
            }
            catch {
                Write-Log "    Could not set static MAC for $($nic.Name): $_" -Level "WARN"
            }
        }
    }

    # Auto start/stop actions
    Set-VM -VM $newVM -AutomaticStartAction $autoStart -AutomaticStopAction $autoStop -AutomaticStartDelay $autoStartDelay
    Write-Log "  Auto Start: $autoStart | Auto Stop: $autoStop"

    # Notes
    $conversionNote = "[Converted Gen1→Gen2 on $(Get-Date -Format 'yyyy-MM-dd HH:mm')]"
    Set-VM -VM $newVM -Notes $(if ($vmNotes) { "$vmNotes`n$conversionNote" } else { $conversionNote })

    # Enable TPM
    try {
        $keyProtector = New-HgsGuardian -Name "UntrustedGuardian_$VMName" -GenerateCertificates -ErrorAction SilentlyContinue
        if ($keyProtector) {
            $kp = New-HgsKeyProtector -Owner $keyProtector -AllowUntrustedRoot
            Set-VMKeyProtector -VM $newVM -KeyProtector $kp.RawData
            Enable-VMTPM -VM $newVM
            Write-Log "  TPM: Enabled" -Level "SUCCESS"
        }
    }
    catch {
        Write-Log "  TPM: Could not enable (non-critical): $_" -Level "WARN"
    }

    Write-Log "  VM configuration applied" -Level "SUCCESS"

    # ── Step 7: Add to Failover Cluster ─────────────────────────────────────────
    Write-Log ""
    Write-Log "Step 7: Adding VM to failover cluster..."

    try {
        Add-ClusterVirtualMachineRole -VMName $VMName
        Write-Log "  VM added to cluster" -Level "SUCCESS"
    }
    catch {
        Write-Log "  Could not add to cluster: $_" -Level "WARN"
        Write-Log "  You may need to add manually: Add-ClusterVirtualMachineRole -VMName '$VMName'" -Level "WARN"
    }
}
catch {
    Write-Log "STOPPED AFTER THE GEN 1 VM WAS REMOVED: $_" -Level "ERROR"
    Write-Log "  The VHDX files were not deleted. Original disks:" -Level "ERROR"
    foreach ($d in $diskDetails) { Write-Log "    $($d.Path)" -Level "ERROR" }
    if ($backupDir) { Write-Log "  Verified backup: $backupDir" -Level "ERROR" }
    Write-Log "  Saved configuration: $configPath" -Level "ERROR"
    Write-Log "  Recreate the VM by hand from these disks (New-VM -Generation 2 -VHDPath <boot disk>), then re-run the remaining steps." -Level "ERROR"
    throw
}

# ── Step 8: Start VM and Validate Boot ──────────────────────────────────────
Write-Log ""
Write-Log "Step 8: Starting Gen 2 VM..."

try {
    Start-VM -Name $VMName
    Write-Log "  VM starting..." -Level "SUCCESS"

    Write-Log "  Waiting for VM to reach heartbeat (up to 5 minutes)..."
    $timeout = 300
    $elapsed = 0
    $heartbeat = $false

    while ($elapsed -lt $timeout) {
        Start-Sleep -Seconds 10
        $elapsed += 10
        $vmState = Get-VM -Name $VMName

        if ($vmState.Heartbeat -match "Ok") {
            $heartbeat = $true
            break
        }
        Write-Log "    Waiting... ($elapsed seconds) State: $($vmState.State) Heartbeat: $($vmState.Heartbeat)"
    }

    if ($heartbeat) {
        Write-Log "  VM booted successfully with heartbeat!" -Level "SUCCESS"
    }
    else {
        Write-Log "  VM did not reach heartbeat within timeout." -Level "WARN"
        Write-Log "  Check the VM console — may need Secure Boot disabled or boot order adjusted." -Level "WARN"
        Write-Log "  Troubleshooting:" -Level "WARN"
        Write-Log "    1. Stop-VM -Name '$VMName' -Force" -Level "WARN"
        Write-Log "    2. Set-VMFirmware -VMName '$VMName' -EnableSecureBoot Off" -Level "WARN"
        Write-Log "    3. Start-VM -Name '$VMName'" -Level "WARN"
    }
}
catch {
    Write-Log "  Failed to start VM: $_" -Level "ERROR"
}

# ── Step 9: Final Validation ─────────────────────────────────────────────────
Write-Log ""
Write-Log "Step 9: Final validation..."

$finalVM = Get-VM -Name $VMName
Write-Log "  VM Name:    $($finalVM.Name)"
Write-Log "  Generation: $($finalVM.Generation)"
Write-Log "  State:      $($finalVM.State)"
Write-Log "  Heartbeat:  $($finalVM.Heartbeat)"
Write-Log "  Processors: $($finalVM.ProcessorCount)"
Write-Log "  Memory:     $($finalVM.MemoryAssigned / 1MB) MB"

$finalDisks = Get-VMHardDiskDrive -VM $finalVM
foreach ($disk in $finalDisks) {
    Write-Log "  Disk: $($disk.Path) ($($disk.ControllerType) $($disk.ControllerNumber):$($disk.ControllerLocation))"
}

$finalNics = Get-VMNetworkAdapter -VM $finalVM
foreach ($nic in $finalNics) {
    Write-Log "  NIC: $($nic.Name) → $($nic.SwitchName) (MAC: $($nic.MacAddress))"
}

try {
    $clusterStatus = Get-ClusterGroup -Name $VMName -ErrorAction SilentlyContinue
    if ($clusterStatus) {
        Write-Log "  Cluster: $($clusterStatus.State) on $($clusterStatus.OwnerNode)" -Level "SUCCESS"
    }
}
catch {
    Write-Log "  Cluster: Not detected" -Level "WARN"
}

# ── Summary ──────────────────────────────────────────────────────────────────
Write-Log ""
Write-Log "═══════════════════════════════════════════════════════════════"
Write-Log "  CONVERSION COMPLETE"
Write-Log "═══════════════════════════════════════════════════════════════"
Write-Log "  VM '$VMName' converted from Gen 1 → Gen 2"
Write-Log "  Generation: $($finalVM.Generation)"
Write-Log "  State:      $($finalVM.State)"
Write-Log "  Log:        $LogFile"

if ($backupDir) {
    Write-Log ""
    Write-Log "  VHDX backups are at: $backupDir"
    Write-Log "  Remove backups once you have confirmed everything is working."
}

Write-Log ""
Write-Log "  POST-CONVERSION CHECKLIST:"
Write-Log "  [ ] Verify VM boots and OS is functional"
Write-Log "  [ ] Confirm BIOS Mode shows 'UEFI' (msinfo32 inside guest)"
Write-Log "  [ ] Verify disk shows as GPT in guest Disk Management"
Write-Log "  [ ] Test application functionality"
Write-Log "  [ ] Remove VHDX backups when satisfied"
Write-Log "═══════════════════════════════════════════════════════════════"
