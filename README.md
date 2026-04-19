# 🛡️ gh-ruleset-sync

**Stop clicking through the UI. Manage your GitHub repository rulesets like code.**

`gh-ruleset-sync` is a GitHub CLI extension for people who manage more than one repository and don't have time to manualy configure branch protections one-by-one. It acts as a lightweight **Policy-as-Code** engine that audits and enforces rules across your entire fleet in seconds.

---

## 🎯 Is this for you?

- **Solo Developers:** If you're tired of "boring UI chores" every time you start a new project. Automate the setup once and get back to coding.
- **Stealth / Small Teams:** If you need to ensure **Repo B** is just as safe as **Repo A** without hiring a dedicated DevOps person. Prevent configuration drift before it becomes a security hole.
- **The "August 30th" Crowd:** GitHub is deprecating legacy "Protected Tags" on August 30th. This tool can migrate your entire organization to the new Tag Ruleset engine in a single command.

> [!NOTE]  
> **Anti-Audience:** If your company is on *GitHub Enterprise* and uses "Global Rulesets," you don't need this. This tool is for the rest of us on **Free and Pro plans** who are tired of clicking through the UI.

---

## ⚡ Quick Start

### 1. Install
You will need the [GitHub CLI](https://cli.github.com/) authenticated (`gh auth login`).
```bash
gh extension install vivek-tech-exp/gh-ruleset-sync
```

### 2. The "August 30th" Migration (Tags)
Migrate every repository in your organization to a moderate Tag protection policy:
```bash
gh ruleset-sync sync --org --moderate --tags --all
```

### 3. The Safety Check (Audit)
See which repositories have rules that have drifted from your master templates:
```bash
gh ruleset-sync audit --all
```

---

## 🧩 The Smart Matrix

Most users don't want to manage raw JSON files. `ruleset-sync` comes with a built-in **Smart Matrix** that covers 90% of common governance needs. Just pick a **Scope** and a **Level**:

| Level / Scope | `--individual` | `--team` | `--org` |
| :--- | :--- | :--- | :--- |
| **`--loose`** | Basic protection | Collaborative | Standard base |
| **`--moderate`** | Recommended | Team-wide strict | Org-wide enforced |
| **`--strict`** | No bypasses | High-security | Maximum lockdown |

*Pass `--tags` to any of these to target Tag Rulesets instead of Branch Rulesets.*

---

## 🛡️ Safety Features

We know that "Automated Deletion" sounds scary. We built this with three layers of safety:

1.  **Audit Mode (`audit`)**: Scan your fleet without changing anything. It produces a drift report showing exactly which repos are out of sync.
2.  **Dry Runs (`--dry-run`)**: Add this flag to any command to see exactly what *would* happen without sending a single write request to GitHub.
3.  **Name Collision Protection**: The tool strictly prevents accidental overwrites. If a repository has a ruleset with the same name that wasn't created by this tool, it will fail loudly and ask for manual review.

---

## 🚀 Advanced Workflows

### Capture Existing Rules
Found a repository that has the "perfect" configuration? Extract it into a reusable template:
```bash
gh ruleset-sync capture "Golden Template" --repo my-best-repo
```

### GitOps / CI-CD
You can run this tool in GitHub Actions to "Set and Forget" your organizational governance. Every time you add a new repo, the tool will automatically apply your policies on the next run.
- See [docs/CI_CD.md](docs/CI_CD.md) for setup guides.

---

## 🛠️ Requirements
- **`gh` cli** (v2.0+)
- **`jq`** (for JSON processing)
- **`bash`** (v3.2+ compatible)

---

*Built because life is too short to click through GitHub Settings menus.*