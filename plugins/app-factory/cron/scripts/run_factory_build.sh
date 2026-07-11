#!/bin/bash
# App Factory: factory-build — 毎日 5:00 / 23:00
# ポートフォリオ全体から着手可能な issue を選び、自律実装 → PR → 条件付き auto-merge
# launchd (com.claude.factory-build) から呼び出される
# bash 事前判定: 対象ステージのアプリが1つも無ければ claude を起動しない

set -euo pipefail

PROJECT_DIR="$HOME/dev/others/claude-cron"
APPS_FILE="$PROJECT_DIR/data/factory_apps.tsv"
LOG_FILE="$PROJECT_DIR/logs/factory_build.log"
CLAUDE="$HOME/.nodebrew/current/bin/claude"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"; }

set -a
source "$PROJECT_DIR/.env"
set +a

log "=== Starting factory build ==="

# 事前判定: portfolio-review が生成する factory_apps.tsv に対象ステージのアプリがあるか
# （列: name \t path \t owner/repo \t stage）
if [ ! -s "$APPS_FILE" ]; then
  log "factory_apps.tsv が無い/空。portfolio-review が未実行のためスキップ"
  exit 0
fi
if ! awk -F'\t' '$4=="building" || $4=="growing" || $4=="validating" {found=1} END {exit !found}' "$APPS_FILE"; then
  log "対象ステージ（building/growing/validating）のアプリなし。スキップ"
  exit 0
fi

cd "$PROJECT_DIR"
if ! $CLAUDE -p --permission-mode bypassPermissions \
  --append-system-prompt "作業ディレクトリは ${PROJECT_DIR} です。これは launchd による無人実行（App Factory の factory-build、1日2回）です。" \
  << 'PROMPT' >> "$LOG_FILE" 2>&1
app-factory:factory-build スキルを最初から最後まで実行してください。

- 安全レールを厳守すること（1回最大2 issue、auto-merge はスイッチと全条件を満たすときだけ、
  センシティブ領域の除外、factory-wip での排他、使い捨て worktree での作業）
- 前回持ち越した factory/ ブランチの open PR の回収を先に行うこと
- 無人実行なのでユーザーへの質問はしないこと。判断できない issue は needs-clarification で人間に回すこと
PROMPT
then
  log "ERROR: claude 実行が非ゼロ終了"
  curl -s -X POST -H 'Content-type: application/json' \
    --data '{"text":":warning: factory-build の実行が失敗しました。logs/factory_build.log を確認してください。"}' \
    "${SLACK_WEBHOOK_URL_FACTORY:-$SLACK_WEBHOOK_URL}" > /dev/null || true
fi

log "=== Finished ==="
