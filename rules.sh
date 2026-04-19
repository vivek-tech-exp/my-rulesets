#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat <<EOF
my-rulesets - Policy-as-Code for GitHub Rulesets

Usage:
  $0 <command> [options]

Commands:
  sync      Deploy or update policies
  audit     Perform fleet discovery to find out-of-sync policies
  capture   Extract an existing ruleset from a repo into a policy template
  nuke      Delete rulesets from repositories

Run '$0 <command> --help' for command-specific options.
EOF
}

if [[ $# -eq 0 ]]; then
  usage
  exit 1
fi

COMMAND="$1"
shift

case "$COMMAND" in
  sync)
    "$SCRIPT_DIR/internal/setup_github_rules.sh" "$@"
    ;;
  audit)
    "$SCRIPT_DIR/internal/setup_github_rules.sh" --audit "$@"
    ;;
  capture)
    if [[ $# -gt 0 && "$1" != -* ]]; then
      CAPTURE_NAME="$1"
      shift
      "$SCRIPT_DIR/internal/setup_github_rules.sh" --capture-as "$CAPTURE_NAME" "$@"
    else
      echo "Error: 'capture' requires a policy name."
      echo "Example: $0 capture \"My New Policy\" --repo my-repo"
      exit 1
    fi
    ;;
  nuke)
    "$SCRIPT_DIR/internal/delete_github_rules.sh" "$@"
    ;;
  help|-h|--help)
    usage
    exit 0
    ;;
  *)
    echo "Unknown command: $COMMAND"
    usage
    exit 1
    ;;
esac
