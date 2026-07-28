# Getting Started

This guide helps you choose the right conversion path and get running quickly.
Before touching anything, read [Gen 1 vs Gen 2: Should You Convert?](gen1-vs-gen2.md) — conversion is destructive and one-way.
If you have already decided to proceed, start here.

---

## Choose Your Path

This toolkit provides two fully separate sets of scripts.
Choose **one** based on how the converted VM needs to be managed after conversion.

| | Path 1 — Azure Local **(primary)** | Path 2 — Hyper-V |
|---|---|---|
| **Scripts** | `scripts/azurelocal/` | `scripts/hyperv/` |
| **Azure required?** | ✓ Subscription, resource group, custom location | ✗ None |
| **VM visible in Azure portal?** | Yes — full `Microsoft.AzureStackHCI/virtualMachineInstances` resource | No — Hyper-V Manager and Failover Cluster Manager only |
| **Azure portal operations** | Start/stop, extensions, RBAC, monitoring | Not available |
| **Arc registration** | Automatic via Arc resource bridge after reconnect | Exists only if your cluster was already Arc-registered separately |
| **Extra step after Gen 2 conversion** | `az stack-hci-vm reconnect-to-azure` (Preview) | None |
| **Best for** | Azure Local 23H2+ — standardizing on portal-managed VMs | Hyper-V-managed clusters, no portal management requirement |

### Use Path 1 — Azure Local if:

- Your cluster is running **Azure Local 23H2+**
- You want the VM to appear in the Azure portal VM blade alongside your other Azure Local VMs
- You are standardizing on Azure-managed infrastructure
- You need Azure policy, extensions, or RBAC on the converted VM

### Use Path 2 — Hyper-V if:

- You only need the VM in Hyper-V Manager / Failover Cluster Manager
- No Azure connectivity is available or required
- You want the simplest possible path with zero Azure dependencies
- Your cluster is a standalone Hyper-V cluster without Azure Local registration

> [!NOTE]
> **Azure Local is the primary focus of this toolkit.** Path 1 is the recommended path for Azure Local clusters. Path 2 is included for environments that need Hyper-V-only management with no Azure dependencies.
>
---

## Before You Start

Regardless of path, complete these checks first.

### 1. Confirm the VM is actually a conversion candidate

