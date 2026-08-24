#!/bin/bash
# App Factory: 通知のリファレンス実装
#
# data/pending.json（人間の行動待ち）と data/events.jsonl（起きたこと）を
# 人間可読に整形して**標準出力に出すだけ**。どこへも配送しない。
#
# App Factory 本体は通知手段を持たない（docs/events.md を参照）。
# このスクリプトは「受け手はこう書ける」を示すためのもので、
# Slack・メール・自前ダッシュボードに繋ぐ例は README の「通知を繋ぐ」にある。
#
# 使い方:
#   notify_stdout.sh                  行動待ち + 今日の要対応イベント
#   notify_stdout.sh --all            info も含めて全イベントを出す
#   notify_stdout.sh --since 2026-08-01T00:00:00+09:00
#   notify_stdout.sh --max-items 3    1グループあたりの明細上限（既定5・0で無制限）
#
# 依存: jq

set -euo pipefail

CONFIG_FILE="$HOME/.config/app-factory/config.env"
# 手で叩くものなので、環境変数で指定された APP_FACTORY_HOME を config.env に上書きさせない
# （config.env は無条件代入なので、素直に source すると環境変数が消える）
_PRESET_HOME="${APP_FACTORY_HOME:-}"
[ -f "$CONFIG_FILE" ] && . "$CONFIG_FILE"
[ -n "$_PRESET_HOME" ] && APP_FACTORY_HOME="$_PRESET_HOME"
PROJECT_DIR="${APP_FACTORY_HOME:-$HOME/dev/business/claude-cron}"
PENDING_FILE="$PROJECT_DIR/data/pending.json"
EVENTS_FILE="$PROJECT_DIR/data/events.jsonl"

# 明細をどこで丸めるかは「表示側の判断」なので受け手であるここが持つ。
# pending.json は常に全件入っている。
MAX_ITEMS=5
SHOW_ALL=0
SINCE="$(date '+%Y-%m-%d')T00:00:00"

while [ $# -gt 0 ]; do
  case "$1" in
    --all)       SHOW_ALL=1; shift ;;
    --since)     SINCE="$2"; shift 2 ;;
    --max-items) MAX_ITEMS="$2"; shift 2 ;;
    *) echo "不明なオプション: $1" >&2; exit 1 ;;
  esac
done

# --- 1. いま人間の行動を待っているもの ---------------------------------------
if [ -f "$PENDING_FILE" ]; then
  jq -r --argjson max "$MAX_ITEMS" '
    def clip(items):
      if $max > 0 and (items | length) > $max
      then items[0:$max][], "    …ほか \((items | length) - $max) 件"
      else items[] end;

    "🗂 判断待ち \(.judge.count)件・推定 \(.judge.cost_total)分（予算 \(.budget_minutes)分）"
      + (if .judge.over_budget then "  ⚠️ 予算に達したので新規 PR の生産は停止中です" else "" end),

    (if (.judge.blocked // 0) > 0 then
      "⚠️ うち \(.judge.blocked)件は CI 失敗かコンフリクトで、人間が依頼をこなしてもマージできません（先に直す必要があります）"
     else empty end),

    (if (.degraded | length) > 0 then
      "⚠️ GitHub API から取得できなかったリポジトリ: \(.degraded | join(", "))",
      "   ↳ 下の件数は実際より少なく出ています"
     else empty end),

    "",

    (.groups[] |
      "▸ \(.label)" + (if .hint == "" then "" else "（\(.hint)）" end),
      (clip(.items) |
        if type == "string" then .
        else "    • \(.app)"
             + (if .ref then " #\(.ref)" else "" end)
             + " \(.title)"
             # ask は書かれた時点の静的テキストで、直っても腐ったまま残る。
             # 「まだ本当にそうなのか」を人間が照合できるよう、CI と mergeable を必ず併記する。
             + ("（" + ([
                  (if .due then .due else empty end),
                  (if .ci then
                     { "ok": "CI green", "failing": "CI 失敗", "pending": "CI 実行中", "none": "CI なし" }[.ci] // ("CI " + .ci)
                   else empty end),
                  (if .mergeable then
                     { "MERGEABLE": "マージ可", "CONFLICTING": "コンフリクト", "UNKNOWN": "判定中" }[.mergeable] // .mergeable
                   else empty end)
                ] | join(" / ")) + "）"
                | if . == "（）" then "" else . end)
             + (if .blocked then
                  "\n      ⚠️ 実態: "
                  + ([ (if .mergeable == "CONFLICTING" then "コンフリクト中" else empty end),
                       (if .ci == "failing" then "CI 失敗中" else empty end) ] | join(" / "))
                  + " — この依頼をこなしても、このままではマージできません"
                else "" end)
             + (if .asked_at then "\n      （この依頼は \(.asked_at) に書かれたものです）" else "" end)
             + (if .url then "\n      \(.url)" else "" end)
        end),
      "    ↳ \(.action)",
      "    ↳ 放置したら: \(.default_if_ignored)",
      ""
    ),

    "（生成: \(.generated)）"
  ' "$PENDING_FILE"
else
  echo "（$PENDING_FILE がありません。run_factory_reminder.sh を先に実行してください）"
fi

# --- 2. 起きたこと -----------------------------------------------------------
echo
echo "──────────────────────────────"
echo

if [ ! -f "$EVENTS_FILE" ]; then
  echo "（$EVENTS_FILE がありません）"
  exit 0
fi

# severity で絞る。既定は action / error だけ（info はタイムライン向けで通知には出さない）
jq -rs --arg since "$SINCE" --argjson all "$SHOW_ALL" '
  map(select(.ts >= $since))
  | map(select($all == 1 or .severity != "info"))
  | if length == 0 then
      "\($since) 以降、対応が要るイベントはありません"
    else
      "📋 \($since) 以降のイベント（\(length)件）",
      "",
      (.[] |
        "  [\(.severity)] \(.ts[11:16]) \(.job)"
          + (if .app then " / \(.app)" else "" end),
        "    \(.title // .kind)",
        (if .url then "    \(.url)" else empty end)
      )
    end
' "$EVENTS_FILE"
