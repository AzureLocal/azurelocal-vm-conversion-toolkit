# Scripting Standards

> **Canonical reference:** [Scripting Standards (full)](https://azurelocal.cloud/standards/scripting/scripting-standards)  
> **Applies to:** All AzureLocal repositories  
> **Last Updated:** 2026-03-17

---

## Script Naming

| Script Type | Pattern | Example |
|-------------|---------|---------|
| PowerShell Core | `Verb-Noun.ps1` | `Convert-VMGeneration.ps1` |
| Azure PowerShell | `Verb-AzResource.ps1` | `Get-AzVM.ps1` |
| Azure CLI (PowerShell) | `az-verb-resource.ps1` | `az-convert-vm.ps1` |
| Standalone (no config) | `Verb-Noun-Standalone.ps1` | `Convert-VMGeneration-Standalone.ps1` |
| Remote/orchestration | `Invoke-<Task>.ps1` | `Invoke-VMConversion.ps1` |

---

## Config-Driven vs Standalone

| Mode | Config File | Dependencies | Use Case |
|------|-------------|-------------|----------|
| Config-driven | `config/variables.yml` | Config loader, helpers | Multi-VM batch conversion |
| Standalone | Inline `#region CONFIGURATION` or CLI parameters | None | Single VM conversion |

### Config-Driven Rules

- Read all values from `config/variables.yml` — never hardcode
- Accept `-ConfigPath` parameter (auto-discover if not provided)

### Standalone / CLI-Parameter Rules

- Scripts currently accept parameters on the command line
- `config/variables.yml` documents canonical values and will be loaded directly in future versions
- Variable names match `variables.yml` paths

---

## `Invoke-` Script Requirements

### Required Parameters

| Parameter | Type | Default | Purpose |
|-----------|------|---------|---------|
| `-ConfigPath` | `[string]` | `""` | Path to `variables.yml` |
| `-VMName` | `[string]` | — | Target VM to convert |
| `-WhatIf` | `[switch]` | `$false` | Dry-run mode |
| `-LogPath` | `[string]` | `""` (auto) | Override log file path |

All `Invoke-` scripts must use `[CmdletBinding()]` to enable `-Verbose` and `-Debug`.

---

## Logging

- Log to `./logs/<task-name>/<timestamp>.log`
- Use `Write-Verbose` for detailed output
- Log format: `[YYYY-MM-DD HH:MM:SS] [LEVEL] Message`

---

## VM-Conversion-Specific Script Conventions

| Convention | Rule |
|-----------|------|
| Dual runbooks | Azure Local path and Hyper-V path share the same variable schema |
| ARM resource IDs | Azure Local variables use full ARM resource IDs for custom locations and logical networks |
| Safety | All conversions must checkpoint the VM before modifying disk layout |
| Idempotency | All scripts must detect existing Gen 2 VMs and skip |

---

## Related Standards

- [PowerShell Organization Standard](https://azurelocal.cloud/standards/scripting/powershell-organization-standard)
- [Scripting Framework](https://azurelocal.cloud/standards/scripting/scripting-framework)
- [Automation Interoperability](automation.md)
