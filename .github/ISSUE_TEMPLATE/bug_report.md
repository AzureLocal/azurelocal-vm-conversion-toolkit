---
name: Bug Report
about: Report a problem with one of the conversion scripts
title: '[BUG] '
labels: bug
assignees: ''
---

## Environment

| Field | Value |
|-------|-------|
| **Azure Local version** | e.g. 23H2, 22H2 |
| **Node OS** | e.g. Windows Server 2025 |
| **Guest OS** | e.g. Windows Server 2022 |
| **PowerShell version** | `$PSVersionTable.PSVersion` |
| **Az module version** | `(Get-Module Az.Accounts).Version` |

## Which script failed?

**Path 1 — Azure Local:**
- [ ] `scripts/azurelocal/01-Setup-ConversionEnvironment.ps1`
- [ ] `scripts/azurelocal/02-Convert-MBRtoGPT.ps1`
- [ ] `scripts/azurelocal/03-Convert-Gen1toGen2.ps1`
- [ ] `scripts/azurelocal/04-Batch-ConvertVMs.ps1`
- [ ] `scripts/azurelocal/05-Reconnect-AzureLocalVM.ps1`

**Path 2 — Hyper-V:**
- [ ] `scripts/hyperv/01-Setup-ConversionEnvironment.ps1`
- [ ] `scripts/hyperv/02-Convert-MBRtoGPT.ps1`
- [ ] `scripts/hyperv/03-Convert-Gen1toGen2.ps1`
- [ ] `scripts/hyperv/04-Batch-ConvertVMs.ps1`

## What happened?

<!-- Describe what you ran and what went wrong -->

## Error message

```
Paste the full error message here
```

## Relevant log output

<!-- Paste relevant lines from the log file in WorkingDirectory\Logs\ -->

```
Paste log output here
```

## Steps to reproduce

1. 
2. 
3. 

## Additional context

<!-- Any other relevant details: cluster topology, number of nodes, VM config, disk layout, etc. -->
