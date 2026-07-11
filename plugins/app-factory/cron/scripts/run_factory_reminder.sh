#!/bin/bash
# App Factory: factory-reminder — 毎日 12:00
# 人間の手動タスクが溜まっていたら Slack にリマインドを1通出す。
# claude は起動しない（bash + gh のみ = トークン消費ゼロ）。溜まっていなければ何も投稿しない。
# launchd (com.claude.factory-reminder) から呼び出される

set -euo pipefail

CONFIG_FILE="$HOME/.config/app-factory/config.env"
[ -f "$CONFIG_FILE" ] && . "$CONFIG_FILE"
PROJECT_DIR="${APP_FACTORY_HOME:-$HOME/dev/others/claude-cron}"
PRD_VAULT="${PRD_VAULT_DIR:-$HOME/dev/prd-vault}"
OWNER="${GITHUB_OWNER:-KojoBarbie}"
APPS_FILE="$PROJECT_DIR/data/factory_apps.tsv"
LOG_FILE="$PROJECT_DIR/logs/factory_reminder.log"
GH="$(command -v gh || echo /opt/homebrew/bin/gh)"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"; }

set -a
source "$PROJECT_DIR/.env"
set +a

log "=== Starting reminder check ==="

LINES=()

count() { echo "${1:-0}" | tr -d '[:space:]'; }

# 1. prd-vault の未マージ PRD PR
VAULT_REPO="$OWNER/$(basename "$PRD_VAULT")"
N=$(count "$($GH pr list -R "$VAULT_REPO" --state open --json number --jq length 2>/dev/null || echo 0)")
[ "$N" -gt 0 ] && LINES+=("📋 PRD の PR が *${N}件* レビュー待ち → https://github.com/$VAULT_REPO/pulls")

# 2. アプリごとの滞留（factory_apps.tsv があるときだけ）
if [ -s "$APPS_FILE" ]; then
  while IFS=$'\t' read -r NAME _PATH REPO _STAGE; do
    [ -z "$NAME" ] && continue
    case "$NAME" in \#*) continue ;; esac
    P=$(count "$($GH issue list -R "$REPO" --label feature-proposal --state open --search '-label:go' --json number --jq length 2>/dev/null || echo 0)")
    [ "$P" -gt 0 ] && LINES+=("💡 ${NAME}: 機能提案が *${P}件* 承認待ち（👍/go か close）")
    B=$(count "$($GH issue list -R "$REPO" --label factory-blocked --state open --json number --jq length 2>/dev/null || echo 0)")
    [ "$B" -gt 0 ] && LINES+=("🧱 ${NAME}: factory-blocked が *${B}件*（人間の判断待ち）")
    C=$(count "$($GH issue list -R "$REPO" --label needs-clarification --state open --json number --jq length 2>/dev/null || echo 0)")
    [ "$C" -gt 0 ] && LINES+=("❓ ${NAME}: 要件確認待ちが *${C}件*")
    R=$(count "$($GH issue list -R "$REPO" --label app-review-rejected --state open --json number --jq length 2>/dev/null || echo 0)")
    [ "$R" -gt 0 ] && LINES+=("🚫 ${NAME}: App Review リジェクト対応待ち")
  done < "$APPS_FILE"
fi

# 3. Xcode Cloud オンボーディング待ち（3日おきの個別リマインドとは別に、件数だけ載せる）
PENDING="$PROJECT_DIR/.data/pending_xcode_cloud.txt"
if [ -s "$PENDING" ]; then
  N=$(grep -cv '^[[:space:]]*$' "$PENDING" || echo 0)
  [ "$N" -gt 0 ] && LINES+=("🍎 ASC/Xcode Cloud の初回設定待ちが *${N}件*")
fi

if [ "${#LINES[@]}" -eq 0 ]; then
  log "滞留なし。投稿せず終了"
  exit 0
fi

TEXT=":bellhop_bell: *今日の人間タスク（溜まっています）*\n"
for l in "${LINES[@]}"; do TEXT+="\n${l}"; done
TEXT+="\n\n_それぞれの放置時のデフォルト動作は週報参照。対応すればこの通知は止まります_"

curl -s -X POST -H 'Content-type: application/json' \
  --data "{\"text\":\"${TEXT//\"/\\\"}\"}" \
  "${SLACK_WEBHOOK_URL_FACTORY:-$SLACK_WEBHOOK_URL}" > /dev/null || log "Slack 投稿失敗"

log "=== Finished (${#LINES[@]} 項目を通知) ==="
