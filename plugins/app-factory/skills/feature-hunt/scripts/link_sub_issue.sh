#!/usr/bin/env bash
#
# link_sub_issue.sh — 子 Issue を親 Issue の GitHub ネイティブ sub-issue として紐づける。
#
# 使い方:
#   bash link_sub_issue.sh <親Issue番号> <子Issue番号>
#
# リポジトリは `gh repo view` から自動取得するので、どの git リポジトリ内でも動く
# （特定リポジトリへのハードコードはしていない）。
#
# 失敗時（sub_issues API 未対応など）は非ゼロで終了するので、
# 呼び出し側は親本文のタスクリスト（- [ ] #子番号）で代替すること。

set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "usage: link_sub_issue.sh <parent_issue_number> <child_issue_number>" >&2
  exit 2
fi

parent="$1"
child="$2"

# owner/repo を動的に取得
owner_repo=$(gh repo view --json owner,name --jq '"\(.owner.login)/\(.name)"')

# 子 Issue の database id（数値）を取得。sub_issues API は Issue 番号ではなく
# この database id を要求する点に注意。
child_id=$(gh api "repos/${owner_repo}/issues/${child}" --jq '.id')

if [[ -z "${child_id}" || "${child_id}" == "null" ]]; then
  echo "error: could not resolve database id for issue #${child}" >&2
  exit 1
fi

# 親に sub-issue として紐づける
gh api \
  -X POST \
  -H "Accept: application/vnd.github+json" \
  "repos/${owner_repo}/issues/${parent}/sub_issues" \
  -F sub_issue_id="${child_id}" \
  >/dev/null

echo "linked: #${child} -> parent #${parent} (${owner_repo})"
