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

setup_state_dir() {
  # Global directory accessible by the importing script and its child jobs
  STATE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/gh_ruleset_state.XXXXXX")"
  trap 'rm -rf "$STATE_DIR"' EXIT
}

# --- GitHub API Helpers ---
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