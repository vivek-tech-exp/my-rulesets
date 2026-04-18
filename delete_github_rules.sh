#!/usr/bin/env bash
set -euo pipefail

OWNER="vivek-tech-exp"
TARGET_RULESET="all" # 'all' deletes everything; otherwise specify a name

MODE="all"
VISIBILITY="public"
INCLUDE_FORKS=false
INCLUDE_ARCHIVED=false
DRY_RUN=false
YES=false
QUIET=false

SELECTED_REPOS=()
TMP_ERR="$(mktemp "${TMPDIR:-/tmp}/gh_ruleset_delete_err.XXXXXX")"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

cleanup() {
  rm -f "$TMP_ERR"
}
trap cleanup EXIT

info() {
  [[ "$QUIET" == true ]] || echo -e "${BLUE}ℹ${NC} $*"
}

success() {
  echo -e "${GREEN}✅${NC} $*"
}

warn() {
  echo -e "${YELLOW}⚠${NC} $*"
}

error() {
  echo -e "${RED}❌${NC} $*" >&2
}

section() {
  echo -e "\n${BOLD}== $* ==${NC}"
}

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
  --dry-run                   Show actions without deleting anything
  --yes                       Skip confirmation prompts
  --quiet                     Reduce non-essential output
  -h, --help                  Show this help
EOF
}

normalize_unicode_dashes() {
  local arg="$1"
  case "$arg" in
    —*|–*)
      error "Detected a Unicode dash in argument: $arg"
      exit 1
      ;;
  esac
}

for raw_arg in "$@"; do
  normalize_unicode_dashes "$raw_arg"
done

while [[ $# -gt 0 ]]; do
  case "$1" in
    --all)
      MODE="all"
      shift
      ;;
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
    --include-forks)
      INCLUDE_FORKS=true
      shift
      ;;
    --include-archived)
      INCLUDE_ARCHIVED=true
      shift
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --yes)
      YES=true
      shift
      ;;
    --quiet)
      QUIET=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      error "Unknown option: $1"
      echo
      usage
      exit 1
      ;;
  esac
done

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    error "Missing required command: $1"
    exit 1
  }
}

require_cmd gh
require_cmd jq

if ! gh auth status >/dev/null 2>&1; then
  error "GitHub CLI is not authenticated. Run: gh auth login"
  exit 1
fi

get_repos() {
  if [[ "$MODE" == "selected" ]]; then
    printf "%s\n" "${SELECTED_REPOS[@]}"
    return
  fi

  local args=(repo list "$OWNER" --limit 2000 --json name)

  if [[ "$VISIBILITY" != "all" ]]; then
    args+=(--visibility "$VISIBILITY")
  fi

  if [[ "$INCLUDE_ARCHIVED" == false ]]; then
    args+=(--no-archived)
  fi

  if [[ "$INCLUDE_FORKS" == false ]]; then
    args+=(--source)
  fi

  gh "${args[@]}" --jq '.[].name'
}

confirm_scope() {
  local repo_count="$1"

  if [[ "$YES" == true || "$DRY_RUN" == true ]]; then
    return 0
  fi

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
  echo "Dry run: $DRY_RUN"
}

# macOS compatible array generation
REPOS=()
while IFS= read -r repo_name; do
  [[ -n "$repo_name" ]] && REPOS+=("$repo_name")
done < <(get_repos)

