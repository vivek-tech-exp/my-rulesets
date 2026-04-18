#!/bin/bash
set -e

OWNER="vivek-tech-exp"
REPOS=("borderless-buy" "my-fi" "commshub" "vivek-tech-resume")

RULESET_PAYLOAD=$(cat <<INNER_EOF
{
  "name": "Protect Master",
  "target": "branch",
  "enforcement": "active",
  "conditions": {
    "ref_name": {
      "include": [
        "refs/heads/master",
        "refs/heads/main"
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
INNER_EOF
)

echo "Starting ruleset setup for $OWNER..."

for REPO in "${REPOS[@]}"; do
  echo "----------------------------------------"
  echo "Applying ruleset to: $REPO"
  
  gh api \
    --method POST \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    /repos/$OWNER/$REPO/rulesets \
    --input - <<< "$RULESET_PAYLOAD"
    
  echo "✅ Successfully protected master/main on $REPO"
done

echo "🎉 All done!"
