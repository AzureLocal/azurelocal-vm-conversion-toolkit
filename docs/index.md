# Azure Local VM Conversion Toolkit

Convert Gen 1 virtual machines to Gen 2 on Azure Local and Hyper-V environments.

## Overview

This toolkit provides automated scripts for converting Generation 1 VMs to Generation 2, enabling UEFI boot, Secure Boot, vTPM, and Trusted Launch capabilities.

!!! warning
    Conversion is a destructive, one-way operation. Always take full backups before proceeding. Read the [Gen 1 vs Gen 2](gen1-vs-gen2.md) guide before deciding to convert.

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
