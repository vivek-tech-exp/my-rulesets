#!/usr/bin/env bash
# shellcheck disable=SC2034
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

TARGET_RULESET="all"
SMART_SCOPE=""
SMART_LEVEL=""
SMART_TAGS=""
ROLLBACK_MODE=false

usage() {
  cat <<EOF
GitHub repository ruleset DELETION tool

Usage:
  $0 [options]

Scope:
  --all                       Apply to all matching repos (default)
  --repo <name>               Apply to one repo
  --repos <a,b,c>             Apply to comma-separated repos
  --owner <name>              GitHub user/org owner (default: $OWNER)
  --visibility <type>         public | private | all (default: $VISIBILITY)
  --include-forks             Include forked repos
  --include-archived          Include archived repos

Target:
  --config <path>             Path to JSON policy file (extracts name to delete)
  --name <name>               Delete only rulesets matching this name (default: all rulesets)

Smart Matrix (Alternative to --config):
  --org | --team | --individual   Select the policy scope
  --strict | --moderate | --loose Select the policy level
  --tags                          Target tags instead of branches (optional)

Behavior:
  --parallel <N>              Process N repos concurrently (default: 1)
  --dry-run                   Show actions without deleting anything
  --yes                       Skip confirmation prompts
  --quiet                     Reduce non-essential output
  --rollback                  Undo the changes from the last delete session
  -h, --help                  Show this help
EOF
}

read_state() {
  local file="$STATE_DIR/$1"
  if [[ -f "$file" ]]; then
    while IFS= read -r line; do
      if [[ -n "$line" ]]; then
        echo "${line#|}"
      fi
    done < "$file"
  fi
}

for raw_arg in "$@"; do normalize_unicode_dashes "$raw_arg"; done

