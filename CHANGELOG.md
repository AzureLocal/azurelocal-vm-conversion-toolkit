# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

> **Note**: This project is under active development. Pre-1.0 versions may include breaking changes without a major version bump.

---

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
