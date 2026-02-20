# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

> **Note**: This project is under active development. Pre-1.0 versions may include breaking changes without a major version bump.

---

## [Unreleased]

### Added
- Initial release of the Azure Local VM Conversion Toolkit
- `scripts/cluster/01-Setup-ConversionEnvironment.ps1` — cluster health validation, Gen 1 VM inventory, and config export
- `scripts/guest/02-Convert-MBRtoGPT.ps1` — in-guest MBR to GPT boot disk conversion via `mbr2gpt.exe`
- `scripts/cluster/03-Convert-Gen1toGen2.ps1` — single-VM Gen 1 to Gen 2 conversion with VHDX backup, re-clustering, and Azure Arc re-registration
- `scripts/cluster/04-Batch-ConvertVMs.ps1` — batch orchestrator for converting multiple VMs with pre-flight checks and summary reporting
- Working directory structure on CSV for backups, configs, logs, and temp files
- Azure Arc re-registration support for both automatic (VM Config Agent) and manual (`az stack-hci-vm create`) fallback paths

[Unreleased]: https://github.com/AzureLocal/azurelocal-vm-conversion-toolkit/commits/main
