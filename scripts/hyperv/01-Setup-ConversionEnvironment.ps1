#Requires -RunAsAdministrator
#Requires -Modules Hyper-V, FailoverClusters

<#
.SYNOPSIS
    Sets up the environment for Gen 1 → Gen 2 VM conversion on a Hyper-V failover cluster.

.DESCRIPTION
    This script:
    - Validates Hyper-V failover cluster health
    - Checks required PowerShell modules (Hyper-V, FailoverClusters)
    - Creates a working directory for conversion artifacts
    - Inventories all Gen 1 VMs across cluster nodes
    - Exports full VM configurations for use by subsequent scripts

    No Azure connectivity or Arc registration is performed.
    This script is for the Hyper-V path only.

.PARAMETER ClusterName
    Name of the Hyper-V failover cluster.

.PARAMETER WorkingDirectory
    Path for conversion artifacts (VHDX backups, logs, configs). Ideally a CSV or shared volume.

.EXAMPLE
    .\01-Setup-ConversionEnvironment.ps1 `
        -ClusterName "HV-Cluster01" `
        -WorkingDirectory "C:\ClusterStorage\Volume01\Gen2Conversion"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ClusterName,

    [Parameter(Mandatory = $true)]
    [string]$WorkingDirectory
)

# ── Global Settings ──────────────────────────────────────────────────────────
$ErrorActionPreference = 'Stop'
$LogFile = Join-Path $WorkingDirectory "ConversionSetup_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $entry = "[$timestamp] [$Level] $Message"
    Write-Host $entry -ForegroundColor $(switch ($Level) { "ERROR" { "Red" } "WARN" { "Yellow" } "SUCCESS" { "Green" } default { "Cyan" } })
    if (Test-Path (Split-Path $LogFile -Parent)) {
        Add-Content -Path $LogFile -Value $entry
    }
}

# ── Step 1: Create Working Directory ─────────────────────────────────────────
Write-Log "═══════════════════════════════════════════════════════════════"
Write-Log "  Hyper-V Gen1 → Gen2 Conversion - Environment Setup"
Write-Log "═══════════════════════════════════════════════════════════════"

Write-Log "Creating working directory: $WorkingDirectory"
$subDirs = @("Backups", "Configs", "Logs", "Temp", "Scripts")
foreach ($dir in $subDirs) {
    $path = Join-Path $WorkingDirectory $dir
    if (-not (Test-Path $path)) {
        New-Item -Path $path -ItemType Directory -Force | Out-Null
        Write-Log "  Created: $path"
    }
}
# Re-set log file now that directory exists
$LogFile = Join-Path $WorkingDirectory "Logs\ConversionSetup_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

# ── Step 2: Validate Required PowerShell Modules ─────────────────────────────
Write-Log "Checking required PowerShell modules..."

$requiredModules = @(
    @{ Name = "Hyper-V";          MinVersion = $null },
    @{ Name = "FailoverClusters"; MinVersion = $null }
)

foreach ($mod in $requiredModules) {
    $installed = Get-Module -ListAvailable -Name $mod.Name | Sort-Object Version -Descending | Select-Object -First 1
    if (-not $installed) {
        Write-Log "  MISSING: $($mod.Name) — this module is built into Windows Server and should already be present." -Level "ERROR"
        throw "$($mod.Name) module not found. Run this script on a Hyper-V cluster node."
    }
    else {
        Write-Log "  OK: $($mod.Name) v$($installed.Version)"
    }
}

# ── Step 3: Validate Cluster Health ──────────────────────────────────────────
Write-Log "Validating Hyper-V failover cluster: $ClusterName"

try {
    $cluster = Get-Cluster -Name $ClusterName
    Write-Log "  Cluster found: $($cluster.Name)" -Level "SUCCESS"

    # Check cluster nodes
    $nodes = Get-ClusterNode -Cluster $ClusterName
    foreach ($node in $nodes) {
        $status = if ($node.State -eq "Up") { "SUCCESS" } else { "WARN" }
        Write-Log "  Node: $($node.Name) - State: $($node.State)" -Level $status
    }

    # Check CSV health
    $csvs = Get-ClusterSharedVolume -Cluster $ClusterName
    foreach ($csv in $csvs) {
        $state = $csv.SharedVolumeInfo.FaultState
        $status = if ($state -eq "NoFaults") { "SUCCESS" } else { "WARN" }
        Write-Log "  CSV: $($csv.Name) - Fault State: $state" -Level $status
    }
}
catch {
    Write-Log "Failed to connect to cluster '$ClusterName': $_" -Level "ERROR"
    throw
}

# ── Step 4: Inventory Current Gen 1 VMs ─────────────────────────────────────
Write-Log "Inventorying Gen 1 VMs across cluster nodes..."

$allVMs = @()
foreach ($node in $nodes) {
    try {
        $vms = Get-VM -ComputerName $node.Name | Where-Object { $_.Generation -eq 1 }
        foreach ($vm in $vms) {
            $vmInfo = [PSCustomObject]@{
                VMName           = $vm.Name
                VMId             = $vm.VMId
                Generation       = $vm.Generation
                State            = $vm.State
                Host             = $node.Name
                MemoryMB         = $vm.MemoryAssigned / 1MB
                ProcessorCount   = $vm.ProcessorCount
                DynamicMemory    = $vm.DynamicMemoryEnabled
                VHDs             = ($vm | Get-VMHardDiskDrive | Select-Object -ExpandProperty Path) -join "; "
                NICs             = ($vm | Get-VMNetworkAdapter | Select-Object -ExpandProperty SwitchName) -join "; "
                CheckpointsExist = ($vm | Get-VMCheckpoint).Count -gt 0
            }
            $allVMs += $vmInfo
        }
    }
    catch {
        Write-Log "  Could not query VMs on node $($node.Name): $_" -Level "WARN"
    }
}

