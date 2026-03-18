# Standards

This repository follows the **org-wide AzureLocal standards** maintained on the central documentation site.

!!! info "Central Standards"
    The full standards suite is at [azurelocal.cloud/standards](https://azurelocal.cloud/standards/).
    This section provides the key rules adapted for the VM Conversion Toolkit.

---

## Standards Pages

| Local Page | Central Reference | Scope |
|-----------|-------------------|-------|
| [Documentation](documentation.md) | [Documentation Standards](https://azurelocal.cloud/standards/documentation/documentation-standards) | Docs formatting, MkDocs, file naming |
| [Scripting](scripting.md) | [Scripting Standards](https://azurelocal.cloud/standards/scripting/scripting-standards) | PowerShell, `Invoke-` patterns, dual runbook conventions |
| [Variables](variables.md) | [Variable Management](https://azurelocal.cloud/standards/variable-management/) | Naming, structure, Key Vault |
| [Naming Conventions](naming.md) | [Naming Conventions](https://azurelocal.cloud/standards/documentation/naming-conventions) | File, directory, resource, variable naming |
| [Solutions](solutions.md) | [Solution Development Standard](https://azurelocal.cloud/standards/solutions/solution-development-standard) | Solution structure, dual runbook pattern |
| [Infrastructure](infrastructure.md) | [Infrastructure Standards](https://azurelocal.cloud/standards/infrastructure/) | IaC, deployment pipeline, conversion phases |
| [Automation](automation.md) | [Scripting Framework](https://azurelocal.cloud/standards/scripting/scripting-framework) | Tool integration, config flow |
| [Examples & IIC](examples.md) | [Fictional Company Policy](https://azurelocal.cloud/standards/fictional-company-policy) | IIC naming patterns, VM conversion examples |

---

## References

- [Variable Reference](../reference/variables.md) — Per-variable catalog for this repo
- [Repository Structure](https://azurelocal.cloud/standards/repo-structure) — Required file layout

---

## Repo-Specific Conventions

- **CLI-parameter driven**: Scripts currently accept parameters on the command line; `config/variables.yml` documents canonical values and will be loaded directly in future versions
- **Dual runbooks**: Azure Local path and Hyper-V path share the same variable schema but differ in which variables are required
- **ARM resource IDs**: Azure Local variables use full ARM resource IDs for custom locations and logical networks
