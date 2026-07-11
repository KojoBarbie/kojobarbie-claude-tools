# App Factory 定期実行テンプレート

App Factory（docs/app-factory.md）の定期実行をジョブ実行環境（`$APP_FACTORY_HOME`。
デフォルト: `~/dev/others/claude-cron`）に配備するためのテンプレート一式。`./install.sh` で導入する。

## 環境設定（`~/.config/app-factory/config.env`）

環境依存の値（`APP_FACTORY_HOME` / `PRD_VAULT_DIR` / `GITHUB_OWNER` / `BUNDLE_ID_PREFIX` /
`APPS_DIR` / `CLAUDE_BIN`）はすべてこのファイルに集約されている。`install.sh` が
`assets/config.env.template` から自動生成するので、デフォルト以外の環境では値を編集してから
再実行する。全 run スクリプトとスキルが最初にこれを読む（無ければデフォルト値で動く）。
シークレットはここではなく `$APP_FACTORY_HOME/.env` に置く。

## ジョブ一覧（深夜帯中心の設計）

| 時刻 | ジョブ | claude 起動条件 |
|---|---|---|
| 毎日 5:00 / 23:00 | factory-build（issue の自律実装） | factory_apps.tsv に building/growing/validating があるときだけ |
| 平日 3:00 | factory-dispatch（feature-hunt / audit / growth-advisor を1日1リポジトリ） | 割当表に当日スロットがあるときだけ |
| 毎日 6:00 | store-release（リリース列車・veto・審査追跡） | review ステージ / open な release-train / MVP 完了 / 水曜、のいずれか |
| 毎日 12:00 | factory-reminder（人力タスクの滞留リマインド） | 起動しない（bash + gh のみ。滞留があるときだけ Slack に1通） |
| 金 17:00 | portfolio-review（計測→判定→割当表生成→週報） | 常時（週1） |

重いジョブ（実装・監査・提案）は深夜に回し、人が読む通知（veto 確認・週報）だけ
朝〜夕方に届く設計。launchd はスリープ中に時刻を過ぎた場合、次の起床時にまとめて1回実行する。

## データファイル（`$APP_FACTORY_HOME/data/`）

| ファイル | 書き手 | 読み手 | 形式 |
|---|---|---|---|
| `factory_apps.tsv` | portfolio-review | 各 run スクリプトの bash 事前判定 | `name \t path \t owner/repo \t stage` |
| `factory_schedule.tsv` | portfolio-review（毎週金曜、翌週分を生成） | factory-dispatch | `date \t app \t path \t job` |
| `factory_automerge_enabled` | 人間（`touch` で作成） | factory-build | 存在すれば auto-merge ON |
| `logs/factory_dispatch_history.tsv` | factory-dispatch | portfolio-review（last_jobs の転記元） | `date \t app \t job \t status` |

状態の本体（ステージ・KPI・メトリクス）は prd-vault/portfolio.yml。上記はその bash 用ミラーと
実行履歴で、すべて portfolio-review が毎週再生成するので壊れても週次で自己修復する。

## 導入手順

```bash
./install.sh            # 新ジョブ一式を配備（旧ジョブはそのまま）
./install.sh --dry-run  # 何が起きるか確認だけ
./install.sh --migrate  # 移行: 旧 feature-hunt 一括 / アプリ別 audit 3本を無効化
```

インストール後の初回ブートストラップ手順は install.sh が最後に表示する。

## ホームスキルからの移行（1回だけ）

app-idea-hunt / app-kickoff / feature-hunt / xcode-cloud-setup は `~/.claude/skills` から
このプラグインに移動した。プラグイン導入後に以下を行う:

1. **重複の解消**（同名スキルが2つあると自動トリガーが競合する）:
   ```bash
   rm -rf ~/.claude/skills/{app-idea-hunt,app-kickoff,feature-hunt,xcode-cloud-setup}
   ```
2. **run_prd_approval_check.sh のパス修正**: bash から直接呼んでいる asc_cloud.py の場所が変わる。
   スクリプト内の `ASC_CLOUD="$HOME/.claude/skills/xcode-cloud-setup/scripts/asc_cloud.py"` を
   次で解決するよう書き換える:
   ```bash
   ASC_CLOUD=$(find "$HOME/.claude/plugins" -path "*app-factory/skills/xcode-cloud-setup/scripts/asc_cloud.py" 2>/dev/null | head -1)
   ```
3. 既存 cron スクリプトのプロンプト内スキル名（`/app-idea-hunt` 等）は、重複解消後は
   プラグイン版が一意に解決されるためそのままでよい（明示するなら `app-factory:app-idea-hunt`）
4. **`.env` に `APPLE_TEAM_ID` を追加**: 公開リポジトリに Team ID を置かないよう
   `project.yml.template` をプレースホルダー化したため、app-kickoff のプロジェクト生成が
   `.env` の `APPLE_TEAM_ID` を必須とする

## ロールアウトとの対応（docs/app-factory.md §8）

- Phase 1: `./install.sh` → portfolio-review を1回対話実行して portfolio.yml を確認
- Phase 2: `./install.sh --migrate`（割当表方式へ移行）
- Phase 3: 1〜2週後に `touch data/factory_automerge_enabled`（auto-merge 解禁）
- Phase 4〜: store-release の初回は人間併走（スキルが提出直前で止めて案内する）
