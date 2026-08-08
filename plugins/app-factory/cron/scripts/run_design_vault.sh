#!/bin/bash
# App Factory: design-vault — 毎日 4:00
# Slack のデザイン収集チャンネルに投げられたスクショを取り込み、カード化 → パターン集約する。
# launchd (com.claude.design-vault) から呼び出される
# bash 事前判定: 用がある日だけ claude を起動する
#   - inbox に未分析（*.json）が残っている
#   - または Slack チャンネルに前回取り込み以降の新着メッセージがある

set -euo pipefail

CONFIG_FILE="$HOME/.config/app-factory/config.env"
[ -f "$CONFIG_FILE" ] && . "$CONFIG_FILE"
PROJECT_DIR="${APP_FACTORY_HOME:-$HOME/dev/others/claude-cron}"
VAULT="${PRD_VAULT_DIR:-$HOME/dev/prd-vault}/design-vault"
LOG_FILE="$PROJECT_DIR/logs/design_vault.log"
CLAUDE="${CLAUDE_BIN:-$HOME/.nodebrew/current/bin/claude}"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"; }

set -a
source "$PROJECT_DIR/.env"
set +a

log "=== Starting design-vault check ==="

if [ -z "${SLACK_DESIGN_CHANNEL_ID:-}" ]; then
  log "SLACK_DESIGN_CHANNEL_ID が未設定。初回セットアップ前なのでスキップ"
  exit 0
fi

NEED=0
REASON=""

# 1. 前回やり残した未分析画像があるか
if [ -d "$VAULT/inbox" ] && [ -n "$(find "$VAULT/inbox" -maxdepth 1 -name '*.json' -print -quit 2>/dev/null)" ]; then
  NEED=1; REASON="inbox_pending"
fi

# 2. Slack に前回取り込み以降の新着があるか（1件でもあれば起動する）
if [ "$NEED" -eq 0 ]; then
  LAST_TS=$(python3 - "$VAULT/.slack_state.json" <<'PY' 2>/dev/null || echo 0
import json, sys, os
p = sys.argv[1]
print(json.load(open(p)).get("last_ts", "0") if os.path.exists(p) else "0")
PY
)
  NEW=$(curl -s -H "Authorization: Bearer $SLACK_BOT_TOKEN" \
    "https://slack.com/api/conversations.history?channel=${SLACK_DESIGN_CHANNEL_ID}&oldest=${LAST_TS}&limit=1" \
    | python3 -c "import json,sys; d=json.load(sys.stdin); print(len(d.get('messages', [])) if d.get('ok') else 0)" 2>/dev/null || echo 0)
  if [ "${NEW:-0}" -gt 0 ]; then
    NEED=1; REASON="slack_new"
  fi
fi

if [ "$NEED" -eq 0 ]; then
  log "新着なし。claude を起動せず終了"
  exit 0
fi

log "起動理由: $REASON"

cd "$PROJECT_DIR"
if ! $CLAUDE -p --permission-mode bypassPermissions \
  --append-system-prompt "作業ディレクトリは ${PROJECT_DIR} です。これは launchd による無人の日次実行（App Factory の design-vault）です。" \
  << 'PROMPT' >> "$LOG_FILE" 2>&1
app-factory:design-vault スキルを collect モードで最初から最後まで実行してください。

- 分析は1回の実行で最大20件まで。残りは inbox に置いたまま次回に回すこと
- 各カードには「効く条件」を必ず書くこと。これが無いカードは作らない
- 「洗練されている」「モダン」のような再現できない形容は書かないこと
- 同一 screen のカードが5枚以上溜まったらパターンを新規作成、
  既存パターンから+5枚増えていたら更新すること（例を足すだけで結論を据え置かない）
- Slack 通知は新しいパターンができた／既存パターンの結論が変わったときだけ。
  カードが増えただけでは通知しないこと
- 無人実行なのでユーザーへの質問はしないこと
PROMPT
then
  log "ERROR: claude 実行が非ゼロ終了"
  curl -s -X POST -H 'Content-type: application/json' \
    --data '{"text":":warning: design-vault の実行が失敗しました。logs/design_vault.log を確認してください。"}' \
    "${SLACK_WEBHOOK_URL_FACTORY:-$SLACK_WEBHOOK_URL}" > /dev/null || true
fi

log "=== Finished ==="
