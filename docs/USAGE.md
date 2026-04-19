# Command Line Usage Guide

The `ruleset-sync` tool operates as a GitHub CLI extension, routing commands to the underlying sync and cleanup engines.

## 🚀 Unified CLI Commands

The CLI supports the following primary commands:

```bash
gh ruleset-sync <command> [options]
```

- `sync` - Deploy or update policies across your fleet.
- `audit` - Perform fleet discovery to find out-of-sync policies.
- `capture` - Extract an existing ruleset from a repository into a reusable JSON template.
- `nuke` - Safely delete rulesets from repositories.

---

## 1. Setting Up & Updating Rulesets (`sync`)

The `sync` command applies configurations using idempotency. If a ruleset already matches the desired policy, no API calls are made.

```bash
# Apply a specific policy file to a single repository (Dry Run)
gh ruleset-sync sync --config policies/team/moderate.json --repo my-repo --dry-run

# Apply structural policies using the Smart Matrix
gh ruleset-sync sync --individual --strict --repos "my-repo, another-repo"

# Scale out: Apply org-level rules to ALL public repositories, processing 5 at a time
gh ruleset-sync sync --org --strict --all --visibility public --parallel 5

# Security Audit: Compare live state against strict policy without making changes
gh ruleset-sync sync --org --strict --all --dry-run
```

## 2. Fleet Discovery (`audit`)

Audit mode crawls your entire infrastructure to instantly map organizational drift against your policy matrix. It does *not* make any mutating API calls.

```bash
# Scan a specific repository against all standard policies to map drift
gh ruleset-sync audit --repo my-rulesets

# Scan the entire public organization fleet against all policies concurrently
gh ruleset-sync audit --all --visibility public --parallel 5
```
*(At the end of an audit, the system provides recommendations on commands to run to fix any disconnected repositories).*

## 3. Policy Onboarding (`capture`)

Translate manual UI-created rulesets directly into portable JSON templates. This strips away repository-specific metadata (IDs, creation dates).

```bash
# Extract the first ruleset from 'my-repo', strip metadata, and save as a template
gh ruleset-sync capture "My Standard Rules" --repo my-repo

# Explicitly target a specific ruleset if multiple exist (e.g., to capture Tags)
gh ruleset-sync capture "My Tag Policy" --repo my-repo --capture-from "Protect Tags"

# Then apply the captured template organization-wide
gh ruleset-sync sync --config policies/captured/My_Standard_Rules.json --all
```

> [!TIP]
> **Smart Capture**: If you are in interactive mode (your terminal) and a repository contains multiple rulesets, the tool will automatically present a menu allowing you to choose between branch and tag rulesets before saving. In non-interactive/CI flows, it defaults to the first ruleset with a warning.

## 4. Deleting Rulesets (`nuke`)

Safely target and delete rulesets. The tool runs a pre-flight check to verify that rulesets actually exist before scaling out destructive actions.

```bash
# Leverage the Smart Matrix to safely simulate deleting a specific policy tier
gh ruleset-sync nuke --team --moderate --all --dry-run

# Delete a ruleset via literal string name instead of config parameters
gh ruleset-sync nuke --repos "my-fi, old-project" --name "Protect Master" --yes

# Nuke Option: Delete ALL rulesets on a specific repository
gh ruleset-sync nuke --repo my-test-repo
```

---

## 🚩 Available Flags Reference

| Flag | Description | Default |
|:---|:---|:---|
| `--config <path>` | **[Required by Sync]** Path to JSON policy file | - |
| `--org` / `--team` / `--individual` | **[Smart Matrix]** Select the policy scope (alternative to `--config`) | - |
| `--strict` / `--moderate` / `--loose` | **[Smart Matrix]** Select the policy level (alternative to `--config`) | - |
| `--tags` | **[Smart Matrix]** Target tags instead of branches | - |
| `--audit` | **[Fleet Discovery]** Check repos against all policies in `policies/` | `false` |
| `--capture-as <name>` | **[Policy Onboarding]** Fetch a ruleset, clean it, and save as JSON | - |
| `--capture-from <name>` | **[Policy Onboarding]** Specific ruleset name to capture from | *First found* |
| `--force` | Force update a policy even if the local logic detects no changes | `false` |
| `--all` | Apply to all matching repos | `true` |
| `--repo <name>` | Apply to a single repository | - |
| `--repos <a,b>` | Apply to comma-separated repositories | - |
| `--owner <name>` | GitHub user/org owner | *Attempts auto-discovery* |
| `--visibility <type>` | Filter by `public`, `private`, or `all` | `all` |
| `--include-forks` | Include forked repositories | `false` |
| `--include-archived` | Include archived repositories | `false` |
| `--parallel <N>` | Process N repositories concurrently | `1` |
| `--dry-run` | Show actions without making any API mutations | - |
| `--yes` | Skip safety confirmation prompts | - |
| `--quiet` | Reduce non-essential terminal output | - |
| `-h, --help` | Show the help menu | - |
