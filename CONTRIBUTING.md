# Contributing

Thank you for your interest in contributing to the Azure Local VM Conversion Toolkit. This project is in early development, and contributions are welcome — especially around testing across different Azure Local versions, OS configurations, and cluster topographies.

## Before You Start

- Read the [README](README.md) thoroughly, including the warnings about destructive operations
- This toolkit modifies partition tables, VM configurations, and Azure resource registrations — **test all changes in a non-production environment**
- Check open issues and pull requests to avoid duplicate work

## How to Contribute

### Reporting Bugs

Use the [bug report issue template](.github/ISSUE_TEMPLATE/bug_report.md). Include:
- Azure Local version (22H2, 23H2, etc.)
- Windows Server version running inside the guest VM
- Which script failed and at which step
- Full error message and relevant log output from the working directory

### Suggesting Features

Use the [feature request issue template](.github/ISSUE_TEMPLATE/feature_request.md). Describe the use case, not just the solution.

### Submitting Pull Requests

1. Fork the repo and create a branch from `main`
2. Name branches descriptively: `fix/mbr2gpt-validation`, `feat/linux-support`, etc.
3. Keep changes focused — one logical change per PR
4. Update the README and relevant `docs/` pages if your change affects usage or prerequisites
5. Add an entry to [CHANGELOG.md](CHANGELOG.md) under `[Unreleased]`
6. Test your changes against at least one real Azure Local environment before submitting
7. Fill out the pull request template completely

## Development Guidelines

### PowerShell Style

- Use approved PowerShell verbs (`Get-`, `Set-`, `New-`, `Remove-`, etc.)
- Include `[CmdletBinding()]` and `param()` blocks on all scripts
- Use `Write-Verbose` for diagnostic output, `Write-Warning` for non-fatal issues, `Write-Error` for failures
- Log to the working directory `Logs/` subfolder, not just the console
- Guard all destructive operations with a `-WhatIf` / `-Confirm` pattern where practical

### Testing

- There is currently no automated test suite — Pester-based tests are a welcome contribution
- At minimum, run `.\01-Setup-ConversionEnvironment.ps1` against a real cluster to validate your changes don't break inventory/export
- Test `.\02-Convert-MBRtoGPT.ps1 -ValidateOnly` inside a guest VM before testing the full conversion

## Code of Conduct

Be respectful and constructive. This is a small project focused on solving a real operational problem — keep discussions on-topic and collaborative.
