# Continuous Integration / Continuous Deployment (Governance-as-Code)

You can transition `ruleset-sync` from a powerful local CLI tool into a fully automated GitOps platform by hooking it directly into GitHub Actions.

This built-in workflow is designed as a "Set and Forget" solution: any merge to the `policies/` directory will automatically trigger a fleet-wide synchronization.

## 🚀 Setting Up the Workflow

A GitHub Actions workflow is already provided in the repository at `.github/workflows/sync-rules.yml`. To activate it, you simply need to provide the workflow with the necessary authentication permissions.

### Prerequisites

1. Navigate to your GitHub **Developer Settings**.
2. Select **Personal Access Tokens** > **Tokens (classic)**.
3. Click **Generate new token**.
4. Grant the token the following scopes:
   - `repo` (Full control of private repositories)
   - `admin:org` (Full control of orgs and teams, required if managing organization-level rules)
5. Copy the generated token.

### Integrating the Secret

1. In your `gh-ruleset-sync` repository on GitHub, navigate to **Settings > Secrets and variables > Actions**.
2. Click **New repository secret**.
3. Name the secret `GH_PAT`.
4. Paste the token you copied earlier into the secret value and save.

## How it Works

Once the `GH_PAT` secret is configured:

1. A collaborator makes a change to a JSON file inside the `policies/` directory (e.g., adding a new Required Status Check to `policies/org/strict.json`).
2. The collaborator opens a Pull Request and it is reviewed and merged into `main`.
3. The merge triggers the `.github/workflows/sync-rules.yml` workflow.
4. The GitHub Actions runner checks out the code, authenticates using your `GH_PAT`, and runs the `./gh-ruleset-sync sync` command.
5. The automation silently propagates that structural rule change across your entire matched fleet using the parallelization limits defined in the file.

By adopting this workflow, you secure your policies through peer review and entirely eliminate configuration drift!
