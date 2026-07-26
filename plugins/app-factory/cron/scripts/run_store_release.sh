#!/bin/bash
# App Factory: store-release — 毎日 6:00
# App Store 提出パイプライン（リリース列車の起票 → メタデータ → 承認ゲート → 提出 → 審査追跡）
# launchd (com.claude.store-release) から呼び出される
# bash 事前判定: 用がある日だけ claude を起動する
#   - review ステージのアプリがある
#   - open な release-train issue がある（承認チェック・提出・審査追跡）
#   - building アプリで実装系 open issue が 0 件（= MVP 完了、列車の起票候補）
#   - 水曜日（定期リリース列車の週次フルスキャン）

set -euo pipefail

CONFIG_FILE="$HOME/.config/app-factory/config.env"
[ -f "$CONFIG_FILE" ] && . "$CONFIG_FILE"
PROJECT_DIR="${APP_FACTORY_HOME:-$HOME/dev/others/claude-cron}"
APPS_FILE="$PROJECT_DIR/data/factory_apps.tsv"
LOG_FILE="$PROJECT_DIR/logs/store_release.log"
CLAUDE="${CLAUDE_BIN:-$HOME/.nodebrew/current/bin/claude}"
GH="/opt/homebrew/bin/gh"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"; }

set -a
source "$PROJECT_DIR/.env"
set +a

log "=== Starting store release check ==="

if [ ! -s "$APPS_FILE" ]; then
  log "factory_apps.tsv が無い/空。portfolio-review が未実行のためスキップ"
  exit 0
fi

NEED=0
REASON=""

# 水曜は定期リリース列車の週次フルスキャン
if [ "$(date '+%u')" = "3" ]; then
  NEED=1; REASON="weekly_scan"
fi

# review ステージがあれば常に用がある（審査追跡）
if [ "$NEED" -eq 0 ] && awk -F'\t' '$4=="review" {f=1} END {exit !f}' "$APPS_FILE"; then
  NEED=1; REASON="stage_review"
fi

# open な release-train issue / MVP 完了の building アプリを探す
if [ "$NEED" -eq 0 ]; then
  while IFS=$'\t' read -r NAME APP_PATH REPO STAGE; do
    [ -z "$NAME" ] && continue
    case "$NAME" in \#*) continue ;; esac
    # release-train が open なら veto/提出/追跡の用がある
    if [ -n "$($GH issue list -R "$REPO" --label release-train --state open --limit 1 --json number --jq '.[].number' 2>/dev/null)" ]; then
      NEED=1; REASON="open_train:$NAME"; break
    fi
    # building で実装系 open issue ゼロ = MVP 完了候補
    if [ "$STAGE" = "building" ]; then
      OPEN_IMPL=$($GH issue list -R "$REPO" --state open --limit 100 --json labels \
        --jq '[.[] | select((.labels | map(.name) | any(. == "feature-proposal" or . == "release-train" or . == "app-review-rejected")) | not)] | length' 2>/dev/null || echo 1)
      if [ "$OPEN_IMPL" = "0" ]; then
        NEED=1; REASON="mvp_done:$NAME"; break
      fi
    fi
  done < "$APPS_FILE"
fi

if [ "$NEED" -eq 0 ]; then
  log "本日は用なし。claude を起動せず終了"
  exit 0
fi

log "起動理由: $REASON"

cd "$PROJECT_DIR"
if ! $CLAUDE -p --permission-mode bypassPermissions \
  --append-system-prompt "作業ディレクトリは ${PROJECT_DIR} です。これは launchd による無人の日次実行（App Factory の store-release）です。" \
  << 'PROMPT' >> "$LOG_FILE" 2>&1
app-factory:store-release スキルを最初から最後まで実行してください。

- リリース列車（release-train issue）の状態機械を厳守すること
- **App Store への提出は人間の明示承認（release-train issue の approved ラベル or 👍）が無い限り実行しないこと**。
  メタデータ生成・TestFlight 用ビルド確保など提出手前の準備は承認前でも進めてよい
- バージョンは semver ルールで決めること（機能追加ありならマイナー↑ / バグ修正のみならパッチ↑ /
  メジャーは人間指示か major ラベルのときだけ）
- 提出・タグ作成などの操作は必ず冪等に（ASC と GitHub の現状態を照会してから）
- そのアプリで ASC API による提出が初回の場合は、承認済みでも提出直前で止めて人間併走の案内を Slack に出すこと
- 無人実行なのでユーザーへの質問はしないこと
PROMPT
then
  log "ERROR: claude 実行が非ゼロ終了"
  curl -s -X POST -H 'Content-type: application/json' \
    --data '{"text":":warning: store-release の実行が失敗しました。logs/store_release.log を確認してください。"}' \
    "${SLACK_WEBHOOK_URL_PRD:-$SLACK_WEBHOOK_URL}" > /dev/null || true
fi

log "=== Finished ==="
