# Azure Local VM Conversion Toolkit

![Azure Local VM Conversion Toolkit](assets/images/azurelocal-vm-conversion-toolkit-banner.svg)

> [!WARNING]
> **Internal tool, work in progress, not yet verified end to end on a live cluster.** Private repository, not for distribution. Do not use in production.
> Script 05 runs `az stack-hci-vm reconnect-to-azure` and needs a `stack-hci-vm` extension version that provides it (`az stack-hci-vm -h`). The Hyper-V path does not use Azure. Version 0.1.0, not released or tagged.
>
> **Azure Migrate keeps the source generation** (a Gen 1 source stays Gen 1), and [Gen 1 VMs have limitations in Azure Local VM management](https://learn.microsoft.com/azure/azure-local/manage/azure-arc-vm-management-overview#limitations-of-azure-local-vm-management). That is why this toolkit exists. If Gen 1 is acceptable, [Azure Migrate](https://learn.microsoft.com/azure/azure-local/migrate/migration-options-overview) (with its [Arc-reuse feature](https://learn.microsoft.com/azure/azure-local/migrate/migrate-arc-reuse)) is the tool for that.

Convert Gen 1 virtual machines to Gen 2 on Azure Local and Hyper-V environments.

## Overview

This toolkit provides automated scripts for converting Generation 1 VMs to Generation 2, enabling UEFI boot, Secure Boot, vTPM, and Trusted Launch capabilities.

> [!WARNING]
> Conversion is a destructive, one-way operation. Always take full backups before proceeding. Read the [Gen 1 vs Gen 2](gen1-vs-gen2.md) guide before deciding to convert.
>
## Quick Navigation

| Guide | Description |
|-------|-------------|
| [Gen 1 vs Gen 2](gen1-vs-gen2.md) | Understand the differences and decide whether to convert |
| [Prerequisites](prerequisites.md) | System requirements and preparation checklist |
| [Getting Started](getting-started.md) | Choose your conversion path and get started |
| [Azure Local Runbook](runbook-azurelocal.md) | Step-by-step conversion on Azure Local |
| [Hyper-V Runbook](runbook-hyperv.md) | Step-by-step conversion on standalone Hyper-V |
| [Troubleshooting](troubleshooting.md) | Common issues and solutions |

## Repository

- **GitHub**: [AzureLocal/azurelocal-vm-conversion-toolkit](https://github.com/AzureLocal/azurelocal-vm-conversion-toolkit)
- **Issues**: [Report a bug or request a feature](https://github.com/AzureLocal/azurelocal-vm-conversion-toolkit/issues)
