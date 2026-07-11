#!/bin/bash
# App Factory: portfolio-review — 週次（金曜 17:00）
# 計測 → KPI/ステージ判定 → portfolio.yml 更新 → 翌週の割当表生成 → 週報
# launchd (com.claude.portfolio-review) から呼び出される

set -euo pipefail

PROJECT_DIR="$HOME/dev/others/claude-cron"
LOG_FILE="$PROJECT_DIR/logs/portfolio_review.log"
CLAUDE="$HOME/.nodebrew/current/bin/claude"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"; }

set -a
source "$PROJECT_DIR/.env"
set +a

log "=== Starting portfolio review ==="

cd "$PROJECT_DIR"
if ! $CLAUDE -p --permission-mode bypassPermissions \
  --append-system-prompt "作業ディレクトリは ${PROJECT_DIR} です。これは launchd による無人の週次実行（App Factory の portfolio-review）です。" \
  << 'PROMPT' >> "$LOG_FILE" 2>&1
app-factory:portfolio-review スキルを最初から最後まで実行してください。

- prd-vault は ~/dev/prd-vault、portfolio.yml が無ければ初回ブートストラップから行うこと
- メトリクスは実データのみ。取れない指標は unmeasured のまま残し、計測の穴は Issue 化すること
- 翌週の割当表 data/factory_schedule.tsv と data/factory_apps.tsv を必ず更新すること
- 週報（要アクション一覧含む）を Slack に1通投稿して終えること
- 無人実行なのでユーザーへの質問はしないこと。判断に迷うものは週報の「要判断」に回すこと
PROMPT
then
  log "ERROR: claude 実行が非ゼロ終了"
  curl -s -X POST -H 'Content-type: application/json' \
    --data '{"text":":warning: portfolio-review の週次実行が失敗しました。logs/portfolio_review.log を確認してください。"}' \
    "${SLACK_WEBHOOK_URL_FACTORY:-$SLACK_WEBHOOK_URL}" > /dev/null || true
fi

log "=== Finished ==="
