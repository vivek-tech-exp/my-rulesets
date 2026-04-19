# 🛡️ my-rulesets

[![GitHub CLI](https://img.shields.io/badge/gh-v2.0+-blue.svg)](https://github.com/cli/cli)
[![Bash](https://img.shields.io/badge/bash-3.2+-lightgrey.svg)](https://www.gnu.org/software/bash/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

A robust GitHub CLI toolset for applying, updating, and deleting standard repository branch rulesets across one repo, selected repos, or all repositories you own.

Engineered for **safety**, **idempotency**, and **scalability**, featuring parallel processing, smart error classification, and state management.

---

## 📖 Table of Contents
- [Features](#-features)
- [Architecture](#-architecture)
- [Requirements](#-requirements)
- [Usage Examples](#-usage-examples)
- [CI/CD Integration](#-cicd-integration-governance-as-code)
- [Available Flags](#-available-flags)
- [Operational Warnings](#-operational-warning-api-rate-limits)
- [Technical Notes](#-technical-notes)

---

## ✨ Features

- 🔄 **Idempotent Updates**: Compares canonicalized live ruleset JSON against desired state to prevent unnecessary API calls and noisy audit logs.
- 🔍 **Fleet Discovery**: Isolated `--audit` mode crawls the full policy matrix to instantly map organizational drift without requiring a specific config or making mutating API calls.
- 📸 **Policy Onboarding**: Translate manual UI-created rulesets directly into portable JSON templates via `--capture-as`.
- ⚡ **Concurrency**: Process multiple repositories simultaneously using the `--parallel` flag for massive speed improvements at scale.
- 🎯 **Smart Targeting**: Dynamically targets the repository's native default branch (`~DEFAULT_BRANCH`) rather than hardcoding `main` or `master`.
- 🕵️ **Bypass Actor Management**: Audit or intentionally wipe `bypass_actors` configuration across your repositories.
- 🚀 **Fail-Fast Deletions**: Performs a highly efficient pre-flight scan to ensure the target ruleset exists before executing loops.
- 🛡️ **Archived Repo Resilience**: Gracefully skips archived repositories (403 errors) while failing loudly for genuine permission issues.
- 🔁 **Auto-Retry Logic**: Built-in exponential backoff for transient 502s and secondary rate limits.

---

## 🏗️ Architecture

This toolset separates policy definitions from execution logic:

| Component | Description |
|:---|:---|
| **`common.sh`** | **Shared Infrastructure**: API helpers, logging, error handling, and parallel state management. |
| **`setup_github_rules.sh`** | **Sync Engine**: Creates and updates rulesets dynamically loaded from JSON policy configurations. |
| **`delete_github_rules.sh`** | **Cleanup Engine**: Safely deletes rulesets using `--config` (extracts name automatically) or raw `--name`. |
| **`policies/`** | **Policy Matrix**: 9 JSON configuration files categorized by scale (`individual`, `team`, `org`) and strictness. |

---

## 🛠️ Requirements

- **GitHub CLI (`gh`)**: Must be [installed](https://cli.github.com/) and authenticated (`gh auth login`).
- **`jq`**: Required for JSON processing and canonicalization.
- **`bash`**: Compatible with macOS default (3.2+) and modern Linux.

---

## 🚀 Usage Examples

### 1. Setting Up & Updating Rulesets
```bash
# Test a policy on a single repository (Dry Run)
./rules.sh sync --config policies/team/moderate.json --repo my-fi --dry-run

# Apply structural policies leveraging the Smart Matrix
./rules.sh sync --individual --strict --repos "my-fi, borderless-buy"

# Scale out: Apply org-level rules to ALL public repositories, processing 5 at a time
./rules.sh sync --org --strict --all --visibility public --parallel 5

# Security Audit: Compare live state against strict policy without making changes
./rules.sh sync --org --strict --all --dry-run
```

### 2. Fleet Discovery (Audit Mode)
```bash
# Scan a specific repository against all policies to map drift
./rules.sh audit --repo my-rulesets

# Scan the entire public organization fleet against all policies concurrently
./rules.sh audit --all --visibility public --parallel 5
```

### 3. Policy Onboarding (Capture Mode)
```bash
# Extract the first ruleset from 'my-repo', strip metadata, and save as a template
./rules.sh capture "My Standard Rules" --repo my-repo

# Then apply the captured template organization-wide
./rules.sh sync --config policies/captured/My_Standard_Rules.json --all
```

### 4. Deleting Rulesets
```bash
# Leverage the Smart Matrix to safely simulate deleting a specific policy tier
./rules.sh nuke --team --moderate --all --dry-run

# Delete a ruleset via literal string name instead of config parameters
./rules.sh nuke --repos "my-fi, old-project" --name "Protect Master" --yes

# Nuke Option: Delete ALL rulesets on a specific repository
./rules.sh nuke --repo my-test-repo
```

---

## 🚀 CI/CD Integration (Governance-as-Code)

You can transition `my-rulesets` from a local CLI tool to a fully automated GitOps platform by hooking it directly into GitHub Actions.

This built-in workflow is designed as a "Set and Forget" solution: any merge to the `policies/` directory will automatically trigger a fleet-wide synchronization.

### Setup Instructions
1. Navigate to your Developer Settings and generate a **Personal Access Token (Classic)** with `repo` and `admin:org` scopes.
2. In your `my-rulesets` repository, go to **Settings > Secrets and variables > Actions**.
3. Create a **New repository secret** named `GH_PAT` and paste your token.

Once set up, whenever a collaborator modifies a policy inside the `policies/` directory, GitHub Actions will silently and automatically propagate that structural change across your fleet!

---

## 🚩 Available Flags

| Flag | Description | Default |
|:---|:---|:---|
| `--config <path>` | **[Required by setup]** Path to JSON policy file | - |
| `--org` / `--team` / `--individual` | **[Smart Matrix]** Select the policy scope (alternative to `--config`) | - |
| `--strict` / `--moderate` / `--loose` | **[Smart Matrix]** Select the policy level (alternative to `--config`) | - |
| `--tags` | **[Smart Matrix]** Target tags instead of branches | - |
| `--audit` | **[Fleet Discovery]** Check repos against all policies in `policies/` | `false` |
| `--capture-as <name>` | **[Policy Onboarding]** Fetch a ruleset, clean it, and save as JSON (replaces `--config`) | - |
| `--force` | Force update a policy even if the local logic detects no changes | `false` |
| `--all` | Apply to all matching repos | `true` |
| `--repo <name>` | Apply to a single repository | - |
| `--repos <a,b>` | Apply to comma-separated repositories | - |
| `--owner <name>` | GitHub user/org owner | `vivek-tech-exp` |
| `--visibility <type>` | Filter by `public`, `private`, or `all` | `all` |
| `--include-forks` | Include forked repositories | `false` |
| `--include-archived` | Include archived repositories | `false` |
| `--parallel <N>` | Process N repositories concurrently | `1` |
| `--dry-run` | Show actions without making any API mutations | - |
| `--yes` | Skip safety confirmation prompts | - |
| `--quiet` | Reduce non-essential terminal output | - |
| `-h, --help` | Show the help menu | - |

---

## ⚠️ Operational Warning: API Rate Limits

> [!IMPORTANT]
> GitHub enforces strict **Secondary Rate Limits** (abuse detection) to prevent rapid, concurrent API mutations. Use the `--parallel` flag judiciously.

- **✅ Safe (Auditing):** `--parallel 20 --dry-run` (GET requests are generally safe at high concurrency).
- **✅ Safe (Mutating):** `--parallel 2` (Slow, steady POST/PUT/DELETE avoid abuse limits).
- **❌ Dangerous:** `--parallel 20` (Blasting mutations will likely result in a temporary 403 API block).

---

## 📝 Technical Notes

- **Resilience**: The toolset utilizes a retry-with-backoff wrapper. If a transient error or rate limit is hit, it pauses and retries up to 3 times.
- **Default Scope**: If no flags are provided, scripts target all **public**, **non-archived**, **non-forked** repositories.
- **Canonicalization**: The `jq` block in `setup_github_rules.sh` ensures that GitHub's slight JSON shape changes (like adding new feature flags) don't trigger false-positive updates.