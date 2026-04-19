#!/usr/bin/env bash

gh_mock_sanitize_key() {
  local raw="$1"
  raw="${raw#/}"
  raw="${raw//\//__}"
  raw="${raw//:/_}"
  raw="${raw//\?/_}"
  raw="${raw//&/_}"
  raw="${raw//=/_}"
  printf '%s' "${raw//[^a-zA-Z0-9_.-]/_}"
}

gh_mock_repo_list_file() {
  local owner="$1"
  printf '%s/repo_list__%s.json' "$GH_MOCK_DATA_DIR" "$(gh_mock_sanitize_key "$owner")"
}

gh_mock_api_response_file() {
  local method="$1"
  local path="$2"
  printf '%s/api__%s__%s.json' \
    "$GH_MOCK_DATA_DIR" \
    "$(gh_mock_sanitize_key "$method")" \
    "$(gh_mock_sanitize_key "$path")"
}

gh_mock_log_call() {
  local subcommand="$1"
  local method="$2"
  local path="$3"
  local body="$4"
  shift 4

  local args_json="[]"
  if [[ $# -gt 0 ]]; then
    args_json="$(jq -nc '$ARGS.positional' --args -- "$@")"
  fi

  jq -nc \
    --arg subcommand "$subcommand" \
    --arg method "$method" \
    --arg path "$path" \
    --arg body "$body" \
    --argjson args "$args_json" \
    '{subcommand: $subcommand, method: $method, path: $path, args: $args, body: $body}' >>"$GH_MOCK_LOG"
}

gh_mock_emit_response() {
  local response_file="$1"
  local jq_filter="${2:-}"
  local default_payload="${3:-{}}"
  local payload="$default_payload"

  if [[ -f "$response_file" ]]; then
    payload="$(<"$response_file")"
  elif [[ "$default_payload" == "__MISSING__" ]]; then
    echo "mock gh: no fixture for $response_file" >&2
    return 1
  fi

  if [[ -n "$jq_filter" ]]; then
    printf '%s' "$payload" | jq -r "$jq_filter"
  else
    printf '%s' "$payload"
  fi
}

gh_mock_handle_auth() {
  local body=""
  gh_mock_log_call "auth" "STATUS" "auth/status" "$body" "$@"
  return "${GH_MOCK_AUTH_STATUS:-0}"
}

gh_mock_handle_repo_list() {
  local raw_args=("$@")
  local owner=""
  local jq_filter=""

  if [[ "${1:-}" != "list" ]]; then
    echo "mock gh: unsupported repo subcommand '$1'" >&2
    return 1
  fi

  shift
  owner="${1:-}"
  if [[ -n "$owner" ]]; then
    shift
  fi

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --jq)
        jq_filter="${2:-}"
        shift 2
        ;;
      --limit|--json|--visibility)
        shift 2
        ;;
      --source|--fork)
        shift
        ;;
      --no-archived)
        shift
        ;;
      *)
        shift
        ;;
    esac
  done

  gh_mock_log_call "repo" "LIST" "$owner" "" "${raw_args[@]}"
  gh_mock_emit_response "$(gh_mock_repo_list_file "$owner")" "$jq_filter" "__MISSING__"
}

gh_mock_handle_api() {
  local raw_args=("$@")
  local method="GET"
  local path=""
  local jq_filter=""
  local body=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --method)
        method="${2:-GET}"
        shift 2
        ;;
      --paginate)
        shift
        ;;
      --jq)
        jq_filter="${2:-}"
        shift 2
        ;;
      --input)
        if [[ "${2:-}" == "-" ]]; then
          body="$(cat)"
        elif [[ -n "${2:-}" && -f "${2:-}" ]]; then
          body="$(<"${2:-}")"
        else
          body=""
        fi
        shift 2
        ;;
      -H)
        shift 2
        ;;
      -*)
        shift
        ;;
      *)
        if [[ -z "$path" ]]; then
          path="$1"
        fi
        shift
        ;;
    esac
  done

  if [[ -z "$path" ]]; then
    echo "mock gh: gh api requires a path" >&2
    return 1
  fi

  gh_mock_log_call "api" "$method" "$path" "$body" "${raw_args[@]}"

  if [[ "$method" == "GET" ]]; then
    gh_mock_emit_response "$(gh_mock_api_response_file "$method" "$path")" "$jq_filter" "__MISSING__"
  else
    gh_mock_emit_response "$(gh_mock_api_response_file "$method" "$path")" "$jq_filter" '{}'
  fi
}

mock_gh_main() {
  set -euo pipefail

  : "${GH_MOCK_DATA_DIR:?GH_MOCK_DATA_DIR is required}"
  : "${GH_MOCK_LOG:?GH_MOCK_LOG is required}"

  local command="${1:-}"
  if [[ -z "$command" ]]; then
    echo "mock gh: missing command" >&2
    exit 1
  fi
  shift

  case "$command" in
    auth)
      gh_mock_handle_auth "$@"
      ;;
    repo)
      gh_mock_handle_repo_list "$@"
      ;;
    api)
      gh_mock_handle_api "$@"
      ;;
    *)
      echo "mock gh: unsupported command '$command'" >&2
      exit 1
      ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  mock_gh_main "$@"
fi
