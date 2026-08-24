#!/bin/bash
# App Factory: factory-reminder — 毎日 12:00
#
# 「いま人間の行動を待っているもの」を全リポジトリから集め、
# $APP_FACTORY_HOME/data/pending.json に上書き生成する。
# claude は起動しない（bash + gh + jq のみ = トークン消費ゼロ）。
# launchd (com.claude.factory-reminder) から呼び出される。
#
# ⚠️ このスクリプトは通知しない。誰にどう知らせるかは利用者の担当で、
#    pending.json を読む受け手を各自で用意する（リファレンス: notify_stdout.sh）。
#    仕様は docs/events.md を参照。
#
# 方針: 「◯件あります」で終わらせない。1件ごとに「どれを・どこで見て・何をするか」と
#       「放置したら何が起きるか」を持たせる。件数の丸めはしない（表示側の判断なので受け手に委ねる）。
#
# 使い方:
#   run_factory_reminder.sh            pending.json を生成
#   run_factory_reminder.sh --stdout   ファイルに書かず、生成した JSON を標準出力に出す

set -euo pipefail

TO_STDOUT=0
[ "${1:-}" = "--stdout" ] && TO_STDOUT=1

CONFIG_FILE="$HOME/.config/app-factory/config.env"
[ -f "$CONFIG_FILE" ] && . "$CONFIG_FILE"
PROJECT_DIR="${APP_FACTORY_HOME:-$HOME/dev/business/claude-cron}"
PRD_VAULT="${PRD_VAULT_DIR:-$HOME/dev/business/prd-vault}"
OWNER="${GITHUB_OWNER:-KojoBarbie}"
APPS_FILE="$PROJECT_DIR/data/factory_apps.tsv"
LOG_FILE="$PROJECT_DIR/logs/factory_reminder.log"
PENDING_FILE="$PROJECT_DIR/data/pending.json"
BUDGET="${JUDGE_BUDGET_MINUTES:-45}"
GH="$(command -v gh || echo /opt/homebrew/bin/gh)"

HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
. "$HERE/lib/judge_common.sh"
# --stdout は中身を確認するためのプレビューなので、イベントは残さない
# （events.jsonl は「実際に起きたこと」だけを持つ）
[ "$TO_STDOUT" -eq 1 ] && EVENTS_FILE=/dev/null
# shellcheck disable=SC1091
. "$HERE/lib/events.sh"
EVENT_JOB="factory-reminder"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"; }

mkdir -p "$PROJECT_DIR/logs" "$PROJECT_DIR/data"
log "=== Starting reminder check ==="
emit_event kind=job_started severity=info

