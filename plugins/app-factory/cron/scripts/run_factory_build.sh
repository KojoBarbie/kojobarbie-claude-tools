#!/bin/bash
# App Factory: factory-build — 8時間ごと（5:00 / 13:00 / 21:00）
# ポートフォリオ全体から着手可能な issue を選び、自律実装 → PR → 条件付き auto-merge
# launchd (com.claude.factory-build) から呼び出される
# bash 事前判定: 対象ステージのアプリが1つも無ければ claude を起動しない
#
# ⚠️ このジョブは通知しない。起きたことは data/events.jsonl に落ちるので、
#    誰にどう知らせるかは利用者の受け手が決める（docs/events.md）。

set -euo pipefail

CONFIG_FILE="$HOME/.config/app-factory/config.env"
[ -f "$CONFIG_FILE" ] && . "$CONFIG_FILE"
PROJECT_DIR="${APP_FACTORY_HOME:-$HOME/dev/business/claude-cron}"
APPS_FILE="$PROJECT_DIR/data/factory_apps.tsv"
LOG_FILE="$PROJECT_DIR/logs/factory_build.log"
CLAUDE="${CLAUDE_BIN:-$HOME/.nodebrew/current/bin/claude}"

HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
. "$HERE/lib/events.sh"
EVENT_JOB="factory-build"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"; }

set -a
source "$PROJECT_DIR/.env"
set +a

log "=== Starting factory build ==="
# ジョブが起動したこと自体の記録。これが無いと「起動すらしなかった」失敗を
# 受け手が検知できない（job_failed は走って失敗した場合しか出ない）
emit_event kind=job_started severity=info

# 事前判定: portfolio-review が生成する factory_apps.tsv に対象ステージのアプリがあるか
# （列: name \t path \t owner/repo \t stage）
if [ ! -s "$APPS_FILE" ]; then
  log "factory_apps.tsv が無い/空。portfolio-review が未実行のためスキップ"
  emit_event kind=job_skipped severity=info \
    title="factory_apps.tsv が無い/空のためスキップ（portfolio-review が未実行）" \
    reason=no_apps_file
  exit 0
fi
if ! awk -F'\t' '$4=="building" || $4=="growing" || $4=="validating" {found=1} END {exit !found}' "$APPS_FILE"; then
  log "対象ステージ（building/growing/validating）のアプリなし。スキップ"
  emit_event kind=job_skipped severity=info \
    title="対象ステージ（building/growing/validating）のアプリが無いためスキップ" \
    reason=no_target_stage
  exit 0
fi

cd "$PROJECT_DIR"
if ! $CLAUDE -p --permission-mode bypassPermissions \
  --append-system-prompt "作業ディレクトリは ${PROJECT_DIR} です。これは launchd による無人実行（App Factory の factory-build、8時間ごと・1日3回）です。" \
  << 'PROMPT' >> "$LOG_FILE" 2>&1
app-factory:factory-build スキルを最初から最後まで実行してください。

- 安全レールを厳守すること（1回最大3 issue かつ同一アプリからは最大1 issue、
  open PR が10本以上のリポジトリには新規 PR を出さない（滞留ガード）、
  回収マージも1アプリ1回1変更まで、auto-merge はスイッチと全条件を満たすときだけ、
  センシティブ領域の除外、factory-wip での排他、使い捨て worktree での作業）
- 前回持ち越した factory/ ブランチの open PR の回収を先に行うこと
- **通知は一切しないこと。Slack にも他のどこにも投稿しない。**
  起きたことは scripts/lib/events.sh の emit_event で data/events.jsonl に追記する
  （ステップ4の報告を参照。触れた PR は1本残らず URL 付きで1件1イベント）
- 無人実行なのでユーザーへの質問はしないこと。判断できない issue は needs-clarification で人間に回すこと
PROMPT
then
  log "ERROR: claude 実行が非ゼロ終了"
  emit_event kind=job_failed severity=error \
    title="factory-build の実行が失敗しました。logs/factory_build.log を確認してください" \
    log="$LOG_FILE"
  exit 0
fi

emit_event kind=job_finished severity=info
log "=== Finished ==="
