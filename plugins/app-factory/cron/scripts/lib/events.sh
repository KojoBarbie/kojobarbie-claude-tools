#!/bin/bash
# App Factory: イベント追記ヘルパー
#
# 仕様は docs/events.md。このリポジトリは通知を持たず、起きたことを
# $APP_FACTORY_HOME/data/events.jsonl に追記するところまでが責務。
#
# 使い方:
#   . "$(dirname "$0")/lib/events.sh"
#   EVENT_JOB=factory-build
#   emit_event kind=job_started severity=info
#   emit_event kind=pr_opened severity=action app=AntiScroll \
#     title="シールド画面の初期表示を短縮" url="https://github.com/…/pull/212" issue=190 cost=5
#
# 予約キー: kind severity app title url job
# それ以外の key=value は全て meta に入る（値は文字列として保存される）。
#
# 依存: jq（JSON のエスケープと UTF-8 の切り詰めを自前でやらないため）

# 呼び出し側が set -u でも壊れないようにデフォルトを置く
EVENTS_FILE="${EVENTS_FILE:-${APP_FACTORY_HOME:-$HOME/dev/business/claude-cron}/data/events.jsonl}"

# docs/events.md の表と同期させること。ここに無い kind は警告を出すが、
# イベント自体は握り潰さずに書く（記録を失うほうが有害なため）。
EVENT_KINDS="job_started job_finished job_failed job_skipped pr_opened pr_merged pr_closed comment_answered blocked needs_input human_task budget_reached proposal_opened release_prepared release_submitted review_passed review_rejected report"
EVENT_SEVERITIES="info action error"

# 1行が 4096 バイト（PIPE_BUF）を超えると O_APPEND の追記が分断されうる。
# 並行実行（factory-build ×3枠 と factory-dispatch）で行が混ざらないよう、
# 文字数と最終的なバイト長の両方で上限をかける。ロックを持たないのはこのため。
#
# 切り詰めは必ず jq の `.[0:N]`（コードポイント単位）で行う。
# bash の ${v:0:N} や cut -c は macOS のロケール次第でバイト単位になり、
# 多バイト文字を途中で割って不正な UTF-8 を吐きうる。
EVENT_MAX_TEXT=300      # title / app など表示用文字列の上限（文字）
EVENT_MAX_META=200      # meta の各値の上限（文字）
EVENT_MAX_BYTES=4000    # 1行の上限（バイト）。超えたら meta を落として作り直す

emit_event() {
  local kind="" severity="" app="" title="" url="" job="${EVENT_JOB:-unknown}"
  local meta='{}' warns=""
  local kv k v line

  for kv in "$@"; do
    case "$kv" in
      *=*) k="${kv%%=*}"; v="${kv#*=}" ;;
      *) warns="${warns}key=value 形式でない引数: '$kv' / "; continue ;;
    esac
    case "$k" in
      kind)     kind="$v" ;;
      severity) severity="$v" ;;
      app)      app="$v" ;;
      title)    title="$v" ;;
      url)      url="$v" ;;
      job)      job="$v" ;;
      *) meta="$(printf '%s' "$meta" \
           | jq -c --arg k "$k" --arg v "$v" --argjson n "$EVENT_MAX_META" \
               '. + {($k): ($v | if length > $n then .[0:$n] + "…" else . end)}')" ;;
    esac
  done

  # 語彙チェック。落とさずに書いたうえで stderr に出す（無人実行ではログに残る）。
  # kind と severity の両方が不正なこともあるので、警告は積み上げて一度に出す
  case " $EVENT_KINDS " in
    *" $kind "*) ;;
    *) warns="${warns}未知の kind: '$kind'（docs/events.md の表に追加が必要） / " ;;
  esac
  case " $EVENT_SEVERITIES " in
    *" $severity "*) ;;
    *) warns="${warns}未知の severity: '$severity'（info / action / error のみ） / " ;;
  esac
  [ -n "$warns" ] && echo "emit_event: ${warns% / }" >&2

  mkdir -p "$(dirname "$EVENTS_FILE")"

  # date の %z は +0900 を返すので、RFC 3339 の +09:00 に直す
  # （コロン無しでも ISO 8601 だが、受け手のパーサを選ばせないため揃える）
  local ts
  ts="$(date +%Y-%m-%dT%H:%M:%S%z | sed 's/\(..\)$/:\1/')"

  # --arg で全部渡してエスケープを jq に任せる。空の任意フィールドはキーごと落とす
  _event_line() {
    jq -cn \
      --arg ts "$ts" --arg job "$job" --arg kind "$kind" --arg severity "$severity" \
      --arg app "$app" --arg title "$title" --arg url "$url" \
      --argjson meta "$1" --argjson n "$EVENT_MAX_TEXT" \
      'def clip: if length > $n then .[0:$n] + "…" else . end;
       {ts:$ts, job:$job, kind:$kind, severity:$severity}
       + (if $app   == "" then {} else {app:   ($app   | clip)} end)
       + (if $title == "" then {} else {title: ($title | clip)} end)
       + (if $url   == "" then {} else {url:   ($url   | clip)} end)
       + (if ($meta | length) == 0 then {} else {meta:$meta} end)'
  }

  line="$(_event_line "$meta")"

  # meta を大量に積まれると上限を超えうる。超えたら meta を捨てて追記の原子性を優先する
  # （行が分断されると JSONL 全体が読めなくなるので、失うなら meta のほうがまし）
  if [ "$(printf '%s' "$line" | wc -c)" -gt "$EVENT_MAX_BYTES" ]; then
    echo "emit_event: 1行が ${EVENT_MAX_BYTES} バイトを超えたため meta を落としました（kind=$kind）" >&2
    line="$(_event_line '{"dropped_meta":"1"}')"
  fi

  printf '%s\n' "$line" >> "$EVENTS_FILE"
  unset -f _event_line
}
