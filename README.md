# kojobarbie-claude-tools

KojoBarbie 個人開発用の [Claude Code](https://docs.claude.com/en/docs/claude-code) プラグイン マーケットプレイス。

GitHub issue から PR・セルフレビューまでの開発ワークフローを支援するスキルをまとめている。
特定のプロジェクトに依存しないよう作ってあるので、別リポジトリにそのまま導入して使える。

## 導入

```
/plugin marketplace add KojoBarbie/kojobarbie-claude-tools
/plugin install dev-workflow-tools@kojobarbie-tools
```

- `marketplace add` は**1マシンにつき1回**でよい（登録はユーザー単位）。2つ目以降のプロジェクトでは `install` だけで済む。
- インストール後、各スキルは `/dev-workflow-tools:<skill-name>` の名前空間付きで呼べる（自動トリガーも有効）。

## 収録プラグイン

### `dev-workflow-tools`

個人開発ワークフロー用スキル集。GitHub issue/PR フロー（「アイデア → Issue 化 → 実装 → PR → セルフレビュー → 修正」）に加え、デザインレビューと画像生成のスキルを収録する。

| スキル | 役割 |
|---|---|
| **feature-planning** | ふわっとした機能アイデアを 1 問ずつ対話的に深掘りし、ユーザーストーリー＋受け入れ条件の親 Issue を作成。実装単位のサブ Issue に分割して GitHub ネイティブの sub-issue としてリンクするところまでを一気通貫で行う。 |
| **ship-issue** | GitHub issue 番号を1つ受け取り、要件読取 → プランモードでの計画承認 → 実装＋テスト → PR 作成 → サブエージェントによるレビュー（PR インラインコメント）→ 修正/返信の1往復 → 停止、までを人手最小で自走させる実装オーケストレーター。`pr-batch-review` / `pr-review-unresolved` / `pr-comment-reply` を内部で利用する。 |
| **pr-batch-review** | 複数のインラインレビューコメントを 1 つの GitHub PR レビューとしてまとめて投稿し、通知ノイズを減らす。 |
| **pr-review-unresolved** | 現在のブランチの PR から未解決のインラインレビューコメントを取得して一覧表示する。 |
| **pr-comment-reply** | comment ID を指定して、特定のインラインレビューコメントに返信を投稿する。 |

デザインレビュー系:

| スキル | 役割 |
|---|---|
| **app-design-craft** | アプリの「美学・プロダクト設計レベル」のビジュアルデザイン設計＆レビュー。引き算・余白・一貫性・トンマナで凡庸さを脱した UI を作る/見極める。iOS/SwiftUI 主対象。 |
| **ui-design-fundamentals** | ロジックに基づく UI デザインの基礎原則。スペーシング・UI 部品・アクセシビリティなど数値基準レベルの設計判断（世界観レベルは app-design-craft が担当）。 |
| **onboarding-advisor** | モバイルアプリのチュートリアル・オンボーディング UI/UX 専門アドバイザー。79 件の日英記事と統計データに基づくレビュー・改善提案・アンチパターン検出。 |

画像生成系（API キーは環境変数で設定。リポジトリに秘密情報は含まない）:

| スキル | 役割 |
|---|---|
| **nanobanana-pro** | Google Nano Banana Pro（Gemini 3 Pro Image）API による画像生成・編集。プロバイダ指定なしの画像生成リクエストのデフォルト。要 `GEMINI_API_KEY`。 |
| **gpt-image-2** | OpenAI gpt-image-2 による画像生成・編集。サイズ/アスペクト比プリセット・複数画像編集・正確なピクセルクロップ対応。「OpenAI で」と指定されたときに使用。要 `OPENAI_API_KEY`。 |

#### 標準的な使い方

1. `feature-planning` でアイデアを Issue 群に落とし込む（改善系は `quality-release-cycle`（app-factory 収録）の audit で洗い出す）
2. `ship-issue <issue番号>` で実装 → PR → セルフレビュー → 修正まで自走させる
   （`ship-issue` がレビュー投稿・未解決取得・返信に他の 3 スキルを自動で使う）
3. リリース前に `quality-release-cycle` の release で可否判定してから配信する

`quality-release-cycle` を使うリポジトリには `.claude/quality-cycle.md`（テストコマンド・リリースフロー・トラッキング Issue 番号・対応済み監査の履歴）を置くと精度が上がる。なければスキルが自動検出し、初回実行後に生成を提案する。

### `app-factory`

「①出す → ②検証・改善 → ③育てる」を人手最小で回し続ける自動アプリ工場。
アプリのライフサイクル全体のスキルをここに集約している。
全体設計は [docs/app-factory.md](docs/app-factory.md) を参照。

①出す:

| スキル | 役割 |
|---|---|
| **app-idea-hunt** | 海外市場からネタ発掘 → JTBD 分析（ジョブ分解・人気の因果・日本への移転可能性）→ KPI 設計（具体的な数値目標）→ モック/トンマナページ生成（prd-vault の showcase サイト）→ PRD を PR として提案。 |
| **app-kickoff** | マージされた PRD から開発環境を一式セットアップ（XcodeGen・GitHub リポジトリ・MVP issue（計測実装 issue 必須）・デザインシート・Bundle ID・Slack 通知）。 |
| **xcode-cloud-setup** | ASC API で TestFlight ワークフロー2本（PR / タグトリガー）を自動作成。Bundle ID 登録も担当。 |
| **factory-build** | 「手」。ポートフォリオ全体から issue を優先度順に選び、計画承認なしで実装 → PR → セルフレビュー → 条件付き auto-merge（段階導入スイッチ + 安全条件）。1回最大2件・1日2回。 |
| **store-release** | App Store 提出の自動化。MVP 完了検知 → PRD からメタデータ生成 → `release-train` issue による24時間拒否権 → ASC API で提出 → 審査追跡。初回は人間併走。 |

②検証・改善 / ③育てる:

| スキル | 役割 |
|---|---|
| **portfolio-review** | 週次の「脳」。全アプリのメトリクス（Firebase / ASC / RevenueCat）→ PRD の KPI マイルストーン（M1〜M3）でステージゲート判定 → `prd-vault/portfolio.yml` 更新 → 翌週の横断ジョブ割当表を生成 → 要判断を集約した週報を Slack に1通。 |
| **quality-release-cycle** | 品質サイクル運用。audit（4次元監査 → コード裏取り → Issue 化）/ release（リリース可否判定）/ status の3モード。 |
| **feature-hunt** | 既存アプリの新機能を週次提案。競合レビュー・コードベース・Firebase Analytics の3情報源から最大3件を Issue 化、承認（👍/go）で sub-issue に分割。 |
| **growth-advisor** | growing アプリへコード探索＋ジョブ分析＋KPI 実績から多軸グロース提案（機能/収益化/ASO/リテンション）。出力は feature-hunt と同じ承認フローに流れる。 |

- **セットアップ・必要なもの・残る人力作業の一覧**: [docs/setup-runbook.md](docs/setup-runbook.md)
- 環境設定（パス・GitHub owner・Bundle ID プレフィックス等）は `~/.config/app-factory/config.env`（`cron/install.sh` が生成。デフォルトは作者環境の値）
- 定期実行（launchd）の導入・移行は `plugins/app-factory/cron/`（深夜帯中心のスケジュール。README に移行手順）
- ⚠️ このリポジトリは**パブリック**。スキルに Slack webhook の実 URL・API キー等のシークレットを書かないこと（参照は環境変数名のみ。実値はジョブ実行環境（`$APP_FACTORY_HOME`）の `.env`）

### 前提

- [GitHub CLI (`gh`)](https://cli.github.com/) がインストール済み・認証済み（`gh auth status`）であること
- `jq` がインストール済みであること（`pr-batch-review` / app-factory の cron スクリプトが使用）

## 日常運用

- **スキルを更新**: このリポジトリで `SKILL.md` を編集して push → 利用側で `/plugin marketplace update kojobarbie-tools`
- **スキルを追加**: `plugins/dev-workflow-tools/skills/` 配下にディレクトリを追加して push するだけ
- **バージョン**: `plugin.json` に `version` を書いていないため、git のコミット SHA がバージョン扱いになり、push のたびに更新が配信される

## ライセンス / 注意

個人運用のツール集です。スクリプトは `gh` CLI の認証情報を利用しますが、リポジトリ内にトークン等の機密情報は含みません。