# --- グループの定義 ---------------------------------------------------------
# 配列の順序がそのまま pending.json の groups の順序になる（重い順ではなく捌く順）。
#
# TSV にしないのは、bash の read が IFS の空白文字（タブを含む）の連続を
# 1つに畳むため。hint が空の行でフィールドが1つずつ手前にずれる。
GROUP_DEFS='[
  { "key": "judge_look", "label": "見るだけ",
    "hint": "各10秒・スクショか変更の要約を見るだけ",
    "action": "内容を見て問題なければマージ、不要ならクローズ",
    "default_if_ignored": "期限を過ぎたら risk に応じて自動でマージまたはクローズされます" },
  { "key": "judge_run", "label": "実機で確認",
    "hint": "各5分・シミュレータでは再現しない挙動",
    "action": "実機で ask のとおり確認し、問題なければマージ",
    "default_if_ignored": "期限を過ぎたら risk に応じて自動でマージまたはクローズされます" },
  { "key": "judge_decide", "label": "あなたにしか決められない",
    "hint": "価格・文言のトーン・出すか引っ込めるか",
    "action": "方針を決めて PR にコメントするかマージ",
    "default_if_ignored": "時効はありません。決めるまで残り続けます" },
  { "key": "judge_other", "label": "種別不明",
    "hint": "判断ブロックの type が不正",
    "action": "PR 本文の judge:v1 ブロックを直すか、内容を見て処理する",
    "default_if_ignored": "時効の判定ができないため放置され続けます" },
  { "key": "human_task", "label": "人にしかできない外部作業",
    "hint": "権限付与・App Store Connect 設定など",
    "action": "issue の手順どおり外部サービス側で操作し、完了したら close",
    "default_if_ignored": "その issue に依存している実装が進みません" },
  { "key": "prd_pr", "label": "PRD の PR がレビュー待ち", "hint": "",
    "action": "ジョブ分析が信じられるか・KPI に具体的数値と根拠があるか・showcase のモックとトンマナを見る。良ければ merge、ボツは close、直しは PR にコメント",
    "default_if_ignored": "新規アプリが生まれないだけで、既存アプリは回り続けます" },
  { "key": "release_train", "label": "App Store 提出の承認待ち", "hint": "",
    "action": "issue のメタデータ（名前/説明/著作権/カテゴリ）・スクリーンショット・バージョン・リリースノートを確認し、出して良ければ approved ラベルか 👍。延期は hold、やめるなら close",
    "default_if_ignored": "提出されないまま待機します（自動提出はしません）" },
  { "key": "feature_proposal", "label": "機能提案が承認待ち", "hint": "",
    "action": "採用するなら 👍 か go ラベル（sub-issue 化されて自動実装に流れる）、やらないなら close",
    "default_if_ignored": "提案が溜まります（未反応6件超で新規提案が自動休止）" },
  { "key": "factory_blocked", "label": "自動実装が詰まっている", "hint": "",
    "action": "issue の 🤖 コメントに失敗理由がある。人手で直すか方針を書く。対応後に factory-blocked ラベルを外すと自動実装が再開",
    "default_if_ignored": "その issue は永久に止まったままです" },
  { "key": "needs_clarification", "label": "要件の確認待ち（この情報をください）", "hint": "",
    "action": "issue の 🤖 コメントにある質問に回答し、needs-clarification ラベルを外す",
    "default_if_ignored": "その issue は進みません" },
  { "key": "app_review_rejected", "label": "App Review リジェクト対応待ち", "hint": "",
    "action": "issue の 🤖 コメントにリジェクト内容の要約がある。対応方針を指示する（自動再提出はしません）",
    "default_if_ignored": "そのアプリのリリースが止まります" },
  { "key": "onboarding", "label": "ASC / Xcode Cloud の初回設定待ち", "hint": "",
    "action": "①App Store Connect でアプリレコードを作成（Bundle ID は登録済み・選ぶだけ）②Xcode で開き Product > Xcode Cloud からオンボーディング（GitHub 接続込み）",
    "default_if_ignored": "そのアプリのリリースが進みません（完了は自動検知されます）" }
]'

# --- 収集 -------------------------------------------------------------------
TMP="$(mktemp -d "/tmp/factory_pending.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

# add_item <group_key> key=value ...
#   app / type / title は必須、それ以外は任意。**空の値はキーごと落とす**
#   （受け手に「0番の issue」や空文字を描かせないため）。
#   ref / cost は数値、blocked は真偽値として入れる。
add_item() {
  local group="$1"; shift
  local obj='{}' kv k v
  for kv in "$@"; do
    k="${kv%%=*}"; v="${kv#*=}"
    [ -z "$v" ] && continue
    case "$k" in
      ref|cost|blocked) obj=$(jq -c --arg k "$k" --argjson v "$v" '. + {($k): $v}' <<< "$obj") ;;
      *)                obj=$(jq -c --arg k "$k" --arg  v "$v" '. + {($k): $v}' <<< "$obj") ;;
    esac
  done
  printf '%s\n' "$obj" >> "$TMP/$group.jsonl"
}

