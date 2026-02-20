#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Registers a sysprepped VHDX as an Azure Local image resource and deploys
    a new Azure Local VM (Microsoft.AzureStackHCI/virtualMachineInstances).

.DESCRIPTION
    This script is part of the Azure Local VM Conversion Toolkit — Path 2 (Azure Local VM).

    It performs the following operations in sequence:
      1. Validates that all required Azure CLI tools and input parameters are present
      2. Registers the source VHDX as an Azure Local gallery image resource
      3. Creates a logical NIC resource on the target logical network
      4. Deploys the VM using 'az stack-hci-vm create'
      5. Verifies the resulting resource in Azure

    The resulting VM is a full Microsoft.AzureStackHCI/virtualMachineInstances resource
    managed by the Azure Local management plane and visible in the Azure portal.

    IMPORTANT:
    - The source VHDX must have been sysprepped (generalized) by script 05 before use.
    - This script requires the Azure CLI with the 'stack-hci-vm' extension installed on
      the machine running it (cluster node or management workstation).
    - The service principal / user account must have the Azure Stack HCI Administrator
      role or the Azure Stack HCI VM Contributor role on the resource group.

.PARAMETER VMName
    Name of the VM to create. Used for the VM resource, image resource, and NIC resource.

.PARAMETER WorkingDirectory
    Path to the working directory created by script 01. Config JSON is read from here.

.PARAMETER SubscriptionId
    Azure subscription ID.

.PARAMETER ResourceGroup
    Azure resource group for all resources.

.PARAMETER CustomLocationId
    Full resource ID of the Azure Local custom location.
    Example: /subscriptions/.../resourceGroups/.../providers/Microsoft.ExtendedLocation/customLocations/myAzureLocal

.PARAMETER LogicalNetworkId
    Full resource ID of the Azure Local logical network to attach the NIC to.
    Example: /subscriptions/.../resourceGroups/.../providers/Microsoft.AzureStackHCI/logicalNetworks/mgmt-lnet

.PARAMETER StoragePathId
    Full resource ID of the Azure Local storage container (storage path) where disks are hosted.
    Example: /subscriptions/.../resourceGroups/.../providers/Microsoft.AzureStackHCI/storageContainers/myStoragePath

.PARAMETER VHDXSourcePath
    Full local path to the sysprepped VHDX file on the cluster storage.
    Example: C:\ClusterStorage\Volume01\Gen2Conversion\Backups\WebServer01\WebServer01_OS.vhdx

.PARAMETER AdminUsername
    Local administrator username for the new VM. Defaults to 'localadmin'.

.PARAMETER OsType
    Operating system type. Valid values: Windows, Linux. Defaults to 'Windows'.

.PARAMETER WhatIf
    Reports what actions would be taken without executing any Azure CLI commands.

.EXAMPLE
    .\scripts\cluster\06-Create-AzureLocalVM.ps1 `
        -VMName "WebServer01" `
        -WorkingDirectory "C:\ClusterStorage\Volume01\Gen2Conversion" `
        -SubscriptionId "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" `
        -ResourceGroup "rg-azurelocal-prod" `
        -CustomLocationId "/subscriptions/.../customLocations/myAzureLocal" `
        -LogicalNetworkId "/subscriptions/.../logicalNetworks/mgmt-lnet" `
        -StoragePathId "/subscriptions/.../storageContainers/myStoragePath" `
        -VHDXSourcePath "C:\ClusterStorage\Volume01\Gen2Conversion\Backups\WebServer01\WebServer01_OS.vhdx"

