#!/usr/bin/env bash
set -euo pipefail

# Robust source pathing
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# Script-specific variables
CONFIG_FILE=""
SMART_SCOPE=""
SMART_LEVEL=""
SMART_TAGS=""
AUDIT_MODE=false
CAPTURE_MODE=false
CAPTURE_NAME=""
CAPTURE_FROM=""
DEBUG_DIFF=false
ENFORCE_NO_BYPASS=false
REMOVE_BYPASS=false
FORCE_UPDATE=false

usage() {
  cat <<EOF
GitHub repository ruleset manager

Usage:
  $0 --config <path> [options]

Config:
  --config <path>             Path to the ruleset JSON policy file (Required if not using Smart Matrix)

Smart Matrix (Alternative to --config):
  --org | --team | --individual   Select the policy scope
  --strict | --moderate | --loose Select the policy level
  --tags                          Target tags instead of branches (optional)

Scope:
  --all                       Apply to all matching repos (default)
  --repo <name>               Apply to one repo
  --repos <a,b,c>             Apply to comma-separated repos
  --owner <name>              GitHub user/org owner (default: $OWNER)
  --visibility <type>         public | private | all (default: $VISIBILITY)
  --include-forks             Include forked repos
  --include-archived          Include archived repos

Behavior:
  --parallel <N>              Process N repos concurrently (default: 1)
  --audit                     Fleet discovery: check repos against all policies in policies/
  --capture-as <name>         Fetch ruleset from --repo, clean it, and save it as <name>.json
  --capture-from <name>       Specific ruleset name to capture from (default: first found)
  --enforce-no-bypass         Fail if the existing ruleset has bypass actors configured
  --remove-bypass             Wipe existing bypass actors from the ruleset
  --force                     Force update policy even if it already matches
  --dry-run                   Show actions without changing anything
  --debug-diff                Print canonical desired/live JSON when repo differs
  --yes                       Skip confirmation prompts
  --quiet                     Reduce non-essential output
  -h, --help                  Show this help
EOF
}

for raw_arg in "$@"; do normalize_unicode_dashes "$raw_arg"; done

