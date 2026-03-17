# Variable Standards

> **Canonical reference:** [Variable Management Standard](https://azurelocal.cloud/standards/variable-management/)  
> **Full variable catalog:** [Variable Reference](../reference/variables.md)  
> **Last Updated:** 2026-03-17

---

## Overview

This repository uses a central configuration file — `config/variables.yml` — to document common values needed across all conversion scripts.

```powershell
cp config/variables.example.yml config/variables.yml
```

**Never commit** `variables.yml` — it is excluded by `.gitignore`.

!!! note "Current usage"
    Scripts currently accept parameters directly on the command line. The config file documents canonical values and serves as the parameter reference. Future versions will support loading from the config file directly.

---

## Config Structure

```
config/
├── variables.example.yml        # Template with example values (committed)
├── variables.yml                # Your actual values (gitignored)
└── schema/
    └── variables.schema.json    # JSON Schema for CI validation
```

---

## Naming Rules

| Rule | Standard | Example |
|------|----------|---------|
| Top-level sections | `snake_case` | `azure`, `azure_local`, `conversion` |
| Keys within sections | `snake_case` | `subscription_id`, `max_parallel` |
| Pattern | `^[a-z][a-z0-9_]*$` | — |
| Azure resource IDs | Full ARM resource ID | `/subscriptions/.../customLocations/cl-01` |
| Secrets | `keyvault://` URI format | `keyvault://kv-platform/admin-password` |

---

## Sections

| Section | Description | Used By |
|---------|-------------|---------|
| `azure` | Subscription, resource group, region | Azure Local runbook |
| `azure_local` | Custom location ID, logical network ID | Azure Local runbook |
| `conversion` | Working directory, parallelism settings | Both runbooks |
| `tags` | Azure resource tags | Azure Local runbook |

---

## CI Validation

Every PR validates `config/variables.example.yml` against `config/schema/variables.schema.json` using the `validate-config.yml` workflow.

---

## Detailed Reference

- **[Variable Reference](../reference/variables.md)** — per-variable documentation with types, defaults, and script parameter mapping
- **[Variable Management Standard](https://azurelocal.cloud/standards/variable-management/)** — org-wide governance
