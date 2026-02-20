#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Batch orchestrator for converting multiple Gen 1 VMs to Gen 2 on a Hyper-V failover cluster.

.DESCRIPTION
    This script orchestrates the conversion of multiple VMs by:
    - Reading the VM inventory CSV from Script 01
    - Allowing selection of VMs to convert
    - Invoking Script 03 for each VM sequentially
    - Tracking progress and generating a summary report

    No Azure connectivity, Arc registration, or Azure resource management is performed.
    This script is for the Hyper-V path only. If you need the VMs managed in the Azure
    portal, use the Azure Local path (scripts/azurelocal/).

    IMPORTANT: Script 02 (MBR→GPT) must be run inside EACH guest VM manually
    before this batch script can process them.

.PARAMETER WorkingDirectory
    Path to the conversion working directory (created by Script 01).

.PARAMETER VMNames
    Optional array of specific VM names to convert. If omitted, shows all Gen 1 VMs for selection.

.EXAMPLE
    # Interactive — shows all Gen 1 VMs for selection
    .\04-Batch-ConvertVMs.ps1 `
        -WorkingDirectory "C:\ClusterStorage\Volume01\Gen2Conversion"

    # Specific VMs
    .\04-Batch-ConvertVMs.ps1 `
        -WorkingDirectory "C:\ClusterStorage\Volume01\Gen2Conversion" `
        -VMNames @("WebServer01", "SQLServer01", "AppServer01")
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$WorkingDirectory,

    [Parameter()]
    [string[]]$VMNames
)

$ErrorActionPreference = 'Stop'
$BatchLogFile = Join-Path $WorkingDirectory "Logs\BatchConversion_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
$ScriptRoot = $PSScriptRoot
if (-not $ScriptRoot) { $ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path }

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $entry = "[$timestamp] [$Level] $Message"
    Write-Host $entry -ForegroundColor $(switch ($Level) { "ERROR" { "Red" } "WARN" { "Yellow" } "SUCCESS" { "Green" } default { "Cyan" } })
    Add-Content -Path $BatchLogFile -Value $entry
}

Write-Log "═══════════════════════════════════════════════════════════════"
Write-Log "  Hyper-V Batch Gen1 → Gen2 Conversion"
Write-Log "═══════════════════════════════════════════════════════════════"

# ── Load Inventory ───────────────────────────────────────────────────────────
$inventoryFiles = Get-ChildItem -Path (Join-Path $WorkingDirectory "Configs") -Filter "Gen1_VM_Inventory_*.csv" |
    Sort-Object LastWriteTime -Descending

if ($inventoryFiles.Count -eq 0) {
    Write-Log "No inventory CSV found. Run Script 01 first!" -Level "ERROR"
    throw "Missing inventory file."
}

$inventory = Import-Csv -Path $inventoryFiles[0].FullName
Write-Log "Loaded inventory: $($inventoryFiles[0].Name) ($($inventory.Count) VMs)"

# ── Filter VMs ───────────────────────────────────────────────────────────────
if ($VMNames) {
    $selectedVMs = $inventory | Where-Object { $_.VMName -in $VMNames }
    $missing = $VMNames | Where-Object { $_ -notin $inventory.VMName }
    if ($missing) {
        Write-Log "VMs not found in inventory: $($missing -join ', ')" -Level "WARN"
    }
}
else {
    Write-Log ""
    Write-Log "── Available Gen 1 VMs ──"
    for ($i = 0; $i -lt $inventory.Count; $i++) {
        $vm = $inventory[$i]
        $checkpointFlag = if ($vm.CheckpointsExist -eq "True") { " ⚠️ HAS CHECKPOINTS" } else { "" }
        Write-Host "  [$i] $($vm.VMName) | State: $($vm.State) | Host: $($vm.Host)$checkpointFlag" -ForegroundColor White
    }
    Write-Host ""
    $selection = Read-Host "Enter VM numbers to convert (comma-separated, e.g., 0,2,4) or 'all'"

    if ($selection -eq 'all') {
        $selectedVMs = $inventory
    }
    else {
        $indices = $selection -split ',' | ForEach-Object { [int]$_.Trim() }
        $selectedVMs = $indices | ForEach-Object { $inventory[$_] }
    }
}

Write-Log ""
Write-Log "Selected $($selectedVMs.Count) VMs for conversion:"
$selectedVMs | ForEach-Object { Write-Log "  - $($_.VMName)" }

# ── Pre-Flight Checks ───────────────────────────────────────────────────────
Write-Log ""
Write-Log "Running pre-flight checks..."

$readyVMs = @()
$skippedVMs = @()

foreach ($vmEntry in $selectedVMs) {
    $vmName = $vmEntry.VMName
    $issues = @()

    try {
        $vm = Get-VM -Name $vmName -ErrorAction Stop
        if ($vm.State -ne 'Off') {
            $issues += "VM is not shut down (State: $($vm.State))"
        }
        if ($vm.Generation -ne 1) {
            $issues += "VM is already Gen $($vm.Generation)"
        }
    }
    catch {
        $issues += "VM not found: $_"
    }

    try {
        $checkpoints = Get-VMCheckpoint -VMName $vmName -ErrorAction SilentlyContinue
        if ($checkpoints.Count -gt 0) {
            $issues += "Has $($checkpoints.Count) checkpoint(s) — must remove first"
        }
    }
    catch { }

    $configPath = Join-Path $WorkingDirectory "Configs\${vmName}_config.json"
    if (-not (Test-Path $configPath)) {
        $issues += "No config file found (run Script 01)"
    }

    if ($issues.Count -gt 0) {
        Write-Log "  SKIP: $vmName" -Level "WARN"
        $issues | ForEach-Object { Write-Log "    ⚠️  $_" -Level "WARN" }
        $skippedVMs += [PSCustomObject]@{ VMName = $vmName; Reason = ($issues -join "; ") }
    }
    else {
        Write-Log "  READY: $vmName" -Level "SUCCESS"
        $readyVMs += $vmEntry
    }
}

if ($readyVMs.Count -eq 0) {
    Write-Log "No VMs are ready for conversion!" -Level "ERROR"
    throw "No VMs to process."
}

Write-Log ""
Write-Log "$($readyVMs.Count) VMs ready, $($skippedVMs.Count) skipped"

# Confirmation
Write-Host ""
Write-Host "╔═══════════════════════════════════════════════════════════════╗" -ForegroundColor Yellow
Write-Host "║  READY TO CONVERT $($readyVMs.Count) VMs FROM GEN 1 → GEN 2               ║" -ForegroundColor Yellow
Write-Host "║                                                               ║" -ForegroundColor Yellow
Write-Host "║  This will:                                                   ║" -ForegroundColor Yellow
Write-Host "║  - Remove each Gen 1 VM                                      ║" -ForegroundColor Yellow
Write-Host "║  - Create new Gen 2 VMs with the same disks                  ║" -ForegroundColor Yellow
Write-Host "╚═══════════════════════════════════════════════════════════════╝" -ForegroundColor Yellow
Write-Host ""

$confirm = Read-Host "Type 'CONVERT' to proceed"
if ($confirm -ne 'CONVERT') {
    Write-Log "Batch conversion cancelled by user." -Level "WARN"
    exit 0
}

# ── Process Each VM ──────────────────────────────────────────────────────────
Write-Log ""
Write-Log "Starting batch conversion..."

$results = @()
$totalCount = $readyVMs.Count
$currentIndex = 0

foreach ($vmEntry in $readyVMs) {
    $currentIndex++
    $vmName = $vmEntry.VMName

    Write-Log ""
    Write-Log "════════════════════════════════════════════════════"
    Write-Log "  [$currentIndex / $totalCount] Converting: $vmName"
    Write-Log "════════════════════════════════════════════════════"

    $startTime = Get-Date
    $status = "SUCCESS"
    $errorMsg = ""

    try {
        $convertScript = Join-Path $ScriptRoot "03-Convert-Gen1toGen2.ps1"

        $params = @{
            VMName           = $vmName
            WorkingDirectory = $WorkingDirectory
            BackupVHDX       = $true
            Confirm          = $false
        }

        & $convertScript @params

        Write-Log "  $vmName conversion completed" -Level "SUCCESS"
    }
    catch {
        $status = "FAILED"
        $errorMsg = $_.Exception.Message
        Write-Log "  $vmName conversion FAILED: $errorMsg" -Level "ERROR"
    }

    $duration = (Get-Date) - $startTime

    $results += [PSCustomObject]@{
        VMName      = $vmName
        Status      = $status
        Duration    = $duration.ToString("hh\:mm\:ss")
        Error       = $errorMsg
        CompletedAt = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    }

    if ($currentIndex -lt $totalCount) {
        Write-Log "  Pausing 10 seconds before next VM..."
        Start-Sleep -Seconds 10
    }
}

# ── Generate Report ──────────────────────────────────────────────────────────
Write-Log ""
Write-Log "═══════════════════════════════════════════════════════════════"
Write-Log "  BATCH CONVERSION REPORT"
Write-Log "═══════════════════════════════════════════════════════════════"

$successCount = ($results | Where-Object { $_.Status -eq "SUCCESS" }).Count
$failCount    = ($results | Where-Object { $_.Status -eq "FAILED" }).Count

Write-Log "  Total:   $totalCount"
Write-Log "  Success: $successCount" -Level "SUCCESS"
Write-Log "  Failed:  $failCount"    -Level $(if ($failCount -gt 0) { "ERROR" } else { "SUCCESS" })
Write-Log "  Skipped: $($skippedVMs.Count)" -Level $(if ($skippedVMs.Count -gt 0) { "WARN" } else { "SUCCESS" })

Write-Log ""
Write-Log "── Results ──"
foreach ($r in $results) {
    $level = if ($r.Status -eq "SUCCESS") { "SUCCESS" } else { "ERROR" }
    $msg = "  $($r.VMName): $($r.Status) ($($r.Duration))"
    if ($r.Error) { $msg += " — $($r.Error)" }
    Write-Log $msg -Level $level
}

if ($skippedVMs.Count -gt 0) {
    Write-Log ""
    Write-Log "── Skipped VMs ──"
    foreach ($s in $skippedVMs) {
        Write-Log "  $($s.VMName): $($s.Reason)" -Level "WARN"
    }
}

$reportPath = Join-Path $WorkingDirectory "Logs\BatchReport_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
$results | Export-Csv -Path $reportPath -NoTypeInformation
Write-Log ""
Write-Log "  Report saved: $reportPath"
Write-Log "  Log file:     $BatchLogFile"
Write-Log "═══════════════════════════════════════════════════════════════"