while [[ $# -gt 0 ]]; do
  case "$1" in
    --config)
      [[ $# -ge 2 ]] || { error "--config requires a value"; exit 1; }
      if [[ ! -f "$2" ]]; then error "Config file not found: $2"; exit 1; fi
      TARGET_RULESET="$(cat "$2" | jq -r .name 2>/dev/null || echo '')"
      if [[ -z "$TARGET_RULESET" || "$TARGET_RULESET" == "null" ]]; then
        error "Failed to extract 'name' from $2"
        exit 1
      fi
      shift 2
      ;;
    --org) SMART_SCOPE="org"; shift ;;
    --team) SMART_SCOPE="team"; shift ;;
    --individual) SMART_SCOPE="individual"; shift ;;
    --strict) SMART_LEVEL="strict"; shift ;;
    --moderate) SMART_LEVEL="moderate"; shift ;;
    --loose) SMART_LEVEL="loose"; shift ;;
    --tags) SMART_TAGS="_tags"; shift ;;
    --all) MODE="all"; shift ;;
    --repo)
      [[ $# -ge 2 ]] || { error "--repo requires a value"; exit 1; }
      MODE="selected"
      SELECTED_REPOS+=("${2#*/}")
      shift 2
      ;;
    --repos)
      [[ $# -ge 2 ]] || { error "--repos requires a value"; exit 1; }
      MODE="selected"
      IFS=',' read -r -a TMP_REPOS <<< "$2"
      for r in "${TMP_REPOS[@]}"; do
        cleaned="${r#"${r%%[![:space:]]*}"}"
        cleaned="${cleaned%"${cleaned##*[![:space:]]}"}"
        SELECTED_REPOS+=("${cleaned#*/}")
      done
      shift 2
      ;;
    --owner)
      [[ $# -ge 2 ]] || { error "--owner requires a value"; exit 1; }
      OWNER="$2"
      shift 2
      ;;
    --visibility)
      [[ $# -ge 2 ]] || { error "--visibility requires a value"; exit 1; }
      VISIBILITY="$2"
      shift 2
      ;;
    --name)
      [[ $# -ge 2 ]] || { error "--name requires a value"; exit 1; }
      TARGET_RULESET="$2"
      shift 2
      ;;
    --parallel)
      [[ $# -ge 2 ]] || { error "--parallel requires a value"; exit 1; }
      [[ "$2" =~ ^[1-9][0-9]*$ ]] || { error "--parallel must be a positive integer"; exit 1; }
      PARALLEL="$2"
      shift 2
      ;;
    --include-forks) INCLUDE_FORKS=true; shift ;;
    --include-archived) INCLUDE_ARCHIVED=true; shift ;;
    --dry-run) DRY_RUN=true; shift ;;
    --yes) YES=true; shift ;;
    --quiet) QUIET=true; shift ;;
    --rollback) ROLLBACK_MODE=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) error "Unknown option: $1"; echo; usage; exit 1 ;;
  esac
done

if [[ "$VISIBILITY" != "public" && "$VISIBILITY" != "private" && "$VISIBILITY" != "all" ]]; then
  error "Invalid --visibility value: $VISIBILITY"
  exit 1
fi

if [[ "$TARGET_RULESET" == "all" && -n "$SMART_SCOPE" && -n "$SMART_LEVEL" ]]; then
  SMART_CONFIG="$SCRIPT_DIR/../policies/${SMART_SCOPE}/${SMART_LEVEL}${SMART_TAGS}.json"
  if [[ -f "$SMART_CONFIG" ]]; then
      TARGET_RULESET="$(cat "$SMART_CONFIG" | jq -r .name 2>/dev/null || echo '')"
      if [[ -z "$TARGET_RULESET" || "$TARGET_RULESET" == "null" ]]; then
        error "Failed to extract 'name' from $SMART_CONFIG"
        exit 1
      fi
  else
      error "Smart Matrix file not found: $SMART_CONFIG"
      exit 1
  fi
fi

require_cmd gh
require_cmd jq
check_auth
setup_state_dir

if [[ "$ROLLBACK_MODE" == true ]]; then
  section "Rollback Mode"
  
  DELETED_REPOS=()
  while IFS= read -r line; do [[ -n "$line" ]] && DELETED_REPOS+=("$line"); done < <(read_state "deleted.log")

  TOTAL_ROLLBACK=${#DELETED_REPOS[@]}
  
  if [[ "$TOTAL_ROLLBACK" -eq 0 ]]; then
    warn "No changes found to rollback in the current session state."
    exit 0
  fi

  # Determine session timestamp (Mac/Linux compatible)
  if date --version >/dev/null 2>&1; then
    M_TIME="$(date -d "@$(stat -c %Y "$STATE_DIR/deleted.log")" '+%Y-%m-%d %I:%M %p')"
  else
    M_TIME="$(date -r "$(stat -f %m "$STATE_DIR/deleted.log")" '+%Y-%m-%d %I:%M %p')"
  fi

  warn "⚠ Proceeding with ROLLBACK."
  echo "This will restore rulesets for $TOTAL_ROLLBACK repositories from session: $M_TIME"
  
  if [[ "$YES" == false ]]; then
    read -r -p "Are you sure you want to continue? [y/N] " answer
    [[ "$answer" =~ ^[Yy]$ ]] || { warn "Rollback cancelled."; exit 0; }
  fi

  echo "----------------------------------------"

  for item in "${DELETED_REPOS[@]}"; do
    REPO="${item%%|*}"
    SAFE_REPO="${REPO//\//_}"
    
    # Find all backups for this repo
    BACKUP_FILES=()
    while IFS= read -r f; do [[ -n "$f" ]] && BACKUP_FILES+=("$f"); done < <(ls "$STATE_DIR/backups/${SAFE_REPO}__"*.json 2>/dev/null || true)
    
    if [[ ${#BACKUP_FILES[@]} -eq 0 ]]; then
      error "[$REPO] No backups found in $STATE_DIR/backups/. Cannot restore."
      continue
    fi

    for backup in "${BACKUP_FILES[@]}"; do
      RULE_NAME="$(basename "$backup" .json | sed "s/^${SAFE_REPO}__//")"
      info "[$REPO] Recreating ruleset: $RULE_NAME..."
      
      if gh api --method POST "/repos/$OWNER/$REPO/rulesets" --input "$backup" >/dev/null 2>&1; then
        success "[$REPO] Restored '$RULE_NAME'."
      else
        error "[$REPO] Failed to restore '$RULE_NAME'."
      fi
    done
  done

  section "Rollback Complete"
  exit 0
fi

confirm_scope() {
  local repo_count="$1"
  if [[ "$YES" == true || "$DRY_RUN" == true ]]; then return 0; fi

  warn "DESTRUCTIVE ACTION: You are about to DELETE rulesets."
  echo "  Target Ruleset(s): $TARGET_RULESET"
  echo "  Owner: $OWNER"
  echo "  Mode: $MODE ($repo_count matched repos)"
  
  read -r -p "Are you sure you want to proceed? [y/N] " answer
  [[ "$answer" =~ ^[Yy]$ ]] || return 1
}

REPOS=()
while IFS= read -r repo_name; do
  [[ -n "$repo_name" ]] && REPOS+=("$repo_name")
done < <(get_repos)

if [[ ${#REPOS[@]} -eq 0 ]]; then
  warn "No repositories matched your filters."
  exit 0
fi

if [[ "$TARGET_RULESET" != "all" ]]; then
  info "Performing pre-flight check for ruleset: '$TARGET_RULESET' (scanning up to 5 repos)..."
  RULESET_EXISTS=false
  
  PRECHECK_LIMIT=5
  if [[ ${#REPOS[@]} -lt 5 ]]; then PRECHECK_LIMIT=${#REPOS[@]}; fi
  
  for (( i=0; i<PRECHECK_LIMIT; i++ )); do
    if gh api --paginate "/repos/$OWNER/${REPOS[$i]}/rulesets" 2>/dev/null | jq -e --arg name "$TARGET_RULESET" 'any(.[]; .name == $name)' >/dev/null; then
      RULESET_EXISTS=true
      break 
    fi
  done

  if [[ "$RULESET_EXISTS" == false ]]; then
    warn "Pre-flight check: Ruleset '$TARGET_RULESET' was not found in the first $PRECHECK_LIMIT repos scanned."
    if [[ "$YES" == true ]]; then
      info "Continuing due to --yes flag..."
    else
      read -r -p "This might be a typo. Continue full parallel scan anyway? [y/N] " answer
      [[ "$answer" =~ ^[Yy]$ ]] || exit 1
    fi
  else
    success "Pre-flight passed: Target ruleset exists."
  fi
  echo "----------------------------------------"
fi

section "Run summary"
echo "Owner: $OWNER"
echo "Mode: $MODE"
echo "Target ruleset: $TARGET_RULESET"
echo "Parallel jobs: $PARALLEL"
echo "Dry run: $DRY_RUN"
echo "Matched repos: ${#REPOS[@]}"

if ! confirm_scope "${#REPOS[@]}"; then
  warn "Cancelled by user."
  exit 0
fi

process_repo() {
  local REPO="$1"
  
  if grep -q -F "|${REPO}|" "$STATE_DIR"/{created,updated,skipped,failed,deleted}.log 2>/dev/null; then
    info "[$REPO] Already processed in a previous run. Resuming..."
    return 0
  fi

  local SAFE_NAME="${REPO//\//_}"
  local TMP_ERR="$STATE_DIR/err_${SAFE_NAME}.log"
  
  info "[$REPO] Processing..."

  if ! RULESET_LIST="$(fetch_rulesets "$REPO" "$TMP_ERR")"; then
    ERR_MSG="$(cat "$TMP_ERR")"
    if [[ "$ERR_MSG" == *"archived"* ]]; then
      warn "[$REPO] Skipped (Archived)"
      record_state "skipped" "$REPO|archived"
      return
    fi
    error "[$REPO] Failed to fetch rulesets: $ERR_MSG"
    record_state "failed" "$REPO|API error"
    return
  fi

  if [[ "$TARGET_RULESET" == "all" ]]; then
    RULESET_IDS="$(printf '%s' "$RULESET_LIST" | jq -r '.[].id')"
  else
    RULESET_IDS="$(printf '%s' "$RULESET_LIST" | jq -r --arg name "$TARGET_RULESET" '.[] | select(.name == $name) | .id')"
  fi

  if [[ -z "$RULESET_IDS" || "$RULESET_IDS" == "null" ]]; then
    success "[$REPO] No matching rulesets to delete"
    record_state "skipped" "$REPO|none found"
    return
  fi

  local REPO_DELETED_COUNT=0
  local REPO_FAILED=false

  while IFS= read -r ID; do
    [[ -z "$ID" ]] && continue
    RULE_NAME="$(printf '%s' "$RULESET_LIST" | jq -r --arg id "$ID" '.[] | select(.id == ($id|tonumber)) | .name')"
    
    # Capture full backup before destructive delete
    if ! FULL_JSON="$(with_retry "$TMP_ERR" gh api "/repos/$OWNER/$REPO/rulesets/$ID" 2>"$TMP_ERR")"; then
       warn "[$REPO] Could not backup '$RULE_NAME' before deletion. Rollback will be missing this ruleset."
    else
       backup_ruleset "$REPO" "$RULE_NAME" "$FULL_JSON"
    fi

    if [[ "$DRY_RUN" == true ]]; then
      warn "[$REPO] Would delete ruleset '$RULE_NAME' (ID: $ID)"
      REPO_DELETED_COUNT=$((REPO_DELETED_COUNT + 1))
      record_state "deleted" "$REPO|dry-run: $RULE_NAME"
    else
      if with_retry "$TMP_ERR" gh api \
        --method DELETE \
        -H "Accept: application/vnd.github+json" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        "/repos/$OWNER/$REPO/rulesets/$ID" >/dev/null 2>"$TMP_ERR"; then
        success "[$REPO] Deleted ruleset '$RULE_NAME'"
        REPO_DELETED_COUNT=$((REPO_DELETED_COUNT + 1))
        record_state "deleted" "$REPO|$RULE_NAME"
      else
        ERR_MSG="$(cat "$TMP_ERR")"
        if [[ "$ERR_MSG" == *"archived"* ]]; then
          warn "[$REPO] Skipped (Archived)"
          record_state "skipped" "$REPO|archived"
          break 
        else
          error "[$REPO] Failed to delete ruleset '$RULE_NAME': $ERR_MSG"
          REPO_FAILED=true
        fi
      fi
    fi
  done <<< "$RULESET_IDS"

  if [[ "$REPO_FAILED" == true ]]; then
    record_state "failed" "$REPO|partial/full failure"
  fi
}

echo "----------------------------------------"
repo_counter=0
pids=()

for REPO in "${REPOS[@]}"; do
  if (( repo_counter % 10 == 0 )); then
    check_rate_limit
  fi
  repo_counter=$((repo_counter + 1))

  if [[ "$PARALLEL" -eq 1 ]]; then
    process_repo "$REPO"
  else
    process_repo "$REPO" &
    pids+=($!)
    if [[ ${#pids[@]} -ge $PARALLEL ]]; then
      for pid in "${pids[@]+"${pids[@]}"}"; do
        if ! wait "$pid"; then
          error "A background job (PID: $pid) crashed unexpectedly."
          record_state "failed" "System Crash|PID: $pid"
        fi
      done
      pids=()
    fi
  fi
done

for pid in "${pids[@]+"${pids[@]}"}"; do 
  if ! wait "$pid"; then
    error "A background job (PID: $pid) crashed unexpectedly."
    record_state "failed" "System Crash|PID: $pid"
  fi
done

DELETED_DETAILS=()
while IFS= read -r line; do DELETED_DETAILS+=("$line"); done < <(read_state "deleted.log")
SKIPPED_DETAILS=()
while IFS= read -r line; do SKIPPED_DETAILS+=("$line"); done < <(read_state "skipped.log")
FAILED_DETAILS=()
while IFS= read -r line; do FAILED_DETAILS+=("$line"); done < <(read_state "failed.log")

section "Final report"
echo "Repos with deletions: ${#DELETED_DETAILS[@]}"
echo "Repos skipped:        ${#SKIPPED_DETAILS[@]}"
echo "Repos failed:         ${#FAILED_DETAILS[@]}"

if [[ ${#DELETED_DETAILS[@]} -gt 0 ]]; then
  echo -e "\nRepos modified:"
  for item in "${DELETED_DETAILS[@]}"; do
    echo " - ${item//|/ (})"
  done
fi
if [[ ${#SKIPPED_DETAILS[@]} -gt 0 ]]; then
  echo -e "\nRepos skipped:"
  for item in "${SKIPPED_DETAILS[@]}"; do
    echo " - ${item//|/ (})"
  done
fi
if [[ ${#FAILED_DETAILS[@]} -gt 0 ]]; then
  echo -e "\nRepos failed:"
  for item in "${FAILED_DETAILS[@]}"; do
    echo " - ${item//|/ (})"
  done
  exit 1
fi