.NOTES
    Requires Azure CLI with 'stack-hci-vm' extension.
    Install the extension if needed: az extension add --name stack-hci-vm
    Tested against Azure Local 23H2+.
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [string]$VMName,

    [Parameter(Mandatory)]
    [string]$WorkingDirectory,

    [Parameter(Mandatory)]
    [string]$SubscriptionId,

    [Parameter(Mandatory)]
    [string]$ResourceGroup,

    [Parameter(Mandatory)]
    [string]$CustomLocationId,

    [Parameter(Mandatory)]
    [string]$LogicalNetworkId,

    [Parameter(Mandatory)]
    [string]$StoragePathId,

    [Parameter(Mandatory)]
    [string]$VHDXSourcePath,

    [Parameter()]
    [string]$AdminUsername = 'localadmin',

    [Parameter()]
    [ValidateSet('Windows', 'Linux')]
    [string]$OsType = 'Windows'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

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
    <#
    .SYNOPSIS
        Runs an az CLI command, captures output and exit code, throws on failure.
    #>
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
Write-Host "  Script 06 — Create Azure Local VM" -ForegroundColor Magenta
Write-Host "  Path: Azure Local VM (Portal-Managed)" -ForegroundColor Magenta
Write-Host "=====================================================================" -ForegroundColor Magenta
Write-Host ""
Write-Host "  VM Name       : $VMName"
Write-Host "  Resource Group: $ResourceGroup"
Write-Host "  Subscription  : $SubscriptionId"
Write-Host ""

#endregion

#region ── Pre-flight Validation ───────────────────────────────────────────────

Write-Step "Pre-flight validation"

$failures = [System.Collections.Generic.List[string]]::new()

# ── Azure CLI present ─────────────────────────────────────────────────────────
if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    $failures.Add("Azure CLI (az) not found. Install from https://aka.ms/installazurecli")
}
else {
    Write-OK "Azure CLI found"
}

# ── stack-hci-vm extension present ───────────────────────────────────────────
try {
    $ext = & az extension show --name 'stack-hci-vm' 2>&1
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

# ── VHDX source file exists ───────────────────────────────────────────────────
if (-not (Test-Path $VHDXSourcePath)) {
    $failures.Add("VHDX source file not found: $VHDXSourcePath")
}
else {
    $vhdxSize = [math]::Round((Get-Item $VHDXSourcePath).Length / 1GB, 2)
    Write-OK "VHDX found: $VHDXSourcePath ($vhdxSize GB)"
}

# ── Working directory exists ──────────────────────────────────────────────────
if (-not (Test-Path $WorkingDirectory)) {
    $failures.Add("Working directory not found: $WorkingDirectory. Run script 01 first.")
}
else {
    Write-OK "Working directory found: $WorkingDirectory"
}

# ── Config JSON exists ────────────────────────────────────────────────────────
$configPath = Join-Path $WorkingDirectory "Configs\${VMName}_config.json"
if (-not (Test-Path $configPath)) {
    Write-Warn "VM config file not found at $configPath. Proceeding without it (manual parameters will be used)."
}
else {
    Write-OK "VM config found: $configPath"
}

# ── Log directory ─────────────────────────────────────────────────────────────
$logDir = Join-Path $WorkingDirectory 'Logs'
if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}
$logFile = Join-Path $logDir "AzLocalVM_Create_${VMName}_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

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

#region ── Resource Names ────────────────────────────────────────────────────────

$imageName  = "img-$VMName"
$nicName    = "nic-$VMName"

Write-Host ""
Write-Host "  Resources to be created:"
Write-Host "    Image  : $imageName"
Write-Host "    NIC    : $nicName"
Write-Host "    VM     : $VMName"
Write-Host ""

#endregion

#region ── Step 1: Register VHDX as Azure Local Image ───────────────────────────

Write-Step "Registering VHDX as Azure Local gallery image: $imageName"
Write-Host "  Source VHDX : $VHDXSourcePath"
Write-Host "  This may take several minutes depending on disk size..." -ForegroundColor Yellow

$imageArgs = @(
    'stack-hci-vm', 'image', 'create',
    '--name', $imageName,
    '--resource-group', $ResourceGroup,
    '--custom-location', $CustomLocationId,
    '--os-type', $OsType,
    '--image-path', $VHDXSourcePath,
    '--storage-path-id', $StoragePathId,
    '--output', 'json'
)

$imageResult = Invoke-AzCli -Arguments $imageArgs -StepName "az stack-hci-vm image create"

