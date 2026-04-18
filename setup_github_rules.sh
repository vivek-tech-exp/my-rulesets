#!/bin/bash

OWNER="vivek-tech-exp"
RULESET_NAME="Protect Master"

echo "Fetching public repositories for $OWNER..."
REPOS=($(gh repo list "$OWNER" --visibility=public --limit 100 --json name --jq '.[].name'))
echo "Found ${#REPOS[@]} public repositories."

RULESET_PAYLOAD=$(cat <<EOF
{
  "name": "$RULESET_NAME",
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

# Normalize our desired payload for exact comparison
DESIRED_STATE=$(echo "$RULESET_PAYLOAD" | jq -S '{name, target, enforcement, conditions, rules}')

echo "Starting ruleset setup..."

for REPO in "${REPOS[@]}"; do
  echo "----------------------------------------"
  echo "📦 Processing: $REPO"
  
  # 1. Fetch the full ruleset if it exists
  EXISTING_RULESET=$(gh api /repos/$OWNER/$REPO/rulesets \
    --jq ".[] | select(.name == \"$RULESET_NAME\")" 2> api_error.log)
  GET_STATUS=$?

  if [ $GET_STATUS -ne 0 ]; then
    echo "  ❌ Failed to access repository settings."
    echo "  📄 Reason: $(cat api_error.log)"
    continue
  fi

  if [ -z "$EXISTING_RULESET" ]; then
    # 2. RULESET DOES NOT EXIST -> CREATE
    echo "  -> Ruleset not found. Creating a new one..."
    if gh api --method POST -H "Accept: application/vnd.github+json" -H "X-GitHub-Api-Version: 2022-11-28" \
      /repos/$OWNER/$REPO/rulesets --input - <<< "$RULESET_PAYLOAD" > /dev/null 2> api_error.log; then
      echo "  ✅ Successfully created ruleset!"
    else
      echo "  ❌ Failed to create ruleset."
      echo "  📄 Reason: $(cat api_error.log)"
    fi

  else
    # 3. RULESET EXISTS -> COMPARE STATE
    RULESET_ID=$(echo "$EXISTING_RULESET" | jq '.id')
    
    # Fetch the exact ruleset details (the list endpoint doesn't always return full rule params)
    FULL_EXISTING=$(gh api /repos/$OWNER/$REPO/rulesets/$RULESET_ID 2> /dev/null)
    
    # Extract only the fields we care about and sort them for comparison
    CURRENT_STATE=$(echo "$FULL_EXISTING" | jq -S '{name, target, enforcement, conditions, rules}')

    if [ "$CURRENT_STATE" == "$DESIRED_STATE" ]; then
      echo "  ✅ Ruleset already exists and matches desired state. Skipping."
    else
      echo "  -> Ruleset exists but differs. Updating to latest configuration..."
      if gh api --method PUT -H "Accept: application/vnd.github+json" -H "X-GitHub-Api-Version: 2022-11-28" \
        /repos/$OWNER/$REPO/rulesets/$RULESET_ID --input - <<< "$RULESET_PAYLOAD" > /dev/null 2> api_error.log; then
        echo "  ✅ Successfully updated ruleset!"
      else
        echo "  ❌ Failed to update ruleset."
        echo "  📄 Reason: $(cat api_error.log)"
      fi
    fi
  fi

done

rm -f api_error.log
echo "----------------------------------------"
echo "🎉 All done!"