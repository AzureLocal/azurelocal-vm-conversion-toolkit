# Azure Local VM Conversion Toolkit

![Azure Local VM Conversion Toolkit](docs/assets/images/azurelocal-vm-conversion-toolkit-banner.svg)

[![Azure Local](https://img.shields.io/badge/Azure%20Local-azurelocal.cloud-0078D4?logo=microsoft-azure)](https://azurelocal.cloud)

Documentation: [azurelocal.cloud](https://azurelocal.cloud) | Solutions: [Azure Local Solutions](https://azurelocal.cloud)

PowerShell toolkit for converting Hyper-V Gen 1 VMs to Gen 2 on Azure Local while preserving Azure Arc management.

---

> **Internal tool. Private repository, not for distribution.**
>
> **Status: work in progress, version 0.1.0, no releases or tags, not yet verified end to end on a live cluster.**
> Script 05 runs `az stack-hci-vm reconnect-to-azure` and needs an Azure CLI `stack-hci-vm` extension version that provides it; check with `az extension show --name stack-hci-vm` and `az stack-hci-vm -h`. The Hyper-V path (scripts 01-04 under `scripts/hyperv/`) does not use Azure at all.
>
> Unit tests (`tests/Unit`, Pester 5) mock every Hyper-V, cluster, disk, BitLocker and `az` call; they do not replace a live proof.

> **⚠️ USE AT YOUR OWN RISK**
>
> This toolkit modifies virtual machine configurations, partition tables, and Azure resource registrations. These are **destructive, potentially irreversible operations**. By using these scripts, you accept full responsibility for any outcomes including data loss, VM downtime, broken Azure Arc registrations, or other unintended consequences. **Always back up your VMs and test in a non-production environment first.** The authors assume no liability for damages resulting from the use of this toolkit.

---

## Why this exists, and where Azure Migrate fits

Azure Migrate keeps the generation of the source VM: a Gen 1 source stays Gen 1 on Azure Local ([Learn](https://learn.microsoft.com/azure/azure-local/migrate/migrate-hyperv-requirements#considerations-for-migrating-hyper-v-vms-to-azure-local)). Gen 1 VMs have [limitations in Azure Local VM management](https://learn.microsoft.com/azure/azure-local/manage/azure-arc-vm-management-overview#limitations-of-azure-local-vm-management), and there is no in-place Gen 1 to Gen 2 upgrade. That gap is what this toolkit covers. If you are migrating VMs onto Azure Local and Gen 1 is acceptable, use [Azure Migrate](https://learn.microsoft.com/azure/azure-local/migrate/migration-options-overview) (its [Arc-reuse feature](https://learn.microsoft.com/azure/azure-local/migrate/migrate-arc-reuse) keeps an existing Azure Arc resource). Use this toolkit when the VM must become Gen 2.

Microsoft lists [cloning or copying an Azure Local VM as an unsupported operation](https://learn.microsoft.com/azure/azure-local/manage/virtual-machine-operations#unsupported-vm-operations). Script 03 removes the Gen 1 VM and rebuilds it from the same disks rather than copying it, and `reconnect-to-azure` (script 05) is the only route this toolkit supports for putting the rebuilt VM back under Azure management.

## What This Does

There is no in-place upgrade path from Hyper-V Gen 1 to Gen 2. This toolkit automates the manual process and supports two distinct conversion paths:

**Path 1 — Azure Local VM (portal-managed)** *(primary)*
1. Inventories Gen 1 VMs and exports their full configurations
2. Converts boot disks from MBR to GPT inside the guest OS
3. Recreates each VM as a Gen 2 Hyper-V VM with identical settings (CPU, memory, NICs, VLANs, disks)
4. Registers the converted Gen 2 VM into the Azure Local management plane using `az stack-hci-vm reconnect-to-azure` — workload-preserving, no Sysprep, no identity loss
5. VM becomes a `Microsoft.AzureStackHCI/virtualMachineInstances` resource visible and managed in the Azure portal

**Path 2 — Hyper-V Cluster (workload-preserving)**
1. Inventories Gen 1 VMs and exports their full configurations
2. Converts boot disks from MBR to GPT inside the guest OS
3. Recreates each VM as a Gen 2 Hyper-V VM with identical settings (CPU, memory, NICs, VLANs, disks)
4. Re-adds VMs to the failover cluster — no Azure, no Arc, no portal

See **[docs/gen1-vs-gen2.md](docs/gen1-vs-gen2.md)** to choose the right path before running anything.

## Should You Actually Convert?

**Probably not.** If your Gen 1 VM is stable and serving its workload, the safest path is to leave it alone. Conversion is a destructive, one-way operation — and in most cases, deploying a new Gen 2 VM and migrating the workload to it is a better approach than converting an existing VM in place.

Gen 2 unlocks specific capabilities — vTPM, Secure Boot, Trusted Launch, and boot disks larger than 2 TB — but those features are rarely worth the conversion risk unless you have a hard requirement for them.

Before running anything, read **[docs/gen1-vs-gen2.md](docs/gen1-vs-gen2.md)** for a full breakdown of what Gen 2 adds, when conversion makes sense, and a decision checklist to work through.

## Prerequisites

- **Operating System (guest, for script 02)**: 64-bit **Windows Server 2019 or later**, or **Windows 10 1703 (build 15063) or later**. `mbr2gpt.exe` ships only with those; Windows Server 2016 does not include it, and offline conversion of Windows 7, 8 and 8.1 is not supported ([Learn](https://learn.microsoft.com/windows/deployment/mbr-to-gpt)). Upgrade older guests first. Script 02 also checks that the file is really present.
- **BitLocker**: MBR2GPT converts a BitLocker volume only while protection is suspended. Script 02 suspends it (after asking) and verifies that before converting; recreate the protectors afterwards.
- **Azure Local**: 23H2 or later recommended (22H2 supported)
- **PowerShell**: 5.1+ with Az modules (Az.Accounts, Az.Resources, Az.StackHCI, Az.ConnectedMachine)
- **Hyper-V & FailoverClusters**: PowerShell modules installed on the cluster node
- **Azure CLI**: `az stack-hci-vm` extension for manual Arc registration fallback
- **Disk Space**: Enough CSV capacity for the VHDX backups (about 1x the total size of the VMs being converted). Script 03 checks free space first.
- **Maintenance Window**: Each VM will have downtime during conversion

See [docs/prerequisites.md](docs/prerequisites.md) for full details and setup commands.

## Safety rules built into script 03

- A full copy of every disk file (including parents of differencing disks) is made to `Backups\<VM>\<timestamp>` and verified by size and SHA256 **before** the VM is removed from the cluster or Hyper-V. The VM is not removed unless every file verified.
- `-BackupVHDX:$false` is refused unless you also pass `-IUnderstandNoBackup`.
- `-WhatIf` reads and reports only: nothing is copied, converted or removed.
- If the rebuild fails after the removal, the log lists where the original disks and the verified backup are. No disk file is ever deleted by the toolkit.

## Scripts

### Path 1 — Azure Local VM (portal-managed, scripts 01–03 + 05) *(primary)*

| Script | Runs On | Purpose |
|--------|---------|--------|
| [`scripts/azurelocal/01-Setup-ConversionEnvironment.ps1`](scripts/azurelocal/01-Setup-ConversionEnvironment.ps1) | Azure Local cluster node | Validates cluster and Azure connectivity, inventories Gen 1 VMs, exports configs |
| [`scripts/azurelocal/02-Convert-MBRtoGPT.ps1`](scripts/azurelocal/02-Convert-MBRtoGPT.ps1) | Inside each guest VM | Validates OS compatibility and runs `mbr2gpt.exe` to convert the boot disk from MBR to GPT |
| [`scripts/azurelocal/03-Convert-Gen1toGen2.ps1`](scripts/azurelocal/03-Convert-Gen1toGen2.ps1) | Azure Local cluster node | Removes Gen 1 VM, creates Gen 2 Hyper-V VM with same config, re-clusters. Run Script 05 next to project into Azure portal. |
| [`scripts/azurelocal/04-Batch-ConvertVMs.ps1`](scripts/azurelocal/04-Batch-ConvertVMs.ps1) | Azure Local cluster node | Runs script 03 and then script 05 for each Gen 1 VM in the inventory |
| [`scripts/azurelocal/05-Reconnect-AzureLocalVM.ps1`](scripts/azurelocal/05-Reconnect-AzureLocalVM.ps1) | Cluster node / mgmt workstation | Creates Azure Local NIC resource, then calls `az stack-hci-vm reconnect-to-azure` to project the Gen 2 VM into the portal as `Microsoft.AzureStackHCI/virtualMachineInstances` |

### Path 2 — Hyper-V Cluster (workload-preserving, scripts 01–04)

| Script | Runs On | Purpose |
|--------|---------|--------|
| [`scripts/hyperv/01-Setup-ConversionEnvironment.ps1`](scripts/hyperv/01-Setup-ConversionEnvironment.ps1) | Hyper-V cluster node | Validates cluster health, inventories all Gen 1 VMs, exports configs. No Azure required. |
| [`scripts/hyperv/02-Convert-MBRtoGPT.ps1`](scripts/hyperv/02-Convert-MBRtoGPT.ps1) | Inside each guest VM | Validates OS compatibility and runs `mbr2gpt.exe` to convert the boot disk from MBR to GPT |
| [`scripts/hyperv/03-Convert-Gen1toGen2.ps1`](scripts/hyperv/03-Convert-Gen1toGen2.ps1) | Hyper-V cluster node | Removes Gen 1 VM, creates Gen 2 Hyper-V VM with same config, re-clusters. No Azure required. |
| [`scripts/hyperv/04-Batch-ConvertVMs.ps1`](scripts/hyperv/04-Batch-ConvertVMs.ps1) | Hyper-V cluster node | Orchestrates Script 03 across multiple VMs with pre-flight checks and reporting. No Azure required. |

## Documentation

| Doc | Description |
|-----|-------------|
| [docs/gen1-vs-gen2.md](docs/gen1-vs-gen2.md) | **Start here** — Gen 1 vs Gen 2 decision guide, feature comparison, path selection, and checklist |
| [docs/getting-started.md](docs/getting-started.md) | Path selection, pre-flight checks, and quick-start commands for both paths |
| [docs/runbook-azurelocal.md](docs/runbook-azurelocal.md) | Full runbook for Path 1 — Azure Local VM (portal-managed, workload-preserving, scripts 01–03 + 05) |
| [docs/runbook-hyperv.md](docs/runbook-hyperv.md) | Full runbook for Path 2 — Hyper-V Cluster (no Azure, scripts 01–04) |
| [docs/prerequisites.md](docs/prerequisites.md) | Full prerequisites, module setup, and Azure permission requirements |
| [docs/troubleshooting.md](docs/troubleshooting.md) | Common issues and solutions, rollback instructions |

## Tests

```powershell
pwsh ./tests/Invoke-Checks.ps1 -Check All    # PSScriptAnalyzer, Pester 5 unit tests, Markdown links
```

Nothing in the tests touches a VM, a cluster, a disk layout or Azure.

## Contributing

This project is in early development. If you find bugs, have suggestions, or want to contribute, feel free to open an issue or submit a pull request. See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## License

MIT
