#!/usr/bin/env bash
set -euo pipefail

OWNER="vivek-tech-exp"
RULESET_NAME="Protect Master"

MODE="all"
VISIBILITY="public"
INCLUDE_FORKS=false
INCLUDE_ARCHIVED=false
DRY_RUN=false
DEBUG_DIFF=false
YES=false
QUIET=false

SELECTED_REPOS=()
TMP_ERR="$(mktemp "${TMPDIR:-/tmp}/gh_ruleset_err.XXXXXX")"

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
GitHub repository ruleset manager

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

Behavior:
  --dry-run                   Show actions without changing anything
  --debug-diff                Print canonical desired/live JSON when repo differs
  --yes                       Skip confirmation prompts
  --quiet                     Reduce non-essential output
  -h, --help                  Show this help

Examples:
  $0
  $0 --repo my-fi
  $0 --repos my-fi,borderless-buy
  $0 --all --visibility all --dry-run
  $0 --all --visibility private --yes
EOF
}

normalize_unicode_dashes() {
  local arg="$1"
  case "$arg" in
    —*|–*)
      error "Detected a Unicode dash in argument: $arg"
      error "Use normal ASCII hyphens, e.g. --repo my-fi"
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
      SELECTED_REPOS+=("$2")
      shift 2
      ;;
    --repos)
      [[ $# -ge 2 ]] || { error "--repos requires a value"; exit 1; }
      MODE="selected"
      IFS=',' read -r -a TMP_REPOS <<< "$2"
      SELECTED_REPOS+=("${TMP_REPOS[@]}")
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
    --debug-diff)
      DEBUG_DIFF=true
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

if [[ "$VISIBILITY" != "public" && "$VISIBILITY" != "private" && "$VISIBILITY" != "all" ]]; then
  error "Invalid --visibility value: $VISIBILITY"
  exit 1
fi

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

read -r -d '' RULESET_PAYLOAD <<'EOF' || true
{
  "name": "Protect Master",
  "target": "branch",
  "enforcement": "active",
  "conditions": {
    "ref_name": {
      "include": [
        "refs/heads/main",
        "refs/heads/master"
      ],
      "exclude": []
    }
  },
  "rules": [
    { "type": "deletion" },
    { "type": "non_fast_forward" },
    {
      "type": "pull_request",
      "parameters": {
        "dismiss_stale_reviews_on_push": true,
        "require_code_owner_review": false,
        "require_last_push_approval": false,
        "required_approving_review_count": 0,
        "required_review_thread_resolution": true
      }
    }
  ]
}
EOF

canonicalize_ruleset() {
  jq -S '
    {
      name,
      target,
      enforcement,
      ref_include: ((.conditions.ref_name.include // []) | sort),
      ref_exclude: ((.conditions.ref_name.exclude // []) | sort),
      rules: (
        (.rules // [])
        | map(
            if .type == "pull_request" then
              {
                type,
                parameters: {
                  dismiss_stale_reviews_on_push: (.parameters.dismiss_stale_reviews_on_push // false),
                  require_code_owner_review: (.parameters.require_code_owner_review // false),
                  require_last_push_approval: (.parameters.require_last_push_approval // false),
                  required_approving_review_count: (.parameters.required_approving_review_count // 0),
                  required_review_thread_resolution: (.parameters.required_review_thread_resolution // false)
                }
              }
            else
              { type }
            end
          )
        | sort_by(.type)
      )
    }
  '
}

DESIRED_CANONICAL="$(printf '%s' "$RULESET_PAYLOAD" | canonicalize_ruleset)"

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

  if [[ "$MODE" == "all" && ( "$VISIBILITY" == "all" || "$VISIBILITY" == "private" || "$INCLUDE_ARCHIVED" == true || "$INCLUDE_FORKS" == true ) ]]; then
    warn "You are about to apply rulesets with a broad scope."
    echo "  Owner: $OWNER"
    echo "  Visibility: $VISIBILITY"
    echo "  Include forks: $INCLUDE_FORKS"
    echo "  Include archived: $INCLUDE_ARCHIVED"
    echo "  Matched repos: $repo_count"
    read -r -p "Continue? [y/N] " answer
    [[ "$answer" =~ ^[Yy]$ ]] || return 1
  fi
}

print_summary_header() {
  section "Run summary"
  echo "Owner: $OWNER"
  echo "Mode: $MODE"
  echo "Visibility: $VISIBILITY"
  echo "Include forks: $INCLUDE_FORKS"
  echo "Include archived: $INCLUDE_ARCHIVED"
  echo "Dry run: $DRY_RUN"
}

mapfile -t REPOS < <(get_repos)

if [[ ${#REPOS[@]} -eq 0 ]]; then
  warn "No repositories matched your filters."
  exit 0
fi

print_summary_header
echo "Matched repos: ${#REPOS[@]}"
printf ' - %s\n' "${REPOS[@]}"

if ! confirm_scope "${#REPOS[@]}"; then
  warn "Cancelled by user."
  exit 0
fi

CREATED=0
UPDATED=0
SKIPPED=0
FAILED=0

CREATED_REPOS=()
UPDATED_REPOS=()
SKIPPED_REPOS=()
FAILED_REPOS=()

for REPO in "${REPOS[@]}"; do
  echo "----------------------------------------"
  info "Processing: $REPO"

  if ! RULESET_LIST="$(gh api "/repos/$OWNER/$REPO/rulesets" 2>"$TMP_ERR")"; then
    error "Failed to list rulesets for $REPO: $(cat "$TMP_ERR")"
    FAILED=$((FAILED + 1))
    FAILED_REPOS+=("$REPO")
    continue
  fi

  RULESET_ID="$(printf '%s' "$RULESET_LIST" | jq -r --arg name "$RULESET_NAME" '.[] | select(.name == $name) | .id' | head -n1)"

  if [[ -z "$RULESET_ID" || "$RULESET_ID" == "null" ]]; then
    if [[ "$DRY_RUN" == true ]]; then
      warn "Would create ruleset for $REPO"
      SKIPPED=$((SKIPPED + 1))
      SKIPPED_REPOS+=("$REPO (dry-run:create)")
    else
      if gh api \
        --method POST \
        -H "Accept: application/vnd.github+json" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        "/repos/$OWNER/$REPO/rulesets" \
        --input - <<<"$RULESET_PAYLOAD" >/dev/null 2>"$TMP_ERR"; then
        success "Created ruleset for $REPO"
        CREATED=$((CREATED + 1))
        CREATED_REPOS+=("$REPO")
      else
        error "Failed to create ruleset for $REPO: $(cat "$TMP_ERR")"
        FAILED=$((FAILED + 1))
        FAILED_REPOS+=("$REPO")
      fi
    fi
    continue
  fi

  if ! LIVE_JSON="$(gh api "/repos/$OWNER/$REPO/rulesets/$RULESET_ID" 2>"$TMP_ERR")"; then
    error "Failed to fetch ruleset $RULESET_ID for $REPO: $(cat "$TMP_ERR")"
    FAILED=$((FAILED + 1))
    FAILED_REPOS+=("$REPO")
    continue
  fi

  LIVE_CANONICAL="$(printf '%s' "$LIVE_JSON" | canonicalize_ruleset)"

  if [[ "$LIVE_CANONICAL" == "$DESIRED_CANONICAL" ]]; then
    success "Already matches desired state for $REPO"
    SKIPPED=$((SKIPPED + 1))
    SKIPPED_REPOS+=("$REPO")
  else
    if [[ "$DEBUG_DIFF" == true ]]; then
      echo "--- desired canonical ---"
      printf '%s\n' "$DESIRED_CANONICAL"
      echo "--- live canonical ---"
      printf '%s\n' "$LIVE_CANONICAL"
    fi

    if [[ "$DRY_RUN" == true ]]; then
      warn "Would update ruleset for $REPO"
      SKIPPED=$((SKIPPED + 1))
      SKIPPED_REPOS+=("$REPO (dry-run:update)")
    else
      if gh api \
        --method PUT \
        -H "Accept: application/vnd.github+json" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        "/repos/$OWNER/$REPO/rulesets/$RULESET_ID" \
        --input - <<<"$RULESET_PAYLOAD" >/dev/null 2>"$TMP_ERR"; then
        success "Updated ruleset for $REPO"
        UPDATED=$((UPDATED + 1))
        UPDATED_REPOS+=("$REPO")
      else
        error "Failed to update ruleset for $REPO: $(cat "$TMP_ERR")"
        FAILED=$((FAILED + 1))
        FAILED_REPOS+=("$REPO")
      fi
    fi
  fi
done

section "Final report"
echo "Created: $CREATED"
echo "Updated: $UPDATED"
echo "Skipped: $SKIPPED"
echo "Failed:  $FAILED"

if [[ ${#CREATED_REPOS[@]} -gt 0 ]]; then
  echo
  echo "Created repos:"
  printf ' - %s\n' "${CREATED_REPOS[@]}"
fi

if [[ ${#UPDATED_REPOS[@]} -gt 0 ]]; then
  echo
  echo "Updated repos:"
  printf ' - %s\n' "${UPDATED_REPOS[@]}"
fi

if [[ ${#SKIPPED_REPOS[@]} -gt 0 ]]; then
  echo
  echo "Skipped repos:"
  printf ' - %s\n' "${SKIPPED_REPOS[@]}"
fi

if [[ ${#FAILED_REPOS[@]} -gt 0 ]]; then
  echo
  echo "Failed repos:"
  printf ' - %s\n' "${FAILED_REPOS[@]}"
  exit 1
fi