if [[ ${#REPOS[@]} -eq 0 ]]; then
  warn "No repositories matched your filters."
  exit 0
fi

print_summary_header
echo "Matched repos: ${#REPOS[@]}"

if ! confirm_scope "${#REPOS[@]}"; then
  warn "Cancelled by user."
  exit 0
fi

DELETED_REPOS_COUNT=0
SKIPPED_REPOS_COUNT=0
FAILED_REPOS_COUNT=0

DELETED_DETAILS=()
SKIPPED_DETAILS=()
FAILED_DETAILS=()

for REPO in "${REPOS[@]}"; do
  echo "----------------------------------------"
  info "Processing: $REPO"

  if ! RULESET_LIST="$(gh api --paginate "/repos/$OWNER/$REPO/rulesets" 2>"$TMP_ERR")"; then
    ERR_MSG="$(cat "$TMP_ERR")"
    if [[ "$ERR_MSG" == *"archived"* ]]; then
      warn "Skipping $REPO (Archived)"
      SKIPPED_REPOS_COUNT=$((SKIPPED_REPOS_COUNT + 1))
      SKIPPED_DETAILS+=("$REPO (archived)")
      continue
    fi
    error "Failed to list rulesets for $REPO: $ERR_MSG"
    FAILED_REPOS_COUNT=$((FAILED_REPOS_COUNT + 1))
    FAILED_DETAILS+=("$REPO (API error)")
    continue
  fi

  # Extract IDs based on whether we are filtering by name or deleting all
  if [[ "$TARGET_RULESET" == "all" ]]; then
    RULESET_IDS="$(printf '%s' "$RULESET_LIST" | jq -r '.[].id')"
  else
    RULESET_IDS="$(printf '%s' "$RULESET_LIST" | jq -r --arg name "$TARGET_RULESET" '.[] | select(.name == $name) | .id')"
  fi

  if [[ -z "$RULESET_IDS" || "$RULESET_IDS" == "null" ]]; then
    success "No matching rulesets to delete in $REPO"
    SKIPPED_REPOS_COUNT=$((SKIPPED_REPOS_COUNT + 1))
    SKIPPED_DETAILS+=("$REPO (none found)")
    continue
  fi

  REPO_DELETED_COUNT=0
  REPO_FAILED=false

  for ID in $RULESET_IDS; do
    RULE_NAME="$(printf '%s' "$RULESET_LIST" | jq -r --arg id "$ID" '.[] | select(.id == ($id|tonumber)) | .name')"
    
    if [[ "$DRY_RUN" == true ]]; then
      warn "Would delete ruleset '$RULE_NAME' (ID: $ID) in $REPO"
      REPO_DELETED_COUNT=$((REPO_DELETED_COUNT + 1))
    else
      if gh api \
        --method DELETE \
        -H "Accept: application/vnd.github+json" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        "/repos/$OWNER/$REPO/rulesets/$ID" >/dev/null 2>"$TMP_ERR"; then
        success "Deleted ruleset '$RULE_NAME' in $REPO"
        REPO_DELETED_COUNT=$((REPO_DELETED_COUNT + 1))
      else
        error "Failed to delete ruleset '$RULE_NAME' in $REPO: $(cat "$TMP_ERR")"
        REPO_FAILED=true
      fi
    fi
  done

  if [[ "$REPO_FAILED" == true ]]; then
    FAILED_REPOS_COUNT=$((FAILED_REPOS_COUNT + 1))
    FAILED_DETAILS+=("$REPO (partial/full failure)")
  elif [[ "$REPO_DELETED_COUNT" -gt 0 ]]; then
    DELETED_REPOS_COUNT=$((DELETED_REPOS_COUNT + 1))
    if [[ "$DRY_RUN" == true ]]; then
      DELETED_DETAILS+=("$REPO (dry-run: $REPO_DELETED_COUNT rulesets)")
    else
      DELETED_DETAILS+=("$REPO ($REPO_DELETED_COUNT rulesets)")
    fi
  fi
done

section "Final report"
echo "Repos with deletions: $DELETED_REPOS_COUNT"
echo "Repos skipped:        $SKIPPED_REPOS_COUNT"
echo "Repos failed:         $FAILED_REPOS_COUNT"

if [[ ${#DELETED_DETAILS[@]} -gt 0 ]]; then
  echo
  echo "Repos modified:"
  printf ' - %s\n' "${DELETED_DETAILS[@]}"
fi

if [[ ${#SKIPPED_DETAILS[@]} -gt 0 ]]; then
  echo
  echo "Repos skipped:"
  printf ' - %s\n' "${SKIPPED_DETAILS[@]}"
fi

if [[ ${#FAILED_DETAILS[@]} -gt 0 ]]; then
  echo
  echo "Repos failed:"
  printf ' - %s\n' "${FAILED_DETAILS[@]}"
  exit 1
fi