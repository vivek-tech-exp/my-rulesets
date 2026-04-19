#!/usr/bin/env bats

load ./test_helper.bash

source "$REPO_ROOT/gh-ruleset-sync"
source "$REPO_ROOT/internal/setup_github_rules.sh"

@test "sanitize_capture_name strips traversal and invalid characters" {
  assert_equal "$(sanitize_capture_name "../My Bad Policy!!")" "MyBadPolicy"
  assert_equal "$(sanitize_capture_name "release_policy-01")" "release_policy-01"
}

@test "canonicalize_ruleset produces different hashes for materially different rulesets" {
  local ruleset_a
  local ruleset_b
  local hash_a
  local hash_b

  ruleset_a='{"name":"Protect main","target":"branch","enforcement":"active","conditions":{"ref_name":{"include":["~DEFAULT_BRANCH"],"exclude":[]}},"bypass_actors":[],"rules":[{"type":"deletion"},{"type":"non_fast_forward"}]}'
  ruleset_b='{"name":"Protect main","target":"branch","enforcement":"disabled","conditions":{"ref_name":{"include":["~DEFAULT_BRANCH"],"exclude":[]}},"bypass_actors":[],"rules":[{"type":"deletion"}]}'

  hash_a="$(canonical_hash "$ruleset_a")"
  hash_b="$(canonical_hash "$ruleset_b")"
  assert [ "$hash_a" != "$hash_b" ]
}

@test "canonicalize_ruleset ignores metadata-only differences and ordering" {
  local policy_json
  local live_json

  policy_json='{"name":"Protect main","target":"branch","enforcement":"active","conditions":{"ref_name":{"include":["develop","main"],"exclude":["legacy"]}},"bypass_actors":[{"actor_id":2,"actor_type":"RepositoryRole"},{"actor_id":1,"actor_type":"OrganizationAdmin"}],"rules":[{"type":"non_fast_forward"},{"type":"deletion"}]}'
  live_json='{"id":9001,"node_id":"RRS_123","repository_id":77,"created_at":"2024-01-01T00:00:00Z","updated_at":"2024-06-01T00:00:00Z","name":"Protect main","target":"branch","enforcement":"active","conditions":{"ref_name":{"include":["main","develop"],"exclude":["legacy"]}},"current_user_can_bypass":"always","bypass_actors":[{"id":44,"actor_id":1,"actor_type":"OrganizationAdmin"},{"id":55,"actor_id":2,"actor_type":"RepositoryRole"}],"rules":[{"id":222,"type":"deletion"},{"id":333,"type":"non_fast_forward"}]}'

  assert_equal "$(canonical_hash "$policy_json")" "$(canonical_hash "$live_json")"
}

@test "check_auth fails in non-interactive mode when owner is missing and multiple orgs exist" {
  mock_user_login "mock-user"
  mock_user_orgs_json '[{"login":"acme"},{"login":"platform"}]'

  run env REPO_ROOT="$REPO_ROOT" bash -c '
    source "$REPO_ROOT/internal/common.sh"
    OWNER=""
    YES=false
    QUIET=false
    check_auth
  '

  assert_failure 1
  assert_output --partial "must specify the target account using --owner"
}

@test "future strict CI auth requirement is documented but not enforced yet" {
  skip "Future strictness: require --owner for all non-interactive runs."
}
