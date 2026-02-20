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

### Path 1 — Azure Local VM (portal-managed, scripts 01–03 + 05) *(primary)*

| Script | Runs On | Purpose |
|--------|---------|--------|
| [`scripts/azurelocal/01-Setup-ConversionEnvironment.ps1`](scripts/azurelocal/01-Setup-ConversionEnvironment.ps1) | Azure Local cluster node | Validates cluster and Azure connectivity, inventories Gen 1 VMs, exports configs |
| [`scripts/azurelocal/02-Convert-MBRtoGPT.ps1`](scripts/azurelocal/02-Convert-MBRtoGPT.ps1) | Inside each guest VM | Validates OS compatibility and runs `mbr2gpt.exe` to convert the boot disk from MBR to GPT |
| [`scripts/azurelocal/03-Convert-Gen1toGen2.ps1`](scripts/azurelocal/03-Convert-Gen1toGen2.ps1) | Azure Local cluster node | Removes Gen 1 VM, creates Gen 2 Hyper-V VM with same config, re-clusters, Arc resource bookkeeping |
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
| [docs/gen1-vs-gen2.adoc](docs/gen1-vs-gen2.adoc) | **Start here** — Gen 1 vs Gen 2 decision guide, feature comparison, path selection, and checklist |
| [docs/getting-started.adoc](docs/getting-started.adoc) | Path selection, pre-flight checks, and quick-start commands for both paths |
| [docs/runbook-azurelocal.adoc](docs/runbook-azurelocal.adoc) | Full runbook for Path 1 — Azure Local VM (portal-managed, workload-preserving, scripts 01–03 + 05) |
| [docs/runbook-hyperv.adoc](docs/runbook-hyperv.adoc) | Full runbook for Path 2 — Hyper-V Cluster (no Azure, scripts 01–04) |
| [docs/prerequisites.adoc](docs/prerequisites.adoc) | Full prerequisites, module setup, and Azure permission requirements |
| [docs/troubleshooting.adoc](docs/troubleshooting.adoc) | Common issues and solutions, rollback instructions |

## Contributing

This project is in early development. If you find bugs, have suggestions, or want to contribute, feel free to open an issue or submit a pull request. See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## License

MIT
