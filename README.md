# 🛡️ gh-ruleset-sync

**Stop clicking through the UI. Manage your GitHub repository rulesets like code.**

`gh-ruleset-sync` is a GitHub CLI extension for people who want fleet-wide ruleset automation without turning this into a full-time admin hobby. It gives solo devs, startups, and small teams on GitHub Free/Pro a way to replace repetitive UI-clicking with repeatable commands, policy files, drift audits, and rollback safety.

> [!IMPORTANT]
> **Anti-Audience:** If you're on GitHub Enterprise with Global Rules, you don't need this. This is for the rest of us.

## Contents

- [Installation](#installation)
- [Quick Start](#quick-start)
- [Smart Matrix](#the-smart-matrix)
- [Operator's Playbook](#the-operators-playbook)
- [Command Reference](#command-reference)
- [GitOps & CI/CD](#gitops--cicd)
- [Why It Stays Safe](#why-it-stays-safe)

## Installation

Requires the [GitHub CLI](https://cli.github.com/) authenticated via `gh auth login`, plus `jq`.

```bash
gh auth login
gh extension install vivek-tech-exp/gh-ruleset-sync
```

Two habits will save you pain:

- Use `--dry-run` before write-heavy operations.
- Use `--parallel 20` for audits and `--parallel 2` for sync/nuke runs.

## Quick Start

### 1. Solo Repo Baseline

```bash
gh ruleset-sync sync --individual --moderate --repo my-side-project --owner your-github-user --yes
```

### 2. Fleet Audit

```bash
gh ruleset-sync audit --owner your-org --all --visibility public --parallel 20
```

### 3. Tag Migration

```bash
gh ruleset-sync sync --org --moderate --tags --all --owner your-org --yes --parallel 2
```

## The Smart Matrix

The Smart Matrix maps three scopes against three security tiers so you can work with intent-based commands instead of hand-picking JSON every time.

The JSON files in `policies/` are the source of truth. Some loose and moderate tiers intentionally overlap in the current matrix.

| Tier | `--individual` | `--team` | `--org` |
| :--- | :--- | :--- | :--- |
| **`--loose`** | Blocks branch deletion and force-pushes on the default branch. | Blocks deletion and force-pushes; requires 1 PR approval with resolved review threads. | Same as team loose, plus signed commits. |
| **`--moderate`** | Same as individual loose today: blocks deletion and force-pushes on the default branch. | Same as team loose today: blocks deletion and force-pushes; requires 1 PR approval with resolved review threads. | Blocks deletion and force-pushes; requires signed commits and 2 PR approvals with resolved review threads. |
| **`--strict`** | Adds signed commits and explicitly enforces zero bypass actors. | Requires signed commits, 2 PR approvals, resolved review threads, and zero bypass actors. | Requires signed commits, 2 PR approvals, code owner review, resolved review threads, and zero bypass actors. |

Append `--tags` to any Smart Matrix command to target tag rulesets instead of branch rulesets.

## The Operator's Playbook

This is the strategy guide. Use the plays below when you know the problem you need to solve, but do not want to rediscover the command shape from scratch.

## Chapter 1: Day Zero (Onboarding & Setup)

### Play 1: Solo Dev Baseline

**The Scenario:** I just started a new side project and need baseline security without clicking 10 times in the UI. I want the sane default, not a ceremony-heavy process.

**The Play (Command):**

```bash
gh ruleset-sync sync --individual --moderate --repo my-side-project --owner your-github-user --yes
```

**The Impact:** This applies the current `individual_moderate` policy to the default branch of `my-side-project`. Today, that means branch deletion and force-pushes are blocked on the default branch. For a solo repo, that is the right level of protection when you want Peace of Mind without slowing yourself down.

**Pro-Tip:** Run the same command with `--dry-run` first if you want to preview the move before it writes anything.

### Play 2: The Policy Clone

**The Scenario:** You already built a complex ruleset once in the GitHub UI on a "Golden Repo," and redoing it manually across 20 more projects would be pure UI-clicking debt.

**The Play (Command):**

```bash
gh ruleset-sync capture GoldenRepoPolicy --repo golden-repo --owner your-org --capture-from "Protect Main"
gh ruleset-sync sync --config policies/captured/GoldenRepoPolicy.json --repos "app-01,app-02,app-03,app-04,app-05,app-06,app-07,app-08,app-09,app-10,app-11,app-12,app-13,app-14,app-15,app-16,app-17,app-18,app-19,app-20" --owner your-org --yes --parallel 2
```

**The Impact:** The first command captures a live ruleset from `golden-repo`, strips GitHub-specific metadata, and saves a reusable JSON template under `policies/captured/GoldenRepoPolicy.json`. The second command fans that exact policy out to the listed repos, which is the right move when the UI already proved the policy and you just need repeatability.

**Pro-Tip:** Keep the capture name simple and filename-safe. The tool sanitizes the saved filename, but clean names make the repo easier to live with.

## Chapter 2: Health & Hygiene (Auditing & Drift)

### Play 3: Fleet-Wide Security Audit

**The Scenario:** You need to know which public repos are fine, which are custom snowflakes, and which have no rulesets at all. This is the "show me the gaps" play.

**The Play (Command):**

```bash
gh ruleset-sync audit --owner your-org --all --visibility public --parallel 20
```

**The Impact:** This scans every matched public repo, compares live rulesets against the local Smart Matrix, and reports classifications without making any mutating API calls. Repos with no rulesets are surfaced in the summary and written to `~/.config/gh-ruleset-sync/state/your-org/audit_github_rules/no_ruleset.log`, which makes it easy to turn drift discovery into an action list.

**Pro-Tip:** Audit is GET-heavy, so `--parallel 20` is a good default when you want speed.

## Chapter 3: The Emergency Room (Migrations & Rollbacks)

### Play 4: The Tag Crisis

**The Scenario:** Legacy protected tags are going away and you need to migrate version tags to the ruleset engine before the August 30 deadline. You want one controlled move, not repo-by-repo panic.

**The Play (Command):**

```bash
gh ruleset-sync sync --org --moderate --tags --all --owner your-org --yes --parallel 2
```

**The Impact:** This resolves to `policies/org/moderate_tags.json` and applies the current org-level tag ruleset across the matched fleet. Today, that means tags matching `refs/tags/v*` are protected from deletion and updates through GitHub's ruleset engine, which is the correct migration path when you want modern tag governance without hand-rebuilding policy in every repo.

**Pro-Tip:** Run it once with `--dry-run` to preview the blast radius, then rerun without `--dry-run` for the real migration.

### Play 5: The Selective Nuke

**The Scenario:** A junk ruleset named `Testing` leaked into the fleet and now it is cluttering repos everywhere. You need to remove only that ruleset without touching production protections.

**The Play (Command):**

```bash
gh ruleset-sync nuke --name "Testing" --all --owner your-org --yes --parallel 2
```

**The Impact:** This targets only rulesets literally named `Testing`, performs a pre-flight existence check, backs each one up before deletion, and leaves differently named production rulesets alone. It is the correct move when the cleanup target is known and you want a surgical delete instead of a broad wipe.

**Pro-Tip:** Add `--dry-run` first, or narrow the scope with `--visibility private` or `--repos` if you want an even tighter blast radius.

### Play 6: The Emergency Undo

**The Scenario:** The last sync blocked the team from pushing and nobody wants a long postmortem before work can resume. You need the fastest safe path back.

**The Play (Command):**

```bash
gh ruleset-sync sync --owner your-org --rollback --yes
```

**The Impact:** This reads the last sync session state from `~/.config/gh-ruleset-sync/state/your-org/setup_github_rules/`, loads the backup JSON captured before each update, and restores the previous rulesets with `PUT` requests. That is the right move because rollback uses the exact backed-up live configuration from the last session instead of guessing what "working" used to be.

**Pro-Tip:** If the bad operation was a delete run instead of a sync run, use `gh ruleset-sync nuke --owner your-org --rollback --yes`.

## Chapter 4: Scaling the Standard (Governance for Teams)

### Play 7: Private Fleet Lockdown

**The Scenario:** The company has a growing pile of private repos and you need one standard that says "this is how we ship here." You want the Smart Matrix to do the boring work consistently.

**The Play (Command):**

```bash
gh ruleset-sync sync --org --strict --all --visibility private --owner your-org --yes --parallel 2
```

**The Impact:** This resolves to `policies/org/strict.json` and applies the current strict org standard across all matched private repositories. Today, that means branch deletion and force-push protection, signed commits, 2 PR approvals, code owner review, resolved review threads, and zero bypass actors. That is the correct move when private repos are now shared production surface area, not personal scratchpads.

**Pro-Tip:** If you want a staged rollout, replace `--all` with `--repos` and walk the standard through a small pilot set first.

### Play 8: The CI/CD Enforcer

**The Scenario:** The policies are finally right, but somebody can still disable them with late-night UI-clicking. You want policy changes to happen through code review, not side-channel admin actions.

**The Play (Command):**

```bash
gh secret set GH_PAT --repo your-org/gh-ruleset-sync --body "$GH_PAT"
```

**The Impact:** This arms the built-in GitHub Actions workflow at `.github/workflows/sync-rules.yml`. Once `GH_PAT` exists, pushes that change `policies/**/*.json` trigger a fleet sync using `./gh-ruleset-sync sync --config policies/org/strict.json --all --yes --quiet --parallel 2`, which turns ruleset governance into reviewed, repeatable automation.

**Pro-Tip:** Test policy changes locally with `--dry-run` before merging them, because `policies/` is production configuration.

## Command Reference

The CLI entrypoint is:

```bash
gh ruleset-sync <command> [options]
```

Core commands:

- `sync`: Deploy or update policies across your fleet.
- `audit`: Perform fleet discovery to find out-of-sync or missing rulesets.
- `capture`: Extract an existing ruleset into a reusable JSON template.
- `nuke`: Delete targeted rulesets with backup and rollback support.

### Common Command Examples

`sync`

```bash
gh ruleset-sync sync --config policies/team/moderate.json --repo my-repo --owner your-org --dry-run
gh ruleset-sync sync --individual --strict --repos "my-repo,another-repo" --owner your-github-user --yes
gh ruleset-sync sync --org --strict --all --visibility public --owner your-org --yes --parallel 2
```

`audit`

```bash
gh ruleset-sync audit --repo my-rulesets --owner your-org
gh ruleset-sync audit --all --visibility public --owner your-org --parallel 20
```

`capture`

```bash
gh ruleset-sync capture MyStandardRules --repo my-repo --owner your-org
gh ruleset-sync capture MyTagPolicy --repo my-repo --owner your-org --capture-from "Protect Tags"
gh ruleset-sync sync --config policies/captured/MyStandardRules.json --owner your-org --all --yes --parallel 2
```

`nuke`

```bash
gh ruleset-sync nuke --team --moderate --all --owner your-org --dry-run
gh ruleset-sync nuke --repos "my-fi,old-project" --owner your-org --name "Protect Master" --yes
gh ruleset-sync nuke --repo my-test-repo --owner your-org --yes
```

### Flags

| Flag | Description | Default |
| :--- | :--- | :--- |
| `--config <path>` | Path to a JSON policy file | - |
| `--org` / `--team` / `--individual` | Smart Matrix scope selector | - |
| `--strict` / `--moderate` / `--loose` | Smart Matrix tier selector | - |
| `--tags` | Target tag rulesets instead of branch rulesets | - |
| `--audit` | Compare repos against all policies in `policies/` | `false` |
| `--capture-from <name>` | Capture a specific live ruleset by name | first found |
| `--force` | Update even if canonicalized desired/live state already matches | `false` |
| `--all` | Apply to all matched repositories | `true` |
| `--repo <name>` | Target a single repository | - |
| `--repos <a,b>` | Target comma-separated repositories | - |
| `--owner <name>` | GitHub user/org owner | attempts auto-discovery |
| `--visibility <type>` | Filter by `public`, `private`, or `all` | `all` |
| `--include-forks` | Include forked repositories | `false` |
| `--include-archived` | Include archived repositories | `false` |
| `--parallel <N>` | Process repositories concurrently | `1` |
| `--dry-run` | Show actions without making mutations | `false` |
| `--yes` | Skip confirmation prompts | `false` |
| `--quiet` | Reduce non-essential output | `false` |
| `--rollback` | Undo the last sync or delete session for the current owner | `false` |

### Capture Behavior

If you run `capture` interactively and the repo contains multiple rulesets, the tool can prompt you to choose which one to save. In non-interactive or CI contexts, it falls back to the first ruleset with a warning unless you pass `--capture-from`.

## GitOps & CI/CD

If you want to stop relying on manual UI fixes, wire policy updates into GitHub Actions and treat `policies/` like production configuration.

The repository already includes a built-in workflow at `.github/workflows/sync-rules.yml`. It runs whenever `policies/**/*.json` changes on `main` or `master`.

### Setup

1. Create a classic GitHub Personal Access Token.
2. Grant it:
   - `repo`
   - `admin:org` if you are managing organization-owned repositories
3. Save it as a repository Actions secret named `GH_PAT`.

You can do that with GitHub CLI:

```bash
gh secret set GH_PAT --repo your-org/gh-ruleset-sync --body "$GH_PAT"
```

### What the Workflow Does

1. A collaborator changes a policy file under `policies/`.
2. That change is reviewed and merged.
3. GitHub Actions checks out the repo and authenticates `gh` using `GH_PAT`.
4. The runner executes:

```bash
./gh-ruleset-sync sync --config policies/org/strict.json --all --yes --quiet --parallel 2
```

That gives you a simple GitOps loop: policy changes happen through pull requests, not through random UI-clicking on production repos.

## Why It Stays Safe

- **Checkpoint state:** Runs store progress in `~/.config/gh-ruleset-sync/state/`, so interrupted sessions can resume cleanly.
- **Hashed idempotency:** The sync engine canonicalizes desired and live rulesets and only sends `PUT` requests when real drift exists.
- **Rollback safety net:** Sync and nuke operations create backups before changing live rulesets.
- **Retry wrappers:** API calls retry on transient failures with backoff.
- **Archived repo handling:** Archived or disabled repos are skipped instead of crashing the whole run.

---

Built for engineers who value their time.
