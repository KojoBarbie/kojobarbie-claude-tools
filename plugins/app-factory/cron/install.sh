#!/bin/bash
# App Factory 定期実行ジョブのインストーラ
#
# やること:
#   1. run スクリプト一式をジョブ実行環境（$APP_FACTORY_HOME）の scripts/ にコピー（既存ファイルは .bak 退避）
#   2. launchd plist を「このスクリプトが $HOME から生成して」~/Library/LaunchAgents/ に配備・load
#      （リポジトリはパブリックのため、ユーザー固有の絶対パスを含む plist はリポジトリに置かない）
#   3. 必要なディレクトリ（data/ logs/）を作成
#
# オプション:
#   --migrate      旧方式のジョブ（feature-hunt 一括 / アプリ別 audit 3本）を unload して
#                  .disabled にリネームする（factory-dispatch への移行。Phase 2 以降で使う）
#   --dry-run      何をするか表示するだけで実行しない
#
# インストール後の手順は末尾に表示される。

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
AGENTS_DIR="$HOME/Library/LaunchAgents"

# == 0/3 環境設定（~/.config/app-factory/config.env）==
# 全ジョブ・スキルが最初に読む設定ファイル。無ければテンプレートから生成する。
CONFIG_DIR="$HOME/.config/app-factory"
CONFIG_FILE="$CONFIG_DIR/config.env"
if [ ! -f "$CONFIG_FILE" ]; then
  mkdir -p "$CONFIG_DIR"
  cp "$HERE/../assets/config.env.template" "$CONFIG_FILE"
  echo "== 0/3 設定ファイルを生成しました: $CONFIG_FILE =="
  echo "   デフォルト値のまま進めます。他の環境で使う場合は先に編集して再実行してください。"
else
  echo "== 0/3 設定ファイルを使用: $CONFIG_FILE =="
fi
# shellcheck disable=SC1090
. "$CONFIG_FILE"
CRON_DIR="${CRON_DIR:-${APP_FACTORY_HOME:-$HOME/dev/others/claude-cron}}"
CLAUDE_BIN="${CLAUDE_BIN:-$HOME/.nodebrew/current/bin/claude}"

SCRIPTS=(run_portfolio_review.sh run_factory_build.sh run_factory_dispatch.sh run_store_release.sh run_factory_reminder.sh run_design_vault.sh)
LEGACY=(com.claude.feature-hunt.plist com.claude.antiscroll-audit.plist com.claude.tomarigi-audit.plist com.claude.daymarks-audit.plist)

DRY=0
MIGRATE=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY=1 ;;
    --migrate) MIGRATE=1 ;;
    *) echo "不明なオプション: $arg"; exit 1 ;;
  esac
done

run() {
  if [ "$DRY" -eq 1 ]; then echo "[dry-run] $*"; else "$@"; fi
}

if [ ! -d "$CRON_DIR" ]; then
  echo "ERROR: ジョブ実行環境が見つかりません: $CRON_DIR （config.env の APP_FACTORY_HOME か CRON_DIR 環境変数で変更可）"
  exit 1
fi
if [ ! -f "$CRON_DIR/.env" ]; then
  echo "WARNING: $CRON_DIR/.env がありません。ジョブは .env を前提とします"
fi

echo "== 1/3 run スクリプトを配備 =="
run mkdir -p "$CRON_DIR/scripts" "$CRON_DIR/data" "$CRON_DIR/logs"
for s in "${SCRIPTS[@]}"; do
  dst="$CRON_DIR/scripts/$s"
  if [ -f "$dst" ] && ! cmp -s "$HERE/scripts/$s" "$dst"; then
    run cp "$dst" "$dst.bak"
    echo "  $s: 既存を $s.bak に退避"
  fi
  run cp "$HERE/scripts/$s" "$dst"
  run chmod +x "$dst"
  echo "  $s → $dst"
done

echo "== 2/3 launchd plist を生成して配備 =="
# StartCalendarInterval の中身を各ジョブごとに定義し、共通スケルトンに埋め込んで生成する
gen_plist() {
  local label="$1" script="$2" cal="$3"
  local dst="$AGENTS_DIR/$label.plist"
  local logname="${label#com.claude.}"
  if [ "$DRY" -eq 1 ]; then echo "[dry-run] generate $dst"; return; fi
  launchctl unload "$dst" 2>/dev/null || true
  cat > "$dst" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${label}</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>${CRON_DIR}/scripts/${script}</string>
    </array>
${cal}
    <key>StandardOutPath</key>
    <string>${CRON_DIR}/logs/${logname}_launchd.log</string>
    <key>StandardErrorPath</key>
    <string>${CRON_DIR}/logs/${logname}_launchd.log</string>
    <key>WorkingDirectory</key>
    <string>${CRON_DIR}</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>$(dirname "$CLAUDE_BIN"):/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
        <key>HOME</key>
        <string>${HOME}</string>
    </dict>
</dict>
</plist>
PLIST
  plutil -lint "$dst" > /dev/null
  launchctl load "$dst"
  echo "  $label → 生成 + load 済み"
}

