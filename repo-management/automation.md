# Automation

Documents every GitHub Actions workflow in this repository.

---

## Workflow Summary

| File | Name | Trigger | Purpose |
|------|------|---------|---------|
| `add-to-project.yml` | Add to Project | Issues/PRs opened or labeled | Adds items to org project board and sets custom fields |
| `deploy-docs.yml` | Deploy Documentation | Push to `main` touching `docs/**` or `mkdocs.yml` | Builds MkDocs site and deploys to GitHub Pages |
| `release-please.yml` | Release Please | Push to `main` | Automates CHANGELOG and releases |
| `validate-config.yml` | Validate Configuration | Push/PR touching `config/**` | Validates config YAML against JSON Schema |
| `validate-repo-structure.yml` | Validate Repo Structure | PR to `main` | Checks required files, directories, and variable reference doc |

---

## add-to-project.yml

**Trigger:** `issues` (opened, labeled) and `pull_request` (opened, labeled)  
**Secrets:** `ADD_TO_PROJECT_PAT`

Two-job pipeline:

1. **add-to-project** — Uses `actions/add-to-project@v1.0.2` to add the item to org project board (`AzureLocal/projects/3`). Outputs the item ID.
2. **set-fields** (issues only) — Uses `gh project item-edit` to set:
   - **ID field** — text value `VMCT-{issue_number}`
   - **Solution field** — maps `solution/*` label to a project board single-select option
   - **Priority field** — maps `priority/*` label
   - **Category field** — maps `type/*` label

---

## deploy-docs.yml

**Trigger:** Push to `main` touching `docs/**` or `mkdocs.yml`; manual via `workflow_dispatch`  
**Permissions:** `contents: read`, `pages: write`, `id-token: write`  
**Concurrency group:** `pages` (cancel-in-progress: false)

Two-job pipeline:

**build:**
1. Sets up Python 3.12
2. Installs `mkdocs-material` and `mkdocs-drawio`
3. `mkdocs build --strict`
4. Uploads `site/` as a pages artifact

**deploy:**
1. Uses `actions/deploy-pages@v4` to publish to GitHub Pages

---

## release-please.yml

**Trigger:** Push to `main`  
**Permissions:** `contents: write`, `pull-requests: write`

Uses `googleapis/release-please-action@v4`. Maintains an automated release PR that updates `CHANGELOG.md` and bumps the version. Merging it creates the GitHub release and tag.

---

## validate-config.yml

**Trigger:** Push to `main` or PR touching `config/**`; manual via `workflow_dispatch`

1. Sets up Python 3.12
2. Installs `pyyaml`, `jsonschema`
3. Validates `config/variables.example.yml` against `config/schema/variables.schema.json`

---

## validate-repo-structure.yml

**Trigger:** PR to `main`

| Check | Required Items |
|-------|---------------|
| Root files | `README.md`, `CONTRIBUTING.md`, `LICENSE`, `CHANGELOG.md`, `.gitignore` |
| Directories | `docs/`, `.github/` |
| PR template | `.github/PULL_REQUEST_TEMPLATE.md` |
| Config structure (if `config/` exists) | `config/variables.example.yml`, `config/schema/variables.schema.json` |
| Variable reference doc (if `config/` exists) | `docs/reference/variables.md` |

**Note:** The variable reference doc check (`docs/reference/variables.md`) is unique to this repo — it enforces that a human-readable variable reference exists whenever a `config/` directory is present.