Write-Log "Found $($allVMs.Count) Gen 1 VMs across the cluster"

# Export inventory
$inventoryPath = Join-Path $WorkingDirectory "Configs\Gen1_VM_Inventory_$(Get-Date -Format 'yyyyMMdd').csv"
$allVMs | Export-Csv -Path $inventoryPath -NoTypeInformation
Write-Log "  Inventory exported: $inventoryPath" -Level "SUCCESS"

# Display summary
Write-Log ""
Write-Log "── Gen 1 VM Inventory Summary ──"
foreach ($vm in $allVMs) {
    $checkpointWarn = if ($vm.CheckpointsExist) { " [HAS CHECKPOINTS - Must remove first!]" } else { "" }
    Write-Log "  $($vm.VMName) | $($vm.State) | Host: $($vm.Host) | VHDs: $($vm.VHDs)$checkpointWarn"
}

# ── Step 5: Export Detailed VM Configurations ────────────────────────────────
Write-Log ""
Write-Log "Exporting detailed VM configurations for conversion..."

$configExportPath = Join-Path $WorkingDirectory "Configs"

foreach ($vm in $allVMs) {
    try {
        $vmDetail = Get-VM -Name $vm.VMName -ComputerName $vm.Host

        $config = [PSCustomObject]@{
            VMName               = $vmDetail.Name
            VMId                 = $vmDetail.VMId.ToString()
            Generation           = $vmDetail.Generation
            Host                 = $vm.Host
            State                = $vmDetail.State.ToString()
            ProcessorCount       = $vmDetail.ProcessorCount
            MemoryStartupMB      = $vmDetail.MemoryStartup / 1MB
            MemoryMinimumMB      = $vmDetail.MemoryMinimum / 1MB
            MemoryMaximumMB      = $vmDetail.MemoryMaximum / 1MB
            DynamicMemory        = $vmDetail.DynamicMemoryEnabled
            AutomaticStartAction = $vmDetail.AutomaticStartAction.ToString()
            AutomaticStopAction  = $vmDetail.AutomaticStopAction.ToString()
            Notes                = $vmDetail.Notes
        }

        # Get disk details
        $disks = Get-VMHardDiskDrive -VM $vmDetail
        $diskConfigs = @()
        foreach ($disk in $disks) {
            $vhd = Get-VHD -Path $disk.Path -ComputerName $vm.Host -ErrorAction SilentlyContinue
            $diskConfigs += [PSCustomObject]@{
                ControllerType     = $disk.ControllerType.ToString()
                ControllerNumber   = $disk.ControllerNumber
                ControllerLocation = $disk.ControllerLocation
                Path               = $disk.Path
                VhdType            = if ($vhd) { $vhd.VhdType.ToString() } else { "Unknown" }
                SizeGB             = if ($vhd) { [math]::Round($vhd.Size / 1GB, 2) } else { 0 }
                FileSizeGB         = if ($vhd) { [math]::Round($vhd.FileSize / 1GB, 2) } else { 0 }
                VhdFormat          = if ($vhd) { $vhd.VhdFormat.ToString() } else { "Unknown" }
            }
        }

        # Get NIC details
        $nics = Get-VMNetworkAdapter -VM $vmDetail
        $nicConfigs = @()
        foreach ($nic in $nics) {
            $nicConfigs += [PSCustomObject]@{
                Name        = $nic.Name
                SwitchName  = $nic.SwitchName
                MacAddress  = $nic.MacAddress
                VlanId      = (Get-VMNetworkAdapterVlan -VMNetworkAdapter $nic).AccessVlanId
                IsLegacy    = $nic.IsLegacy
                IPAddresses = ($nic.IPAddresses -join ", ")
            }
        }

        # Save full config as JSON
        $fullConfig = @{
            VM    = $config
            Disks = $diskConfigs
            NICs  = $nicConfigs
        }

        $jsonPath = Join-Path $configExportPath "$($vm.VMName)_config.json"
        $fullConfig | ConvertTo-Json -Depth 5 | Out-File -FilePath $jsonPath -Encoding UTF8
        Write-Log "  Config exported: $jsonPath"
    }
    catch {
        Write-Log "  Failed to export config for $($vm.VMName): $_" -Level "ERROR"
    }
}

# ── Summary ──────────────────────────────────────────────────────────────────
Write-Log ""
Write-Log "═══════════════════════════════════════════════════════════════"
Write-Log "  Environment Setup Complete"
Write-Log "═══════════════════════════════════════════════════════════════"
Write-Log "  Working Directory: $WorkingDirectory"
Write-Log "  Gen 1 VMs Found:  $($allVMs.Count)"
Write-Log "  Inventory CSV:    $inventoryPath"
Write-Log "  VM Configs:       $configExportPath"
Write-Log "  Log File:         $LogFile"
Write-Log ""
Write-Log "  Next Step: Run 02-Convert-MBRtoGPT.ps1 inside each guest VM,"
Write-Log "  then run 03-Convert-Gen1toGen2.ps1 from this cluster node."
Write-Log "═══════════════════════════════════════════════════════════════"