while [[ $# -gt 0 ]]; do
  case "$1" in
    --config)
      [[ $# -ge 2 ]] || { error "--config requires a value"; exit 1; }
      CONFIG_FILE="$2"
      shift 2
      ;;
    --org) SMART_SCOPE="org"; shift ;;
    --team) SMART_SCOPE="team"; shift ;;
    --individual) SMART_SCOPE="individual"; shift ;;
    --strict) SMART_LEVEL="strict"; shift ;;
    --moderate) SMART_LEVEL="moderate"; shift ;;
    --loose) SMART_LEVEL="loose"; shift ;;
    --tags) SMART_TAGS="_tags"; shift ;;
    --audit) AUDIT_MODE=true; shift ;;
    --capture-as)
      [[ $# -ge 2 ]] || { error "--capture-as requires a policy name"; exit 1; }
      CAPTURE_MODE=true
      CAPTURE_NAME="$2"
      shift 2
      ;;
    --capture-from)
      [[ $# -ge 2 ]] || { error "--capture-from requires a source ruleset name"; exit 1; }
      CAPTURE_FROM="$2"
      shift 2
      ;;
    --force) FORCE_UPDATE=true; shift ;;
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
    --parallel)
      [[ $# -ge 2 ]] || { error "--parallel requires a value"; exit 1; }
      [[ "$2" =~ ^[1-9][0-9]*$ ]] || { error "--parallel must be a positive integer"; exit 1; }
      PARALLEL="$2"
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

require_cmd gh
require_cmd jq

check_auth
setup_state_dir

# Smart Matrix Resolution
if [[ -z "$CONFIG_FILE" && -n "$SMART_SCOPE" && -n "$SMART_LEVEL" ]]; then
  CONFIG_FILE="$SCRIPT_DIR/../policies/${SMART_SCOPE}/${SMART_LEVEL}${SMART_TAGS}.json"
fi

if [[ "$AUDIT_MODE" == true ]]; then
  # Overlay our state prefix for audits
  setup_state_dir "audit_github_rules"
fi

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

if [[ "$AUDIT_MODE" == true ]]; then
  POLICY_COUNT=0
  POLICY_NAMES=()
  POLICY_CANONICALS=()
  POLICY_PATHS=()
  if [[ -d "$SCRIPT_DIR/../policies" ]]; then
    while IFS= read -r -d '' p; do
       POLICY_NAMES+=("$(jq -r .name < "$p")")
       POLICY_CANONICALS+=("$(cat "$p" | canonicalize_ruleset)")
       POLICY_PATHS+=("policies/${p#*/policies/}")
       POLICY_COUNT=$((POLICY_COUNT + 1))
    done < <(find "$SCRIPT_DIR/../policies" -type f -name "*.json" -print0)
  fi
  if [[ "$POLICY_COUNT" -eq 0 ]]; then
    error "Audit mode: No policies found in $SCRIPT_DIR/../policies/"
    exit 1
  fi
elif [[ "$CAPTURE_MODE" == false ]]; then
  if [[ -z "$CONFIG_FILE" || ! -f "$CONFIG_FILE" ]]; then
    error "You must specify a valid policy JSON file using --config (or run with --audit / --capture-as)"
    exit 1
  fi

  BASE_PAYLOAD="$(cat "$CONFIG_FILE")"
  RULESET_NAME="$(printf '%s' "$BASE_PAYLOAD" | jq -r .name)"
  if [[ -z "$RULESET_NAME" || "$RULESET_NAME" == "null" ]]; then
    error "Failed to extract 'name' from $CONFIG_FILE"
    exit 1
  fi
fi

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
  echo "Parallel jobs: $PARALLEL"
  echo "Audit mode: $AUDIT_MODE"
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

if [[ "$CAPTURE_MODE" == true ]]; then
  if [[ "${#REPOS[@]}" -ne 1 ]]; then
    error "--capture-as requires exactly one --repo to capture from."
    exit 1
  fi
  
  TARGET_REPO="${REPOS[0]}"
  info "Capturing policy from $TARGET_REPO..."
  
  TMP_ERR="$STATE_DIR/tmp_err"
  
  if ! RULESET_LIST="$(with_retry "$TMP_ERR" gh api --paginate "/repos/$OWNER/$TARGET_REPO/rulesets" 2>"$TMP_ERR")"; then
    error "Failed to list rulesets on $TARGET_REPO"
    exit 1
  fi
  
  local rule_count
  rule_count="$(printf '%s' "$RULESET_LIST" | jq '. | length')"
  
  if [[ "$rule_count" -eq 0 ]]; then
    error "No rulesets found on $TARGET_REPO to capture."
    exit 1
  fi
  
  local target_id=""
  
  if [[ -n "$CAPTURE_FROM" ]]; then
    target_id="$(printf '%s' "$RULESET_LIST" | jq -r --arg n "$CAPTURE_FROM" '.[] | select(.name == $n) | .id // empty' | head -n1)"
    if [[ -z "$target_id" ]]; then
      error "Could not find ruleset named '$CAPTURE_FROM' on $TARGET_REPO"
      exit 1
    fi
  elif [[ "$rule_count" -gt 1 ]]; then
    if [[ "$YES" == false && "$QUIET" == false && -t 0 ]]; then
      warn "Multiple rulesets found on $TARGET_REPO. Please select one to capture:"
      
      local options=()
      local ids=()
      while IFS= read -r row; do
        [[ -n "$row" ]] || continue
        # Format: "Name (Target: branch)"
        options+=("$(echo "$row" | cut -d'|' -f2) (Target: $(echo "$row" | cut -d'|' -f3))")
        ids+=("$(echo "$row" | cut -d'|' -f1)")
      done < <(printf '%s' "$RULESET_LIST" | jq -r '.[] | "\(.id)|\(.name)|\(.target)"')
      
      PS3="Select ruleset (1-${#options[@]}): "
      select choice in "${options[@]}"; do
        if [[ -n "$choice" ]]; then
          target_id="${ids[$((REPLY-1))]}"
          break
        else
          echo "Invalid selection."
        fi
      done
    else
      warn "Multiple rulesets found. Defaulting to the first one: $(printf '%s' "$RULESET_LIST" | jq -r '.[0].name')"
      target_id="$(printf '%s' "$RULESET_LIST" | jq -r '.[0].id')"
    fi
  else
    target_id="$(printf '%s' "$RULESET_LIST" | jq -r '.[0].id')"
  fi
  
  if ! LIVE_JSON="$(with_retry "$TMP_ERR" gh api "/repos/$OWNER/$TARGET_REPO/rulesets/$target_id" 2>"$TMP_ERR")"; then
    error "Failed to fetch ruleset $target_id: $(cat "$TMP_ERR")"
    exit 1
  fi
  
  CLEANED_JSON="$(printf '%s' "$LIVE_JSON" | jq --arg new_name "$CAPTURE_NAME" '
    del(.id, .node_id, .repository_id, .created_at, .updated_at, .source_type, .source) |
    .name = $new_name
  ')"
  
  CAPTURE_DIR="$SCRIPT_DIR/../policies/captured"
  mkdir -p "$CAPTURE_DIR"
  TARGET_FILE="$CAPTURE_DIR/${CAPTURE_NAME}.json"
  
  printf '%s\n' "$CLEANED_JSON" > "$TARGET_FILE"
  
  success "Policy captured! Saved to: policies/captured/${CAPTURE_NAME}.json"
  echo "To scale this template to all repos, run:"
  echo "./setup_github_rules.sh --config policies/captured/${CAPTURE_NAME}.json --all"
  exit 0
fi

print_summary_header
echo "Matched repos: ${#REPOS[@]}"
if [[ "$PARALLEL" -eq 1 ]]; then
  [[ ${#REPOS[@]} -gt 0 ]] && printf ' - %s\n' "${REPOS[@]}"
else
  echo " (Names omitted for brevity due to parallel mode)"
fi

if ! confirm_scope "${#REPOS[@]}"; then
  warn "Cancelled by user."
  exit 0
fi

process_repo() {
  local REPO="$1"
  
  if grep -q -F "|${REPO}|" "$STATE_DIR"/{created,updated,skipped,failed,deleted,matched,off_matrix,no_ruleset}.log 2>/dev/null; then
    info "[$REPO] Already processed in a previous run. Resuming..."
    return 0
  fi

  local SAFE_NAME="${REPO//\//_}"
  local TMP_ERR="$STATE_DIR/err_${SAFE_NAME}.log"
  
  info "[$REPO] Processing..."

  if ! RULESET_LIST="$(with_retry "$TMP_ERR" gh api --paginate "/repos/$OWNER/$REPO/rulesets" 2>"$TMP_ERR")"; then
    ERR_MSG="$(cat "$TMP_ERR")"
    if [[ "$ERR_MSG" == *"archived"* ]]; then
      warn "[$REPO] Skipped (Archived)"
      record_state "skipped" "$REPO|archived"
      return
    fi
    error "[$REPO] Failed to list rulesets: $ERR_MSG"
    record_state "failed" "$REPO|"
    return
  fi

  if [[ "$AUDIT_MODE" == true ]]; then
    if [[ -z "$RULESET_LIST" || "$RULESET_LIST" == "[]" ]]; then
      echo -e "${BLUE}[$REPO] NO RULESET FOUND${NC}"
      record_state "no_ruleset" "$REPO|"
      return
    fi
    
    local matched=false
    local match_name=""
    local ids
    local first_live_json=""
    local first_canonical=""

    ids="$(printf '%s' "$RULESET_LIST" | jq -r '.[].id')"
    for ID in $ids; do
       if ! LIVE_JSON="$(with_retry "$TMP_ERR" gh api "/repos/$OWNER/$REPO/rulesets/$ID" 2>"$TMP_ERR")"; then
         continue
       fi
       LIVE_CANONICAL="$(printf '%s' "$LIVE_JSON" | canonicalize_ruleset)"
       
       if [[ -z "$first_live_json" ]]; then
         first_live_json="$LIVE_JSON"
         first_canonical="$LIVE_CANONICAL"
       fi
       
       for i in "${!POLICY_CANONICALS[@]}"; do
          if [[ "$LIVE_CANONICAL" == "${POLICY_CANONICALS[$i]}" ]]; then
             matched=true
             match_name="${POLICY_NAMES[$i]}"
             break 2
          fi
       done
    done
    
    if [[ "$matched" == true ]]; then
      echo -e "${GREEN}[$REPO] MATCHED: $match_name${NC}"
      record_state "matched" "$REPO|$match_name"
    else
      echo -e "${YELLOW}[$REPO] OFF-MATRIX / CUSTOM${NC}"
      
      if [[ -n "$first_live_json" ]]; then
        local live_name
        live_name="$(printf '%s' "$first_live_json" | jq -r '.name // empty')"
        
        local target_idx=-1
        for i in "${!POLICY_NAMES[@]}"; do
          if [[ "${POLICY_NAMES[$i]}" == "$live_name" ]]; then
            target_idx=$i
            break
          fi
        done
        
        if [[ "$target_idx" -ge 0 ]]; then
          echo -e "       ${BLUE}↳ Drift detected against matrix policy '${live_name}':${NC}"
          diff -u <(printf '%s\n' "${POLICY_CANONICALS[$target_idx]}") <(printf '%s\n' "$first_canonical") | \
            tail -n +3 | sed 's/^/         /' || true
          record_state "off_matrix" "$REPO|./rules.sh sync --config ${POLICY_PATHS[$target_idx]} --repo $REPO"
        else
          echo -e "       ${BLUE}↳ Custom ruleset name: '${live_name}' (No matching matrix template)${NC}"
          record_state "off_matrix" "$REPO|./rules.sh capture \"${live_name}\" --repo $REPO"
        fi
      else
        record_state "off_matrix" "$REPO|./rules.sh capture \"unknown\" --repo $REPO"
      fi
    fi
    return
  fi

  RULESET_ID="$(printf '%s' "$RULESET_LIST" | jq -r --arg name "$RULESET_NAME" '.[] | select(.name == $name) | .id' | head -n1)"

  if [[ -z "$RULESET_ID" || "$RULESET_ID" == "null" ]]; then
    CREATE_PAYLOAD="$(printf '%s' "$BASE_PAYLOAD" | jq '. + {bypass_actors: []}')"

    if [[ "$DRY_RUN" == true ]]; then
      warn "[$REPO] Would create ruleset"
      record_state "skipped" "$REPO|dry-run:create"
    else
      if with_retry "$TMP_ERR" gh api \
        --method POST \
        -H "Accept: application/vnd.github+json" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        "/repos/$OWNER/$REPO/rulesets" \
        --input - <<<"$CREATE_PAYLOAD" >/dev/null 2>"$TMP_ERR"; then
        success "[$REPO] Created ruleset"
        record_state "created" "$REPO|"
      else
        ERR_MSG="$(cat "$TMP_ERR")"
        if [[ "$ERR_MSG" == *"archived"* ]]; then
          warn "[$REPO] Skipped (Archived)"
          record_state "skipped" "$REPO|archived"
        else
          error "[$REPO] Failed to create ruleset: $ERR_MSG"
          record_state "failed" "$REPO|"
        fi
      fi
    fi
    return
  fi

  if ! LIVE_JSON="$(with_retry "$TMP_ERR" gh api "/repos/$OWNER/$REPO/rulesets/$RULESET_ID" 2>"$TMP_ERR")"; then
    error "[$REPO] Failed to fetch ruleset $RULESET_ID: $(cat "$TMP_ERR")"
    record_state "failed" "$REPO|"
    return
  fi

  if [[ "$ENFORCE_NO_BYPASS" == true ]]; then
    BYPASS_COUNT="$(printf '%s' "$LIVE_JSON" | jq '.bypass_actors | length')"
    if [[ "$BYPASS_COUNT" -gt 0 ]]; then
      error "[$REPO] Has bypass actors configured, but --enforce-no-bypass was set."
      record_state "failed" "$REPO|bypass enforced"
      return
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

  if [[ "$LIVE_CANONICAL" == "$DESIRED_CANONICAL" && "$FORCE_UPDATE" == false ]]; then
    success "[$REPO] Already matches desired state"
    record_state "skipped" "$REPO|"
  else
    if [[ "$FORCE_UPDATE" == true && "$LIVE_CANONICAL" == "$DESIRED_CANONICAL" ]]; then
       info "[$REPO] State identical, but proceeding due to --force"
    fi

    if [[ "$DEBUG_DIFF" == true ]]; then
      echo "--- [$REPO] desired canonical ---"
      printf '%s\n' "$DESIRED_CANONICAL"
      echo "--- [$REPO] live canonical ---"
      printf '%s\n' "$LIVE_CANONICAL"
    fi

    if [[ "$DRY_RUN" == true ]]; then
      warn "[$REPO] Would update ruleset"
      record_state "skipped" "$REPO|dry-run:update"
    else
      if with_retry "$TMP_ERR" gh api \
        --method PUT \
        -H "Accept: application/vnd.github+json" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        "/repos/$OWNER/$REPO/rulesets/$RULESET_ID" \
        --input - <<<"$MERGED_PAYLOAD" >/dev/null 2>"$TMP_ERR"; then
        
        if [[ "$FORCE_UPDATE" == true && "$LIVE_CANONICAL" == "$DESIRED_CANONICAL" ]]; then
          success "[$REPO] Force-synced policy from $RULESET_NAME"
        else
          success "[$REPO] Updated ruleset"
        fi
        record_state "updated" "$REPO|"
      else
        ERR_MSG="$(cat "$TMP_ERR")"
        if [[ "$ERR_MSG" == *"archived"* ]]; then
          warn "[$REPO] Skipped (Archived)"
          record_state "skipped" "$REPO|archived"
        else
          error "[$REPO] Failed to update ruleset: $ERR_MSG"
          record_state "failed" "$REPO|"
        fi
      fi
    fi
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

if [[ "$AUDIT_MODE" == true ]]; then
  MATCHED_REPOS=()
  while IFS= read -r line; do MATCHED_REPOS+=("$line"); done < <(read_state "matched.log")
  OFF_MATRIX_REPOS=()
  while IFS= read -r line; do OFF_MATRIX_REPOS+=("$line"); done < <(read_state "off_matrix.log")
  NO_RULESET_REPOS=()
  while IFS= read -r line; do NO_RULESET_REPOS+=("$line"); done < <(read_state "no_ruleset.log")
  SKIPPED_REPOS=()
  while IFS= read -r line; do SKIPPED_REPOS+=("$line"); done < <(read_state "skipped.log")
  FAILED_REPOS=()
  while IFS= read -r line; do FAILED_REPOS+=("$line"); done < <(read_state "failed.log")

  section "Fleet Discovery Summary"
  echo "Matched:    ${#MATCHED_REPOS[@]}"
  echo "Off-Matrix: ${#OFF_MATRIX_REPOS[@]}"
  echo "No Ruleset: ${#NO_RULESET_REPOS[@]}"
  echo "Skipped:    ${#SKIPPED_REPOS[@]}"
  echo "Failed:     ${#FAILED_REPOS[@]}"
  
  if [[ ${#MATCHED_REPOS[@]} -gt 0 ]]; then echo -e "\nMatched repos:\n$(printf ' - %s\n' "${MATCHED_REPOS[@]//|/ (} )")"; fi
  if [[ ${#OFF_MATRIX_REPOS[@]} -gt 0 ]]; then
    echo -e "\nOff-Matrix repos (Action Required):"
    for item in "${OFF_MATRIX_REPOS[@]}"; do
      # Item format is `|repo|fix command`
      # Strip leading `|`
      item="${item#|}"
      r="${item%%|*}"
      cmd="${item#*|}"
      if [[ "$r" != "$cmd" ]]; then
        echo -e " - $r\n     ↳ Fix: $cmd"
      else
        echo " - $r"
      fi
    done
  fi
  if [[ ${#NO_RULESET_REPOS[@]} -gt 0 ]]; then echo -e "\nNo Ruleset repos:\n$(printf ' - %s\n' "${NO_RULESET_REPOS[@]//|/}")"; fi
  if [[ ${#FAILED_REPOS[@]} -gt 0 ]]; then echo -e "\nFailed repos:\n$(printf ' - %s\n' "${FAILED_REPOS[@]//|/ (} )")"; exit 1; fi
else
  CREATED_REPOS=()
  while IFS= read -r line; do CREATED_REPOS+=("$line"); done < <(read_state "created.log")
  UPDATED_REPOS=()
  while IFS= read -r line; do UPDATED_REPOS+=("$line"); done < <(read_state "updated.log")
  SKIPPED_REPOS=()
  while IFS= read -r line; do SKIPPED_REPOS+=("$line"); done < <(read_state "skipped.log")
  FAILED_REPOS=()
  while IFS= read -r line; do FAILED_REPOS+=("$line"); done < <(read_state "failed.log")

  section "Final report"
  echo "Created: ${#CREATED_REPOS[@]}"
  echo "Updated: ${#UPDATED_REPOS[@]}"
  echo "Skipped: ${#SKIPPED_REPOS[@]}"
  echo "Failed:  ${#FAILED_REPOS[@]}"

  if [[ ${#CREATED_REPOS[@]} -gt 0 ]]; then echo -e "\nCreated repos:\n$(printf ' - %s\n' "${CREATED_REPOS[@]//|/}")"; fi
  if [[ ${#UPDATED_REPOS[@]} -gt 0 ]]; then echo -e "\nUpdated repos:\n$(printf ' - %s\n' "${UPDATED_REPOS[@]//|/}")"; fi
  if [[ ${#SKIPPED_REPOS[@]} -gt 0 ]]; then echo -e "\nSkipped repos:\n$(printf ' - %s\n' "${SKIPPED_REPOS[@]//|/ (} )")"; fi
  if [[ ${#FAILED_REPOS[@]} -gt 0 ]]; then echo -e "\nFailed repos:\n$(printf ' - %s\n' "${FAILED_REPOS[@]//|/ (} )")"; exit 1; fi
fi