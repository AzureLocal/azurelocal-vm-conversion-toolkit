#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Projects an existing Gen 2 Hyper-V VM into the Azure Local management plane
    as a Microsoft.AzureStackHCI/virtualMachineInstances resource.

.DESCRIPTION
    This script is part of the Azure Local VM Conversion Toolkit — Path 1 (Azure Local VM).
    It is the final step after scripts 01, 02, and 03 have completed.

    At this point the VM is already running as a Gen 2 Hyper-V VM on the cluster.
    This script makes it visible and manageable in the Azure portal by:

      1. Creating an Azure Local logical NIC resource on the target logical network
      2. Calling 'az stack-hci-vm reconnect-to-azure' to register the Hyper-V VM
         as a Microsoft.AzureStackHCI/virtualMachineInstances resource

    The VM workload is completely untouched — no Sysprep, no identity loss, no
    reinstallation required. The machine keeps its domain join, installed applications,
    and full OS state.

    IMPORTANT: 'az stack-hci-vm reconnect-to-azure' is a Preview command.
    Confirm it is available in your stack-hci-vm extension version before use.
    Run 'az stack-hci-vm reconnect-to-azure --help' to verify availability.

.PARAMETER VMName
    Name of the VM as it appears in Hyper-V Manager on the cluster node.
    Also used as the Azure resource name unless -AzureVMName is specified.

.PARAMETER ResourceGroup
    Azure resource group for the VM and NIC resources.

.PARAMETER SubscriptionId
    Azure subscription ID.

.PARAMETER CustomLocationId
    Full resource ID of the Azure Local custom location.
    Example: /subscriptions/.../resourceGroups/.../providers/Microsoft.ExtendedLocation/customLocations/myAzureLocal

.PARAMETER LogicalNetworkId
    Full resource ID of the Azure Local logical network for the NIC.
    Example: /subscriptions/.../resourceGroups/.../providers/Microsoft.AzureStackHCI/logicalNetworks/mgmt-lnet

.PARAMETER AzureVMName
    Name to use for the Azure resource. Defaults to the value of -VMName.
    Use this if the Hyper-V VM name and the desired Azure resource name differ.

.PARAMETER WorkingDirectory
    Optional. Path to the working directory from script 01. Used for logging only.

.EXAMPLE
    .\scripts\cluster\05-Reconnect-AzureLocalVM.ps1 `
        -VMName "WebServer01" `
        -ResourceGroup "rg-azurelocal-prod" `
        -SubscriptionId "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" `
        -CustomLocationId "/subscriptions/.../customLocations/myAzureLocal" `
        -LogicalNetworkId "/subscriptions/.../logicalNetworks/mgmt-lnet"

.NOTES
    Requires Azure CLI with the 'stack-hci-vm' extension installed.
    Install the extension if needed: az extension add --name stack-hci-vm
    Tested against Azure Local 23H2+.
    'az stack-hci-vm reconnect-to-azure' is in Preview — verify availability first.
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [string]$VMName,

    [Parameter(Mandatory)]
    [string]$ResourceGroup,

    [Parameter(Mandatory)]
    [string]$SubscriptionId,

    [Parameter(Mandatory)]
    [string]$CustomLocationId,

    [Parameter(Mandatory)]
    [string]$LogicalNetworkId,

    [Parameter()]
    [string]$AzureVMName,

    [Parameter()]
    [string]$WorkingDirectory
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $AzureVMName) { $AzureVMName = $VMName }

#region ── Helpers ──────────────────────────────────────────────────────────────

function Write-Step {
    param([string]$Message)
    Write-Host "`n[*] $Message" -ForegroundColor Cyan
}

function Write-OK {
    param([string]$Message)
    Write-Host "    [OK] $Message" -ForegroundColor Green
}

function Write-Warn {
    param([string]$Message)
    Write-Host "    [WARN] $Message" -ForegroundColor Yellow
}

