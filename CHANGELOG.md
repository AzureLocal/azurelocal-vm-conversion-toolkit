# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

> **Note**: This project is under active development. Pre-1.0 versions may include breaking changes without a major version bump.

---

## [0.2.0](https://github.com/AzureLocal/azurelocal-vm-conversion-toolkit/compare/v0.1.0...v0.2.0) (2026-10-16)


### Features

* add config/variables.example.yml for org-wide consistency (issue [#15](https://github.com/AzureLocal/azurelocal-vm-conversion-toolkit/issues/15)) ([7b6aa51](https://github.com/AzureLocal/azurelocal-vm-conversion-toolkit/commit/7b6aa51ce54bd39376941ff92c584b97d9524db1))
* add correctly named icon SVG, banner SVG, and update docs home page ([334740c](https://github.com/AzureLocal/azurelocal-vm-conversion-toolkit/commit/334740cd51021b5d0632af175fc4191ed8947754)), closes [#15](https://github.com/AzureLocal/azurelocal-vm-conversion-toolkit/issues/15)
* add unique project ID field automation (VMCT-N prefix) ([c45052f](https://github.com/AzureLocal/azurelocal-vm-conversion-toolkit/commit/c45052f01f322a15f81bbe1bc087fee00df9afe2))
* **claude:** add Claude Code scaffold ([5849959](https://github.com/AzureLocal/azurelocal-vm-conversion-toolkit/commit/58499590651844b34a813d871dd598a4da260478))
* **claude:** add Claude Code scaffold ([ba88790](https://github.com/AzureLocal/azurelocal-vm-conversion-toolkit/commit/ba887901a3400ec3a91b5c030553f1afb7633b75))
* GitHub Project & Repo Standardization (Plan 1) ([8bb5d1a](https://github.com/AzureLocal/azurelocal-vm-conversion-toolkit/commit/8bb5d1a4ae02c36c8f8d4eae37be7f753ef4fdd7))
* split toolkit into two conversion paths ([630a7db](https://github.com/AzureLocal/azurelocal-vm-conversion-toolkit/commit/630a7db61d28e0d42858bbd789316f34a325b413))


### Bug Fixes

* add reopened trigger to add-to-project workflow ([ef28a81](https://github.com/AzureLocal/azurelocal-vm-conversion-toolkit/commit/ef28a81a813e56ce874580f2630d7aa1e21ab5a1))
* correct 5 accuracy bugs across azurelocal scripts ([d96297e](https://github.com/AzureLocal/azurelocal-vm-conversion-toolkit/commit/d96297ef74f396aff318b51ffd52f9b5d18c2048))
* correct Arc registration docs for Azure Local VM platform model ([fe9a7aa](https://github.com/AzureLocal/azurelocal-vm-conversion-toolkit/commit/fe9a7aa7baefddfd8b175df6f63c9326f19e2e29))
* correct inverted path references in arc-registration troubleshooting section ([953f53e](https://github.com/AzureLocal/azurelocal-vm-conversion-toolkit/commit/953f53ee0aff0dc161332fff3928b75bb3ea83ee))
* **docs:** inject base path and convert mkdocs admonitions AB[#4945](https://github.com/AzureLocal/azurelocal-vm-conversion-toolkit/issues/4945) ([64a8f7d](https://github.com/AzureLocal/azurelocal-vm-conversion-toolkit/commit/64a8f7d2acc9ed8e9dbab1ca82643fecba1d76ed))
* **docs:** restore branding and ignore dead links AB[#4945](https://github.com/AzureLocal/azurelocal-vm-conversion-toolkit/issues/4945) ([926a0f5](https://github.com/AzureLocal/azurelocal-vm-conversion-toolkit/commit/926a0f543d629efebc5a001e86870c377f33bef4))
* **docs:** restore custom navigation, logos, and github links AB[#4945](https://github.com/AzureLocal/azurelocal-vm-conversion-toolkit/issues/4945) ([a31379a](https://github.com/AzureLocal/azurelocal-vm-conversion-toolkit/commit/a31379a629e03ae12bc7434573b6504ebae64828))
* **hooks:** substitute {{REPO_ROOT}} placeholder in hook scripts ([9773b5e](https://github.com/AzureLocal/azurelocal-vm-conversion-toolkit/commit/9773b5ebc2c73a966e5d583ca5b9f4a5c8cc6409))
* make set-fields resilient to add-to-project failures ([0fffb9c](https://github.com/AzureLocal/azurelocal-vm-conversion-toolkit/commit/0fffb9cdc6d4518f6df5b84630e0f938578c9a7f))
* pin actions/add-to-project to v1.0.2 ([92e5b67](https://github.com/AzureLocal/azurelocal-vm-conversion-toolkit/commit/92e5b67a14f0091052dcca852aa7d4f26b742e86))
* remove invalid sitemap plugin, move gtag to preset options ([875602c](https://github.com/AzureLocal/azurelocal-vm-conversion-toolkit/commit/875602c26f378b09dabdd4425ff39c548cb17e81))
* remove stale Arc references from README and Script 03 docs ([8dfb343](https://github.com/AzureLocal/azurelocal-vm-conversion-toolkit/commit/8dfb3431825cbe3b6ba4b0b9e86cb2ca94a2071c))
* restore docs standards for mkdocs build ([5edc111](https://github.com/AzureLocal/azurelocal-vm-conversion-toolkit/commit/5edc111140f8ccc2a36f1b7f35c52862ade6e4d6))
* **safety:** verified backup before removal, correct mbr2gpt OS gate, BitLocker check ([f74c429](https://github.com/AzureLocal/azurelocal-vm-conversion-toolkit/commit/f74c4299b81ad4130a62e1eb39cb1a88a9740503))
* **standards:** update canonical path to docs/standards/ in platform ([9cd5758](https://github.com/AzureLocal/azurelocal-vm-conversion-toolkit/commit/9cd575813e7f49c98e97395a902e1b51af7f5223))
* update Solution field option IDs after Toolkit option added to Project [#3](https://github.com/AzureLocal/azurelocal-vm-conversion-toolkit/issues/3) ([e9a927d](https://github.com/AzureLocal/azurelocal-vm-conversion-toolkit/commit/e9a927d245d8c5b8223c944be4f8511fe037009b))
* use action output for item ID, fix stale solution field option IDs ([e905067](https://github.com/AzureLocal/azurelocal-vm-conversion-toolkit/commit/e9050672c5048e23611e1402d27755fdd0907d2a))

## [Unreleased]

### Safety

- Script 02: the OS gate now matches Microsoft Learn (Windows Server 2019 / Windows 10 1703 or later; Server 2016 has no `mbr2gpt.exe`), the file must really exist, and BitLocker protection must be suspended and is re-checked after suspending. Exit code 100 is reported as converted-with-warnings.
- Script 03: every disk file (and differencing parents) is copied to a timestamped folder and verified by size and SHA256 before the VM is removed; the removal is gated on that proof. `-BackupVHDX:$false` needs `-IUnderstandNoBackup`. Free space is checked first, existing backups are never overwritten, `-WhatIf` copies and removes nothing, a VM with no NIC is refused before removal, and a failure after removal prints where the disks and backup are.
- Script 05 and the docs state the extension requirement for `reconnect-to-azure` and the internal, work-in-progress status; the docs no longer suggest deleting the Azure resource to undo a reconnect.

### Fixed

- `scripts/azurelocal/04-Batch-ConvertVMs.ps1` passed parameters script 03 does not have, so every VM failed; it now runs 03 then 05.
- README links pointed at `.adoc` files that were migrated to `.md`.
- The VitePress nav and sidebar gave `Reference` an object instead of a list, so the docs build logged `items is not iterable` on every page.

### Added

- `scripts/common/ConversionSafety` (testable gates), Pester 5 unit tests (`tests/Unit`), PSScriptAnalyzer settings, `tests/Invoke-Checks.ps1`, a pull-request CI workflow and release-please. Version 0.1.0 is recorded in the manifests only; nothing is tagged.
- Azure Migrate positioning in the README and docs.

### Added (earlier, unreleased)

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
