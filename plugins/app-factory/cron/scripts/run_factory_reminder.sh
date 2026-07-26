#!/bin/bash
# App Factory: factory-reminder — 毎日 12:00
# 人間の手動タスクが溜まっていたら Slack にリマインドを1通出す。
# claude は起動しない（bash + gh のみ = トークン消費ゼロ）。溜まっていなければ何も投稿しない。
# launchd (com.claude.factory-reminder) から呼び出される
#
# 方針: 「◯件あります」で終わらせない。1件ごとに「どれを・どこで見て・何をするか」を
#       タイトル＋直リンク＋具体アクション（この情報をください / これを承認してください）付きで出す。

set -euo pipefail

CONFIG_FILE="$HOME/.config/app-factory/config.env"
[ -f "$CONFIG_FILE" ] && . "$CONFIG_FILE"
PROJECT_DIR="${APP_FACTORY_HOME:-$HOME/dev/others/claude-cron}"
PRD_VAULT="${PRD_VAULT_DIR:-$HOME/dev/prd-vault}"
OWNER="${GITHUB_OWNER:-KojoBarbie}"
APPS_FILE="$PROJECT_DIR/data/factory_apps.tsv"
LOG_FILE="$PROJECT_DIR/logs/factory_reminder.log"
GH="$(command -v gh || echo /opt/homebrew/bin/gh)"

# 1カテゴリあたり明細を出す上限（超えた分は「ほか N 件」に丸める）
MAX_ITEMS=5

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"; }

set -a
source "$PROJECT_DIR/.env"
set +a

log "=== Starting reminder check ==="

LINES=()

# gh issue list の結果（number/title/url の TSV）を「  • #N タイトル → URL（+ アクション）」に整形して LINES へ。
# $1=見出し行  $2=TSV本体（number<TAB>title<TAB>url の複数行）  $3=各明細に付ける手順文
emit_items() {
  local header="$1" tsv="$2" action="$3"
  [ -z "$tsv" ] && return 0
  local total shown=0
  total=$(printf '%s\n' "$tsv" | grep -c . || true)
  LINES+=("$header")
  while IFS=$'\t' read -r NUM TITLE URL; do
    [ -z "$NUM" ] && continue
    if [ "$shown" -ge "$MAX_ITEMS" ]; then
      LINES+=("    …ほか $((total - MAX_ITEMS)) 件")
      break
    fi
    LINES+=("    • #${NUM} ${TITLE} → ${URL}")
    shown=$((shown + 1))
  done <<< "$tsv"
  [ -n "$action" ] && LINES+=("      ↳ ${action}")
}

# --- 1. prd-vault の未マージ PRD PR ---
VAULT_REPO="$OWNER/$(basename "$PRD_VAULT")"
PR_TSV=$($GH pr list -R "$VAULT_REPO" --state open --json number,title,url \
  --jq '.[] | "\(.number)\t\(.title)\t\(.url)"' 2>/dev/null || true)
emit_items "📋 *PRD の PR がレビュー待ち*" "$PR_TSV" \
  "見るのは「ジョブ分析が信じられるか・KPI に具体的数値と根拠があるか・showcase のモック/トンマナ」。良ければ merge、ボツは close、直しは PR にコメント。放置＝新規アプリが生まれないだけ（既存は回り続ける）"

