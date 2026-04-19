# 🛡️ ruleset-sync (Governance-as-Code)

[![GitHub CLI](https://img.shields.io/badge/gh-v2.0+-blue.svg)](https://github.com/cli/cli)
[![Bash](https://img.shields.io/badge/bash-3.2+-lightgrey.svg)](https://www.gnu.org/software/bash/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

> [!IMPORTANT]
> ### 🚨 Urgent: August 30th Tag Migration
> GitHub is deprecating legacy "Protected Tags." To keep your releases secure, all repositories must be migrated to the new **Tag Rulesets** engine by **August 30th**.
>
> Don't do it manually. `ruleset-sync` includes built-in templates to migrate your entire organization to the new system in seconds:
> ```bash
> gh ruleset-sync sync --org --moderate --tags --all
> ```

**The Enterprise Problem:** 
Managing branch protections manually across dozens (or hundreds) of GitHub repositories is a scaling nightmare. Doing it through the UI takes hours, inevitably leads to configuration drift, and leaves security gaps where teams bypass standard compliance protocols unnoticed.

**The Solution:** 
`ruleset-sync` acts as a **Policy-as-Code** automated engine. You define your organizational rulesets once in JSON, and this tool applies, audits, and enforces those rules across your entire fleet in seconds—powered by safe, concurrent GitHub API automation.

---

## ⚡ The "Aha!" Moment

Detect configuration drift silently without touching live systems...

```bash
# Instantly audit your entire public fleet across all policies
$ gh ruleset-sync audit --org --all --visibility public --parallel 5

== Fleet Discovery Summary ==
Matched:    45
Off-Matrix: 2
Failed:     0

Off-Matrix repos (Action Required):
 - core-auth-service
     ↳ Fix: gh ruleset-sync sync --config policies/org/strict.json --repo core-auth-service
 - experiments-repo
     ↳ Fix: gh ruleset-sync capture "Custom Override" --repo experiments-repo
```

...then fix it automatically!

```bash
# Instantly push the strict organizational template to the disconnected repository
$ gh ruleset-sync sync --org --strict --repo core-auth-service

[core-auth-service] Processing...
[core-auth-service] Updated ruleset
✅ Run summary: 1 Updated, 0 Failed
```

---

## 🏁 Quick Start

**1. Install Extension**
You will need the [GitHub CLI](https://cli.github.com/) authenticated.
```bash
gh extension install vivek-tech-exp/gh-ruleset-sync
gh auth login
```

**2. Preview Changes (Dry Run)**
Target a repository and simulate applying the moderate team-level ruleset template:
```bash
gh ruleset-sync sync --team --moderate --repo my-testing-repo --dry-run
```

**3. Deploy the Policy**
Remove `--dry-run` to blast it live!
```bash
gh ruleset-sync sync --team --moderate --repo my-testing-repo
```

---

## 📚 Deep Dive Documentation

This tool is built for total automation. Explore the documentation to learn how to scale it across thousands of repositories or integrate it into a zero-touch CI/CD workflow:

- [📖 Usage Manual (`docs/USAGE.md`)](docs/USAGE.md) - Full CLI command guide, Smart Matrix parameters, and the complete flag reference table.
- [🤖 CI/CD Integration (`docs/CI_CD.md`)](docs/CI_CD.md) - Turn this tool into an automated "Set and Forget" GitOps pipeline.
- [🏗️ System Architecture (`docs/ARCHITECTURE.md`)](docs/ARCHITECTURE.md) - Deep dive into state management, idempotency canonicalization, parallel threading, and resilience engineering.

---

## 🛠️ Minimal Requirements

- **GitHub CLI (`gh`)**: Must be [installed](https://cli.github.com/) and authenticated.
- **`jq`**: Required for JSON structural processing.
- **`bash`**: Compatible with macOS default (3.2+) and modern Linux distributions.