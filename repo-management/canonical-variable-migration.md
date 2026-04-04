# Canonical Variable Migration Checklist — azurelocal-vm-conversion-toolkit

## Status: Wave 2 (Trivial)

## Assessment
This repo does **not load YAML variables at runtime**. All 9 PowerShell scripts use
parameter-based input. The `config/variables.example.yml` exists for documentation
and CI schema validation only.

## Prerequisites
- [x] CanonicalVariable.psm1 deployed to `scripts/common/`
- [x] `config/variables.example.yml` exists

## Migration Steps

### Step 1: Schema Validation (only required action)
- [ ] Run canonical schema validator against `config/variables.example.yml`
- [ ] Confirm zero unknown paths
- [ ] Add CI check to validate schema on PR

### Step 2: Future Enhancement (optional)
If scripts are ever updated to load config from YAML:
- Import `CanonicalVariable.psm1` for canonical path resolution
- Replace parameter defaults with `Get-CanonicalVariable` lookups
- Add fail-fast validation for required variables

## Notes
- Zero runtime YAML loading = zero migration work beyond schema validation
- Module is deployed for future use if scripts evolve to use config files
