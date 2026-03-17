# Naming Conventions

> **Canonical reference:** [Naming Conventions (full)](https://azurelocal.cloud/standards/documentation/naming-conventions)  
> **Applies to:** All AzureLocal repositories  
> **Last Updated:** 2026-03-17

---

## File & Directory Naming

| Type | Convention | Pattern | Example |
|------|-----------|---------|---------|
| Directories | lowercase-with-hyphens | `^[a-z][a-z0-9-]*$` | `reference/`, `standards/` |
| Markdown (docs/) | lowercase with hyphens | `*.md` | `runbook-azurelocal.md` |
| Root files | UPPERCASE | — | `README.md`, `CHANGELOG.md` |
| PowerShell scripts | PascalCase | `Verb-Noun.ps1` | `Convert-VMGeneration.ps1` |
| Config files | lowercase-with-hyphens | — | `variables.example.yml` |

---

## Azure Resource Naming

All resources follow the [IIC naming patterns](examples.md):

| Resource Type | Pattern | Example |
|--------------|---------|---------|
| Resource Group | `rg-iic-vmconv-<##>` | `rg-iic-vmconv-01` |
| VM (source Gen 1) | `iic-vm-<purpose>-g1` | `iic-vm-web-g1` |
| VM (target Gen 2) | `iic-vm-<purpose>` | `iic-vm-web` |
| Key Vault | `kv-iic-<purpose>` | `kv-iic-platform` |
| Custom Location | Full ARM resource ID | — |

---

## Variable Naming

| Rule | Standard | Example |
|------|----------|---------|
| YAML sections | `snake_case` | `azure_local`, `conversion` |
| YAML keys | `snake_case` | `subscription_id`, `vm_name` |
| Pattern | `^[a-z][a-z0-9_]*$` | — |
| Max length | 50 characters | — |

---

## Git Branch Naming

| Pattern | Usage | Example |
|---------|-------|---------|
| `main` | Default branch | — |
| `feature/<description>` | New features | `feature/batch-conversion` |
| `fix/<description>` | Bug fixes | `fix/disk-layout-detection` |
| `docs/<description>` | Documentation | `docs/troubleshooting` |
| `infra/<description>` | CI/CD | `infra/add-pester-tests` |

---

## Related Standards

- [Full Naming Conventions](https://azurelocal.cloud/standards/documentation/naming-conventions)
- [Repository Structure](https://azurelocal.cloud/standards/repo-structure)
- [Documentation Standards](documentation.md)
- [Examples & IIC](examples.md)