function Write-Fail {
    param([string]$Message)
    Write-Host "    [FAIL] $Message" -ForegroundColor Red
}

function Invoke-AzCli {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$Arguments,
        [string]$StepName = 'az command'
    )
    if ($WhatIfPreference) {
        Write-Host "    [WhatIf] az $($Arguments -join ' ')" -ForegroundColor DarkGray
        return $null
    }
    $output = & az @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Fail "$StepName failed (exit code $LASTEXITCODE)."
        Write-Fail ($output | Out-String)
        throw "$StepName failed."
    }
    return ($output | ConvertFrom-Json -ErrorAction SilentlyContinue)
}

#endregion

#region ── Banner ────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "=====================================================================" -ForegroundColor Magenta
Write-Host "  Azure Local VM Conversion Toolkit" -ForegroundColor Magenta
Write-Host "  Script 05 — Reconnect VM to Azure Local Management Plane" -ForegroundColor Magenta
Write-Host "  Path: Azure Local VM (Portal-Managed)" -ForegroundColor Magenta
Write-Host "=====================================================================" -ForegroundColor Magenta
Write-Host ""
Write-Host "  Hyper-V VM Name : $VMName"
Write-Host "  Azure VM Name   : $AzureVMName"
Write-Host "  Resource Group  : $ResourceGroup"
Write-Host "  Subscription    : $SubscriptionId"
Write-Host ""

#endregion

#region ── Pre-flight Validation ───────────────────────────────────────────────

Write-Step "Pre-flight validation"

$failures = [System.Collections.Generic.List[string]]::new()

# ── Azure CLI ─────────────────────────────────────────────────────────────────
if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    $failures.Add("Azure CLI (az) not found. Install from https://aka.ms/installazurecli")
}
else {
    Write-OK "Azure CLI found"
}

# ── stack-hci-vm extension ───────────────────────────────────────────────────
try {
    $null = & az extension show --name 'stack-hci-vm' 2>&1
    if ($LASTEXITCODE -ne 0) {
        $failures.Add("Azure CLI extension 'stack-hci-vm' not installed. Run: az extension add --name stack-hci-vm")
    }
    else {
        Write-OK "stack-hci-vm extension found"
    }
}
catch {
    $failures.Add("Could not check Azure CLI extension: $_")
}

# ── reconnect-to-azure command available (preview check) ─────────────────────
try {
    $helpOutput = & az stack-hci-vm reconnect-to-azure --help 2>&1
    if ($LASTEXITCODE -ne 0 -or ($helpOutput -join '') -match 'is not in the') {
        $failures.Add("'az stack-hci-vm reconnect-to-azure' is not available in your extension version. Update with: az extension update --name stack-hci-vm")
    }
    else {
        Write-OK "reconnect-to-azure command is available (Preview)"
    }
}
catch {
    $failures.Add("Could not verify reconnect-to-azure availability: $_")
}

# ── Hyper-V module available ──────────────────────────────────────────────────
if (-not (Get-Module -ListAvailable -Name Hyper-V)) {
    $failures.Add("Hyper-V PowerShell module not found. Run this script from a cluster node.")
}
else {
    Write-OK "Hyper-V module found"
}

# ── VM exists in Hyper-V and is Gen 2 ────────────────────────────────────────
try {
    $vm = Get-VM -Name $VMName -ErrorAction Stop
    if ($vm.Generation -ne 2) {
        $failures.Add("VM '$VMName' is Generation $($vm.Generation). This script requires a Gen 2 VM. Run script 03 first.")
    }
    else {
        Write-OK "VM '$VMName' found in Hyper-V, Generation 2, State: $($vm.State)"
    }
}
catch {
    $failures.Add("VM '$VMName' not found in Hyper-V on this host. Confirm the VM name and that you are running from the correct cluster node.")
}

