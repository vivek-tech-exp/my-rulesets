#!/bin/bash
set -e

OWNER="vivek-tech-exp"

echo "Fetching public repositories for $OWNER..."
# Dynamically fetch all public repo names as an array
REPOS=($(gh repo list "$OWNER" --public --limit 100 --json name --jq '.[].name'))

echo "Found ${#REPOS[@]} public repositories."

RULESET_PAYLOAD=$(cat <<EOF
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
EOF
)

echo "Starting ruleset setup..."

for REPO in "${REPOS[@]}"; do
  echo "----------------------------------------"
  echo "Applying ruleset to: $REPO"
  
  # || true ensures the script doesn't completely crash if one repo fails (e.g. if you lack permissions on one)
  gh api \
    --method POST \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    /repos/$OWNER/$REPO/rulesets \
    --input - <<< "$RULESET_PAYLOAD" || echo "⚠️ Failed to update $REPO, skipping..."
    
  echo "✅ Successfully protected master/main on $REPO"
done

echo "🎉 All done!"