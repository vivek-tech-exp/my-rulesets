#!/usr/bin/env bash
# common.sh - Shared logic for GitHub ruleset scripts

# --- Default Global Variables ---
OWNER="vivek-tech-exp"
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
}

# --- State Management (Persistent & Isolated) ---
setup_state_dir() {
  local caller_script
  caller_script="$(basename "$0" .sh)"
  
  # Creates isolated, persistent states: .gh_state_setup_github_rules_vivek-tech-exp
  STATE_DIR="${PWD}/.gh_state_${caller_script}_${OWNER}"
  mkdir -p "$STATE_DIR"
  
  # Ensure log files exist so grep doesn't fail later
  touch "$STATE_DIR/created.log" "$STATE_DIR/updated.log" \
        "$STATE_DIR/skipped.log" "$STATE_DIR/failed.log" \
        "$STATE_DIR/deleted.log"
        
  info "State directory: $STATE_DIR"
}

# --- Rate Limit Protection (Graceful Exit) ---
check_rate_limit() {
  local rate_data
  if ! rate_data="$(gh api /rate_limit 2>/dev/null)"; then
    return 0 
  fi

  local remaining
  local reset_time
  # Suppress jq errors if JSON is malformed
  remaining="$(echo "$rate_data" | jq -r '.resources.core.remaining' 2>/dev/null || true)"
  reset_time="$(echo "$rate_data" | jq -r '.resources.core.reset' 2>/dev/null || true)"

  # Fail silently and let the main script continue if we didn't get a valid integer back
  if [[ -z "$remaining" || ! "$remaining" =~ ^[0-9]+$ ]]; then
    return 0 
  fi

  if [[ "$remaining" -lt 50 ]]; then
    echo "----------------------------------------"
    warn "PRIMARY API RATE LIMIT EXHAUSTED ($remaining requests left)."
    
    # Calculate human-readable time for macOS/Linux compatibility
    if date --version >/dev/null 2>&1; then
      local reset_str="$(date -d "@$reset_time" '+%I:%M %p')"
    else
      local reset_str="$(date -r "$reset_time" '+%I:%M %p')"
    fi

    warn "GitHub will reset your quota at $reset_str."
    warn "The script has safely saved its state to $STATE_DIR."
    warn "Waiting for running background jobs to finish securely..."
    
    # Wait for the currently active parallel jobs to finish and save state
    wait 
    
    warn "Simply run the exact same command later to resume from where it left off."
    echo "----------------------------------------"
    
    exit 429
  fi
}

# --- GitHub API Helpers ---
get_repos() {
  if [[ "$MODE" == "selected" ]]; then
    printf "%s\n" "${SELECTED_REPOS[@]}"
    return
  fi

  # Upgraded to 10,000 for enterprise scale compatibility
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

  gh "${args[@]}" --jq '.[].name'
}