CAL_BUILD='    <key>StartCalendarInterval</key>
    <array>
        <dict><key>Hour</key><integer>5</integer><key>Minute</key><integer>0</integer></dict>
        <dict><key>Hour</key><integer>13</integer><key>Minute</key><integer>0</integer></dict>
        <dict><key>Hour</key><integer>21</integer><key>Minute</key><integer>0</integer></dict>
    </array>'
CAL_DISPATCH='    <key>StartCalendarInterval</key>
    <array>
        <dict><key>Weekday</key><integer>1</integer><key>Hour</key><integer>3</integer><key>Minute</key><integer>0</integer></dict>
        <dict><key>Weekday</key><integer>2</integer><key>Hour</key><integer>3</integer><key>Minute</key><integer>0</integer></dict>
        <dict><key>Weekday</key><integer>3</integer><key>Hour</key><integer>3</integer><key>Minute</key><integer>0</integer></dict>
        <dict><key>Weekday</key><integer>4</integer><key>Hour</key><integer>3</integer><key>Minute</key><integer>0</integer></dict>
        <dict><key>Weekday</key><integer>5</integer><key>Hour</key><integer>3</integer><key>Minute</key><integer>0</integer></dict>
    </array>'
CAL_STORE='    <key>StartCalendarInterval</key>
    <dict><key>Hour</key><integer>6</integer><key>Minute</key><integer>0</integer></dict>'
CAL_REVIEW='    <key>StartCalendarInterval</key>
    <dict><key>Weekday</key><integer>5</integer><key>Hour</key><integer>17</integer><key>Minute</key><integer>0</integer></dict>'
CAL_REMINDER='    <key>StartCalendarInterval</key>
    <dict><key>Hour</key><integer>12</integer><key>Minute</key><integer>0</integer></dict>'
CAL_DESIGN='    <key>StartCalendarInterval</key>
    <dict><key>Hour</key><integer>4</integer><key>Minute</key><integer>0</integer></dict>'

gen_plist com.claude.factory-build     run_factory_build.sh     "$CAL_BUILD"
gen_plist com.claude.factory-dispatch  run_factory_dispatch.sh  "$CAL_DISPATCH"
gen_plist com.claude.store-release     run_store_release.sh     "$CAL_STORE"
gen_plist com.claude.portfolio-review  run_portfolio_review.sh  "$CAL_REVIEW"
gen_plist com.claude.factory-reminder  run_factory_reminder.sh  "$CAL_REMINDER"
gen_plist com.claude.design-vault      run_design_vault.sh      "$CAL_DESIGN"

if [ "$MIGRATE" -eq 1 ]; then
  echo "== 3/3 旧ジョブを無効化（--migrate）=="
  for p in "${LEGACY[@]}"; do
    src="$AGENTS_DIR/$p"
    if [ -f "$src" ]; then
      run launchctl unload "$src" 2>/dev/null || true
      run mv "$src" "$src.disabled"
      echo "  $p → unload + .disabled（元に戻すには mv して launchctl load）"
    fi
  done
else
  echo "== 3/3 旧ジョブはそのまま（移行時に --migrate を付けて再実行）=="
fi

cat <<NEXT

インストール完了。次の手順:

1. 初回ブートストラップ（portfolio.yml と割当表を作る）:
     cd $CRON_DIR && claude "app-factory:portfolio-review を実行して"
   対話で実行し、アプリ一覧とステージの推定が正しいか確認するのを推奨。

2. .env（$CRON_DIR/.env）に追加:
     APPLE_TEAM_ID=XXXXXXXXXX        # 必須: app-kickoff のプロジェクト生成が使う（公開リポジトリに置かないため）
     SLACK_WEBHOOK_URL_FACTORY=...   # 任意: factory 系通知の専用チャンネル（無ければ SLACK_WEBHOOK_URL に流れる）
     REVENUECAT_API_KEY=...          # 任意: 収益計測を有効化する場合
     SLACK_DESIGN_CHANNEL_ID=C0XXX   # 任意: design-vault の収集チャンネル。未設定なら日次ジョブは何もしない

   design-vault を使うには、Slack でデザイン収集用チャンネルを作り /invite @<bot名> して、
   そのチャンネル ID を上記に設定する（Slack App の設定変更は不要 — 既存 bot が必要スコープを保有済み）。
   以後、スクショをそのチャンネルに投げるだけで毎日 4:00 に取り込み・分析される。

3. factory-build の auto-merge は初期状態で OFF（PR 作成まで）。
   1〜2週様子を見て問題なければ ON にする:
     touch $CRON_DIR/data/factory_automerge_enabled

4. 旧ジョブ（feature-hunt 一括 / アプリ別 audit）から移行する準備ができたら:
     ./install.sh --migrate
NEXT
