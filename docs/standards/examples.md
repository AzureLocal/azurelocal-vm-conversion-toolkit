# Examples & IIC Policy

> **Canonical reference:** [Fictional Company Policy (full)](https://azurelocal.cloud/standards/fictional-company-policy)  
> **Applies to:** All AzureLocal repositories  
> **Last Updated:** 2026-03-17

---

## Policy

All examples, sample configurations, walkthroughs, and documentation across every AzureLocal repository use **one** fictional company: **Infinite Improbability Corp (IIC)**.

!!! warning "Mandatory"
    Never use `contoso`, `fabrikam`, `adventure-works`, `woodgrove`, `example.com`, or any real customer name.
    **IIC only** — in every repo, every example, every sample config.

---

## IIC Reference Card

| Attribute | Value |
|-----------|-------|
| **Full Name** | Infinite Improbability Corp |
| **Abbreviation** | IIC |
| **Domain (public)** | `improbability.cloud` / `iic.cloud` |
| **Domain (on-prem AD)** | `iic.local` |
| **NetBIOS Name** | `IMPROBABLE` |
| **Entra ID Tenant** | `improbability.onmicrosoft.com` |
| **Email Pattern** | `user@improbability.cloud` |
| **Origin** | A nod to *The Hitchhiker's Guide to the Galaxy* |

---

## VM Conversion Naming Patterns

### VMs

| Resource | Pattern | Example |
|----------|---------|---------|
| Source VM (Gen 1) | `iic-vm-<purpose>-g1` | `iic-vm-web-g1` |
| Target VM (Gen 2) | `iic-vm-<purpose>` | `iic-vm-web` |
| Checkpoint | `pre-conversion-<timestamp>` | `pre-conversion-20260317` |

### Azure Resources

| Resource | Pattern | Example |
|----------|---------|---------|
| Resource Group | `rg-iic-vmconv-<##>` | `rg-iic-vmconv-01` |
| Key Vault | `kv-iic-<purpose>` | `kv-iic-platform` |
| Custom Location | Full ARM resource ID | — |

---

## Real Identities

These are **not** fictional — use for authorship and attribution:

| Name | Usage |
|------|-------|
| **Azure Local Cloud** | Community project, GitHub org, `azurelocal.cloud` |
| **Hybrid Cloud Solutions** | Author/maintainer LLC, script headers, copyright |

---

## Usage Examples

### In `config/variables.example.yml`

```yaml
azure:
  subscription_id: "00000000-0000-0000-0000-000000000000"
  resource_group: "rg-iic-vmconv-01"
  location: "eastus"

conversion:
  vm_name: "iic-vm-web-g1"
  target_generation: 2
  checkpoint_before_convert: true
```

### In Documentation

> Infinite Improbability Corp converts their legacy Gen 1 web server (`iic-vm-web-g1`)
> to Gen 2 using the Azure Local conversion runbook.

### In Scripts

```powershell
# Example: Convert IIC Gen 1 VM to Gen 2
$vmName = "iic-vm-web-g1"
Invoke-VMConversion -VMName $vmName -WhatIf
```

---

## Enforcement

- **PR review**: Reviewers flag any use of `contoso`, `fabrikam`, or other non-IIC names
- **Config validation**: `variables.example.yml` uses IIC naming patterns in all placeholders
- **CI**: Vale linting rules can flag non-IIC fictional company names (when configured)
