---
name: pr-review-unresolved
description: Fetch and display unresolved inline review comments from the current branch's pull request using gh command. This skill should be used when asked to check unresolved PR comments, review feedback that needs attention, or list pending review discussions.
---

# PR Review Unresolved

## Overview

Fetch unresolved inline review comments from the current branch's pull request. Display file paths, line numbers, and original comment text to help identify which feedback requires attention.

## When to Use This Skill

Use this skill when encountering requests such as:

- "Show me unresolved PR comments"
- "List pending review feedback"
- "What review comments need to be addressed?"
- "Check for unresolved code review discussions"

## How It Works

Execute the bundled shell script to:

1. Identify the current git branch
2. Find the associated pull request using `gh` CLI
3. Query GitHub's GraphQL API for review threads
4. Filter for unresolved conversations
5. Display file path, line number, and comment body

## Usage

Run the script from the repository root:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/pr-review-unresolved/scripts/get_unresolved_comments.sh
```

The script outputs unresolved comments in the following format:

```
Repository: owner/repo
PR Number: #123
Branch: feature-branch

Fetching unresolved review comments...

📁 src/components/Header.tsx:42
🆔 Comment ID: 1234567890
💬 Consider using useMemo here to avoid unnecessary re-renders

📁 src/utils/helpers.ts:15
🆔 Comment ID: 9876543210
💬 This function should handle edge cases for null values

✅ Completed fetching unresolved comments
```

## Requirements

- Git repository with a remote configured
- GitHub CLI (`gh`) installed and authenticated
- Current branch must have an associated pull request

## Output Format

The output includes:

- **Repository information**: `Repository: owner/repo`
- **PR number**: `PR Number: #123`
- **Branch name**: `Branch: feature-branch`

Each unresolved comment displays:

- **File path and line number**: `📁 path/to/file.ext:line`
- **Comment ID**: `🆔 Comment ID: 1234567890`
- **Comment body**: `💬 [original comment text]`

Only inline review comments are included (PR-level comments are excluded). Resolution status is determined by GitHub's "Resolve conversation" feature.

## Resources

### scripts/get_unresolved_comments.sh

Executable shell script that uses GitHub CLI and GraphQL API to fetch unresolved review threads. The script handles branch detection, PR lookup, and comment filtering automatically.
