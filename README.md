# my-rulesets

A small GitHub CLI tool for applying a standard repository branch ruleset across one repo, selected repos, or all repos you own.

## Features

- Apply to all repos or selected repos
- Filter by visibility: public, private, or all
- Exclude forks and archived repos by default
- Dry-run mode
- Safer confirmation prompt for broad scopes
- Attempts idempotent behavior by comparing canonicalized ruleset JSON before updating
- Final report with created, updated, skipped, and failed repos

## Requirements

- `gh` installed and authenticated
- `jq` installed

## Usage

```bash
chmod +x setup_github_rules.sh
./setup_github_rules.sh
./setup_github_rules.sh --repo my-fi
./setup_github_rules.sh --repos my-fi,borderless-buy
./setup_github_rules.sh --all --visibility all --dry-run
./setup_github_rules.sh --all --visibility private --yes
```

## Notes

- Default scope is public, non-archived, non-fork repos.
- The ruleset currently targets both `main` and `master`.
- If GitHub returns live ruleset JSON in a different shape from the create/update payload, canonicalization may still need fine-tuning for exact no-op detection.