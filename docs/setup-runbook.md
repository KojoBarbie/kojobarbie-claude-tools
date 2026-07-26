# App Factory セットアップ & 運用ランブック

セットアップに必要なもの・初回チェックリスト・恒常的に残る人力作業を1枚に集約したもの。
設計の背景は [app-factory.md](app-factory.md)、cron の詳細は
[plugins/app-factory/cron/README.md](../plugins/app-factory/cron/README.md) を参照。

## 0. 環境設定（`~/.config/app-factory/config.env`）

App Factory の環境依存パスはすべてこのファイルに集約されている。**`cron/install.sh` が
テンプレート（`plugins/app-factory/assets/config.env.template`）から自動生成**するので、
自分の環境に合わせて値を編集する（デフォルトのままなら編集不要）。全ての cron ジョブと
スキルが最初にこれを読む。シークレット（webhook・API キー）はここではなく
`$APP_FACTORY_HOME/.env` に置く（§2）。

| 変数 | 意味 | デフォルト |
|---|---|---|
| `APP_FACTORY_HOME` | ジョブ実行環境。`.env`・`data/`・`logs/` の置き場所 | `$HOME/dev/others/claude-cron` |
| `PRD_VAULT_DIR` | PRD・portfolio.yml・showcase を置くリポジトリ（private 推奨） | `$HOME/dev/prd-vault` |
| `GITHUB_OWNER` | アプリリポジトリの GitHub owner | `KojoBarbie` |
| `BUNDLE_ID_PREFIX` | 新規アプリの Bundle ID プレフィックス | `com.kojobarbie` |
| `APPS_DIR` | 新規アプリ（Xcode プロジェクト）の生成先 | `$HOME/dev/swift` |
| `CLAUDE_BIN` | claude CLI のパス（launchd から PATH が引けないため明示） | `$HOME/.nodebrew/current/bin/claude` |

以降の本文では `$APP_FACTORY_HOME` 等の変数名で参照する。

## 1. 前提ツール（インストール済みであること）

| ツール | 用途 | 確認コマンド |
|---|---|---|
| GitHub CLI `gh`（認証済み） | 全スキルの issue/PR 操作 | `gh auth status` |
| `jq` | cron スクリプトの JSON 判定 | `jq --version` |
| Claude Code CLI | 全ジョブの実行本体（launchd が `$CLAUDE_BIN` を参照） | `claude --version` |
| Xcode + XcodeGen | app-kickoff のプロジェクト生成・ビルド確認 | `xcodegen --version` |
| Node.js | showcase（Next.js）・LP（Vite）のビルド | `node --version` |
| Firebase CLI（`firebase login` 済み） | kickoff の Firebase プロジェクト作成 + LP / showcase の Hosting デプロイ | `firebase projects:list` |
| ジョブ実行環境の `.venv`（pyjwt / cryptography / requests） | ASC API（asc_cloud.py） | `$APP_FACTORY_HOME/.venv/bin/python3 -c "import jwt"` |
| `fvm`（Flutter アプリを対象にする場合のみ） | Flutter 系の監査・テスト | `fvm --version` |

## 2. `.env` に必要なキー（`$APP_FACTORY_HOME/.env`）

⚠️ 実値は `.env` のみに置く。このリポジトリはパブリックなので絶対にコミットしない。

