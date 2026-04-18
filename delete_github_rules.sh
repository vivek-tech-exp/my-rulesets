#!/usr/bin/env bash
set -euo pipefail

# Source the shared library dynamically based on script location
source "$(dirname "$0")/common.sh"

# Script-specific variables
TARGET_RULESET="all"

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
  --name <name>               Delete only rulesets matching this name (default: all rulesets)

Behavior:
  --parallel <N>              Process N repos concurrently (default: 1)
  --dry-run                   Show actions without deleting anything
  --yes                       Skip confirmation prompts
  --quiet                     Reduce non-essential output
  -h, --help                  Show this help
EOF
}

for raw_arg in "$@"; do
  normalize_unicode_dashes "$raw_arg"
done

while [[ $# -gt 0 ]]; do
  case "$1" in
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
      PARALLEL="$2"
      shift 2
      ;;
    --include-forks) INCLUDE_FORKS=true; shift ;;
    --include-archived) INCLUDE_ARCHIVED=true; shift ;;
    --dry-run) DRY_RUN=true; shift ;;
    --yes) YES=true; shift ;;
    --quiet) QUIET=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) error "Unknown option: $1"; echo; usage; exit 1 ;;
  esac
done

require_cmd gh
require_cmd jq
check_auth
setup_state_dir

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

print_summary_header() {
  section "Run summary"
  echo "Owner: $OWNER"
  echo "Mode: $MODE"
  echo "Target ruleset: $TARGET_RULESET"
  echo "Parallel jobs: $PARALLEL"
  echo "Dry run: $DRY_RUN"
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
  info "Performing pre-flight check for ruleset: '$TARGET_RULESET'..."
  RULESET_EXISTS=false
  
  for PRECHECK_REPO in "${REPOS[@]}"; do
    if gh api --paginate "/repos/$OWNER/$PRECHECK_REPO/rulesets" 2>/dev/null | jq -e --arg name "$TARGET_RULESET" 'any(.[]; .name == $name)' >/dev/null; then
      RULESET_EXISTS=true
      break 
    fi
  done

  if [[ "$RULESET_EXISTS" == false ]]; then
    error "Fail-Fast Abort: The ruleset '$TARGET_RULESET' does not exist in any of the ${#REPOS[@]} targeted repositories."
    error "Please check the name for typos."
    exit 1
  fi
  success "Pre-flight passed: Target ruleset exists."
  echo "----------------------------------------"
fi

print_summary_header
echo "Matched repos: ${#REPOS[@]}"

if ! confirm_scope "${#REPOS[@]}"; then
  warn "Cancelled by user."
  exit 0
fi

process_repo() {
  local REPO="$1"
  local SAFE_NAME="${REPO//\//_}"
  local TMP_ERR="$STATE_DIR/err_${SAFE_NAME}.log"
  
  info "[$REPO] Processing..."

  if ! RULESET_LIST="$(gh api --paginate "/repos/$OWNER/$REPO/rulesets" 2>"$TMP_ERR")"; then
    ERR_MSG="$(cat "$TMP_ERR")"
    if [[ "$ERR_MSG" == *"archived"* ]]; then
      warn "[$REPO] Skipped (Archived)"
      echo "$REPO (archived)" >> "$STATE_DIR/skipped.log"
      return
    fi
    error "[$REPO] Failed to list rulesets: $ERR_MSG"
    echo "$REPO (API error)" >> "$STATE_DIR/failed.log"
    return
  fi

  if [[ "$TARGET_RULESET" == "all" ]]; then
    RULESET_IDS="$(printf '%s' "$RULESET_LIST" | jq -r '.[].id')"
  else
    RULESET_IDS="$(printf '%s' "$RULESET_LIST" | jq -r --arg name "$TARGET_RULESET" '.[] | select(.name == $name) | .id')"
  fi

  if [[ -z "$RULESET_IDS" || "$RULESET_IDS" == "null" ]]; then
    success "[$REPO] No matching rulesets to delete"
    echo "$REPO (none found)" >> "$STATE_DIR/skipped.log"
    return
  fi

  local REPO_DELETED_COUNT=0
  local REPO_FAILED=false

  for ID in $RULESET_IDS; do
    RULE_NAME="$(printf '%s' "$RULESET_LIST" | jq -r --arg id "$ID" '.[] | select(.id == ($id|tonumber)) | .name')"
    
    if [[ "$DRY_RUN" == true ]]; then
      warn "[$REPO] Would delete ruleset '$RULE_NAME' (ID: $ID)"
      REPO_DELETED_COUNT=$((REPO_DELETED_COUNT + 1))
    else
      if gh api \
        --method DELETE \
        -H "Accept: application/vnd.github+json" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        "/repos/$OWNER/$REPO/rulesets/$ID" >/dev/null 2>"$TMP_ERR"; then
        success "[$REPO] Deleted ruleset '$RULE_NAME'"
        REPO_DELETED_COUNT=$((REPO_DELETED_COUNT + 1))
      else
        ERR_MSG="$(cat "$TMP_ERR")"
        if [[ "$ERR_MSG" == *"archived"* ]]; then
          warn "[$REPO] Skipped (Archived)"
          echo "$REPO (archived)" >> "$STATE_DIR/skipped.log"
          break # The whole repo is read-only, stop trying to delete other IDs
        else
          error "[$REPO] Failed to delete ruleset '$RULE_NAME': $ERR_MSG"
          REPO_FAILED=true
        fi
      fi
    fi
  done

  if [[ "$REPO_FAILED" == true ]]; then
    echo "$REPO (partial/full failure)" >> "$STATE_DIR/failed.log"
  elif [[ "$REPO_DELETED_COUNT" -gt 0 ]]; then
    if [[ "$DRY_RUN" == true ]]; then
      echo "$REPO (dry-run: $REPO_DELETED_COUNT rulesets)" >> "$STATE_DIR/deleted.log"
    else
      echo "$REPO ($REPO_DELETED_COUNT rulesets)" >> "$STATE_DIR/deleted.log"
    fi
  fi
}

echo "----------------------------------------"
job_count=0
for REPO in "${REPOS[@]}"; do
  if [[ "$PARALLEL" -eq 1 ]]; then
    process_repo "$REPO"
  else
    process_repo "$REPO" &
    job_count=$((job_count + 1))
    if [[ $job_count -ge $PARALLEL ]]; then
      wait
      job_count=0
    fi
  fi
done
wait

read_state() {
  local file="$STATE_DIR/$1"
  if [[ -f "$file" ]]; then
    while IFS= read -r line; do
      [[ -n "$line" ]] && echo "$line"
    done < "$file"
  fi
}

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

if [[ ${#DELETED_DETAILS[@]} -gt 0 ]]; then echo -e "\nRepos modified:\n$(printf ' - %s\n' "${DELETED_DETAILS[@]}")"; fi
if [[ ${#SKIPPED_DETAILS[@]} -gt 0 ]]; then echo -e "\nRepos skipped:\n$(printf ' - %s\n' "${SKIPPED_DETAILS[@]}")"; fi
if [[ ${#FAILED_DETAILS[@]} -gt 0 ]]; then echo -e "\nRepos failed:\n$(printf ' - %s\n' "${FAILED_DETAILS[@]}")"; exit 1; fi