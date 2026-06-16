#!/bin/bash

# Script to fetch unresolved review comments from the current branch's PR

set -e

# Get current branch name
CURRENT_BRANCH=$(git branch --show-current)

if [ -z "$CURRENT_BRANCH" ]; then
    echo "Error: Not in a git repository or no current branch found"
    exit 1
fi

# Get repository owner and name
REPO_INFO=$(gh repo view --json owner,name -q '.owner.login + "/" + .name')
OWNER=$(echo "$REPO_INFO" | cut -d'/' -f1)
REPO=$(echo "$REPO_INFO" | cut -d'/' -f2)

# Find PR for current branch
PR_NUMBER=$(gh pr list --head "$CURRENT_BRANCH" --json number --jq '.[0].number')

if [ -z "$PR_NUMBER" ]; then
    echo "Error: No pull request found for branch '$CURRENT_BRANCH'"
    exit 1
fi

echo "Repository: $OWNER/$REPO"
echo "PR Number: #$PR_NUMBER"
echo "Branch: $CURRENT_BRANCH"
echo ""
echo "Fetching unresolved review comments..."
echo ""

# Use GraphQL to get conversations with resolution status and comment IDs
gh api graphql -f query='
query($owner: String!, $repo: String!, $prNumber: Int!) {
  repository(owner: $owner, name: $repo) {
    pullRequest(number: $prNumber) {
      reviewThreads(first: 100) {
        nodes {
          isResolved
          comments(first: 100) {
            nodes {
              id
              databaseId
              path
              line
              body
            }
          }
        }
      }
    }
  }
}' -f owner="$OWNER" -f repo="$REPO" -F prNumber="$PR_NUMBER" \
    --jq '.data.repository.pullRequest.reviewThreads.nodes[] |
    select(.isResolved == false) |
    .comments.nodes[0] |
    "📁 \(.path):\(.line)\n🆔 Comment ID: \(.databaseId)\n💬 \(.body)\n"'

echo ""
echo "✅ Completed fetching unresolved comments"
