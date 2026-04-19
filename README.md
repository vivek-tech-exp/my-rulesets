# 🛡️ my-rulesets (Governance-as-Code)

[![GitHub CLI](https://img.shields.io/badge/gh-v2.0+-blue.svg)](https://github.com/cli/cli)
[![Bash](https://img.shields.io/badge/bash-3.2+-lightgrey.svg)](https://www.gnu.org/software/bash/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

**The Enterprise Problem:** 
Managing branch protections manually across dozens (or hundreds) of GitHub repositories is a scaling nightmare. Doing it through the UI takes hours, inevitably leads to configuration drift, and leaves security gaps where teams bypass standard compliance protocols unnoticed.

**The Solution:** 
`my-rulesets` acts as a **Policy-as-Code** automated engine. You define your organizational rulesets once in JSON, and this tool applies, audits, and enforces those rules across your entire fleet in seconds—powered by safe, concurrent GitHub API automation.

---

## ⚡ The "Aha!" Moment

Detect configuration drift silently without touching live systems...

```bash
# Instantly audit your entire public fleet across all policies
$ ./rules.sh audit --org --all --visibility public --parallel 5

== Fleet Discovery Summary ==
Matched:    45
Off-Matrix: 2
Failed:     0

Off-Matrix repos (Action Required):
 - legacy-auth-service
     ↳ Fix: ./rules.sh sync --config policies/org/strict.json --repo legacy-auth-service
 - experiments-repo
     ↳ Fix: ./rules.sh capture "Custom Override" --repo experiments-repo
```

...then fix it automatically!

```bash
# Instantly push the strict organizational template to the disconnected repository
$ ./rules.sh sync --org --strict --repo legacy-auth-service

[legacy-auth-service] Processing...
[legacy-auth-service] Updated ruleset
✅ Run summary: 1 Updated, 0 Failed
```

---

## 🏁 Quick Start

**1. Clone & Authenticate**
You will need the [GitHub CLI](https://cli.github.com/) authenticated with an account capable of managing the spaces you wish to target. 
```bash
git clone https://github.com/vivek-tech-exp/my-rulesets.git
cd my-rulesets
gh auth login
```

**2. Preview Changes (Dry Run)**
Target a repository and simulate applying the moderate team-level ruleset template:
```bash
./rules.sh sync --team --moderate --repo my-testing-repo --dry-run
```

**3. Deploy the Policy**
Remove `--dry-run` to blast it live!
```bash
./rules.sh sync --team --moderate --repo my-testing-repo
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