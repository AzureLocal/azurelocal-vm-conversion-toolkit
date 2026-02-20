#Requires -RunAsAdministrator
#Requires -Modules Hyper-V, FailoverClusters

<#
.SYNOPSIS
    Converts a Gen 1 VM to Gen 2 on Azure Local and re-registers it as an Arc-managed VM.

.DESCRIPTION
    This script runs on an Azure Local (HCI) cluster node and:
    1. Exports the Gen 1 VM configuration (NICs, memory, CPU, disks, etc.)
    2. Backs up the VHDX files
    3. Removes the Gen 1 VM from the cluster and Hyper-V (preserving VHDXs)
    4. Creates a new Gen 2 VM with the same configuration
    5. Attaches the existing VHDX disks (already converted to GPT via Script 02)
    6. Adds the VM back to the cluster
    7. Re-registers the VM as an Azure Arc-managed VM on Azure Local

    PREREQUISITES:
    - Script 01 has been run (environment setup, config exports exist)
    - Script 02 has been run inside the guest (MBR → GPT conversion done)
    - The VM is SHUT DOWN

.PARAMETER VMName
    Name of the VM to convert.

.PARAMETER WorkingDirectory
    Path to the conversion working directory (created by Script 01).

.PARAMETER ResourceGroup
    Azure resource group for Arc VM re-registration.

.PARAMETER SubscriptionId
    Azure subscription ID.

.PARAMETER CustomLocationId
    Azure Local custom location resource ID for Arc VM creation.
    Example: /subscriptions/{sub}/resourceGroups/{rg}/providers/Microsoft.ExtendedLocation/customLocations/{name}

.PARAMETER LogicalNetworkId
    Azure Local logical network resource ID for the VM NIC.
    Example: /subscriptions/{sub}/resourceGroups/{rg}/providers/Microsoft.AzureStackHCI/logicalNetworks/{name}

.PARAMETER SkipArcRegistration
    Skip the Azure Arc re-registration step (useful for testing).

.PARAMETER BackupVHDX
    Create a backup copy of VHDX files before conversion. Default: $true

.EXAMPLE
    .\03-Convert-Gen1toGen2.ps1 `
        -VMName "WebServer01" `
        -WorkingDirectory "C:\ClusterStorage\Volume01\Gen2Conversion" `
        -ResourceGroup "rg-azurelocal-prod" `
        -SubscriptionId "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" `
        -CustomLocationId "/subscriptions/.../customLocations/myAzureLocal" `
        -LogicalNetworkId "/subscriptions/.../logicalNetworks/mgmt-lnet"
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory = $true)]
    [string]$VMName,

    [Parameter(Mandatory = $true)]
    [string]$WorkingDirectory,

    [Parameter(Mandatory = $true)]
    [string]$ResourceGroup,

    [Parameter(Mandatory = $true)]
    [string]$SubscriptionId,

    [Parameter(Mandatory = $true)]
    [string]$CustomLocationId,

    [Parameter(Mandatory = $true)]
    [string]$LogicalNetworkId,

    [Parameter()]
    [switch]$SkipArcRegistration,

    [Parameter()]
    [bool]$BackupVHDX = $true
)

# ── Global Settings ──────────────────────────────────────────────────────────
$ErrorActionPreference = 'Stop'
$LogFile = Join-Path $WorkingDirectory "Logs\Gen2Convert_${VMName}_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $entry = "[$timestamp] [$Level] $Message"
    Write-Host $entry -ForegroundColor $(switch ($Level) { "ERROR" { "Red" } "WARN" { "Yellow" } "SUCCESS" { "Green" } default { "Cyan" } })
    Add-Content -Path $LogFile -Value $entry
}

Write-Log "═══════════════════════════════════════════════════════════════"
Write-Log "  Azure Local Gen 1 → Gen 2 VM Conversion"
Write-Log "  VM: $VMName"
Write-Log "═══════════════════════════════════════════════════════════════"

# ── Step 1: Load and Validate VM Configuration ──────────────────────────────
Write-Log "Step 1: Loading VM configuration..."

