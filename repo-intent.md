# Repo intent — azurelocal-vm-conversion-toolkit

**PowerShell toolkit for converting Hyper-V Gen 1 VMs to Gen 2 on Azure Local while preserving Azure Arc management.**

## What this repo is

Converts Hyper-V Generation 1 VMs to Generation 2 on Azure Local without breaking
existing Azure Arc management registrations.

> **⚠️ Use at your own risk.** This toolkit modifies VM configurations, partition
> tables, and Azure resource registrations — destructive, potentially
> irreversible operations. Data loss, VM downtime, and broken Arc registrations
> are explicitly called out as possible outcomes.

## How it relates to other repos

- Part of the AzureLocal toolkit family; docs at azurelocal.cloud

## Status

Preview, version 0.1.0, no releases or tags. The Azure Local path (script 05) depends on a
command from the invitation-only Azure Local private preview, so it is not for production.
Unit tests (Pester 5, everything mocked) run on every pull request; there is no live proof yet
on a production cluster. Azure Migrate keeps the source generation, so this toolkit is for the
case where the VM must become Gen 2.
