# 外部サービスの一気通貫セットアップ（Firebase / RevenueCat / AdMob / Vercel）

方針: **API・CLI で自動化できるものは kickoff がその場でやり、できないものは「迷わず実行できる
粒度のチェックリスト」として Slack に送る**。すべて冪等（既存があれば作らずスキップ）。
シークレット実値はこのリポジトリに書かず、`~/dev/others/claude-cron/.env` を参照する。

## 命名規約（先に決めておくと URL が予告できる）

| もの | 規約 |
|---|---|
| Firebase プロジェクト ID | `{slug}-app` |
| Vercel の LP プロジェクト名 | `{slug}-lp` → URL は `https://{slug}-lp.vercel.app` |
| 利用規約 / プライバシーポリシー | `https://{slug}-lp.vercel.app/terms` / `/privacy`（設定画面 issue とストア提出が参照） |

## Firebase（Analytics / Crashlytics）— CLI で自動化

前提: `firebase login` 済み（`firebase projects:list` で確認。未認証ならチェックリスト行き）。

```bash
firebase projects:create {slug}-app --display-name "{AppName}"
firebase apps:create ios "{AppName}" --bundle-id com.kojobarbie.{slug} --project {slug}-app
# 出力された App ID で設定ファイルを取得し、Xcode ターゲット直下に配置
firebase apps:sdkconfig ios <APP_ID> --project {slug}-app > {AppName}/GoogleService-Info.plist
```

- `GoogleService-Info.plist` はアプリリポジトリ（private）にコミットしてよい（クライアント用の公開前提キー）
- SDK 導入・初期化・イベント実装は「計測実装」issue の作業。kickoff はプロジェクト作成と plist 配置まで
- **人力に残るもの**（計測 issue のチェックリストに含める）: Analytics の BigQuery エクスポート有効化
  （コンソール操作）、`.env` への `analytics_env_prefix` 追記

## RevenueCat — API で自動化を試みる

`.env` の `REVENUECAT_API_KEY`（v2 secret key）があれば API v2 で:

```bash
curl -s -X POST https://api.revenuecat.com/v2/projects \
  -H "Authorization: Bearer $REVENUECAT_API_KEY" -H "Content-Type: application/json" \
  -d '{"name": "{AppName}"}'
curl -s -X POST https://api.revenuecat.com/v2/projects/<PROJECT_ID>/apps \
  -H "Authorization: Bearer $REVENUECAT_API_KEY" -H "Content-Type: application/json" \
  -d '{"name": "{AppName}", "type": "app_store", "bundle_id": "com.kojobarbie.{slug}"}'
```

- 作成できたら public API key を取得し、**ペイウォール issue の本文に記載**（public key は公開可能な値。
  ただしコードでは設定ファイル1箇所に集約する、と issue に書く）
- portfolio.yml の `revenuecat_project` にプロジェクト ID を記入
- API が使えない/権限不足 → チェックリスト行き（ダッシュボードで2分: プロジェクト作成 → iOS アプリ追加 → public key を控える）

## AdMob — アプリ作成 API が存在しないため人力（5分）

AdMob API はレポート専用でアプリ登録はできない。チェックリストに以下を入れる:

```
☐ AdMob コンソールで「アプリを追加」（iOS・ストア未掲載として登録）→ アプリID (ca-app-pub-…~…) を控える
☐ PRD の収益化方針に沿って広告ユニットを作成（例: バナー1本）
☐ アプリ設定 > app-ads.txt の案内に従い、デベロッパーサイトとして https://{slug}-lp.vercel.app を登録
☐ 控えたアプリIDを広告実装 issue にコメントで貼る（Info.plist の GADApplicationIdentifier に使う）
```

- `app-ads.txt` は LP に**自動配置済み**（`.env` の `ADMOB_PUBLISHER_ID` から生成:
  `google.com, {ADMOB_PUBLISHER_ID}, DIRECT, f08c47fec0942fa0`）。AdMob のクロール反映は最大24時間
- `ADMOB_PUBLISHER_ID` が `.env` に無い場合は app-ads.txt をプレースホルダーで置き、チェックリストに追記依頼を入れる

## Vercel（LP の公開）— CLI で自動化を試みる

```bash
cd ~/dev/swift/{AppName}/lp
vercel link --yes --project {slug}-lp && vercel git connect   # 認証済みなら通る
vercel deploy --prod --yes                                     # 初回デプロイ
```

- 失敗しても止めない。手動フォールバックをチェックリストへ:
  `☐ vercel.com で {AppName} リポジトリを import（プロジェクト名 {slug}-lp・Root Directory=lp）`
- 接続確認: `https://{slug}-lp.vercel.app/app-ads.txt` が 200 を返すこと（広告実装 issue の受け入れ条件にも入れる）
