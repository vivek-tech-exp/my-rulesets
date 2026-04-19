# 🛡️ gh-ruleset-sync

**Stop clicking through the UI. Manage your GitHub repository rulesets like code.**

`gh-ruleset-sync` is a high-performance GitHub CLI extension designed to audit and enforce repository rulesets across your entire fleet. It translates complex GitHub API interactions into a simple, idempotent policy-as-code workflow.

---

## 🎯 Is this for you?

- **Solo Developers (Free/Pro):** "The UI Click-Killer." If you're tired of repetitive configuration chores every time you start a project, automate it once and never look back.
- **Small/Stealth Teams:** "The Configuration Guard." Ensure that **Repo B** is exactly as safe as **Repo A** without a dedicated DevOps person. Prevent configuration drift before it becomes a security deficit.
- **The "August 30th" Migrators:** GitHub is deprecating legacy "Protected Tags" on August 30th. This tool enables a single-command migration from legacy tags to the new Rulesets engine organization-wide.

> [!IMPORTANT]
> **Anti-Audience:** If you are on *GitHub Enterprise* with "Global Rulesets" enabled, you likely don't need this. This is for the rest of us on **Free and Pro plans** who need fleet-wide governance without the Enterprise price tag.

---

## ⚡ Installation

Requires the [GitHub CLI](https://cli.github.com/) (authenticated via `gh auth login`) and `jq`.

```bash
gh extension install vivek-tech-exp/gh-ruleset-sync
```

---

## 🚀 Top 3 Commands (Quick Start)

Immediately secure your fleet with these common patterns:

### 1. The "August 30th" Fix (Sync Tags)
Apply a moderate tag-protection policy to every repository in your organization:
```bash
gh ruleset-sync sync --org --moderate --tags --all
```

### 2. The Safety Check (Audit)
Scan your entire account for configuration drift without changing anything:
```bash
gh ruleset-sync audit --all
```

### 3. The Copy-Paste Setup (Capture)
Extract a "perfect" ruleset from a repository and save it as a reusable JSON template:
```bash
gh ruleset-sync capture "My Template" --repo my-best-repo
```

---

## 🧩 The Smart Matrix

Avoid managing raw JSON by using the built-in Smart Matrix. It maps three **Scopes** against three **Security Tiers**.

| Tier | `--individual` | `--team` | `--org` |
| :--- | :--- | :--- | :--- |
| **`--loose`** | Basic protection; allows force-pushes for the owner. | Low friction; focus on preventing accidental deletions. | Standard base; minimal restrictions for broad visibility. |
| **`--moderate`** | **Recommended.** Linear history required; no force-pushes. | Team-wide safety; requires status checks or PR reviews. | Org-wide enforced; 1 review required for all changes. |
| **`--strict`** | Maximum lockdown; no bypasses allowed. | High-security; requires multiple reviews and signed commits. | Maximum governance; zero bypass actors. |

*Note: Append `--tags` to any matrix command to target Tag Rulesets instead of Branch Rulesets.*

---

## 🛠️ Unified CLI Interface

### Core Commands
- **`sync`**: Deploy or update policies. Uses idempotency—only sends API requests if drift is detected.
- **`audit`**: Fleet discovery. Maps your entire infrastructure against known policies and provides "Fix" recommendations.
- **`capture`**: Policy onboarding. Strips repository-specific metadata to turn live rules into portable templates.
- **`nuke`**: Selective cleanup. Safely removes rulesets leveraging pre-flight checks to prevent accidental data loss.

### Essential Flags
| Flag | Description |
| :--- | :--- |
| `--config <path>` | Path to a custom JSON policy file. |
| `--repo <name>` | Target a single repository. |
| `--all` | Target every repository the user can access (respects `--visibility`). |
| `--parallel <N>` | Process N repositories concurrently (Recommended: `20` for audits, `2` for syncs). |
| `--dry-run` | Preview actions without making any API changes. |
| `--force` | Overwrite existing rules even if no structural change is detected. |

---

## 🏗️ Architecture & Resilience

Designed for scalability and reliability in professional environments:

- **Checkpoint State Management:** Every run generates `.gh_state_*` logs. If a session is interrupted (e.g., rate limits, network drop), running the same command again will **instantly resume** exactly where it left off.
- **Hashed Idempotency:** The engine performs a `jq`-based canonicalization check before every sync. It compares the "Desired" vs "Live" state and only dispatches a `PUT` request if a delta is physically identified, minimizing GitHub API pressure.
- **Resilience Wrappers:** All API calls use a `with_retry` backoff system that handles transient `502/503` errors and GitHub Secondary Rate Limits automatically.
- **Smart Archival Bypass:** Native detection of archived or disabled repositories ensures that fleet-wide commands don't fail due to read-only entities.

---

## 🤖 GitOps & CI/CD
Integrate `gh-ruleset-sync` into your GitHub Actions pipelines to enforce governance on every commit or on a schedule. See [docs/CI_CD.md](docs/CI_CD.md) for pre-configured workflow templates.

---
*Built for engineers who value their time.*