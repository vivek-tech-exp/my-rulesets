# Internal Architecture Notes

This file is for maintainers working on the implementation. Reader-facing usage, plays, commands, and CI setup now live in `README.md`.

The `ruleset-sync` tool is engineered for safety, idempotency, and scalability at an enterprise level. It strictly separates policy definitions from execution routing.

## 🏗️ Directory Map & Component Design

| Component | Description |
|:---|:---|
| **`gh-ruleset-sync`** | **The Unified Entry Point**: A thin routing layer that translates user intents (`sync`, `audit`, `capture`, `nuke`) into execution flows. |
| **`internal/common.sh`**| **Shared Infrastructure**: Handles API helpers, logging, error handling, rate-limit evaluation, and parallel execution state management. |
| **`internal/setup_github_rules.sh`**| **The Sync Engine**: Translates and synchronizes rulesets dynamically loaded from JSON policy configurations against live repository rule layouts. |
| **`internal/delete_github_rules.sh`**| **The Cleanup Engine**: Safely queries and deletes targeted rulesets leveraging pre-flight checks to prevent empty destructive loops at scale. |
| **`policies/`** | **The Policy Matrix**: The repository scaling layer consisting of JSON configuration templates categorized by impact radius (`individual`, `team`, `org`) and strictness constraints. |

---

## 🛠️ Performance & Scalability

### 1. Smart Concurrency
Through the `--parallel` flag, the engine spawns background sub-shells allowing multiple repositories to be evaluated or modified simultaneously. A wait-and-catch system ensures that failed threads report accurately without hanging the primary session.

### 2. Operational API Limits
Running aggressive mutative requests introduces the risk of triggering GitHub's **Secondary Rate Limits** (abuse detection). 
- **Auditing**: `--parallel 20` is generally safe as GET requests are lenient.
- **Mutating (Sync/Nuke)**: Limit to `--parallel 2` to safely trickle API mutations globally without tripping abuse filters.

---

## 🛡️ Resilience Engineering

### 1. Checkpoint State Management
Every operation builds lightweight state logs dynamically. If a process drops, breaks, or gets rate-limited, running the exact same command will read the session state and resume where it left off. 

State is stored in centralized, XDG-compliant directories:
`~/.config/gh-ruleset-sync/state/${OWNER}/${script_name}/`

This structure ensures that multiple owners (orgs/users) and different operations (`sync` vs `audit` vs `nuke`) have isolated state and rollback history.
### 2. Auto-Retry Backoff Wrappers
All direct GitHub API calls (`gh api`) are executed via a `with_retry` wrapper. 
- Transient 502/503 errors and secondary rate limits trigger an **exponential backoff delay** (2s -> 4s -> 8s) up to 3 attempts.
- Known terminal errors (e.g., 404 Not Found, 403 Archived Repo) are short-circuited to "fail-fast," saving bandwidth and time.

### 3. Smart Archival Bypass
The engine natively catches API errors indicating a repository was archived or disabled by the owner, immediately classifying the action as a "Skip" rather than emitting false-positive Pipeline/Action failures.

---

## 🔄 State Evaluation & Canonicalization
To minimize API calls (and bloated Audit Logs on GitHub), `setup_github_rules.sh` strictly utilizes Canonicalization Checks.

1. Live JSON is polled for the target repository via a GET request.
2. Both the Live JSON and the Desired JSON undergo `jq` canonicalization (alphabetical ordering, metadata stripping, mapping structural arrays).
3. The engine performs a hashed-string comparison.
4. An update PUT request is **only dispatched** if structural drift is physically identified. 

*(You can bypass structural validation forcing an API overwrite using the `--force` flag).*