# Check for config file from Script 01
$configPath = Join-Path $WorkingDirectory "Configs\${VMName}_config.json"
$savedConfig = $null
if (Test-Path $configPath) {
    $savedConfig = Get-Content $configPath -Raw | ConvertFrom-Json
    Write-Log "  Loaded saved config from: $configPath" -Level "SUCCESS"
}

# Get live VM state
$vm = Get-VM -Name $VMName -ErrorAction Stop
Write-Log "  VM State:      $($vm.State)"
Write-Log "  Generation:    $($vm.Generation)"
Write-Log "  Host:          $($vm.ComputerName)"

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
    Write-Log "  Checkpoints:" -Level "ERROR"
    $checkpoints | ForEach-Object { Write-Log "    - $($_.Name) (Created: $($_.CreationTime))" -Level "ERROR" }
    throw "Remove all checkpoints before proceeding."
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

        # Update the path reference
        if ($disk.Path -eq $bootDiskPath) { $bootDiskPath = $newPath }
        $disk.Path = $newPath
    }
}

if ($BackupVHDX) {
    $backupDir = Join-Path $WorkingDirectory "Backups\$VMName"
    if (-not (Test-Path $backupDir)) { New-Item -Path $backupDir -ItemType Directory -Force | Out-Null }

    foreach ($disk in $diskDetails) {
        $destPath = Join-Path $backupDir (Split-Path $disk.Path -Leaf)
        Write-Log "  Backing up: $($disk.Path) → $destPath"
        Write-Log "    This may take a while for large disks..."

        Copy-Item -Path $disk.Path -Destination $destPath -Force
        Write-Log "    Backup complete: $([math]::Round((Get-Item $destPath).Length / 1GB, 2)) GB" -Level "SUCCESS"
    }
}

# ── Step 4: Save Arc VM Resource Info (Before Deletion) ─────────────────────
Write-Log ""
Write-Log "Step 4: Capturing Azure Arc VM resource information..."

$arcResourceId = $null
$arcVMTags = @{}

try {
    Connect-AzAccount -SubscriptionId $SubscriptionId -ErrorAction SilentlyContinue | Out-Null
    Set-AzContext -SubscriptionId $SubscriptionId -ErrorAction SilentlyContinue | Out-Null

    # Look for the Arc-enabled VM resource
    # Azure Local VMs are typically Microsoft.AzureStackHCI/virtualMachineInstances
    # or Microsoft.HybridCompute/machines depending on version
    $arcResources = Get-AzResource -ResourceGroupName $ResourceGroup -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like "*$VMName*" -or $_.Name -eq $VMName }

    foreach ($res in $arcResources) {
        Write-Log "  Found Arc resource: $($res.Name) | Type: $($res.ResourceType) | ID: $($res.ResourceId)"
        if ($res.ResourceType -match "virtualMachine|HybridCompute") {
            $arcResourceId = $res.ResourceId
            $arcVMTags = $res.Tags
        }
    }

    if ($arcResourceId) {
        Write-Log "  Arc Resource ID: $arcResourceId" -Level "SUCCESS"
        # Save for later re-registration
        $arcInfo = @{
            ResourceId   = $arcResourceId
            Tags         = $arcVMTags
            VMName       = $VMName
            CapturedAt   = (Get-Date).ToString("o")
        }
        $arcInfoPath = Join-Path $WorkingDirectory "Configs\${VMName}_arc_info.json"
        $arcInfo | ConvertTo-Json -Depth 3 | Out-File -FilePath $arcInfoPath -Encoding UTF8
        Write-Log "  Arc info saved: $arcInfoPath"
    }
    else {
        Write-Log "  No Arc VM resource found for '$VMName'" -Level "WARN"
    }
}
catch {
    Write-Log "  Could not query Arc resources: $_" -Level "WARN"
}

# ── Step 5: Remove Gen 1 VM (Preserve Disks) ────────────────────────────────
Write-Log ""
Write-Log "Step 5: Removing Gen 1 VM..."

if (-not $PSCmdlet.ShouldProcess($VMName, "Remove Gen 1 VM (disks will be preserved)")) {
    throw "User cancelled VM removal."
}

