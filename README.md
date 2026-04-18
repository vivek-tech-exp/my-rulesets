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
- [Available Flags](#-available-flags)
- [Operational Warnings](#-operational-warning-api-rate-limits)
- [Technical Notes](#-technical-notes)

---

## ✨ Features

- 🔄 **Idempotent Updates**: Compares canonicalized live ruleset JSON against desired state to prevent unnecessary API calls and noisy audit logs.
- ⚡ **Concurrency**: Process multiple repositories simultaneously using the `--parallel` flag for massive speed improvements at scale.
- 🎯 **Smart Targeting**: Dynamically targets the repository's native default branch (`~DEFAULT_BRANCH`) rather than hardcoding `main` or `master`.
- 🕵️ **Bypass Actor Management**: Audit or intentionally wipe `bypass_actors` configuration across your repositories.
- 🚀 **Fail-Fast Deletions**: Performs a highly efficient pre-flight scan to ensure the target ruleset exists before executing loops.
- 🛡️ **Archived Repo Resilience**: Gracefully skips archived repositories (403 errors) while failing loudly for genuine permission issues.
- 🔁 **Auto-Retry Logic**: Built-in exponential backoff for transient 502s and secondary rate limits.

---

## 🏗️ Architecture

This toolset consists of three core components:

| Component | Description |
|:---|:---|
| [`common.sh`](file:///Users/vivekmankonda/Documents/GitHub/my-rulesets/common.sh) | **Shared Infrastructure**: API helpers, logging, error handling, and parallel state management. |
| [`setup_github_rules.sh`](file:///Users/vivekmankonda/Documents/GitHub/my-rulesets/setup_github_rules.sh) | **Sync Engine**: The primary tool for creating and updating the "Protect Master" ruleset. |
| [`delete_github_rules.sh`](file:///Users/vivekmankonda/Documents/GitHub/my-rulesets/delete_github_rules.sh) | **Cleanup Engine**: Safely deletes rulesets by name or wipes all rulesets from a target. |

---

## 🛠️ Requirements

- **GitHub CLI (`gh`)**: Must be [installed](https://cli.github.com/) and authenticated (`gh auth login`).
- **`jq`**: Required for JSON processing and canonicalization.
- **`bash`**: Compatible with macOS default (3.2+) and modern Linux.

---

## 🚀 Usage Examples

### 1. Setting Up & Updating Rulesets
```bash
# Test on a single repository (Dry Run)
./setup_github_rules.sh --repo my-fi --dry-run

# Apply to specific repositories with debug output
./setup_github_rules.sh --repos "my-fi, borderless-buy" --debug-diff

# Scale out: Apply to ALL public repositories, processing 5 at a time
./setup_github_rules.sh --all --visibility public --parallel 5

# Security Audit: Apply but FAIL if any currently have Bypass Actors configured
./setup_github_rules.sh --all --enforce-no-bypass

# Security Remediation: Force wipe Bypass Actors across all private repos
./setup_github_rules.sh --all --visibility private --remove-bypass
```

### 2. Deleting Rulesets
```bash
# Safely verify what would happen if you delete a specific ruleset
./delete_github_rules.sh --all --name "Protect Master" --dry-run

# Delete a specifically named ruleset from multiple selected repositories
./delete_github_rules.sh --repos "my-fi, old-project" --name "Protect Master" --yes

# Nuke Option: Delete ALL rulesets on a specific repository
./delete_github_rules.sh --repo my-test-repo
```

---

## 🚩 Available Flags

| Flag | Description | Default |
|:---|:---|:---|
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