# statusCheckRollup の配列から CI の状態を1語にまとめる。$1 = PR の JSON
# 「チェックが1つも無い」を green 扱いするのは判断ブロック運用と揃えるため
# （PR 作成時にローカルテストが通っているのが factory-build の前提）。
ci_state() {
  printf '%s' "$1" | jq -r '
    [.statusCheckRollup[]? | (.conclusion // .state // "")] as $s
    | if ($s | length) == 0 then "none"
      elif ($s | any(. == "FAILURE" or . == "ERROR" or . == "CANCELLED"
                     or . == "TIMED_OUT" or . == "ACTION_REQUIRED" or . == "STARTUP_FAILURE")) then "failing"
      elif ($s | any(. == "PENDING" or . == "IN_PROGRESS" or . == "QUEUED"
                     or . == "WAITING" or . == "REQUESTED" or . == "EXPECTED")) then "pending"
      else "ok" end'
}

JUDGE_COUNT=0
JUDGE_TOTAL=0
JUDGE_BLOCKED=0
FAILED_REPOS=()

for REPO in $(judge_repos); do
  APP="$(basename "$REPO")"

  # --- 判断待ちの PR（横断で1本のキューとして扱う）---
  # ask（PR 本文に埋め込まれた静的テキスト）だけでは実態が分からないので、
  # CI と mergeable も必ず一緒に取る。ask は書かれた時点のスナップショットで、
  # 直っても腐ったまま残る（実測: 直後に 🤖 が解消を報告した PR が2日間
  # 「コンフリクトしています」と表示され続けた）。受け手が照合できるようにする。
  if ! PRS=$(gh_retry "$GH" pr list -R "$REPO" --state open --limit 100 \
      --json number,title,url,body,isDraft,mergeable,statusCheckRollup); then
    # 取得できなかったことを黙って0件にしない（実際より軽く見えるのが一番まずい壊れ方）
    FAILED_REPOS+=("${APP}")
    continue
  fi

  CNT=$(printf '%s' "$PRS" | jq 'length' 2>/dev/null || echo 0)
  if [ "$CNT" -gt 0 ]; then
    for i in $(seq 0 $((CNT - 1))); do
      BODY=$(printf '%s' "$PRS" | jq -r ".[$i].body // \"\"")
      TYPE=$(judge_field "$BODY" type)
      [ -z "$TYPE" ] && continue                                                  # 判断ブロックが無い＝判断待ちではない
      [ "$(printf '%s' "$PRS" | jq -r ".[$i].isDraft")" = "true" ] && continue    # human-task 待ちの draft

      NUM=$(printf '%s' "$PRS" | jq -r ".[$i].number")
      URL=$(printf '%s' "$PRS" | jq -r ".[$i].url")
      COST=$(judge_field "$BODY" cost); [ -z "$COST" ] && COST=1
      ASK=$(judge_ask "$BODY")
      [ -z "$ASK" ] && ASK=$(printf '%s' "$PRS" | jq -r ".[$i].title")
      DUE=$(judge_due_text "$(judge_field "$BODY" expires)")
      ASKED_AT=$(judge_field "$BODY" asked_at)

      PR_JSON=$(printf '%s' "$PRS" | jq -c ".[$i]")
      CI=$(ci_state "$PR_JSON")
      MERGEABLE=$(printf '%s' "$PR_JSON" | jq -r '.mergeable // "UNKNOWN"')
      # blocked = 人間が ask をこなしても、そのままではマージできない状態。
      # 「実機で5分確認してください」と書かれた PR が実は CONFLICTING、が実際に起きている。
      BLOCKED=false
      if [ "$CI" = "failing" ] || [ "$MERGEABLE" = "CONFLICTING" ]; then BLOCKED=true; fi

      case "$TYPE" in
        look)   KEY=judge_look ;;
        run)    KEY=judge_run ;;
        decide) KEY=judge_decide ;;
        *)      KEY=judge_other ;;
      esac
      add_item "$KEY" app="${APP}" type=pr ref="$NUM" title="$ASK" url="$URL" \
        cost="$COST" due="$DUE" ci="$CI" mergeable="$MERGEABLE" blocked="$BLOCKED" \
        asked_at="$ASKED_AT"

      [ "$BLOCKED" = "true" ] && JUDGE_BLOCKED=$((JUDGE_BLOCKED + 1))
      JUDGE_COUNT=$((JUDGE_COUNT + 1))
      JUDGE_TOTAL=$(awk -v a="$JUDGE_TOTAL" -v b="$COST" 'BEGIN { printf "%g", a + b }')
    done
  fi

  # --- ラベル駆動の issue 群 ---
  # key<TAB>label のペアで回す。prd-vault にはアプリ用ラベルが無いので空振りするだけ。
  #
  # ⚠️ `|| true` でエラーを握り潰さないこと。握り潰すと「該当0件」と「取得に失敗」が
  #    区別できなくなり、実際より状況が軽く見える（実測: factory-blocked 84件が
  #    0件として出た）。失敗は degraded に積んで受け手に伝える。
  while IFS=$'\t' read -r KEY LABEL; do
    [ -z "$KEY" ] && continue
    if ! TSV=$(gh_retry "$GH" issue list -R "$REPO" --label "$LABEL" --state open --limit 200 \
        --json number,title,url --jq '.[] | "\(.number)\t\(.title)\t\(.url)"'); then
      FAILED_REPOS+=("${APP}:${LABEL}")
      continue
    fi
    [ -z "$TSV" ] && continue
    while IFS=$'\t' read -r N T U; do
      [ -z "$N" ] && continue
      add_item "$KEY" app="${APP}" type=issue ref="$N" title="$T" url="$U"
    done <<< "$TSV"
  done <<'LABELS'
