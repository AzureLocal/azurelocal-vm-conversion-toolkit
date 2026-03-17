# Variable Reference

All VM conversion scripts use a central configuration file: `config/variables.yml`. This file documents the common values you will need across all scripts. Future versions may support loading from this file directly.

!!! tip "Getting started"
    Copy the example and fill in your values:
    ```powershell
    cp config/variables.example.yml config/variables.yml
    ```
    **Never commit** `variables.yml` — it is excluded by `.gitignore` because it contains environment-specific values.

!!! note "Current usage"
    These scripts currently accept parameters directly on the command line.
    This file documents the common values you will need and serves as the canonical parameter reference.

---

## Naming Rules

| Scope | Convention | Example |
|-------|-----------|---------|
| Top-level sections | `snake_case` | `azure_local`, `conversion` |
| Keys within sections | `snake_case` | `subscription_id`, `max_parallel` |
| Azure resource IDs | Full ARM resource ID | `/subscriptions/.../customLocations/cl-01` |

---

## Azure

```yaml
azure:
  subscription_id: "00000000-0000-0000-0000-000000000000"
  resource_group: "rg-azurelocal-prod"
  location: "eastus"
```

| Variable | Type | Required | Description | Default |
|----------|------|:--------:|-------------|---------|
| `azure.subscription_id` | string | **Yes** | Azure subscription ID | — |
| `azure.resource_group` | string | **Yes** | Resource group containing the target VMs | — |
| `azure.location` | string | **Yes** | Azure region | `eastus` |

---

## Azure Local

```yaml
azure_local:
  custom_location_id: "/subscriptions/.../customLocations/cl-azurelocal-01"
  logical_network_id: "/subscriptions/.../logicalNetworks/lnet-mgmt-01"
```

| Variable | Type | Required | Description | Default |
|----------|------|:--------:|-------------|---------|
| `azure_local.custom_location_id` | string | **Yes** | Full ARM resource ID of the Azure Local custom location | — |
| `azure_local.logical_network_id` | string | **Yes** | Full ARM resource ID of the logical network for the converted VM | — |

---

## Conversion Settings

```yaml
conversion:
  working_directory: "C:\\ClusterStorage\\Volume01\\Gen2Conversion"
  max_parallel: 1
```

| Variable | Type | Required | Description | Default |
|----------|------|:--------:|-------------|---------|
| `conversion.working_directory` | string | **Yes** | Scratch directory for conversion work files (must have sufficient free space) | — |
| `conversion.max_parallel` | integer | No | Number of VMs to process in parallel (`1` = sequential) | `1` |

---

## Tags

```yaml
tags:
  project: "VM-Conversion"
  environment: "production"
  workload: "gen1-to-gen2"
  solution: "vmconvert-azure-local"
```

| Variable | Type | Required | Description | Default |
|----------|------|:--------:|-------------|---------|
| `tags.project` | string | No | Project tag | `VM-Conversion` |
| `tags.environment` | string | No | Environment tag | `production` |
| `tags.workload` | string | No | Workload type tag | `gen1-to-gen2` |
| `tags.solution` | string | No | Solution identifier tag | `vmconvert-azure-local` |

---

## Script Parameter Mapping

The table below maps `variables.yml` keys to the actual script parameters:

| Variable Key | Azure Local Script Param | Hyper-V Script Param |
|-------------|-------------------------|---------------------|
| `azure.subscription_id` | `-SubscriptionId` | N/A |
| `azure.resource_group` | `-ResourceGroup` | N/A |
| `azure_local.custom_location_id` | `-CustomLocationId` | N/A |
| `azure_local.logical_network_id` | `-LogicalNetworkId` | N/A |
| `conversion.working_directory` | `-WorkingDirectory` | `-WorkingDirectory` |
| `conversion.max_parallel` | `-MaxParallel` | `-MaxParallel` |
