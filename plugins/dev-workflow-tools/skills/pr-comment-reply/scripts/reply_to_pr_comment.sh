#!/bin/bash
# Reply to a PR inline comment using GitHub CLI

set -e

# Check if gh is installed
if ! command -v gh &> /dev/null; then
    echo "Error: GitHub CLI (gh) is not installed."
    echo "Install it from https://cli.github.com/"
    exit 1
fi

# Parse arguments
if [ "$#" -ne 5 ]; then
    echo "Usage: $0 <owner> <repo> <pr_number> <comment_id> <body>"
    echo ""
    echo "Arguments:"
    echo "  owner       - Repository owner (user or organization)"
    echo "  repo        - Repository name"
    echo "  pr_number   - Pull request number"
    echo "  comment_id  - ID of the PR review comment to reply to"
    echo "  body        - Reply message text"
    echo ""
    echo "Example:"
    echo "  $0 octocat my-repo 42 123456789 'Fixed this issue!'"
    exit 1
fi

OWNER="$1"
REPO="$2"
PR_NUMBER="$3"
COMMENT_ID="$4"
BODY="$5"

# Create the reply using GitHub API
echo "Replying to comment ID ${COMMENT_ID} in ${OWNER}/${REPO} PR #${PR_NUMBER}..."

RESPONSE=$(gh api \
    --method POST \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "/repos/${OWNER}/${REPO}/pulls/${PR_NUMBER}/comments/${COMMENT_ID}/replies" \
    -f body="${BODY}")

if [ $? -eq 0 ]; then
    HTML_URL=$(echo "$RESPONSE" | jq -r '.html_url')
    echo "✅ Reply posted successfully!"
    echo "URL: ${HTML_URL}"
else
    echo "❌ Failed to post reply"
    exit 1
fi