if (-not $WhatIfPreference) {
    if ($imageResult.provisioningState -ne 'Succeeded') {
        Write-Fail "Image provisioning state: $($imageResult.provisioningState)"
        throw "Image creation did not complete successfully."
    }
    Write-OK "Image registered successfully: $($imageResult.id)"
    $imageId = $imageResult.id
}
else {
    $imageId = "<WhatIf: image resource ID>"
}

#endregion

#region ── Step 2: Create NIC Resource ──────────────────────────────────────────

Write-Step "Creating logical NIC resource: $nicName"

$nicArgs = @(
    'stack-hci-vm', 'network', 'nic', 'create',
    '--name', $nicName,
    '--resource-group', $ResourceGroup,
    '--custom-location', $CustomLocationId,
    '--subnet-id', $LogicalNetworkId,
    '--output', 'json'
)

$nicResult = Invoke-AzCli -Arguments $nicArgs -StepName "az stack-hci-vm network nic create"

if (-not $WhatIfPreference) {
    if ($nicResult.provisioningState -ne 'Succeeded') {
        Write-Fail "NIC provisioning state: $($nicResult.provisioningState)"
        throw "NIC creation did not complete successfully."
    }
    Write-OK "NIC created successfully: $($nicResult.id)"
    $nicId = $nicResult.id
}
else {
    $nicId = "<WhatIf: NIC resource ID>"
}

#endregion

#region ── Step 3: Deploy Azure Local VM ────────────────────────────────────────

Write-Step "Deploying Azure Local VM: $VMName"
Write-Host "  Image  : $imageName"
Write-Host "  NIC    : $nicName"
Write-Host "  This may take several minutes..." -ForegroundColor Yellow

# Prompt for admin password securely — required by az stack-hci-vm create
$adminPassword = $null
if (-not $WhatIfPreference) {
    $securePassword = Read-Host "  Enter local administrator password for '$AdminUsername'" -AsSecureString
    $adminPassword  = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
        [Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword)
    )
}

$vmArgs = @(
    'stack-hci-vm', 'create',
    '--name', $VMName,
    '--resource-group', $ResourceGroup,
    '--custom-location', $CustomLocationId,
    '--image', $imageName,
    '--nics', $nicName,
    '--storage-path-id', $StoragePathId,
    '--admin-username', $AdminUsername,
    '--output', 'json'
)

if ($adminPassword) {
    $vmArgs += @('--admin-password', $adminPassword)
}

$vmResult = Invoke-AzCli -Arguments $vmArgs -StepName "az stack-hci-vm create"

# Clear password from memory
if ($adminPassword) { $adminPassword = $null }

if (-not $WhatIfPreference) {
    if ($vmResult.provisioningState -ne 'Succeeded') {
        Write-Fail "VM provisioning state: $($vmResult.provisioningState)"
        throw "VM creation did not complete successfully."
    }
    Write-OK "VM deployed successfully: $($vmResult.id)"
}

#endregion

#region ── Summary ───────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "=====================================================================" -ForegroundColor Green
Write-Host "  Deployment Complete" -ForegroundColor Green
Write-Host "=====================================================================" -ForegroundColor Green
Write-Host ""
if (-not $WhatIfPreference) {
    Write-Host "  VM Name       : $VMName"
    Write-Host "  Resource Group: $ResourceGroup"
    Write-Host "  Resource ID   : $($vmResult.id)"
    Write-Host ""
}
Write-Host "  Next Steps:" -ForegroundColor Cyan
Write-Host "    1. Connect to the VM via Azure portal or RDP"
Write-Host "    2. Complete Windows OOBE / specialization pass"
Write-Host "    3. Rename the computer (Rename-Computer -NewName '$VMName' -Restart)"
Write-Host "    4. Re-join domain and update DNS records"
Write-Host "    5. Re-install applications and restore data from backup"
Write-Host ""
Write-Host "  See runbook-azurelocal.adoc Step 5 for full post-deployment checklist."
Write-Host ""

if ($logFile) {
    "Deployment completed at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" | Out-File -FilePath $logFile -Append
    "VM: $VMName | ResourceGroup: $ResourceGroup | SubscriptionId: $SubscriptionId" | Out-File -FilePath $logFile -Append
    Write-Host "  Log written to: $logFile" -ForegroundColor Gray
}

#endregion
