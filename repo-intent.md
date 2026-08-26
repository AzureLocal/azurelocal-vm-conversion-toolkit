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

Active, early — under active development, not fully tested across all
configurations.