| キー | 用途 | 必須 |
|---|---|---|
| `SLACK_WEBHOOK_URL` | デフォルト通知チャンネル | ✅ |
| `SLACK_WEBHOOK_URL_PRD` | PRD・キックオフ・リリース系通知 | ✅ |
| `APP_STORE_KEY_ID` / `APP_STORE_ISSUER_ID` / `APP_STORE_P8_KEY` | ASC API（Bundle ID 登録・Xcode Cloud・ストア提出）。鍵は .p8 の中身を literal `\n` で格納 | ✅ |
| `APPLE_TEAM_ID` | app-kickoff のプロジェクト生成（テンプレートから Team ID を排除したため） | ✅ |
| `SLACK_WEBHOOK_URL_FEATURE` | 機能提案系の専用チャンネル | 任意（無ければデフォルトへ） |
| `SLACK_WEBHOOK_URL_FACTORY` | factory-build / portfolio-review 系の専用チャンネル | 任意（同上） |
| `SUPPORT_EMAIL` | 各アプリの設定画面と LP の問い合わせ先 | ✅ |
| `STORE_COPYRIGHT_HOLDER` | ストア提出の著作権表記に使う著作権者名（例: `KojoBarbie`）。store-release が `<西暦> <この値>` を `copyright.txt` に生成 | 任意（無ければ `GITHUB_OWNER` を使う） |
| `ADMOB_PUBLISHER_ID` | LP の app-ads.txt 生成（`pub-…`。app-ads.txt 上で公開される値） | ✅（広告収益化するなら） |
| `REVENUECAT_API_KEY` | 収益計測（portfolio-review）+ kickoff のプロジェクト自動作成 | 任意（無ければ収益は未計測扱い・作成は人力） |
| GA / BigQuery のサービスアカウント認証 | Firebase Analytics 計測（firebase-bigquery スキル） | 任意（アプリごとの `analytics_env_prefix` とセット） |
| `ADMOB_CLIENT_ID` / `ADMOB_CLIENT_SECRET` / `ADMOB_REFRESH_TOKEN` | 広告収益の週次計測（AdMob API はレポート専用 OAuth。初回に同意フロー1回） | 任意（無ければ広告収益は未計測扱い） |

## 3. 初回セットアップ チェックリスト（1回だけ）

上から順に。所要 30分程度（showcase の Firebase Hosting 接続含む）。

- [ ] 1. プラグイン更新: `/plugin marketplace update kojobarbie-tools` → `/plugin install app-factory@kojobarbie-tools`
- [ ] 2. **ホームスキルの削除**（プラグイン版と重複すると自動トリガーが競合する）:
  `rm -rf ~/.claude/skills/{app-idea-hunt,app-kickoff,feature-hunt,xcode-cloud-setup}`
- [ ] 3. `run_prd_approval_check.sh` の `ASC_CLOUD` パスをプラグイン内解決に修正
  （手順: [cron/README.md](../plugins/app-factory/cron/README.md) の「ホームスキルからの移行」）
- [ ] 4. `.env` に `APPLE_TEAM_ID` を追加（§2 の任意キーもこのタイミングで）
- [ ] 5. 定期実行の配備: `plugins/app-factory/cron/install.sh`（まず `--dry-run` で確認推奨）
- [ ] 6. **portfolio-review を1回対話実行**して portfolio.yml のブートストラップ内容
  （アプリ一覧・ステージ推定）を確認: `cd "$APP_FACTORY_HOME" && claude "app-factory:portfolio-review を実行して"`
- [ ] 7. **showcase の Firebase Hosting 接続**: 初回の app-idea-hunt 実行後、prd-vault 専用の
  Firebase プロジェクトを作成（`firebase projects:create pv-showcase-{ランダム}`）し
  `cd showcase && npm run build && firebase deploy --only hosting`（プロジェクト ID を推測されにくく）
- [ ] 8. 1〜2週様子を見て問題なければ:
  - [ ] auto-merge 解禁: `touch "$APP_FACTORY_HOME"/data/factory_automerge_enabled`
  - [ ] 旧ジョブの置き換え: `install.sh --migrate`（feature-hunt 一括・アプリ別 audit 3本を無効化）

## 4. 恒常的に残る人力作業（週30分想定）

自動化の設計上、**意図的に**残しているもの。何もしなくてもサイクルは止まらない（デフォルト動作が決まっている）。