Not every Gen 1 VM is worth converting. Read [the decision checklist](gen1-vs-gen2.md#decision-checklist) and work through it honestly. If the VM is stable and serving its workload, the safest answer is often to leave it alone.

### 2. Check guest OS compatibility

Run this **inside the guest VM** before doing anything else:

```powershell
# Copy the path-specific script into the guest VM first, then run:
.\02-Convert-MBRtoGPT.ps1 -ValidateOnly
```

This runs `mbr2gpt.exe /validate` without making any changes.
If validation fails, see [mbr2gpt fails validation](troubleshooting.md#mbr2gpt-fails-validation) before continuing.

Requirements:

- 64-bit Windows only (`mbr2gpt.exe` does not support 32-bit)
- Windows Server 2012 R2 / Windows 10 build 14393 or later
- Boot disk must have 3 or fewer primary partitions, no extended/logical partitions
- Hyper-V Integration Services installed and current

### 3. Check disk space

You need approximately **1x the total VHDX size** of each VM being converted available on the target CSV for backups.
Run this on the cluster node to check free space:

```powershell
Get-ClusterSharedVolume | ForEach-Object {
    $info = $_.SharedVolumeInfo
    [PSCustomObject]@{
        Name      = $_.Name
        FreeGB    = [math]::Round($info.Partition.FreeSpace / 1GB, 1)
        TotalGB   = [math]::Round($info.Partition.Size / 1GB, 1)
    }
} | Format-Table -AutoSize
```

### 4. Remove VM checkpoints

Script 03 will refuse to run if the VM has any checkpoints. Remove them all before starting:

```powershell
Get-VMCheckpoint -VMName "WebServer01" | Remove-VMCheckpoint
```

### 5. Schedule a maintenance window

Each VM will be offline from shutdown (Step 2) through Gen 2 first boot (end of Step 3) — typically **5–15 minutes plus VHDX backup time**. The reconnect step (Path 1 Step 4) does not require additional downtime.

---

## Path 1 — Azure Local **(Primary Path)**

### Prerequisites

In addition to the common checks above, you need:

- Azure Local cluster running **23H2 or later**
- Azure subscription with the following roles on the cluster resource group:
    - `Azure Stack HCI Administrator` — required to run conversion scripts
    - `Azure Stack HCI VM Contributor` — sufficient for scoped service accounts
- Azure CLI with the `stack-hci-vm` extension:

    ```powershell
    az extension add --name stack-hci-vm
    az extension show --name stack-hci-vm
    ```

- Your Azure resource IDs ready (find them with the commands in [Finding Required Azure Resource IDs](prerequisites.md#finding-required-azure-resource-ids))

### Scripts

`scripts/azurelocal/` — all four scripts, Azure-aware:

| Script | What it does |
|---|---|
| `01-Setup-ConversionEnvironment.ps1` | Validates cluster and Azure connectivity, inventories Gen 1 VMs, exports configs |
| *(guest)* `02-Convert-MBRtoGPT.ps1` | Converts boot disk MBR → GPT inside the guest VM |
| `03-Convert-Gen1toGen2.ps1` | Gen 1 → Gen 2 conversion — removes old VM, creates Gen 2, re-clusters |
| `05-Reconnect-AzureLocalVM.ps1` | Projects the Gen 2 Hyper-V VM into Azure as a `virtualMachineInstances` resource |

### Run the Conversion

Follow [Runbook: Azure Local VM Path](runbook-azurelocal.md) for the full step-by-step walkthrough.

Quick reference — run these four steps in order:

```powershell
# Step 1 — Cluster node
.\scripts\azurelocal\01-Setup-ConversionEnvironment.ps1 `
    -ClusterName "MyAzureLocalCluster" `
    -WorkingDirectory "C:\ClusterStorage\Volume01\Gen2Conversion" `
    -SubscriptionId "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" `
    -ResourceGroup "rg-azurelocal-prod"

# Step 2 — Inside the guest VM (copy script into guest first)
.\02-Convert-MBRtoGPT.ps1
# Then: Stop-Computer -Force  (do NOT reboot)

# Step 3 — Cluster node (after guest is shut down)
.\scripts\azurelocal\03-Convert-Gen1toGen2.ps1 `
    -VMName "WebServer01" `
    -WorkingDirectory "C:\ClusterStorage\Volume01\Gen2Conversion" `
    -ResourceGroup "rg-azurelocal-prod" `
    -SubscriptionId "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" `
    -CustomLocationId "/subscriptions/.../customLocations/myAzureLocal" `
    -LogicalNetworkId "/subscriptions/.../logicalNetworks/mgmt-lnet"

# Step 4 — Cluster node / management workstation
.\scripts\azurelocal\05-Reconnect-AzureLocalVM.ps1 `
    -VMName "WebServer01" `
    -ResourceGroup "rg-azurelocal-prod" `
    -SubscriptionId "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" `
    -CustomLocationId "/subscriptions/.../customLocations/myAzureLocal" `
    -LogicalNetworkId "/subscriptions/.../logicalNetworks/mgmt-lnet"
```

> [!CAUTION]
> `az stack-hci-vm reconnect-to-azure` is a **Preview** command. Confirm it is available in your `stack-hci-vm` extension before running Step 4: `az stack-hci-vm reconnect-to-azure --help`
>
---

## Path 2 — Hyper-V

### Prerequisites

In addition to the common checks above, you need:

- Hyper-V and FailoverClusters PowerShell modules (built into Windows Server — no install needed)
- No Azure connectivity or credentials required

### Scripts

`scripts/hyperv/` — three scripts, zero Azure dependencies:

| Script | What it does |
|---|---|
| `01-Setup-ConversionEnvironment.ps1` | Validates cluster health, inventories Gen 1 VMs, exports configs. No Azure. |
| *(guest)* `02-Convert-MBRtoGPT.ps1` | Converts boot disk MBR → GPT inside the guest VM |
| `03-Convert-Gen1toGen2.ps1` | Gen 1 → Gen 2 conversion — removes old VM, creates Gen 2, re-clusters. No Azure. |
| `04-Batch-ConvertVMs.ps1` | Batch orchestrator for multiple VMs. No Azure. |

### Run the Conversion

Follow [Runbook: Hyper-V Cluster Path](runbook-hyperv.md) for the full step-by-step walkthrough.

Quick reference:

```powershell
# Step 1 — Cluster node
.\scripts\hyperv\01-Setup-ConversionEnvironment.ps1 `
    -ClusterName "HV-Cluster01" `
    -WorkingDirectory "C:\ClusterStorage\Volume01\Gen2Conversion"

# Step 2 — Inside the guest VM
.\02-Convert-MBRtoGPT.ps1
# Then: Stop-Computer -Force  (do NOT reboot)

# Step 3 — Cluster node (after guest is shut down)
.\scripts\hyperv\03-Convert-Gen1toGen2.ps1 `
    -VMName "WebServer01" `
    -WorkingDirectory "C:\ClusterStorage\Volume01\Gen2Conversion"

# Optional: batch convert multiple VMs
.\scripts\hyperv\04-Batch-ConvertVMs.ps1 `
    -WorkingDirectory "C:\ClusterStorage\Volume01\Gen2Conversion" `
    -VMNames @("WebServer01", "SQLServer01")
```

---

## After Conversion

Regardless of path, verify the following inside the guest VM after first boot:

```powershell
# Confirm UEFI boot mode (should show "UEFI", not "Legacy")
msinfo32

# Confirm GPT partition table
Get-Disk | Select-Object Number, PartitionStyle, FriendlyName
```

If the VM fails to boot, see [VM Won't Boot After Gen 2 Conversion](troubleshooting.md#vm-wont-boot).

If you need to roll back, see [Rolling Back a Failed Conversion](troubleshooting.md#rolling-back-a-failed-conversion) — VHDX backups are in `WorkingDirectory\Backups\<VMName>\`.

---

## Full Documentation

| Document | Contents |
|---|---|
| [Gen 1 vs Gen 2: Should You Convert?](gen1-vs-gen2.md) | Feature comparison, decision checklist, and path selection guide. **Read this first.** |
| [Prerequisites](prerequisites.md) | Full module, permission, and connectivity requirements for both paths |
| [Runbook: Azure Local VM Path](runbook-azurelocal.md) | Complete step-by-step walkthrough for Path 1 |
| [Runbook: Hyper-V Cluster Path](runbook-hyperv.md) | Complete step-by-step walkthrough for Path 2 |
| [Troubleshooting](troubleshooting.md) | Common failure scenarios, rollback instructions, Arc registration issues |
