#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Usage function
usage() {
    echo "Usage: $0 --input <json-file>"
    echo ""
    echo "Options:"
    echo "  --input    Path to JSON file containing review data (required)"
    echo ""
    echo "JSON Format:"
    echo "{"
    echo "  \"owner\": \"repo-owner\","
    echo "  \"repo\": \"repo-name\","
    echo "  \"pr\": 42,"
    echo "  \"body\": \"Overall review comment (optional)\","
    echo "  \"comments\": ["
    echo "    {"
    echo "      \"path\": \"path/to/file.dart\","
    echo "      \"line\": 123,"
    echo "      \"body\": \"Comment text\""
    echo "    }"
    echo "  ]"
    echo "}"
    echo ""
    echo "Example:"
    echo "  $0 --input /tmp/review.json"
    exit 1
}

# Parse arguments
INPUT_FILE=""
while [[ $# -gt 0 ]]; do
    case $1 in
        --input)
            INPUT_FILE="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo -e "${RED}Error: Unknown option $1${NC}"
            usage
            ;;
    esac
done

# Validate required parameters
if [[ -z "$INPUT_FILE" ]]; then
    echo -e "${RED}Error: --input is required${NC}"
    usage
fi

if [[ ! -f "$INPUT_FILE" ]]; then
    echo -e "${RED}Error: Input file not found: $INPUT_FILE${NC}"
    exit 1
fi

# Validate that jq is installed
if ! command -v jq &> /dev/null; then
    echo -e "${RED}Error: jq is not installed. Please install it from https://jqlang.github.io/jq/${NC}"
    exit 1
fi

# Validate that gh CLI is installed
if ! command -v gh &> /dev/null; then
    echo -e "${RED}Error: gh CLI is not installed. Please install it from https://cli.github.com/${NC}"
    exit 1
fi

# Check gh authentication
if ! gh auth status &> /dev/null; then
    echo -e "${RED}Error: gh CLI is not authenticated. Please run 'gh auth login'${NC}"
    exit 1
fi

# Validate JSON format
if ! jq empty "$INPUT_FILE" 2>/dev/null; then
    echo -e "${RED}Error: Invalid JSON format in input file${NC}"
    exit 1
fi

# Extract values from JSON
OWNER=$(jq -r '.owner // empty' "$INPUT_FILE")
REPO=$(jq -r '.repo // empty' "$INPUT_FILE")
PR=$(jq -r '.pr // empty' "$INPUT_FILE")
BODY=$(jq -r '.body // ""' "$INPUT_FILE")
COMMENT_COUNT=$(jq '.comments | length' "$INPUT_FILE")

# Validate required fields
if [[ -z "$OWNER" ]] || [[ -z "$REPO" ]] || [[ -z "$PR" ]]; then
    echo -e "${RED}Error: JSON must contain 'owner', 'repo', and 'pr' fields${NC}"
    exit 1
fi

if [[ "$COMMENT_COUNT" -eq 0 ]]; then
    echo -e "${RED}Error: JSON must contain at least one comment in 'comments' array${NC}"
    exit 1
fi

echo -e "${GREEN}Preparing to submit review for PR #${PR} in ${OWNER}/${REPO}${NC}"
echo -e "Number of comments: ${COMMENT_COUNT}"
echo ""

# Get list of changed files in PR for validation
echo -e "${GREEN}Fetching PR diff...${NC}"
CHANGED_FILES=$(gh pr diff "$PR" --name-only 2>/dev/null || echo "")

# Validate and prepare comments
VALID_COMMENTS="[]"
SKIPPED=0

for i in $(seq 0 $((COMMENT_COUNT - 1))); do
    PATH_VALUE=$(jq -r ".comments[$i].path" "$INPUT_FILE")
    LINE_VALUE=$(jq -r ".comments[$i].line" "$INPUT_FILE")
    BODY_VALUE=$(jq -r ".comments[$i].body" "$INPUT_FILE")

    # Validate required fields
    if [[ -z "$PATH_VALUE" ]] || [[ -z "$LINE_VALUE" ]] || [[ -z "$BODY_VALUE" ]]; then
        echo -e "${YELLOW}Warning: Skipping comment #$((i+1)) - missing required fields${NC}"
        ((SKIPPED++))
        continue
    fi

    # Validate line number is numeric
    if ! [[ "$LINE_VALUE" =~ ^[0-9]+$ ]]; then
        echo -e "${YELLOW}Warning: Skipping comment #$((i+1)) - line number must be numeric: $LINE_VALUE${NC}"
        ((SKIPPED++))
        continue
    fi

    # Validate that file was modified in PR
    if [[ -n "$CHANGED_FILES" ]] && ! echo "$CHANGED_FILES" | grep -qxF "$PATH_VALUE"; then
        echo -e "${YELLOW}Warning: Skipping comment #$((i+1)) - file not modified in PR: $PATH_VALUE${NC}"
        ((SKIPPED++))
        continue
    fi

    # Add comment to valid array with 'side' parameter
    VALID_COMMENTS=$(echo "$VALID_COMMENTS" | jq \
        --arg path "$PATH_VALUE" \
        --argjson line "$LINE_VALUE" \
        --arg body "$BODY_VALUE" \
        '. + [{"path": $path, "line": $line, "side": "RIGHT", "body": $body}]')

    echo -e "${GREEN}✓${NC} Comment #$((i+1)): ${PATH_VALUE}:${LINE_VALUE}"
done

# Check if we have any valid comments
VALID_COUNT=$(echo "$VALID_COMMENTS" | jq 'length')
if [[ "$VALID_COUNT" -eq 0 ]]; then
    echo -e "${RED}Error: No valid comments to submit (skipped: $SKIPPED)${NC}"
    exit 1
fi

if [[ "$SKIPPED" -gt 0 ]]; then
    echo -e "${YELLOW}Skipped $SKIPPED invalid comment(s)${NC}"
fi

echo ""

# Build final JSON payload
if [[ -n "$BODY" ]]; then
    PAYLOAD=$(jq -n \
        --arg body "$BODY" \
        --argjson comments "$VALID_COMMENTS" \
        '{event: "COMMENT", body: $body, comments: $comments}')
else
    PAYLOAD=$(jq -n \
        --argjson comments "$VALID_COMMENTS" \
        '{event: "COMMENT", comments: $comments}')
fi

echo -e "${GREEN}Submitting review...${NC}"

# Submit review using gh api
RESPONSE=$(gh api \
    --method POST \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "/repos/${OWNER}/${REPO}/pulls/${PR}/reviews" \
    --input - <<< "$PAYLOAD" 2>&1)

if [[ $? -eq 0 ]]; then
    echo -e "${GREEN}✓ Review submitted successfully!${NC}"
    echo -e "${GREEN}  Valid comments: ${VALID_COUNT}${NC}"

    # Extract and display review URL if available
    REVIEW_URL=$(echo "$RESPONSE" | jq -r '.html_url // empty' 2>/dev/null || echo "")
    if [[ -n "$REVIEW_URL" ]]; then
        echo -e "${GREEN}  Review URL: ${REVIEW_URL}${NC}"
    fi
else
    echo -e "${RED}✗ Failed to submit review${NC}"
    echo -e "${RED}Response: ${RESPONSE}${NC}"
    exit 1
fi
