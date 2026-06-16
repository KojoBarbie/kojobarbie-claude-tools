---
name: pr-batch-review
description: Submit multiple inline code review comments as a single GitHub PR review to reduce notification noise and improve readability. This skill should be used when reviewing pull requests and wanting to add multiple inline comments at once, particularly in GitHub Actions workflows.
---

# PR Batch Review

## Overview

Submit multiple inline code review comments as a single GitHub PR review instead of posting them one by one. This reduces notification spam and improves the review experience by grouping related comments together.

## When to Use

Use this skill when:

- Reviewing a pull request with multiple feedback points
- Working in GitHub Actions workflows (e.g., `.github/workflows/claude-code-review.yml`)
- Wanting to minimize notification noise for PR authors
- Needing to group related review comments together

Trigger phrases:

- "Review this PR and add multiple inline comments together"
- "Review this PR with batched comments"
- "Add review comments in a single batch"

## Workflow

### 1. Create Review JSON

Create a JSON file containing all review information using the **Write tool**.

**Recommended file location:** `log/review_<pr-number>.json`

**JSON Format:**

```json
{
  "owner": "repo-owner",
  "repo": "repo-name",
  "pr": 42,
  "body": "Overall review comment (optional)",
  "comments": [
    {
      "path": "path/to/file.dart",
      "line": 123,
      "body": "Comment text"
    },
    {
      "path": "another/file.dart",
      "line": 45,
      "body": "Another comment"
    }
  ]
}
```

**Field Descriptions:**

- `owner` (required): Repository owner (organization or user)
- `repo` (required): Repository name
- `pr` (required): Pull request number
- `body` (optional): Overall review summary comment
- `comments` (required): Array of inline comments
  - `path` (required): Relative path from repository root
  - `line` (required): Line number in the new version of the file
  - `body` (required): The review comment text

### 2. Submit Batched Review

Use the bundled `submit_batch_review.sh` script with the JSON file (call it via the plugin root):

```bash
${CLAUDE_PLUGIN_ROOT}/skills/pr-batch-review/scripts/submit_batch_review.sh --input log/review_42.json
```

**Example workflow:**

1. **Create the review JSON using Write tool:**

```json
{
  "owner": "myorg",
  "repo": "myrepo",
  "pr": 42,
  "body": "Found a few issues that need attention",
  "comments": [
    {
      "path": "lib/main.dart",
      "line": 15,
      "body": "Consider using const here for better performance"
    },
    {
      "path": "lib/utils.dart",
      "line": 23,
      "body": "This function could be simplified"
    },
    {
      "path": "test/widget_test.dart",
      "line": 45,
      "body": "Missing test case for error handling"
    }
  ]
}
```

Save this to `log/review_42.json` using the Write tool.

2. **Submit the review using Bash tool:**

```bash
${CLAUDE_PLUGIN_ROOT}/skills/pr-batch-review/scripts/submit_batch_review.sh --input log/review_42.json
```

## Important Notes

### Line Numbers

- Use **line numbers from the new version** of the file (after changes)
- The script automatically adds the `side: "RIGHT"` parameter for GitHub API
- All comments must be on lines that were modified in the PR
- Comments on unchanged lines will be skipped with a warning

### Validation

The script performs the following validations:

- JSON format correctness
- Required fields presence (`owner`, `repo`, `pr`, and comment fields)
- Line numbers are numeric
- Files were actually modified in the PR (fetches PR diff for validation)
- Skips invalid comments and reports them

### Comment Limitations

- All comments must be on lines that were modified in the PR
- Maximum of 100 comments per review (GitHub API limit)
- Comments on unchanged lines will be automatically skipped

### Error Handling

The script will:

- Validate JSON format before processing
- Validate all required fields
- Skip invalid comments with warnings
- Report the number of valid vs skipped comments
- Return success only if at least one comment was submitted

## Resources

### scripts/submit_batch_review.sh

Shell script that uses `gh` CLI to submit multiple inline comments as a single GitHub PR review. This script:

- Accepts a JSON file path as input (via `--input` parameter)
- Validates JSON format and required fields
- Fetches PR diff to validate that files were modified
- Filters out invalid comments (missing fields, non-numeric lines, unchanged files)
- Adds `side: "RIGHT"` parameter for GitHub API compatibility
- Constructs the GitHub API request using `jq`
- Submits all valid comments in a single review
- Reports success/failure with detailed output

**Requirements:**

- `gh` CLI installed and authenticated
- `jq` installed for JSON processing

**Exit codes:**

- `0`: Review submitted successfully
- `1`: Error occurred (invalid input, no valid comments, API failure)
