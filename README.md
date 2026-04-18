# my-rulesets

A robust GitHub CLI toolset for applying, updating, and deleting standard repository branch rulesets across one repo, selected repos, or all repositories you own. 

It is engineered for safety, idempotency, and scalability, featuring parallel processing, smart error classification, and state management.

## Features

- **Idempotent Updates:** Compares canonicalized live ruleset JSON against the desired state to prevent unnecessary API calls and noisy audit logs.
- **Concurrency:** Process multiple repositories simultaneously using the `--parallel` flag for massive speed improvements at scale.
- **Smart Targeting:** Dynamically targets the repository's native default branch (`~DEFAULT_BRANCH`) rather than hardcoding `main` or `master`.
- **Bypass Actor Management:** Audit or intentionally wipe `bypass_actors` configuration across your repositories.
- **Fail-Fast Deletions:** The deletion script performs a highly efficient pre-flight scan to ensure the target ruleset actually exists before executing massive loops.
- **Archived Repo Resilience:** Correctly classifies 403 API errors to skip gracefully if a repository is archived, while failing loudly for genuine token/scope permission issues.

## Architecture

This toolset consists of three core files:

1. **`common.sh`** — The shared infrastructure containing API helpers, logging, error handling, and parallel state management. **(Required)**
2. **`setup_github_rules.sh`** — The engine for creating and updating the default "Protect Master" ruleset.
3. **`delete_github_rules.sh`** — The engine for safely deleting rulesets (all or by specific name).

## Requirements

- `gh` (GitHub CLI) installed and authenticated (`gh auth login`)
- `jq` installed
- `bash` (compatible with macOS default Bash 3.2+ and Linux)

---

## Common Usage Examples

```bash
# ==========================================
# 1. SETTING UP & UPDATING RULESETS
# ==========================================

# Test on a single repository (Dry Run)
./setup_github_rules.sh --repo my-fi --dry-run

# Apply to specific repositories with debug output
./setup_github_rules.sh --repos "my-fi, borderless-buy" --debug-diff

# Scale out: Apply to ALL public repositories, processing 5 at a time
./setup_github_rules.sh --all --visibility public --parallel 5

# Security Audit: Apply to all repos, but FAIL if any currently have Bypass Actors configured
./setup_github_rules.sh --all --enforce-no-bypass

# Security Remediation: Force wipe any existing Bypass Actors across all private repos
./setup_github_rules.sh --all --visibility private --remove-bypass

# ==========================================
# 2. DELETING RULESETS
# ==========================================

# Safely verify what would happen if you delete a specific ruleset
./delete_github_rules.sh --all --name "Protect Master" --dry-run

# Delete a specifically named ruleset from multiple selected repositories
./delete_github_rules.sh --repos "my-fi, old-project" --name "Protect Master" --yes

# Nuke Option: Delete ALL rulesets on a specific repository
./delete_github_rules.sh --repo my-test-repo
```

## Available Flags

| Flag | Description |
|------|-------------|
| `--all` | Apply to all matching repos (default) |
| `--repo <name>` | Apply to a single repository |
| `--repos <a,b>` | Apply to comma-separated repositories |
| `--owner <name>` | GitHub user/org owner (default: `vivek-tech-exp`) |
| `--visibility <type>` | Filter by `public`, `private`, or `all` |
| `--include-forks` | Include forked repositories (ignored by default) |
| `--include-archived` | Include archived repositories (ignored by default) |
| `--parallel <N>` | Process N repositories concurrently (default: 1) |
| `--dry-run` | Show actions without making any API mutations |
| `--yes` | Skip safety confirmation prompts |
| `--quiet` | Reduce non-essential terminal output |
| `-h, --help` | Show the help menu |

## ⚠️ Operational Warning: API Rate Limits

GitHub enforces strict Secondary Rate Limits (abuse detection mechanisms) to prevent rapid, concurrent API mutations.

When using the `--parallel` flag, please observe the following safety limits to avoid a temporary 403 API ban:

**Safe (Auditing):** 
```bash
./setup_github_rules.sh --all --parallel 20 --dry-run
```
(Heavy GET requests are generally safe to run at high concurrency)

**Safe (Mutating):** 
```bash
./setup_github_rules.sh --all --parallel 2
```
(Slow, steady POST/PUT/DELETE mutations avoid triggering abuse limits)

**Dangerous:** 
```bash
./setup_github_rules.sh --all --parallel 20
```
(Blasting 20 simultaneous mutations will likely result in an immediate temporary block)

## Notes

- **Default Scope:** By default, if no flags are provided, the scripts target all public, non-archived, non-forked repositories.
- **Canonicalization:** If GitHub returns live ruleset JSON in a slightly different shape from the initial create/update payload (e.g., adding new feature flags to the API in the future), the jq canonicalization block in `setup_github_rules.sh` may need minor fine-tuning to ensure perfect no-op detection.