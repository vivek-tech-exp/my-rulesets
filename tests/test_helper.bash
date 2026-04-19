#!/usr/bin/env bash

load_bats_library_path() {
  local library="$1"
  local bats_lib_path="${BATS_LIB_PATH:-}"
  local candidate=""
  local entry=""

  IFS=':' read -r -a paths <<<"$bats_lib_path"
  for entry in "${paths[@]}"; do
    if [[ -f "$entry/$library/load.bash" ]]; then
      candidate="$entry/$library/load.bash"
      break
    fi
    if [[ -f "$entry/$library/load" ]]; then
      candidate="$entry/$library/load"
      break
    fi
  done

  if [[ -z "$candidate" ]]; then
    echo "Unable to locate $library via BATS_LIB_PATH=$bats_lib_path" >&2
    return 1
  fi

  load "$candidate"
}

load_bats_library_path bats-support
load_bats_library_path bats-assert

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_HELPER_ORIGINAL_PATH="$PATH"

# shellcheck source=tests/mock_gh.bash
source "$REPO_ROOT/tests/mock_gh.bash"

setup() {
  TEST_TMPDIR="$(mktemp -d "${TMPDIR:-/tmp}/gh-ruleset-sync-tests.XXXXXX")"
  export TEST_TMPDIR
  export HOME="$TEST_TMPDIR/home"
  export XDG_CONFIG_HOME="$HOME/.config"
  export GH_MOCK_DATA_DIR="$TEST_TMPDIR/mock-data"
  export GH_MOCK_LOG="$TEST_TMPDIR/gh-calls.jsonl"
  export GH_MOCK_AUTH_STATUS=0
  export PATH="$TEST_TMPDIR/bin:$TEST_HELPER_ORIGINAL_PATH"

  mkdir -p "$HOME" "$XDG_CONFIG_HOME" "$GH_MOCK_DATA_DIR" "$TEST_TMPDIR/bin"
  : >"$GH_MOCK_LOG"

  printf '#!/usr/bin/env bash\nexec bash %q "$@"\n' "$REPO_ROOT/tests/mock_gh.bash" >"$TEST_TMPDIR/bin/gh"
  chmod +x "$TEST_TMPDIR/bin/gh"

  mock_user_login "mock-user"
  mock_user_orgs_json '[]'
}

teardown() {
  rm -rf "$TEST_TMPDIR"
}

write_json_file() {
  local path="$1"
  local json="$2"

  mkdir -p "$(dirname "$path")"
  printf '%s\n' "$json" >"$path"
}

mock_api_response() {
  local method="$1"
  local path="$2"
  local json="$3"

  write_json_file "$(gh_mock_api_response_file "$method" "$path")" "$json"
}

mock_repo_list_json() {
  local owner="$1"
  local json="$2"

  write_json_file "$(gh_mock_repo_list_file "$owner")" "$json"
}

mock_repo_list() {
  local owner="$1"
  shift

  local payload="[]"
  if [[ $# -gt 0 ]]; then
    payload="$(jq -nc '$ARGS.positional | map({name: .})' --args -- "$@")"
  fi

  mock_repo_list_json "$owner" "$payload"
}

mock_user_login() {
  local login="$1"
  mock_api_response GET "user" "$(jq -nc --arg login "$login" '{login: $login}')"
}

mock_user_orgs_json() {
  local json="$1"
  mock_api_response GET "user/orgs" "$json"
}

mock_owner_type() {
  local owner="$1"
  local owner_type="$2"
  mock_api_response GET "users/$owner" "$(jq -nc --arg type "$owner_type" '{type: $type}')"
}

mock_rate_limit_ok() {
  mock_api_response GET "/rate_limit" '{"resources":{"core":{"remaining":5000,"reset":4102444800}}}'
}

mock_auth_failure() {
  export GH_MOCK_AUTH_STATUS=1
}

reset_mock_calls() {
  : >"$GH_MOCK_LOG"
}

run_ruleset_sync() {
  run "$REPO_ROOT/gh-ruleset-sync" "$@"
}

write_policy_file() {
  local name="$1"
  local json="$2"
  local path="$TEST_TMPDIR/${name}.json"

  write_json_file "$path" "$json"
  printf '%s' "$path"
}

state_dir_for() {
  local owner="$1"
  local script_name="$2"
  printf '%s/gh-ruleset-sync/state/%s/%s' "$XDG_CONFIG_HOME" "$owner" "$script_name"
}

state_file_for() {
  local owner="$1"
  local script_name="$2"
  local log_name="$3"
  printf '%s/%s.log' "$(state_dir_for "$owner" "$script_name")" "$log_name"
}

backup_file_for() {
  local owner="$1"
  local script_name="$2"
  local repo="$3"
  local ruleset_name="$4"
  local safe_repo="${repo//\//_}"
  local safe_ruleset="${ruleset_name//\//_}"

  printf '%s/backups/%s__%s.json' "$(state_dir_for "$owner" "$script_name")" "$safe_repo" "$safe_ruleset"
}

read_state_entries() {
  local owner="$1"
  local script_name="$2"
  local log_name="$3"
  local path

  path="$(state_file_for "$owner" "$script_name" "$log_name")"
  if [[ -f "$path" ]]; then
    sed 's/^|//' "$path"
  fi
}

strip_ansi() {
  printf '%s' "$1" | sed -E $'s/\x1B\\[[0-9;]*[[:alpha:]]//g'
}

sha256_stream() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 | awk '{print $1}'
  else
    sha256sum | awk '{print $1}'
  fi
}

canonical_hash() {
  local json="$1"
  printf '%s' "$json" | canonicalize_ruleset | jq -c . | sha256_stream
}

gh_api_call_count() {
  local method="$1"
  local path="$2"

  if [[ ! -s "$GH_MOCK_LOG" ]]; then
    printf '0'
    return
  fi

  jq -s \
    --arg method "$method" \
    --arg path "$path" \
    '[.[] | select(.subcommand == "api" and .method == $method and .path == $path)] | length' \
    "$GH_MOCK_LOG"
}

gh_api_method_count() {
  local method="$1"

  if [[ ! -s "$GH_MOCK_LOG" ]]; then
    printf '0'
    return
  fi

  jq -s \
    --arg method "$method" \
    '[.[] | select(.subcommand == "api" and .method == $method)] | length' \
    "$GH_MOCK_LOG"
}

assert_api_call_count() {
  local method="$1"
  local path="$2"
  local expected="$3"
  local actual

  actual="$(gh_api_call_count "$method" "$path")"
  assert_equal "$actual" "$expected"
}

assert_api_method_count() {
  local method="$1"
  local expected="$2"
  local actual

  actual="$(gh_api_method_count "$method")"
  assert_equal "$actual" "$expected"
}

last_api_body() {
  local method="$1"
  local path="$2"

  if [[ ! -s "$GH_MOCK_LOG" ]]; then
    printf ''
    return
  fi

  jq -sr \
    --arg method "$method" \
    --arg path "$path" \
    'map(select(.subcommand == "api" and .method == $method and .path == $path)) | last | .body // ""' \
    "$GH_MOCK_LOG"
}

assert_json_equal() {
  local actual_json="$1"
  local expected_json="$2"
  local actual_normalized
  local expected_normalized

  actual_normalized="$(printf '%s' "$actual_json" | jq -S .)"
  expected_normalized="$(printf '%s' "$expected_json" | jq -S .)"
  assert_equal "$actual_normalized" "$expected_normalized"
}
