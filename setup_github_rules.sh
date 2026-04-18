#!/usr/bin/env bash
set -euo pipefail

# Source the shared library dynamically based on script location
source "$(dirname "$0")/common.sh"

# Script-specific variables
RULESET_NAME="Protect Master"
DEBUG_DIFF=false
ENFORCE_NO_BYPASS=false
REMOVE_BYPASS=false

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
  --enforce-no-bypass         Fail if the existing ruleset has bypass actors configured
  --remove-bypass             Wipe existing bypass actors from the ruleset
  --dry-run                   Show actions without changing anything
  --debug-diff                Print canonical desired/live JSON when repo differs
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
    --include-forks) INCLUDE_FORKS=true; shift ;;
    --include-archived) INCLUDE_ARCHIVED=true; shift ;;
    --enforce-no-bypass) ENFORCE_NO_BYPASS=true; shift ;;
    --remove-bypass) REMOVE_BYPASS=true; shift ;;
    --dry-run) DRY_RUN=true; shift ;;
    --debug-diff) DEBUG_DIFF=true; shift ;;
    --yes) YES=true; shift ;;
    --quiet) QUIET=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) error "Unknown option: $1"; echo; usage; exit 1 ;;
  esac
done

if [[ "$VISIBILITY" != "public" && "$VISIBILITY" != "private" && "$VISIBILITY" != "all" ]]; then
  error "Invalid --visibility value: $VISIBILITY"
  exit 1
fi

if [[ "$ENFORCE_NO_BYPASS" == true && "$REMOVE_BYPASS" == true ]]; then
  error "Cannot use --enforce-no-bypass and --remove-bypass at the same time."
  exit 1
fi

# Environment Setup
require_cmd gh
require_cmd jq
check_auth
setup_temp_file

read -r -d '' BASE_PAYLOAD <<'EOF' || true
{
  "name": "Protect Master",
  "target": "branch",
  "enforcement": "active",
  "conditions": {
    "ref_name": {
      "include": [
        "~DEFAULT_BRANCH"
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
      bypass_actors: ((.bypass_actors // []) | map({actor_id, actor_type, bypass_mode}) | sort_by(.actor_id, .actor_type)),
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

confirm_scope() {
  local repo_count="$1"
  if [[ "$YES" == true || "$DRY_RUN" == true ]]; then return 0; fi

  if [[ "$MODE" == "all" && "$repo_count" -gt 1 ]]; then
    warn "You are about to apply rulesets to multiple repositories ($repo_count)."
    echo "  Owner: $OWNER"
    echo "  Visibility: $VISIBILITY"
    echo "  Include forks: $INCLUDE_FORKS"
    echo "  Include archived: $INCLUDE_ARCHIVED"
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
  echo "Enforce no bypass: $ENFORCE_NO_BYPASS"
  echo "Remove bypass: $REMOVE_BYPASS"
}

# Fetch Repositories
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

  if ! RULESET_LIST="$(gh api --paginate "/repos/$OWNER/$REPO/rulesets" 2>"$TMP_ERR")"; then
    ERR_MSG="$(cat "$TMP_ERR")"
    if [[ "$ERR_MSG" == *"archived"* ]]; then
      warn "Skipping $REPO (Archived)"
      SKIPPED=$((SKIPPED + 1))
      SKIPPED_REPOS+=("$REPO (archived)")
      continue
    fi
    error "Failed to list rulesets for $REPO: $ERR_MSG"
    FAILED=$((FAILED + 1))
    FAILED_REPOS+=("$REPO")
    continue
  fi

  RULESET_ID="$(printf '%s' "$RULESET_LIST" | jq -r --arg name "$RULESET_NAME" '.[] | select(.name == $name) | .id' | head -n1)"

  if [[ -z "$RULESET_ID" || "$RULESET_ID" == "null" ]]; then
    CREATE_PAYLOAD="$(printf '%s' "$BASE_PAYLOAD" | jq '. + {bypass_actors: []}')"

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
        --input - <<<"$CREATE_PAYLOAD" >/dev/null 2>"$TMP_ERR"; then
        success "Created ruleset for $REPO"
        CREATED=$((CREATED + 1))
        CREATED_REPOS+=("$REPO")
      else
        ERR_MSG="$(cat "$TMP_ERR")"
        if [[ "$ERR_MSG" == *"archived"* ]]; then
          warn "Skipping $REPO (Archived)"
          SKIPPED=$((SKIPPED + 1))
          SKIPPED_REPOS+=("$REPO (archived)")
        else
          error "Failed to create ruleset for $REPO: $ERR_MSG"
          FAILED=$((FAILED + 1))
          FAILED_REPOS+=("$REPO")
        fi
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

  if [[ "$ENFORCE_NO_BYPASS" == true ]]; then
    BYPASS_COUNT="$(printf '%s' "$LIVE_JSON" | jq '.bypass_actors | length')"
    if [[ "$BYPASS_COUNT" -gt 0 ]]; then
      error "Ruleset for $REPO has bypass actors configured, but --enforce-no-bypass was set."
      FAILED=$((FAILED + 1))
      FAILED_REPOS+=("$REPO (bypass enforced)")
      continue
    fi
  fi

  MERGED_PAYLOAD="$(jq -n \
    --argjson base "$BASE_PAYLOAD" \
    --argjson live "$LIVE_JSON" \
    --arg remove_bypass "$REMOVE_BYPASS" '
    $base + {
      bypass_actors: (if $remove_bypass == "true" then [] else ($live.bypass_actors // []) end),
      rules: (
        $base.rules | map(
          . as $rule |
          ($live.rules // []) | map(select(.type == $rule.type)) | .[0].id as $id |
          if $id then $rule + {id: $id} else $rule end
        )
      )
    }
  ')"

  DESIRED_CANONICAL="$(printf '%s' "$MERGED_PAYLOAD" | canonicalize_ruleset)"
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
        --input - <<<"$MERGED_PAYLOAD" >/dev/null 2>"$TMP_ERR"; then
        success "Updated ruleset for $REPO"
        UPDATED=$((UPDATED + 1))
        UPDATED_REPOS+=("$REPO")
      else
        ERR_MSG="$(cat "$TMP_ERR")"
        if [[ "$ERR_MSG" == *"archived"* ]]; then
          warn "Skipping $REPO (Archived)"
          SKIPPED=$((SKIPPED + 1))
          SKIPPED_REPOS+=("$REPO (archived)")
        else
          error "Failed to update ruleset for $REPO: $ERR_MSG"
          FAILED=$((FAILED + 1))
          FAILED_REPOS+=("$REPO")
        fi
      fi
    fi
  fi
done

section "Final report"
echo "Created: $CREATED"
echo "Updated: $UPDATED"
echo "Skipped: $SKIPPED"
echo "Failed:  $FAILED"

if [[ ${#CREATED_REPOS[@]} -gt 0 ]]; then echo -e "\nCreated repos:\n$(printf ' - %s\n' "${CREATED_REPOS[@]}")"; fi
if [[ ${#UPDATED_REPOS[@]} -gt 0 ]]; then echo -e "\nUpdated repos:\n$(printf ' - %s\n' "${UPDATED_REPOS[@]}")"; fi
if [[ ${#SKIPPED_REPOS[@]} -gt 0 ]]; then echo -e "\nSkipped repos:\n$(printf ' - %s\n' "${SKIPPED_REPOS[@]}")"; fi
if [[ ${#FAILED_REPOS[@]} -gt 0 ]]; then echo -e "\nFailed repos:\n$(printf ' - %s\n' "${FAILED_REPOS[@]}")"; exit 1; fi