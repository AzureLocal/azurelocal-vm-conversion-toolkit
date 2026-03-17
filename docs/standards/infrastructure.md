# Infrastructure Standards

> **Canonical reference:** [Infrastructure Standards (full)](https://azurelocal.cloud/standards/infrastructure/)  
> **Applies to:** All AzureLocal repositories  
> **Last Updated:** 2026-03-17

---

## Overview

Standards for Infrastructure as Code (IaC) and deployment processes for the VM Conversion Toolkit.

---

## Conversion Pipeline

```mermaid
flowchart LR
    A[Load Config] --> B[Validate VM State]
    B --> C[Checkpoint VM]
    C --> D[Convert Disk Layout]
    D --> E[Update VM Generation]
    E --> F[Validate & Boot]
```

---

## VM-Conversion-Specific Infrastructure

| Convention | Rule |
|-----------|------|
| Primary tooling | PowerShell scripts (CLI-parameter and config-driven) |
| Config source | `config/variables.yml` (documents canonical values) |
| Dual paths | Azure Local path uses ARM resource IDs; Hyper-V path uses local cmdlets |
| Safety | Always checkpoint before conversion; never modify running VMs |

### Azure Local Path

| Step | Operation |
|------|-----------|
| 1 | Validate VM is Gen 1 and powered off |
| 2 | Create checkpoint |
| 3 | Convert disk from MBR to GPT |
| 4 | Update VM configuration to Gen 2 |
| 5 | Boot and validate |

### Hyper-V Path

| Step | Operation |
|------|-----------|
| 1 | Validate VM is Gen 1 and powered off |
| 2 | Export VM (backup) |
| 3 | Convert disk from MBR to GPT |
| 4 | Create new Gen 2 VM with converted disk |
| 5 | Boot and validate |

---

## Related Standards

- [Infrastructure Generation & Deployment Process](https://azurelocal.cloud/standards/infrastructure/infrastructure-generation-deployment-process)
- [Solution Development Standard](solutions.md)
- [Variable Standards](variables.md)
- [Automation Interoperability](automation.md)