| タイミング | やること | 放置した場合のデフォルト |
|---|---|---|
| 月〜（PRD PR が来たら） | prd-vault の PR をマージ / クローズ / コメント。見るのは「ジョブ分析が信じられるか」「KPI に具体的数値と根拠があるか」「showcase のモック/トンマナ」 | 新規アプリが生まれない（既存は回り続ける） |
| 随時（提案 issue が来たら） | `feature-proposal` に 👍 / `go` または close | 提案が溜まる（6件超で新規提案は自動休止） |
| キックオフ直後 | **ASC でアプリレコード作成 + Xcode Cloud 初回オンボーディング + AdMob アプリ追加（計10分）**。Firebase / RevenueCat / LP の Firebase Hosting は自動（失敗時のみフォールバック手順が Slack に届く） | そのアプリのリリース・広告収益化が進まない（3日ごとにリマインド） |
| リリース前（1回/アプリ） | スクリーンショットを `docs/store-assets/` に置く | 提出が保留される（Slack で1回だけ依頼が来る） |
| アプリ初回提出時（1回/アプリ） | store-release が提出直前で止まるので、ASC で内容確認して提出（or「提出して」と指示） | 提出されないまま待機 |
| 提出承認の通知が来たら | release-train issue の内容（メタデータ・スクショ・著作権・カテゴリ・バージョン）を確認し、よければ `approved` ラベル or 👍。延期は `hold`、やめるなら close | **提出されない**（承認しない限り待機） |
| 金 | 週報を読む。「要判断」があれば返信 | 保守的側（現状維持）に倒れる |
| 随時 | App Review リジェクトへの対応（自動再提出はしない） | そのアプリのリリースが止まる |

## 5. アプリ1本あたりの人力ポイント（時系列まとめ）

```
PRD レビュー（PR 1本: ジョブ分析・KPI・モック/トンマナ）→ マージ
  └ キックオフ後: ASC レコード + Xcode Cloud オンボーディング（5分）
      └ 開発中: なし（factory-build が無人実装。条件外の PR だけレビュー）
          └ リリース前: スクショ配置 + 初回提出の併走（2回目以降は不要）
              └ リリース後: なし（リジェクト時のみ対応）
```

## 6. 未実装・将来課題（記録）

- **スクリーンショット自動撮影**（simctl でのスクショ→フレーム合成）— 現状最大の人手。次の拡張候補
- **トークン消費の台帳**: 方針決定済み・未実装（cron ランナー共通ラッパーで `claude -p --output-format json`
  の usage を `logs/token_ledger.tsv` に記録 → portfolio-review が週報でアプリ別 ROI 集計）
- **旧 cron スクリプトのリポジトリ取り込み**: run_app_idea_hunt.sh / run_prd_approval_check.sh /
  run_daily_report.sh 等はまだジョブ実行環境（`$APP_FACTORY_HOME`。作者環境）にしか実体がない
  （version 管理外）。cron/ に取り込んで install.sh 配備方式に統一する
- **store-release の実運用検証**: まだ1本も流していない。最初の1本は人間併走で ASC API の落とし穴を潰す
- **prd-vault の PRD テンプレート更新**: スキルは references/prd-sections.md で自給できるが、
  テンプレート本体への反映は初回実行時に1回だけ提案される
- **既存の日次分析スキル群との整理**: ジョブ実行環境（`$APP_FACTORY_HOME`。作者環境）には `daily-app-report`（毎日10:30、ストアCVR +
  オンボーディングファネル + DAU/MAU を Slack 投稿）とその部品 `app-store-analytics` /
  `firebase-bigquery` が既にある。portfolio-review はこの部品2つを週次で再利用する設計。
  daily-app-report（日次・現状把握用）と週報（週次・意思決定用）は役割が違うので当面併存でよいが、
  対象アプリが増えたら daily 側も portfolio.yml 連動に寄せる
- **統合ダッシュボード構想（別リポジトリ・private）**: 収益（RevenueCat + AdMob）・アナリティクス
  （DAU/ファネル）・トークン消費（token_ledger）を1画面で見る Web ダッシュボード。
  データは既に集まる場所が決まっている（portfolio.yml = prd-vault、token_ledger.tsv と
  dispatch 履歴 = ジョブ実行環境 `$APP_FACTORY_HOME`）ので、実装は「週次ジョブが JSON スナップショットをダッシュボード
  リポジトリにコミット → Next.js 静的エクスポート → Firebase Hosting（Firebase Auth でアクセス保護）」が最小構成。
  週報（Slack・プッシュ型）とダッシュボード（プル型・時系列）の関係は補完