human_task	human-task
factory_blocked	factory-blocked
needs_clarification	needs-clarification
app_review_rejected	app-review-rejected
LABELS

  # --- 提出承認待ちのリリース列車（approved / hold が付いていない open な release-train）---
  if ! RT=$(gh_retry "$GH" issue list -R "$REPO" --label release-train --state open --limit 200 \
      --json number,title,url,labels \
      --jq '.[] | select((.labels|map(.name)|index("approved"))|not)
                | select((.labels|map(.name)|index("hold"))|not)
                | "\(.number)\t\(.title)\t\(.url)"'); then
    FAILED_REPOS+=("${APP}:release-train")
    RT=""
  fi
  if [ -n "$RT" ]; then
    while IFS=$'\t' read -r N T U; do
      [ -z "$N" ] && continue
      add_item release_train app="${APP}" type=issue ref="$N" title="$T" url="$U"
    done <<< "$RT"
  fi

  # --- 未承認の機能提案（go ラベルが無いもの）---
  if ! FP=$(gh_retry "$GH" issue list -R "$REPO" --label feature-proposal --state open --limit 200 \
      --search '-label:go' --json number,title,url \
      --jq '.[] | "\(.number)\t\(.title)\t\(.url)"'); then
    FAILED_REPOS+=("${APP}:feature-proposal")
    FP=""
  fi
  if [ -n "$FP" ]; then
    while IFS=$'\t' read -r N T U; do
      [ -z "$N" ] && continue
      add_item feature_proposal app="${APP}" type=issue ref="$N" title="$T" url="$U"
    done <<< "$FP"
  fi
done

# --- prd-vault の未マージ PRD PR ---------------------------------------------
# 判断ブロックを持つ PR は上の判断キューに既に入っているので除外する
# （同じ PR が2箇所に出ると「どっちを見ればいいのか」で認知負荷が戻る）
VAULT_REPO="$OWNER/$(basename "$PRD_VAULT")"
if ! PRD_TSV=$(gh_retry "$GH" pr list -R "$VAULT_REPO" --state open --limit 100 --json number,title,url,body \
    --jq '.[] | select((.body // "") | test("judge:v1") | not) | "\(.number)\t\(.title)\t\(.url)"'); then
  FAILED_REPOS+=("$(basename "$PRD_VAULT"):PRD")
  PRD_TSV=""
fi
if [ -n "$PRD_TSV" ]; then
  while IFS=$'\t' read -r N T U; do
    [ -z "$N" ] && continue
    add_item prd_pr app="$(basename "$PRD_VAULT")" type=pr ref="$N" title="$T" url="$U"
  done <<< "$PRD_TSV"
fi

# --- Xcode Cloud / ASC 初回オンボーディング待ち --------------------------------
PENDING_XC="$PROJECT_DIR/.data/pending_xcode_cloud.txt"
if [ -s "$PENDING_XC" ]; then
  while read -r APPNAME _; do
    [ -z "$APPNAME" ] && continue
    add_item onboarding app="${APPNAME}" type=app title="App Store Connect のアプリ作成と Xcode Cloud オンボーディングが未完了"
  done < "$PENDING_XC"
fi

# --- 組み立て ---------------------------------------------------------------
GROUP_JSON='[]'
while IFS= read -r KEY; do
  [ -z "$KEY" ] && continue
  [ -f "$TMP/$KEY.jsonl" ] || continue
  GROUP_JSON=$(jq -c --arg key "$KEY" --argjson defs "$GROUP_DEFS" \
    --slurpfile items "$TMP/$KEY.jsonl" \
    '. + [ ($defs[] | select(.key == $key)) + {items: $items} ]' <<< "$GROUP_JSON")
done < <(printf '%s' "$GROUP_DEFS" | jq -r '.[].key')

OVER=false
awk -v t="$JUDGE_TOTAL" -v b="$BUDGET" 'BEGIN { exit !(t >= b) }' && OVER=true

DEGRADED='[]'
if [ "${#FAILED_REPOS[@]}" -gt 0 ]; then
  DEGRADED=$(printf '%s\n' "${FAILED_REPOS[@]}" | jq -Rc . | jq -sc .)
fi

PENDING=$(jq -n \
  --arg generated "$(date +%Y-%m-%dT%H:%M:%S%z | sed 's/\(..\)$/:\1/')" \
  --argjson budget "$BUDGET" \
  --argjson count "$JUDGE_COUNT" \
  --argjson total "$JUDGE_TOTAL" \
  --argjson blocked "$JUDGE_BLOCKED" \
  --argjson over "$OVER" \
  --argjson degraded "$DEGRADED" \
  --argjson groups "$GROUP_JSON" \
  '{generated:$generated, budget_minutes:$budget,
    judge:{count:$count, cost_total:$total, over_budget:$over, blocked:$blocked},
    degraded:$degraded, groups:$groups}')

if [ "$TO_STDOUT" -eq 1 ]; then
  printf '%s\n' "$PENDING" | jq .
  exit 0
fi

printf '%s\n' "$PENDING" > "$PENDING_FILE"

ITEMS=$(printf '%s' "$PENDING" | jq '[.groups[].items[]] | length')
log "pending.json を生成: ${ITEMS}件 / 判断 ${JUDGE_COUNT}件 ${JUDGE_TOTAL}分（うち blocked ${JUDGE_BLOCKED}件）/ 取得失敗 ${#FAILED_REPOS[@]}リポジトリ"

# 予算に達して新規着手が止まっているのは「人間が動かないと再開しない」状態なのでイベントにする
if [ "$OVER" = "true" ]; then
  emit_event kind=budget_reached severity=action \
    title="判断キューが ${JUDGE_TOTAL}分（予算 ${BUDGET}分）に達したため、新規 PR の生産を止めています" \
    count="$JUDGE_COUNT" cost_total="$JUDGE_TOTAL" budget="$BUDGET"
fi

if [ "${#FAILED_REPOS[@]}" -gt 0 ]; then
  emit_event kind=job_failed severity=error \
    title="GitHub API から取得できなかったリポジトリがあります: ${FAILED_REPOS[*]}（件数は実際より少なく出ています）" \
    repos="${FAILED_REPOS[*]}"
fi

emit_event kind=job_finished severity=info \
  summary="pending ${ITEMS}件 / 判断 ${JUDGE_COUNT}件 ${JUDGE_TOTAL}分"

log "=== Finished ==="
