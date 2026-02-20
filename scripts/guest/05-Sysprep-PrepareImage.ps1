#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Prepares a Windows guest VM for deployment as an Azure Local VM image by
    running Sysprep to generalize the operating system.

.DESCRIPTION
    This script is part of the Azure Local VM Conversion Toolkit — Path 2 (Azure Local VM).

    It validates pre-conditions and then runs Sysprep with /generalize /oobe /shutdown
    to produce a generalized VHDX that can be registered as an Azure Local image resource
    and deployed via 'az stack-hci-vm create'.

    *** THIS IS A DESTRUCTIVE, ONE-WAY OPERATION ***

    Sysprep removes:
      - Machine SID and computer account credentials
      - Domain join state (the VM will boot in workgroup mode)
      - User profile data in some configurations
      - Machine-bound application state and licenses

    After Sysprep the VM will shut down. Do NOT boot it again before registering
    the VHDX in Azure Local — doing so will regeneralize the image or leave it in
    an inconsistent state.

    Run this script INSIDE the guest VM, not from the cluster host.

.PARAMETER ValidateOnly
    Performs all pre-flight checks and reports findings without making any changes.
    No sysprep is run. Use this to confirm readiness before committing.

.EXAMPLE
    # Dry run — validate only
    .\05-Sysprep-PrepareImage.ps1 -ValidateOnly

    # Perform sysprep (VM will shut down when complete)
    .\05-Sysprep-PrepareImage.ps1

.NOTES
    Run this script inside the guest VM.
    Requires Windows PowerShell 5.1 or PowerShell 7+.
    Tested on: Windows Server 2019, Windows Server 2022.
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter()]
    [switch]$ValidateOnly
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

#endregion

#region ── Banner ────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "=====================================================================" -ForegroundColor Magenta
Write-Host "  Azure Local VM Conversion Toolkit" -ForegroundColor Magenta
Write-Host "  Script 05 — Sysprep / Prepare Image" -ForegroundColor Magenta
Write-Host "  Path: Azure Local VM (Portal-Managed)" -ForegroundColor Magenta
Write-Host "=====================================================================" -ForegroundColor Magenta
Write-Host ""

if ($ValidateOnly) {
    Write-Host "  MODE: VALIDATE ONLY — no changes will be made" -ForegroundColor Yellow
    Write-Host ""
}
else {
    Write-Host "  !! WARNING: THIS OPERATION IS DESTRUCTIVE AND IRREVERSIBLE !!" -ForegroundColor Red
    Write-Host ""
    Write-Host "  Sysprep will:" -ForegroundColor Yellow
    Write-Host "    - Remove the machine SID and computer account" -ForegroundColor Yellow
    Write-Host "    - Remove domain join state" -ForegroundColor Yellow
    Write-Host "    - Invalidate machine-bound application licenses" -ForegroundColor Yellow
    Write-Host "    - Shut down this VM when complete" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  Ensure you have:"
    Write-Host "    [ ] A pre-sysprep backup of the VHDX"
    Write-Host "    [ ] Documented ALL applications, licenses, and domain join settings"
    Write-Host "    [ ] Moved any data you need to keep to a separate data disk"
    Write-Host ""

    $confirm = Read-Host "  Type CONFIRM to proceed with Sysprep, or anything else to exit"
    if ($confirm -ne 'CONFIRM') {
        Write-Host "`nAborted. No changes were made." -ForegroundColor Green
        exit 0
    }
}

#endregion

#region ── Pre-flight Validation ───────────────────────────────────────────────

$failures = [System.Collections.Generic.List[string]]::new()
$warnings  = [System.Collections.Generic.List[string]]::new()

Write-Step "Pre-flight checks"

# ── 1. OS must be Windows ──────────────────────────────────────────────────────
try {
    $os = Get-CimInstance -ClassName Win32_OperatingSystem
    if ($os.Caption -notmatch 'Windows') {
        $failures.Add("Operating system does not appear to be Windows: $($os.Caption)")
    }
    else {
        Write-OK "Operating system: $($os.Caption)"
    }
}
catch {
    $failures.Add("Could not query OS information: $_")
}

# ── 2. Sysprep executable must exist ──────────────────────────────────────────
$sysprepPath = "$env:SystemRoot\System32\Sysprep\Sysprep.exe"
if (-not (Test-Path $sysprepPath)) {
    $failures.Add("Sysprep.exe not found at expected path: $sysprepPath")
}
else {
    Write-OK "Sysprep.exe found: $sysprepPath"
}