# ── Log setup ─────────────────────────────────────────────────────────────────
$logFile = $null
if ($WorkingDirectory -and (Test-Path $WorkingDirectory)) {
    $logDir  = Join-Path $WorkingDirectory 'Logs'
    if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
    $logFile = Join-Path $logDir "Reconnect_${VMName}_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
}

if ($failures.Count -gt 0) {
    foreach ($f in $failures) { Write-Fail $f }
    Write-Host "`n[!] Pre-flight FAILED. Resolve the issues above and re-run." -ForegroundColor Red
    exit 1
}

Write-OK "All pre-flight checks passed"

#endregion

#region ── Set Azure Subscription ───────────────────────────────────────────────

Write-Step "Setting active Azure subscription"
Invoke-AzCli -Arguments @('account', 'set', '--subscription', $SubscriptionId) `
              -StepName 'az account set'
Write-OK "Subscription set: $SubscriptionId"

#endregion

#region ── Step 1: Create Logical NIC Resource ──────────────────────────────────

$nicName = "nic-$AzureVMName"

Write-Step "Creating Azure Local NIC resource: $nicName"
Write-Host "  Logical network: $LogicalNetworkId"

$nicArgs = @(
    'stack-hci-vm', 'network', 'nic', 'create',
    '--name', $nicName,
    '--resource-group', $ResourceGroup,
    '--custom-location', $CustomLocationId,
    '--subnet-id', $LogicalNetworkId,
    '--output', 'json'
)

$nicResult = Invoke-AzCli -Arguments $nicArgs -StepName 'az stack-hci-vm network nic create'

$nicId = $null
if (-not $WhatIfPreference) {
    if ($nicResult.provisioningState -ne 'Succeeded') {
        Write-Fail "NIC provisioning state: $($nicResult.provisioningState)"
        throw "NIC creation did not complete successfully."
    }
    $nicId = $nicResult.id
    Write-OK "NIC created: $nicId"
}
else {
    $nicId = '<WhatIf: NIC resource ID>'
}

#endregion

#region ── Step 2: Reconnect VM to Azure ────────────────────────────────────────

Write-Step "Reconnecting '$VMName' (Hyper-V) to Azure as '$AzureVMName'"
Write-Host "  This registers the VM with the Azure Local management plane." -ForegroundColor Yellow
Write-Host "  The VM workload, identity, and state are not touched." -ForegroundColor Yellow

$reconnectArgs = @(
    'stack-hci-vm', 'reconnect-to-azure',
    '--name', $AzureVMName,
    '--resource-group', $ResourceGroup,
    '--custom-location', $CustomLocationId,
    '--local-vm-name', $VMName,
    '--nics', $nicId,
    '--output', 'json'
)

$reconnectResult = Invoke-AzCli -Arguments $reconnectArgs -StepName 'az stack-hci-vm reconnect-to-azure'

if (-not $WhatIfPreference) {
    Write-OK "VM successfully reconnected to Azure Local management plane"
    if ($reconnectResult.id) {
        Write-OK "Resource ID: $($reconnectResult.id)"
    }
}

#endregion

#region ── Summary ───────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "=====================================================================" -ForegroundColor Green
Write-Host "  Reconnect Complete" -ForegroundColor Green
Write-Host "=====================================================================" -ForegroundColor Green
Write-Host ""
Write-Host "  VM '$AzureVMName' is now a Microsoft.AzureStackHCI/virtualMachineInstances resource."
Write-Host ""
Write-Host "  Verify in the Azure portal:" -ForegroundColor Cyan
Write-Host "    Azure Local instance > Virtual Machines > $AzureVMName"
Write-Host ""
Write-Host "  The VM workload is unchanged. No reboot or reconfiguration required."
Write-Host ""

if ($logFile) {
    "Reconnect completed at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" | Out-File -FilePath $logFile -Append
    "VM: $VMName -> $AzureVMName | ResourceGroup: $ResourceGroup | NIC: $nicId" | Out-File -FilePath $logFile -Append
    Write-Host "  Log written to: $logFile" -ForegroundColor Gray
}

#endregion
