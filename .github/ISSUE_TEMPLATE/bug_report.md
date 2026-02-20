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

- [ ] `scripts/cluster/01-Setup-ConversionEnvironment.ps1`
- [ ] `scripts/guest/02-Convert-MBRtoGPT.ps1`
- [ ] `scripts/cluster/03-Convert-Gen1toGen2.ps1`
- [ ] `scripts/cluster/04-Batch-ConvertVMs.ps1`

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