# ── 3. Must be running as a local admin ───────────────────────────────────────
$currentPrincipal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $failures.Add("Script must be run as a local administrator.")
}
else {
    Write-OK "Running as administrator"
}

# ── 4. Warn if already domain-joined ──────────────────────────────────────────
$computerSystem = Get-CimInstance -ClassName Win32_ComputerSystem
if ($computerSystem.PartOfDomain) {
    $warnings.Add("VM is currently domain-joined ($($computerSystem.Domain)). Sysprep will remove domain join state. Document OU path and re-join credentials before proceeding.")
}
else {
    Write-OK "VM is in workgroup mode (not domain-joined)"
}

# ── 5. Warn if Sysprep panel log exists from a prior failed attempt ──────────
$panther = "$env:SystemRoot\System32\Sysprep\Panther\setupact.log"
if (Test-Path $panther) {
    $warnings.Add("A previous Sysprep log exists at $panther — review for prior failures before proceeding.")
}

# ── 6. Check for known Sysprep blockers ───────────────────────────────────────

# Windows Store / AppX packages that can block generalization
Write-Host "    Checking for provisioned AppX packages that may block Sysprep..." -ForegroundColor Gray
try {
    $blockers = Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue |
        Where-Object { $_.PackageName -match 'MicrosoftTeams|WindowsStore' }
    if ($blockers) {
        foreach ($b in $blockers) {
            $warnings.Add("AppX package may block Sysprep: $($b.PackageName). Consider removing before proceeding.")
        }
    }
    else {
        Write-OK "No known AppX Sysprep blockers detected"
    }
}
catch {
    $warnings.Add("Could not enumerate AppX packages: $_")
}

# Pending reboots
$pendingRebootKeys = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending',
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired',
    'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\PendingFileRenameOperations'
)
foreach ($key in $pendingRebootKeys) {
    if (Test-Path $key) {
        $warnings.Add("Pending reboot detected ($key). Reboot and re-run script before Sysprep to avoid issues.")
        break
    }
}

# ── Report results ────────────────────────────────────────────────────────────
Write-Host ""
foreach ($w in $warnings) {
    Write-Warn $w
}
foreach ($f in $failures) {
    Write-Fail $f
}

if ($failures.Count -gt 0) {
    Write-Host "`n[!] Pre-flight FAILED — $($failures.Count) issue(s) must be resolved before proceeding." -ForegroundColor Red
    exit 1
}

if ($warnings.Count -gt 0) {
    Write-Host ""
    Write-Host "  $($warnings.Count) warning(s) above require your attention." -ForegroundColor Yellow
    if (-not $ValidateOnly) {
        $proceed = Read-Host "  Type PROCEED to continue despite warnings, or anything else to exit"
        if ($proceed -ne 'PROCEED') {
            Write-Host "`nAborted. No changes were made." -ForegroundColor Green
            exit 0
        }
    }
}

if ($ValidateOnly) {
    Write-Host ""
    Write-Host "  [Validate Only] All checks passed. Run without -ValidateOnly to perform Sysprep." -ForegroundColor Green
    exit 0
}

#endregion

#region ── Run Sysprep ──────────────────────────────────────────────────────────

Write-Step "Running Sysprep (/generalize /oobe /shutdown)"
Write-Host "  Sysprep is running. The VM will shut down when generalization completes." -ForegroundColor Yellow
Write-Host "  Do NOT power on this VM again before registering the VHDX in Azure Local." -ForegroundColor Yellow
Write-Host ""

if ($PSCmdlet.ShouldProcess($env:COMPUTERNAME, 'Sysprep /generalize /oobe /shutdown')) {
    try {
        $sysprepArgs = '/generalize', '/oobe', '/shutdown', '/quiet'
        $result = Start-Process -FilePath $sysprepPath `
                                -ArgumentList $sysprepArgs `
                                -Wait `
                                -PassThru

        if ($result.ExitCode -ne 0) {
            Write-Fail "Sysprep exited with code $($result.ExitCode)."
            Write-Fail "Review $env:SystemRoot\System32\Sysprep\Panther\setupact.log for details."
            exit $result.ExitCode
        }

        # If /shutdown is working correctly the VM should power off before we reach this line.
        # If somehow execution continues, log it.
        Write-OK "Sysprep completed successfully. VM is shutting down."
    }
    catch {
        Write-Fail "Failed to start Sysprep: $_"
        exit 1
    }
}

#endregion
