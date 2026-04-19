#!/usr/bin/env bats

load ./test_helper.bash

policy_name() {
  jq -r '.name' "$REPO_ROOT/policies/org/moderate.json"
}

managed_live_ruleset() {
  jq -c '
    . + {
      id: 101,
      node_id: "RRS_managed",
      repository_id: 123,
      created_at: "2024-01-01T00:00:00Z",
      updated_at: "2024-06-01T00:00:00Z",
      rules: (.rules | map(. + {id: ((.type | explode | add) // 0)}))
    }
  ' "$REPO_ROOT/policies/org/moderate.json"
}

custom_live_ruleset() {
  jq -nc '
    {
      id: 202,
      name: "Custom Guard",
      target: "branch",
      enforcement: "active",
      conditions: {
        ref_name: {
          include: ["main"],
          exclude: []
        }
      },
      bypass_actors: [],
      rules: [
        {
          type: "required_linear_history"
        }
      ]
    }
  '
}

sample_policy_json() {
  jq -nc '
    {
      name: "Protect main",
      target: "branch",
      enforcement: "active",
      conditions: {
        ref_name: {
          include: ["~DEFAULT_BRANCH"],
          exclude: []
        }
      },
      bypass_actors: [],
      rules: [
        {
          type: "deletion"
        },
        {
          type: "non_fast_forward"
        }
      ]
    }
  '
}

sample_live_equal_json() {
  jq -nc '
    {
      id: 101,
      node_id: "RRS_equal",
      repository_id: 77,
      created_at: "2024-02-01T00:00:00Z",
      updated_at: "2024-02-02T00:00:00Z",
      name: "Protect main",
      target: "branch",
      enforcement: "active",
      current_user_can_bypass: "never",
      conditions: {
        ref_name: {
          include: ["~DEFAULT_BRANCH"],
          exclude: []
        }
      },
      bypass_actors: [],
      rules: [
        {
          id: 501,
          type: "non_fast_forward"
        },
        {
          id: 502,
          type: "deletion"
        }
      ]
    }
  '
}

sample_live_old_json() {
  jq -nc '
    {
      id: 101,
      node_id: "RRS_old",
      repository_id: 77,
      created_at: "2024-02-01T00:00:00Z",
      updated_at: "2024-02-02T00:00:00Z",
      name: "Protect main",
      target: "branch",
      enforcement: "evaluate",
      conditions: {
        ref_name: {
          include: ["~DEFAULT_BRANCH"],
          exclude: []
        }
      },
      bypass_actors: [],
      rules: [
        {
          id: 700,
          type: "deletion"
        }
      ]
    }
  '
}

@test "audit marks repos as matched with extras when managed and unmanaged rulesets coexist" {
  local policy
  local policy_title
  local ruleset_list

  policy="$(managed_live_ruleset)"
  policy_title="$(policy_name)"
  ruleset_list="$(jq -nc --arg policy_name "$policy_title" '[{id: 101, name: $policy_name}, {id: 202, name: "Custom Guard"}]')"

  mock_owner_type "acme" "Organization"
  mock_rate_limit_ok
  mock_repo_list "acme" "demo"
  mock_api_response GET "/repos/acme/demo/rulesets" "$ruleset_list"
  mock_api_response GET "/repos/acme/demo/rulesets/101" "$policy"
  mock_api_response GET "/repos/acme/demo/rulesets/202" "$(custom_live_ruleset)"

  run_ruleset_sync audit --owner acme --repo demo --yes

  assert_success
  assert_output --partial "MATCHED WITH EXTRAS"
  assert_equal "$(read_state_entries acme audit_github_rules matched_with_extras)" "demo|$policy_title (Managed: 1, Unmanaged: 1)"
}

@test "sync exits with failure on name collisions and does not dispatch PUT requests" {
  local policy_file
  local policy_json

  policy_json="$(sample_policy_json)"
  policy_file="$(write_policy_file "collision-policy" "$policy_json")"

  mock_owner_type "acme" "Organization"
  mock_rate_limit_ok
  mock_repo_list "acme" "demo"
  mock_api_response GET "/repos/acme/demo/rulesets" '[{"id":11,"name":"Protect main"},{"id":22,"name":"Protect main"}]'

  run_ruleset_sync sync --config "$policy_file" --owner acme --repo demo --yes

  assert_failure 1
  assert_output --partial "Multiple rulesets found with name 'Protect main'"
  assert_api_method_count PUT 0
  assert_equal "$(read_state_entries acme setup_github_rules failed)" "demo|name collision"
}

@test "sync stays idempotent when desired and live rulesets are canonically equal" {
  local policy_file
  local policy_json

  policy_json="$(sample_policy_json)"
  policy_file="$(write_policy_file "idempotent-policy" "$policy_json")"

  mock_owner_type "acme" "Organization"
  mock_rate_limit_ok
  mock_repo_list "acme" "demo"
  mock_api_response GET "/repos/acme/demo/rulesets" '[{"id":101,"name":"Protect main"}]'
  mock_api_response GET "/repos/acme/demo/rulesets/101" "$(sample_live_equal_json)"

  run_ruleset_sync sync --config "$policy_file" --owner acme --repo demo --yes

  assert_success
  assert_output --partial "Already matches desired state"
  assert_api_call_count PUT "/repos/acme/demo/rulesets/101" 0
  assert_equal "$(read_state_entries acme setup_github_rules skipped)" "demo|"
}

@test "sync rollback replays the saved backup through PUT" {
  local policy_file
  local policy_json
  local old_live_json
  local backup_path
  local rollback_body

  policy_json="$(sample_policy_json)"
  old_live_json="$(sample_live_old_json)"
  policy_file="$(write_policy_file "rollback-policy" "$policy_json")"

  mock_owner_type "acme" "Organization"
  mock_rate_limit_ok
  mock_repo_list "acme" "demo"
  mock_api_response GET "/repos/acme/demo/rulesets" '[{"id":101,"name":"Protect main"}]'
  mock_api_response GET "/repos/acme/demo/rulesets/101" "$old_live_json"

  run_ruleset_sync sync --config "$policy_file" --owner acme --repo demo --yes

  assert_success
  assert_api_call_count PUT "/repos/acme/demo/rulesets/101" 1
  backup_path="$(backup_file_for acme setup_github_rules demo "Protect main")"
  assert [ -f "$backup_path" ]
  assert_json_equal "$(<"$backup_path")" "$old_live_json"
  assert_equal "$(read_state_entries acme setup_github_rules updated)" "demo|Protect main"

  reset_mock_calls

  run_ruleset_sync sync --owner acme --yes --rollback

  assert_success
  assert_output --partial "Restored successfully."
  assert_api_call_count PUT "/repos/acme/demo/rulesets/101" 1
  rollback_body="$(last_api_body PUT "/repos/acme/demo/rulesets/101")"
  assert_json_equal "$rollback_body" "$old_live_json"
}

@test "nuke creates a rollback backup before deleting a ruleset" {
  local live_json
  local backup_path

  live_json="$(sample_live_old_json)"

  mock_owner_type "acme" "Organization"
  mock_rate_limit_ok
  mock_repo_list "acme" "demo"
  mock_api_response GET "/repos/acme/demo/rulesets" '[{"id":901,"name":"Protect main"}]'
  mock_api_response GET "/repos/acme/demo/rulesets/901" "$(printf '%s' "$live_json" | jq '.id = 901')"

  run_ruleset_sync nuke --name "Protect main" --owner acme --repo demo --yes

  assert_success
  backup_path="$(backup_file_for acme delete_github_rules demo "Protect main")"
  assert [ -f "$backup_path" ]
  assert_api_call_count DELETE "/repos/acme/demo/rulesets/901" 1
}
