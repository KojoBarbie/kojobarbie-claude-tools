#!/bin/bash
# App Factory: factory-dispatch — 平日 3:00
# portfolio-review が生成した割当表（data/factory_schedule.tsv）から当日のスロットを読み、
# feature-hunt / audit / growth-advisor のいずれかを「1日1リポジトリ」だけ実行する。
# スロットが空の日は claude を起動せず即終了（トークン消費ゼロ）。
# launchd (com.claude.factory-dispatch) から呼び出される

set -euo pipefail

CONFIG_FILE="$HOME/.config/app-factory/config.env"
[ -f "$CONFIG_FILE" ] && . "$CONFIG_FILE"
PROJECT_DIR="${APP_FACTORY_HOME:-$HOME/dev/others/claude-cron}"
SCHEDULE_FILE="$PROJECT_DIR/data/factory_schedule.tsv"
HISTORY_FILE="$PROJECT_DIR/logs/factory_dispatch_history.tsv"
LOG_FILE="$PROJECT_DIR/logs/factory_dispatch.log"
CLAUDE="${CLAUDE_BIN:-$HOME/.nodebrew/current/bin/claude}"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"; }

set -a
source "$PROJECT_DIR/.env"
set +a

TODAY=$(date '+%Y-%m-%d')
log "=== Starting dispatch for $TODAY ==="

if [ ! -s "$SCHEDULE_FILE" ]; then
  log "割当表なし（portfolio-review 未実行？）。スキップ"
  exit 0
fi

# 割当表の列: date \t app \t path \t job（#始まりはコメント）
SLOT=$(awk -F'\t' -v d="$TODAY" '$0 !~ /^#/ && $1 == d { print; exit }' "$SCHEDULE_FILE")
if [ -z "$SLOT" ]; then
  log "本日のスロットなし。claude を起動せず終了"
  exit 0
fi

APP_NAME=$(echo "$SLOT" | cut -f2)
APP_PATH=$(echo "$SLOT" | cut -f3)
JOB=$(echo "$SLOT" | cut -f4)

if [ ! -d "$APP_PATH" ]; then
  log "$APP_NAME: パスが存在しない ($APP_PATH)。スキップ"
  echo -e "${TODAY}\t${APP_NAME}\t${JOB}\tpath_missing" >> "$HISTORY_FILE"
  exit 0
fi

log "$APP_NAME: $JOB を実行 ($APP_PATH)"
STATUS="ok"

run_claude() {
  # $1 = 作業ディレクトリ, $2 = プロンプト
  cd "$1"
  echo "$2" | $CLAUDE -p --permission-mode bypassPermissions \
    --append-system-prompt "作業ディレクトリは $1（アプリ: ${APP_NAME}）です。これは launchd による無人実行（App Factory の factory-dispatch）です。ユーザーへの質問はしないでください。" \
    >> "$LOG_FILE" 2>&1 || STATUS="error"
}

case "$JOB" in
  audit)
    # 監査は既存 audit ジョブと同じく origin の default branch を使い捨て worktree に展開して読み取り専用で行う
    DEFAULT=$(git -C "$APP_PATH" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@' || true)
    DEFAULT="${DEFAULT:-main}"
    git -C "$APP_PATH" fetch origin >> "$LOG_FILE" 2>&1 || true
    WT=$(mktemp -d "/tmp/factory_audit_${APP_NAME}.XXXXXX")
    cleanup() { git -C "$APP_PATH" worktree remove --force "$WT" >> "$LOG_FILE" 2>&1 || rm -rf "$WT"; }
    trap cleanup EXIT
    git -C "$APP_PATH" worktree add "$WT" "origin/$DEFAULT" >> "$LOG_FILE" 2>&1
    run_claude "$WT" "quality-release-cycle スキルの audit モードを実行してください。

- これは読み取り専用の使い捨て worktree です。Issue の起票先は $(git -C "$APP_PATH" remote get-url origin | sed -E 's@.*github.com[:/]@@; s@\.git$@@') です
- 前回監査以降の差分を中心に、新規起票は最大10件の規律を守ること
- 完了したら結果の要約を Slack（\$SLACK_WEBHOOK_URL_FACTORY、無ければ \$SLACK_WEBHOOK_URL）に投稿すること"
    ;;
  feature-hunt)
    run_claude "$APP_PATH" "/feature-hunt スキルの Run（週次実行）を最初から最後まで実行してください。

- .claude/product-context.md と .claude/feature-hunt-log.md を必ず最初に読むこと
- 前回提案の承認（go/👍）・却下（close）チェックを忘れずに行うこと
- 成果物: 最大3件の提案Issue + Slack通知。基準を満たす案がなければ無理に出さず、その旨をSlackに報告すること"
    ;;
  growth-advisor)
    run_claude "$APP_PATH" "app-factory:growth-advisor スキルを最初から最後まで実行してください。

- prd-vault（\$PRD_VAULT_DIR。~/.config/app-factory/config.env 参照、デフォルト ~/dev/prd-vault）の portfolio.yml と PRD のジョブ分析・KPI セクションを必ず入力に使うこと
- 提案は最大3件、根拠・前提・検証方法の3点セットを必須とすること"
    ;;
  *)
    log "$APP_NAME: 不明なジョブ種別 '$JOB'。スキップ"
    STATUS="unknown_job"
    ;;
esac

echo -e "${TODAY}\t${APP_NAME}\t${JOB}\t${STATUS}" >> "$HISTORY_FILE"

if [ "$STATUS" = "error" ]; then
  curl -s -X POST -H 'Content-type: application/json' \
    --data "{\"text\":\":warning: factory-dispatch (${APP_NAME} / ${JOB}) が失敗しました。logs/factory_dispatch.log を確認してください。\"}" \
    "${SLACK_WEBHOOK_URL_FACTORY:-$SLACK_WEBHOOK_URL}" > /dev/null || true
fi

log "=== Finished ($STATUS) ==="