# --- 2. アプリごとの滞留（factory_apps.tsv があるときだけ）---
if [ -s "$APPS_FILE" ]; then
  while IFS=$'\t' read -r NAME _PATH REPO _STAGE; do
    [ -z "$NAME" ] && continue
    case "$NAME" in \#*) continue ;; esac

    # 2-a. 提出承認待ちのリリース列車（approved ラベルが無い open な release-train）
    RT_TSV=$($GH issue list -R "$REPO" --label release-train --state open --json number,title,url,labels \
      --jq '.[] | select((.labels|map(.name)|index("approved"))|not) | select((.labels|map(.name)|index("hold"))|not) | "\(.number)\t\(.title)\t\(.url)"' 2>/dev/null || true)
    emit_items "🚦 ${NAME}: *App Store 提出の承認待ち*" "$RT_TSV" \
      "issue を開き、メタデータ（名前/説明/著作権/カテゴリ）・スクリーンショット・バージョン・リリースノートを確認。出して良ければ \`approved\` ラベル or 👍。延期は \`hold\`、やめるなら close。放置＝提出されないまま待機"

    # 2-b. 未承認の機能提案（go ラベルが無いもの）
    FP_TSV=$($GH issue list -R "$REPO" --label feature-proposal --state open --search '-label:go' --json number,title,url \
      --jq '.[] | "\(.number)\t\(.title)\t\(.url)"' 2>/dev/null || true)
    emit_items "💡 ${NAME}: *機能提案が承認待ち*" "$FP_TSV" \
      "採用するなら 👍 か \`go\` ラベル（→ sub-issue 化されて自動実装に流れる）、やらないなら close。放置＝提案が溜まる（6件超で新規提案は自動休止）"

    # 2-c. factory-blocked（自動実装が2回失敗して止まっている）
    FB_TSV=$($GH issue list -R "$REPO" --label factory-blocked --state open --json number,title,url \
      --jq '.[] | "\(.number)\t\(.title)\t\(.url)"' 2>/dev/null || true)
    emit_items "🧱 ${NAME}: *自動実装が詰まっている（factory-blocked）*" "$FB_TSV" \
      "issue の 🤖 コメントに失敗理由がある。人手で直す/方針を書く、または触らせたくないなら close。対応後に \`factory-blocked\` ラベルを外すと自動実装が再開"

    # 2-d. 要件確認待ち（この情報をください）
    NC_TSV=$($GH issue list -R "$REPO" --label needs-clarification --state open --json number,title,url \
      --jq '.[] | "\(.number)\t\(.title)\t\(.url)"' 2>/dev/null || true)
    emit_items "❓ ${NAME}: *要件の確認待ち（この情報をください）*" "$NC_TSV" \
      "issue の 🤖 コメントに質問がある。回答をコメントし \`needs-clarification\` ラベルを外すと自動実装が拾う。放置＝その issue は進まない"

    # 2-e. App Review リジェクト
    AR_TSV=$($GH issue list -R "$REPO" --label app-review-rejected --state open --json number,title,url \
      --jq '.[] | "\(.number)\t\(.title)\t\(.url)"' 2>/dev/null || true)
    emit_items "🚫 ${NAME}: *App Review リジェクト対応待ち*" "$AR_TSV" \
      "issue の 🤖 コメントにリジェクト内容の要約がある。対応方針を指示（自動再提出はしない）。放置＝そのアプリのリリースが止まる"
  done < "$APPS_FILE"
fi

# --- 3. Xcode Cloud / ASC 初回オンボーディング待ち ---
PENDING="$PROJECT_DIR/.data/pending_xcode_cloud.txt"
if [ -s "$PENDING" ]; then
  APPS=$(awk 'NF{print $1}' "$PENDING" | paste -sd', ' -)
  if [ -n "$APPS" ]; then
    LINES+=("🍎 *ASC / Xcode Cloud の初回設定待ち*: ${APPS}")
    LINES+=("      ↳ 各アプリで ①ASC でアプリレコード作成（Bundle ID は登録済み・選ぶだけ） ②Xcode で開き Product > Xcode Cloud からオンボーディング（GitHub 接続込み）。完了は毎日9時/21時に自動検知され、TestFlight ワークフローが自動作成される。放置＝そのアプリのリリースが進まない")
  fi
fi

if [ "${#LINES[@]}" -eq 0 ]; then
  log "滞留なし。投稿せず終了"
  exit 0
fi

TEXT=":bellhop_bell: *今日の人間タスク（溜まっています）*\n"
for l in "${LINES[@]}"; do TEXT+="\n${l}"; done
TEXT+="\n\n_対応すればこの通知は止まります。金曜の週報にも同じ一覧が「放置時のデフォルト動作」付きで再掲されます_"

curl -s -X POST -H 'Content-type: application/json' \
  --data "{\"text\":\"${TEXT//\"/\\\"}\"}" \
  "${SLACK_WEBHOOK_URL_FACTORY:-$SLACK_WEBHOOK_URL}" > /dev/null || log "Slack 投稿失敗"

log "=== Finished (${#LINES[@]} 行を通知) ==="
