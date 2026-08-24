#!/bin/bash
# 判断ブロック（judge:v1）を扱う共通関数。
# run_pr_expiry.sh / run_factory_reminder.sh から source される。
#
# 判断ブロックの規約は kojobarbie-claude-tools の
# plugins/dev-workflow-tools/skills/ship-issue/references/judge-block.md を参照。

# gh をリトライ付きで実行し、標準出力だけを返す。
#
# GitHub API は 503（No server is currently available）を断続的に返す。実測では8リポジトリ中
# 4つが同時に失敗することもあった。リトライが無いと「取得できなかった＝0件」と区別できず、
# キュー残高が過少に見積もられて判断予算ガードが素通りしてしまう。
# 全滅した場合は非ゼロで返すので、呼び出し側は必ず終了ステータスを見ること。
gh_retry() {
  local out i
  for i in 1 2 3 4; do
    if out=$("$@" 2>/dev/null); then
      printf '%s' "$out"
      return 0
    fi
    sleep $((i * 3))
  done
  return 1
}

# ⚠️ macOS の /bin/bash は 3.2 で、全角文字を識別子の一部として読もうとする。
#    "$VAR（...）" は変数名が `VAR（` と解釈されて set -u で unbound variable になるので、
#    日本語メッセージ中の変数展開は必ず "${VAR}" とブレースで囲むこと。
#    検出: grep -nE '\$[A-Za-z_][A-Za-z0-9_]*[^\x00-\x7F]' scripts/*.sh
#
# judge:v1 ブロックから1フィールドを取り出す。$1=PR本文 $2=フィールド名
# details に畳んだ従来本文にも同名の行がありうるので、必ずブロック内に限定して読む。
judge_field() {
  printf '%s\n' "$1" | awk -v f="$2" '
    /<!--[[:space:]]*judge:v1/ { inb = 1; next }
    inb && /-->/               { exit }
    inb && $0 ~ "^" f ":"      { sub("^" f ":[[:space:]]*", ""); sub("[[:space:]]+$", ""); print; exit }
  '
}

# 「## 判断してほしいこと」直下の太字1文（ask）を取り出す。$1=PR本文
# 見出しの後の最初の **...** 行を拾い、前後の ** を落とす。
judge_ask() {
  printf '%s\n' "$1" | awk '
    /^##[[:space:]]*判断してほしいこと/ { inb = 1; next }
    inb && /^\*\*/ {
      sub(/^\*\*/, ""); sub(/\*\*[[:space:]]*$/, "")
      print; exit
    }
    inb && /^##/ { exit }
  '
}

# 種別の表示名と絵文字
judge_type_label() {
  case "$1" in
    look)   echo "👁 見るだけ" ;;
    run)    echo "📱 実機で確認" ;;
    decide) echo "🤔 あなたにしか決められない" ;;
    *)      echo "❔ 種別不明" ;;
  esac
}

# 対象リポジトリの一覧を1行1件で出力する（factory_apps.tsv のアプリ + prd-vault）
# 事前に APPS_FILE / OWNER / PRD_VAULT が設定されていること。
judge_repos() {
  if [ -s "$APPS_FILE" ]; then
    awk -F'\t' 'NF >= 3 && $1 !~ /^#/ && $1 != "" { print $3 }' "$APPS_FILE"
  fi
  echo "$OWNER/$(basename "$PRD_VAULT")"
}

# CI が green か（FAILURE 系も PENDING 系も無ければ green。チェックが1つも無い場合も green 扱い
# — PR 作成時にローカルテストが通っているのが factory-build の前提のため）
# $1=owner/repo $2=PR番号
ci_is_green() {
  local repo="$1" num="$2" states
  states=$("${GH:-gh}" pr view "$num" -R "$repo" --json statusCheckRollup \
    -q '[.statusCheckRollup[]? | (.conclusion // .state // "")] | join(",")' 2>/dev/null || echo "")
  case ",$states," in
    *FAILURE*|*ERROR*|*CANCELLED*|*TIMED_OUT*|*ACTION_REQUIRED*|*STARTUP_FAILURE*) return 1 ;;
    *PENDING*|*IN_PROGRESS*|*QUEUED*|*WAITING*|*REQUESTED*) return 1 ;;
  esac
  return 0
}

# 期限までの残り日数を「あとN日」「今日まで」「N日超過」の形で返す。$1=YYYY-MM-DD
judge_due_text() {
  local exp="$1" e t diff
  [ -z "$exp" ] && { echo ""; return; }
  e=$(date -j -f '%Y-%m-%d' "$exp" '+%s' 2>/dev/null) || { echo ""; return; }
  t=$(date -j -f '%Y-%m-%d' "$(date '+%Y-%m-%d')" '+%s')
  diff=$(( (e - t) / 86400 ))
  if   [ "$diff" -gt 0 ]; then echo "あと${diff}日"
  elif [ "$diff" -eq 0 ]; then echo "今日まで"
  else echo "$(( -diff ))日超過"
  fi
}
