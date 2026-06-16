---
name: pr-comment-reply
description: Reply to specific inline review comments on GitHub Pull Requests. This skill should be used when asked to reply to a PR comment, respond to review feedback, or post a follow-up message on a specific comment thread using its comment ID.
---

# PR Comment Reply

## Overview

Post replies to specific inline review comments on GitHub Pull Requests using comment IDs. Enables targeted responses to code review feedback without requiring manual GitHub API calls or complex gh command construction.

## When to Use

Use this skill when:

- Asked to reply to a specific PR review comment by its ID
- Need to respond to inline code review feedback
- Want to post follow-up messages in a comment thread
- User provides a comment ID and asks for a reply to be posted

Example user requests:

- "Reply to PR comment ID 12345 with [message]"
- "この PR のコメント ID 67890 に返信して"
- "Post a response to comment 11111 saying the issue is fixed"

## How to Reply to a Comment

### Step 1: Gather Required Information

Collect the following information:

- **owner**: Repository owner (username or organization)
- **repo**: Repository name
- **comment_id**: The ID of the PR review comment to reply to
- **body**: The reply message text

If any information is missing, ask the user or determine it from context (e.g., current repository for owner/repo).

### Step 2: Execute the Script

Run the bundled shell script with the gathered information:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/pr-comment-reply/scripts/reply_to_pr_comment.sh <owner> <repo> <comment_id> "<body>"
```

**Example:**

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/pr-comment-reply/scripts/reply_to_pr_comment.sh KojoBarbie tomarigi 2458874183 "Fixed this issue in commit abc123"
```

### Step 3: Verify Success

The script will:

- Validate that GitHub CLI (gh) is installed
- Post the reply using GitHub API
- Output the URL of the posted reply
- Display a success or error message

If successful, confirm to the user that the reply was posted and provide the comment URL if available.

## Script Details

The `scripts/reply_to_pr_comment.sh` script:

- Uses GitHub CLI (`gh api`) to interact with the GitHub API
- Requires GitHub CLI to be installed and authenticated
- Posts replies to the `/repos/{owner}/{repo}/pulls/comments/{comment_id}/replies` endpoint
- Returns the HTML URL of the posted reply
- Includes error handling for common issues

## Troubleshooting

**GitHub CLI not found:**

- Ensure `gh` is installed: https://cli.github.com/
- Verify authentication: `gh auth status`

**Permission denied:**

- Ensure the authenticated user has write access to the repository
- Check that the PR is in the specified repository

**Comment not found:**

- Verify the comment ID is correct
- Ensure the comment ID belongs to a PR review comment (not an issue comment)
