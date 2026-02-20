# Azure Local VM Conversion Toolkit

PowerShell toolkit for converting Hyper-V Gen 1 VMs to Gen 2 on Azure Local while preserving Azure Arc management.

---

> **🚧 UNDER ACTIVE DEVELOPMENT**
>
> This project is a work in progress. Scripts are being actively developed and have **not been fully tested** across all Azure Local configurations, OS versions, or deployment scenarios. Features may be incomplete, and breaking changes can occur without notice.

> **⚠️ USE AT YOUR OWN RISK**
>
> This toolkit modifies virtual machine configurations, partition tables, and Azure resource registrations. These are **destructive, potentially irreversible operations**. By using these scripts, you accept full responsibility for any outcomes including data loss, VM downtime, broken Azure Arc registrations, or other unintended consequences. **Always back up your VMs and test in a non-production environment first.** The authors assume no liability for damages resulting from the use of this toolkit.

---

## What This Does

There is no in-place upgrade path from Hyper-V Gen 1 to Gen 2. This toolkit automates the manual process and supports two distinct conversion paths:

**Path 1 — Hyper-V Cluster (workload-preserving)**
1. Inventories Gen 1 VMs and exports their full configurations
2. Converts boot disks from MBR to GPT inside the guest OS
3. Recreates each VM as a Gen 2 Hyper-V VM with identical settings (CPU, memory, NICs, VLANs, disks)
4. Re-adds VMs to the failover cluster and re-registers with Azure Arc

**Path 2 — Azure Local VM (portal-managed)**
1. Same inventory and MBR→GPT steps as Path 1
2. Syspreps (generalizes) the guest OS — identity-destructive; machine SID and domain join are lost
3. Registers the sysprepped VHDX as an Azure Local image resource
4. Deploys a new `Microsoft.AzureStackHCI/virtualMachineInstances` resource via `az stack-hci-vm create`

See **[docs/gen1-vs-gen2.adoc](docs/gen1-vs-gen2.adoc)** to choose the right path before running anything.

## Should You Actually Convert?

**Probably not.** If your Gen 1 VM is stable and serving its workload, the safest path is to leave it alone. Conversion is a destructive, one-way operation — and in most cases, deploying a new Gen 2 VM and migrating the workload to it is a better approach than converting an existing VM in place.

Gen 2 unlocks specific capabilities — vTPM, Secure Boot, Trusted Launch, and boot disks larger than 2 TB — but those features are rarely worth the conversion risk unless you have a hard requirement for them.

Before running anything, read **[docs/gen1-vs-gen2.adoc](docs/gen1-vs-gen2.adoc)** for a full breakdown of what Gen 2 adds, when conversion makes sense, and a decision checklist to work through.

## Prerequisites

- **Operating System**: 64-bit Windows Server 2012 R2+ or Windows 10+ (or supported Linux distros) running inside the VMs
- **Azure Local**: 23H2 or later recommended (22H2 supported)
- **PowerShell**: 5.1+ with Az modules (Az.Accounts, Az.Resources, Az.StackHCI, Az.ConnectedMachine)
- **Hyper-V & FailoverClusters**: PowerShell modules installed on the cluster node
- **Azure CLI**: `az stack-hci-vm` extension for manual Arc registration fallback
- **Disk Space**: Enough CSV capacity for VHDX backups (~1x the total size of VMs being converted)
- **Maintenance Window**: Each VM will have downtime during conversion

See [docs/prerequisites.adoc](docs/prerequisites.adoc) for full details and setup commands.

## Scripts

### Path 1 — Hyper-V Cluster (workload-preserving, scripts 01–04)

| Script | Runs On | Purpose |
|--------|---------|--------|
| [`scripts/cluster/01-Setup-ConversionEnvironment.ps1`](scripts/cluster/01-Setup-ConversionEnvironment.ps1) | Azure Local cluster node | Validates cluster health, Azure connectivity, inventories all Gen 1 VMs, exports configs |
| [`scripts/guest/02-Convert-MBRtoGPT.ps1`](scripts/guest/02-Convert-MBRtoGPT.ps1) | Inside each guest VM | Validates OS compatibility and runs `mbr2gpt.exe` to convert the boot disk from MBR to GPT |
| [`scripts/cluster/03-Convert-Gen1toGen2.ps1`](scripts/cluster/03-Convert-Gen1toGen2.ps1) | Azure Local cluster node | Removes Gen 1 VM, creates Gen 2 Hyper-V VM with same config, re-clusters, re-registers with Arc |
| [`scripts/cluster/04-Batch-ConvertVMs.ps1`](scripts/cluster/04-Batch-ConvertVMs.ps1) | Azure Local cluster node | Orchestrates Script 03 across multiple VMs with pre-flight checks and reporting |

### Path 2 — Azure Local VM (portal-managed, scripts 01–02 + 05–06)

| Script | Runs On | Purpose |
|--------|---------|--------|
| [`scripts/cluster/01-Setup-ConversionEnvironment.ps1`](scripts/cluster/01-Setup-ConversionEnvironment.ps1) | Azure Local cluster node | Same as Path 1 — inventory and setup |
| [`scripts/guest/02-Convert-MBRtoGPT.ps1`](scripts/guest/02-Convert-MBRtoGPT.ps1) | Inside each guest VM | Same as Path 1 — MBR to GPT conversion |
| [`scripts/guest/05-Sysprep-PrepareImage.ps1`](scripts/guest/05-Sysprep-PrepareImage.ps1) | Inside each guest VM | Validates, then runs Sysprep `/generalize /oobe /shutdown` — **destructive, identity-destroying** |
| [`scripts/cluster/06-Create-AzureLocalVM.ps1`](scripts/cluster/06-Create-AzureLocalVM.ps1) | Cluster node / mgmt workstation | Registers sysprepped VHDX as image resource, creates NIC, deploys Azure Local VM via `az stack-hci-vm create` |

## Documentation

| Doc | Description |
|-----|-------------|
| [docs/gen1-vs-gen2.adoc](docs/gen1-vs-gen2.adoc) | **Start here** — Gen 1 vs Gen 2 decision guide, feature comparison, path selection, and checklist |
| [docs/runbook-hyperv.adoc](docs/runbook-hyperv.adoc) | Runbook for Path 1 — Hyper-V Cluster (workload-preserving, scripts 01–04) |
| [docs/runbook-azurelocal.adoc](docs/runbook-azurelocal.adoc) | Runbook for Path 2 — Azure Local VM (portal-managed, requires Sysprep, scripts 01–02 + 05–06) |
| [docs/prerequisites.adoc](docs/prerequisites.adoc) | Full prerequisites, module setup, and Azure permission requirements |
| [docs/troubleshooting.adoc](docs/troubleshooting.adoc) | Common issues and solutions, rollback instructions |

## Contributing

This project is in early development. If you find bugs, have suggestions, or want to contribute, feel free to open an issue or submit a pull request. See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## License

MIT