# Remove from cluster first if clustered
if ($clusterGroup) {
    Write-Log "  Removing from failover cluster..."
    try {
        Remove-ClusterGroup -Name $VMName -RemoveResources -Force
        Write-Log "  Removed from cluster" -Level "SUCCESS"
    }
    catch {
        Write-Log "  Cluster removal issue: $_ (continuing...)" -Level "WARN"
    }
    Start-Sleep -Seconds 3
}

# Delete the Arc resource if it exists (so we can cleanly re-register)
if ($arcResourceId -and -not $SkipArcRegistration) {
    Write-Log "  Deleting existing Arc VM resource..."
    try {
        Remove-AzResource -ResourceId $arcResourceId -Force -ErrorAction SilentlyContinue
        Write-Log "  Arc resource deleted" -Level "SUCCESS"
        Start-Sleep -Seconds 5
    }
    catch {
        Write-Log "  Could not delete Arc resource: $_ (may need manual cleanup)" -Level "WARN"
    }
}

# Remove VM (without deleting VHDXs)
Write-Log "  Removing Hyper-V VM '$VMName' (preserving VHDXs)..."
Remove-VM -Name $VMName -Force
Write-Log "  Gen 1 VM removed" -Level "SUCCESS"

Start-Sleep -Seconds 3

# ── Step 6: Create Gen 2 VM ─────────────────────────────────────────────────
Write-Log ""
Write-Log "Step 6: Creating Gen 2 VM..."

# Determine VM path (use same location as original)
$vmPath = Split-Path (Split-Path $bootDiskPath -Parent) -Parent

# Create the new Gen 2 VM
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

# ── Step 7: Configure VM Settings ───────────────────────────────────────────
Write-Log ""
Write-Log "Step 7: Applying VM configuration..."

# Processor
Set-VMProcessor -VM $newVM -Count $processorCount
Write-Log "  Processors: $processorCount"

# Memory
if ($dynamicMemory) {
    Set-VMMemory -VM $newVM -DynamicMemoryEnabled $true -MinimumBytes $memoryMin -MaximumBytes $memoryMax -StartupBytes $memoryStartup
    Write-Log "  Dynamic Memory: $($memoryMin / 1MB)MB - $($memoryMax / 1MB)MB (Start: $($memoryStartup / 1MB)MB)"
}

