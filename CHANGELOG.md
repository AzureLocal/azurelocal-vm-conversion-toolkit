# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

> **Note**: This project is under active development. Pre-1.0 versions may include breaking changes without a major version bump.

---

## 1.0.0 (2026-05-12)


### Features

* add config/variables.example.yml for org-wide consistency (issue [#15](https://github.com/AzureLocal/azurelocal-vm-conversion-toolkit/issues/15)) ([7b6aa51](https://github.com/AzureLocal/azurelocal-vm-conversion-toolkit/commit/7b6aa51ce54bd39376941ff92c584b97d9524db1))
* add correctly named icon SVG, banner SVG, and update docs home page ([334740c](https://github.com/AzureLocal/azurelocal-vm-conversion-toolkit/commit/334740cd51021b5d0632af175fc4191ed8947754)), closes [#15](https://github.com/AzureLocal/azurelocal-vm-conversion-toolkit/issues/15)
* add unique project ID field automation (VMCT-N prefix) ([c45052f](https://github.com/AzureLocal/azurelocal-vm-conversion-toolkit/commit/c45052f01f322a15f81bbe1bc087fee00df9afe2))
* GitHub Project & Repo Standardization (Plan 1) ([8bb5d1a](https://github.com/AzureLocal/azurelocal-vm-conversion-toolkit/commit/8bb5d1a4ae02c36c8f8d4eae37be7f753ef4fdd7))
* split toolkit into two conversion paths ([630a7db](https://github.com/AzureLocal/azurelocal-vm-conversion-toolkit/commit/630a7db61d28e0d42858bbd789316f34a325b413))


### Bug Fixes

* add reopened trigger to add-to-project workflow ([ef28a81](https://github.com/AzureLocal/azurelocal-vm-conversion-toolkit/commit/ef28a81a813e56ce874580f2630d7aa1e21ab5a1))
* correct 5 accuracy bugs across azurelocal scripts ([d96297e](https://github.com/AzureLocal/azurelocal-vm-conversion-toolkit/commit/d96297ef74f396aff318b51ffd52f9b5d18c2048))
* correct Arc registration docs for Azure Local VM platform model ([fe9a7aa](https://github.com/AzureLocal/azurelocal-vm-conversion-toolkit/commit/fe9a7aa7baefddfd8b175df6f63c9326f19e2e29))
* correct inverted path references in arc-registration troubleshooting section ([953f53e](https://github.com/AzureLocal/azurelocal-vm-conversion-toolkit/commit/953f53ee0aff0dc161332fff3928b75bb3ea83ee))
* make set-fields resilient to add-to-project failures ([0fffb9c](https://github.com/AzureLocal/azurelocal-vm-conversion-toolkit/commit/0fffb9cdc6d4518f6df5b84630e0f938578c9a7f))
* pin actions/add-to-project to v1.0.2 ([92e5b67](https://github.com/AzureLocal/azurelocal-vm-conversion-toolkit/commit/92e5b67a14f0091052dcca852aa7d4f26b742e86))
* remove invalid sitemap plugin, move gtag to preset options ([875602c](https://github.com/AzureLocal/azurelocal-vm-conversion-toolkit/commit/875602c26f378b09dabdd4425ff39c548cb17e81))
* remove stale Arc references from README and Script 03 docs ([8dfb343](https://github.com/AzureLocal/azurelocal-vm-conversion-toolkit/commit/8dfb3431825cbe3b6ba4b0b9e86cb2ca94a2071c))
* restore docs standards for mkdocs build ([5edc111](https://github.com/AzureLocal/azurelocal-vm-conversion-toolkit/commit/5edc111140f8ccc2a36f1b7f35c52862ade6e4d6))
* **standards:** update canonical path to docs/standards/ in platform ([9cd5758](https://github.com/AzureLocal/azurelocal-vm-conversion-toolkit/commit/9cd575813e7f49c98e97395a902e1b51af7f5223))
* update Solution field option IDs after Toolkit option added to Project [#3](https://github.com/AzureLocal/azurelocal-vm-conversion-toolkit/issues/3) ([e9a927d](https://github.com/AzureLocal/azurelocal-vm-conversion-toolkit/commit/e9a927d245d8c5b8223c944be4f8511fe037009b))
* use action output for item ID, fix stale solution field option IDs ([e905067](https://github.com/AzureLocal/azurelocal-vm-conversion-toolkit/commit/e9050672c5048e23611e1402d27755fdd0907d2a))

## [Unreleased]

### Added
- Initial release of the Azure Local VM Conversion Toolkit
- Two fully separate script paths — `scripts/hyperv/` (Hyper-V only, no Azure) and `scripts/azurelocal/` (Azure Local portal-managed)
- `scripts/hyperv/01-Setup-ConversionEnvironment.ps1` — cluster health validation, Gen 1 VM inventory and config export. No Azure dependencies.
- `scripts/guest/02-Convert-MBRtoGPT.ps1` — in-guest MBR to GPT boot disk conversion via `mbr2gpt.exe`
- `scripts/hyperv/03-Convert-Gen1toGen2.ps1` — single-VM Gen 1 to Gen 2 conversion with VHDX backup and re-clustering. No Azure dependencies.
- `scripts/hyperv/04-Batch-ConvertVMs.ps1` — batch orchestrator for the Hyper-V path. No Azure dependencies.
- `scripts/azurelocal/01-Setup-ConversionEnvironment.ps1` — same as Hyper-V variant plus Azure connectivity and HCI registration validation
- `scripts/azurelocal/03-Convert-Gen1toGen2.ps1` — same Gen 1→Gen 2 conversion plus Arc resource bookkeeping
- `scripts/azurelocal/04-Batch-ConvertVMs.ps1` — batch orchestrator for the Azure Local path
- `scripts/azurelocal/05-Reconnect-AzureLocalVM.ps1` — projects an existing Gen 2 Hyper-V VM into the Azure Local management plane via `az stack-hci-vm reconnect-to-azure`
- Working directory structure on CSV for backups, configs, logs, and temp files

[Unreleased]: https://github.com/AzureLocal/azurelocal-vm-conversion-toolkit/commits/main
