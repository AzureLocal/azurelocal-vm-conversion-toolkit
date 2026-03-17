# Solution Development Standards

> **Canonical reference:** [Solution Development Standard (full)](https://azurelocal.cloud/standards/solutions/solution-development-standard)  
> **Applies to:** All AzureLocal repositories  
> **Last Updated:** 2026-03-17

---

## Overview

Standards for solution packaging and deployment best practices for the VM Conversion Toolkit.

---

## Solution Structure

| Directory | Purpose |
|-----------|---------|
| `config/` | Configuration files — variables, schemas |
| `docs/` | Documentation source (MkDocs) |
| `scripts/` | PowerShell conversion scripts |
| `styles/` | Vale linting styles |
| `project_management/` | Project tracking |

---

## Dual Runbook Pattern

This solution provides two deployment paths sharing the same variable schema:

| Runbook | Target Environment | Key Differences |
|---------|-------------------|-----------------|
| Azure Local Path | Azure Local cluster | Uses ARM resource IDs, custom locations, logical networks |
| Hyper-V Path | Standalone Hyper-V | Uses local Hyper-V cmdlets, virtual switches |

Both paths read from `config/variables.yml` but differ in which variables are required.

---

## Idempotency

All scripts must be safe to re-run without side effects:

- Detect existing Gen 2 VMs and skip conversion
- Checkpoint VMs before modifying disk layout
- Use `-WhatIf` for dry-run validation
- Log all operations for audit trail

---

## Related Standards

- [Scripting Standards](scripting.md)
- [Variable Standards](variables.md)
- [Infrastructure Standards](infrastructure.md)
- [Automation Interoperability](automation.md)