# Secure Boot (enable for Windows, disable for Linux)
# Default to Microsoft Windows template - adjust if needed
try {
    Set-VMFirmware -VM $newVM -EnableSecureBoot On -SecureBootTemplate "MicrosoftWindows"
    Write-Log "  Secure Boot: Enabled (MicrosoftWindows template)"
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

# Attach additional data disks (boot disk already attached)
$additionalDisks = $diskDetails | Where-Object { $_.Path -ne $bootDiskPath }
$scsiLocation = 1  # 0 is the boot disk
foreach ($disk in $additionalDisks) {
    Write-Log "  Attaching data disk: $($disk.Path) at SCSI 0:$scsiLocation"
    Add-VMHardDiskDrive -VM $newVM -ControllerType SCSI -ControllerNumber 0 -ControllerLocation $scsiLocation -Path $disk.Path
    $scsiLocation++
}

# Configure additional NICs (first NIC already created with New-VM)
# Update first NIC VLAN if needed
$firstNic = Get-VMNetworkAdapter -VM $newVM | Select-Object -First 1
if ($nicDetails[0].VlanId -and $nicDetails[0].VlanId -gt 0) {
    Set-VMNetworkAdapterVlan -VMNetworkAdapter $firstNic -Access -VlanId $nicDetails[0].VlanId
    Write-Log "  NIC 1 VLAN: $($nicDetails[0].VlanId)"
}

# Set static MAC if original had one
if ($nicDetails[0].MacAddress -and $nicDetails[0].MacAddress -ne "000000000000") {
    try {
        Set-VMNetworkAdapter -VMNetworkAdapter $firstNic -StaticMacAddress $nicDetails[0].MacAddress
        Write-Log "  NIC 1 MAC (static): $($nicDetails[0].MacAddress)"
    }
    catch {
        Write-Log "  Could not set static MAC (may be in use): $_" -Level "WARN"
    }
}

# Add any additional NICs (skip legacy NICs - Gen 2 doesn't support them)
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
if ($vmNotes) {
    $updatedNotes = "$vmNotes`n[Converted Gen1→Gen2 on $(Get-Date -Format 'yyyy-MM-dd HH:mm')]"
    Set-VM -VM $newVM -Notes $updatedNotes
}
else {
    Set-VM -VM $newVM -Notes "[Converted Gen1→Gen2 on $(Get-Date -Format 'yyyy-MM-dd HH:mm')]"
}

# Enable TPM (Gen 2 feature, helpful for Windows 11 / Secured-core)
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

# ── Step 8: Add to Failover Cluster ─────────────────────────────────────────
Write-Log ""
Write-Log "Step 8: Adding VM to failover cluster..."

try {
    Add-ClusterVirtualMachineRole -VMName $VMName
    Write-Log "  VM added to cluster" -Level "SUCCESS"
}
catch {
    Write-Log "  Could not add to cluster: $_" -Level "WARN"
    Write-Log "  You may need to add manually: Add-ClusterVirtualMachineRole -VMName '$VMName'" -Level "WARN"
}

# ── Step 9: Start VM and Validate Boot ──────────────────────────────────────
Write-Log ""
Write-Log "Step 9: Starting Gen 2 VM..."

try {
    Start-VM -Name $VMName
    Write-Log "  VM starting..." -Level "SUCCESS"

    # Wait for VM to boot
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

# ── Step 10: Re-Register as Azure Arc VM ─────────────────────────────────────
Write-Log ""
Write-Log "Step 10: Re-registering VM with Azure Arc on Azure Local..."

if ($SkipArcRegistration) {
    Write-Log "  Arc registration SKIPPED (-SkipArcRegistration specified)" -Level "WARN"
}
else {
    try {
        # Ensure Az context
        $context = Get-AzContext
        if (-not $context -or $context.Subscription.Id -ne $SubscriptionId) {
            Connect-AzAccount -SubscriptionId $SubscriptionId | Out-Null
        }

        # Get the VM's current VHDX path for the image reference
        $currentVM = Get-VM -Name $VMName
        $currentBootDisk = ($currentVM | Get-VMHardDiskDrive | Where-Object {
            $_.ControllerType -eq "SCSI" -and $_.ControllerNumber -eq 0 -and $_.ControllerLocation -eq 0
        }).Path

        Write-Log "  Creating Arc-enabled VM resource..."

        # Method 1: Use az CLI (Azure Local Arc VM management)
        # This is the most reliable method for Azure Local 23H2+
        $arcVMCreateCmd = @"
az stack-hci-vm create ``
    --name "$VMName" ``
    --resource-group "$ResourceGroup" ``
    --subscription "$SubscriptionId" ``
    --custom-location "$CustomLocationId" ``
    --admin-username "arcadmin" ``
    --computer-name "$VMName" ``
    --enable-vm-config-agent true ``
    --hardware-profile memory-mb=$([math]::Round($memoryStartup / 1MB)) processors=$processorCount vm-size="Custom" ``
    --storage-profile os-disk-name="$($VMName)_osdisk" ``
    --nic-id "$LogicalNetworkId"
"@

        Write-Log "  NOTE: For Azure Local 23H2+, the VM should auto-register with Arc"
        Write-Log "  once the VM Config Agent detects the new Gen 2 VM."
        Write-Log ""
        Write-Log "  If auto-registration doesn't occur within 10 minutes, use:"
        Write-Log "  $arcVMCreateCmd"
        Write-Log ""

        # For Azure Local 23H2+ with MOC, VMs auto-register when:
        # 1. The cluster is Arc-enabled
        # 2. The VM Config Agent is running
        # 3. The VM is clustered

        # Wait for auto-registration
        Write-Log "  Waiting for Arc auto-registration (checking every 30s for up to 10 minutes)..."
        $arcTimeout = 600
        $arcElapsed = 0
        $arcRegistered = $false

        while ($arcElapsed -lt $arcTimeout) {
            Start-Sleep -Seconds 30
            $arcElapsed += 30

            $arcCheck = Get-AzResource -ResourceGroupName $ResourceGroup -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -eq $VMName -and $_.ResourceType -match "virtualMachine" }

            if ($arcCheck) {
                $arcRegistered = $true
                Write-Log "  Arc VM registered: $($arcCheck.ResourceId)" -Level "SUCCESS"
                break
            }

            Write-Log "    Checking... ($arcElapsed seconds)"
        }

        if (-not $arcRegistered) {
            Write-Log "  Arc auto-registration did not complete within timeout." -Level "WARN"
            Write-Log "  This is not uncommon — registration may take longer or require manual steps." -Level "WARN"
            Write-Log ""
            Write-Log "  ── Manual Registration Options ──" -Level "WARN"
            Write-Log "  Option A: Wait longer — Arc agent may still be syncing" -Level "WARN"
            Write-Log "  Option B: Restart the Arc agent on the cluster node:" -Level "WARN"
            Write-Log "    Restart-Service HostAgentService" -Level "WARN"
            Write-Log "  Option C: Use az CLI to manually create the Arc VM resource:" -Level "WARN"
            Write-Log "    $arcVMCreateCmd" -Level "WARN"
        }

        # Re-apply tags if we had them
        if ($arcRegistered -and $arcVMTags -and $arcVMTags.Count -gt 0) {
            try {
                $newArcResource = Get-AzResource -ResourceGroupName $ResourceGroup |
                    Where-Object { $_.Name -eq $VMName -and $_.ResourceType -match "virtualMachine" } |
                    Select-Object -First 1

                if ($newArcResource) {
                    Set-AzResource -ResourceId $newArcResource.ResourceId -Tag $arcVMTags -Force
                    Write-Log "  Re-applied Azure tags" -Level "SUCCESS"
                }
            }
            catch {
                Write-Log "  Could not re-apply tags: $_" -Level "WARN"
            }
        }
    }
    catch {
        Write-Log "  Arc registration error: $_" -Level "ERROR"
        Write-Log "  You may need to manually register the VM with Azure Arc." -Level "WARN"
    }
}

# ── Step 11: Final Validation ────────────────────────────────────────────────
Write-Log ""
Write-Log "Step 11: Final validation..."

$finalVM = Get-VM -Name $VMName
Write-Log "  VM Name:        $($finalVM.Name)"
Write-Log "  Generation:     $($finalVM.Generation)"
Write-Log "  State:          $($finalVM.State)"
Write-Log "  Heartbeat:      $($finalVM.Heartbeat)"
Write-Log "  Processors:     $($finalVM.ProcessorCount)"
Write-Log "  Memory:         $($finalVM.MemoryAssigned / 1MB) MB"

$finalDisks = Get-VMHardDiskDrive -VM $finalVM
foreach ($disk in $finalDisks) {
    Write-Log "  Disk:           $($disk.Path) ($($disk.ControllerType) $($disk.ControllerNumber):$($disk.ControllerLocation))"
}

$finalNics = Get-VMNetworkAdapter -VM $finalVM
foreach ($nic in $finalNics) {
    Write-Log "  NIC:            $($nic.Name) → $($nic.SwitchName) (MAC: $($nic.MacAddress))"
}

# Check cluster status
try {
    $clusterStatus = Get-ClusterGroup -Name $VMName -ErrorAction SilentlyContinue
    if ($clusterStatus) {
        Write-Log "  Cluster:        $($clusterStatus.State) on $($clusterStatus.OwnerNode)" -Level "SUCCESS"
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

if ($BackupVHDX) {
    Write-Log ""
    Write-Log "  VHDX backups are at: $(Join-Path $WorkingDirectory "Backups\$VMName")"
    Write-Log "  Once you confirm everything is working, you can remove the backups"
    Write-Log "  to reclaim disk space."
}

Write-Log ""
Write-Log "  POST-CONVERSION CHECKLIST:"
Write-Log "  [ ] Verify VM boots and OS is functional"
Write-Log "  [ ] Confirm BIOS Mode shows 'UEFI' (msinfo32 inside guest)"
Write-Log "  [ ] Verify disk shows as GPT in guest Disk Management"
Write-Log "  [ ] Test application functionality"
Write-Log "  [ ] Confirm Azure Arc registration in Azure Portal"
Write-Log "  [ ] Verify VM appears in Azure Local portal blade"
Write-Log "  [ ] Enable Azure policies/extensions as needed"
Write-Log "  [ ] Remove VHDX backups when satisfied"
Write-Log "═══════════════════════════════════════════════════════════════"
