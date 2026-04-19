#!/usr/bin/env bash
# common.sh - Shared logic for GitHub ruleset scripts

# --- Default Global Variables ---
OWNER=""
MODE="all"
VISIBILITY="public"
INCLUDE_FORKS=false
INCLUDE_ARCHIVED=false
DRY_RUN=false
YES=false
QUIET=false
PARALLEL=1
SELECTED_REPOS=()

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

# --- Logging Functions ---
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

# --- Validation & Setup ---
normalize_unicode_dashes() {
  local arg="$1"
  case "$arg" in
    —*|–*)
      error "Detected a Unicode dash in argument: $arg"
      error "Use normal ASCII hyphens."
      exit 1
      ;;
  esac
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    error "Missing required command: $1"
    exit 1
  }
}

check_auth() {
  if ! gh auth status >/dev/null 2>&1; then
    error "GitHub CLI is not authenticated. Run: gh auth login"
    exit 1
  fi

  if [[ -z "$OWNER" ]]; then
    local personal_user
    personal_user="$(gh api user --jq .login 2>/dev/null)" || {
      error "Failed to retrieve default GitHub owner. Please specify with --owner."
      exit 1
    }

    local user_orgs
    user_orgs="$(gh api user/orgs --jq '.[].login' 2>/dev/null || true)"

    if [[ -n "$user_orgs" && "$YES" == false && "$QUIET" == false && -t 0 ]]; then
      info "You are part of multiple organizations."
      echo "To prevent accidental deployments, please select the target owner:"
      echo
      
      local options=("$personal_user (Personal Account)")
      local org_list=()
      while IFS= read -r org; do
        [[ -n "$org" ]] && org_list+=("$org")
      done <<< "$user_orgs"
      
      options+=("${org_list[@]}")
      
      # Use select for an interactive menu
      PS3="Select owner (1-${#options[@]}): "
      select choice in "${options[@]}"; do
        if [[ -n "$choice" ]]; then
          if [[ "$REPLY" -eq 1 ]]; then
            OWNER="$personal_user"
          else
            OWNER="${org_list[$((REPLY-2))]}"
          fi
          break
        else
          echo "Invalid selection. Please try again."
        fi
      done
      
      echo
      info "Selected owner: $OWNER"
      info "(Tip: You can skip this prompt in the future by passing: --owner $OWNER)"
      echo "----------------------------------------"
    else
      # Fallback to personal account for non-interactive or explicit bypass
      OWNER="$personal_user"
      if [[ -n "$user_orgs" && "$QUIET" == false ]]; then
         info "Defaulting to personal account: $OWNER"
      fi
    fi
  fi
}

# --- State Management ---
setup_state_dir() {
  local script_name="${1:-$(basename "$0" .sh)}"
  
  STATE_DIR="${PWD}/.gh_state_${script_name}_${OWNER}"
  mkdir -p "$STATE_DIR"
  
  # Ensure all possible log files exist so grep/read_state doesn't fail during evaluation
  touch "$STATE_DIR"/{created,updated,skipped,failed,deleted,matched,off_matrix,no_ruleset}.log
        
  info "State directory: $STATE_DIR"
}

# POSIX atomic append (safe for strings < PIPE_BUF / 512 bytes)
record_state() {
  local state_type="$1"
  local text="$2"
  printf '|%s\n' "$text" >> "$STATE_DIR/${state_type}.log"
}

# --- Rate Limit Protection (Graceful Exit) ---
check_rate_limit() {
  local rate_data
  if ! rate_data="$(gh api /rate_limit 2>/dev/null)"; then return 0; fi

  local remaining
  local reset_time
  remaining="$(echo "$rate_data" | jq -r '.resources.core.remaining' 2>/dev/null || true)"
  reset_time="$(echo "$rate_data" | jq -r '.resources.core.reset' 2>/dev/null || true)"

  if [[ -z "$remaining" || ! "$remaining" =~ ^[0-9]+$ ]]; then return 0; fi

  if [[ "$remaining" -lt 50 ]]; then
    echo "----------------------------------------"
    warn "PRIMARY API RATE LIMIT EXHAUSTED ($remaining requests left)."
    
    if date --version >/dev/null 2>&1; then
      local reset_str="$(date -d "@$reset_time" '+%I:%M %p')"
    else
      local reset_str="$(date -r "$reset_time" '+%I:%M %p')"
    fi

    warn "GitHub will reset your quota at $reset_str."
    warn "The script has safely saved its state to $STATE_DIR."
    warn "Waiting for running background jobs to finish securely..."
    
    wait 
    
    warn "Simply run the exact same command later to resume from where it left off."
    echo "----------------------------------------"
    exit 429
  fi
}

# --- Resilient API Execution (Backoff & Retry) ---
with_retry() {
  local tmp_err="$1"
  shift
  local max_attempts=3
  local attempt=1
  local backoff=2
  local exit_code=0

  while (( attempt <= max_attempts )); do
    # Execute the passed command (e.g., gh api ...)
    if "$@"; then
      return 0
    fi
    exit_code=$?
    
    # Fast-fail for known permanent errors to avoid useless delays
    if [[ -f "$tmp_err" ]]; then
      if grep -qiE "archived|not found|bad credentials|requires authentication" "$tmp_err"; then
        return "$exit_code"
      fi
    fi

    if (( attempt == max_attempts )); then
      return "$exit_code"
    fi

    # Output to stderr so it doesn't corrupt stdout variable captures
    echo -e "\033[1;33m⚠\033[0m API transient error (Exit: $exit_code). Retrying in ${backoff}s (Attempt $attempt/$max_attempts)..." >&2
    sleep "$backoff"
    backoff=$(( backoff * 2 ))
    attempt=$(( attempt + 1 ))
  done
}

# --- GitHub API Helpers ---
get_repos() {
  if [[ "$MODE" == "selected" ]]; then
    [[ ${#SELECTED_REPOS[@]} -gt 0 ]] && printf "%s\n" "${SELECTED_REPOS[@]}"
    return
  fi

  local args=(repo list "$OWNER" --limit 10000 --json name)

  if [[ "$VISIBILITY" != "all" ]]; then
    args+=(--visibility "$VISIBILITY")
  fi

  if [[ "$INCLUDE_ARCHIVED" == false ]]; then
    args+=(--no-archived)
  fi

  if [[ "$INCLUDE_FORKS" == false ]]; then
    args+=(--source)
  fi

  gh "${args[@]+"${args[@]}"}" --jq '.[].name'
}