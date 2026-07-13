# 外部サービスの一気通貫セットアップ（Firebase / RevenueCat / AdMob / LP公開）

方針: **API・CLI で自動化できるものは kickoff がその場でやり、できないものは「迷わず実行できる
粒度のチェックリスト」として Slack に送る**。すべて冪等（既存があれば作らずスキップ）。
シークレット実値はこのリポジトリに書かず、`$APP_FACTORY_HOME/.env`（デフォルト: `~/dev/others/claude-cron/.env`。`~/.config/app-factory/config.env` 参照）を参照する。

## 命名規約（先に決めておくと URL が予告できる）

| もの | 規約 |
|---|---|
| Firebase プロジェクト ID | `{slug}-app` |
| LP の Hosting サイト（同プロジェクト内） | `{slug}-lp` → URL は `https://{slug}-lp.web.app` |
| 利用規約 / プライバシーポリシー | `https://{slug}-lp.web.app/terms` / `/privacy`（設定画面 issue とストア提出が参照） |

> LP は **Vercel を使わない**（無料枠が商用利用不可のため）。アプリの Firebase プロジェクト内に
> `{slug}-lp` という Hosting サイトを追加して公開する。`.web.app` サブドメインはグローバル一意なので、
> `{slug}-lp` が取れなかった場合はサフィックスを足し、**実際に確定したサイト名（= URL のサブドメイン）を
> portfolio.yml と後続 issue に必ず反映する**（下の各所の `{slug}-lp` は確定値で読み替える）。

## Firebase（Analytics / Crashlytics）— CLI で自動化

前提: `firebase login` 済み（`firebase projects:list` で確認。未認証ならチェックリスト行き）。

```bash
firebase projects:create {slug}-app --display-name "{AppName}"
firebase apps:create ios "{AppName}" --bundle-id "${BUNDLE_ID_PREFIX}.{slug}" --project {slug}-app
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
  -d "{\"name\": \"{AppName}\", \"type\": \"app_store\", \"bundle_id\": \"${BUNDLE_ID_PREFIX}.{slug}\"}"
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
☐ アプリ設定 > app-ads.txt の案内に従い、デベロッパーサイトとして https://{slug}-lp.web.app を登録
☐ 控えたアプリIDを広告実装 issue にコメントで貼る（Info.plist の GADApplicationIdentifier に使う）
```

- `app-ads.txt` は LP に**自動配置済み**（`.env` の `ADMOB_PUBLISHER_ID` から生成:
  `google.com, {ADMOB_PUBLISHER_ID}, DIRECT, f08c47fec0942fa0`）。AdMob のクロール反映は最大24時間
- `ADMOB_PUBLISHER_ID` が `.env` に無い場合は app-ads.txt をプレースホルダーで置き、チェックリストに追記依頼を入れる

## Firebase Hosting（LP の公開）— firebase CLI で自動化

LP はアプリの Firebase プロジェクト（`{slug}-app`）内に専用の Hosting サイトを作って公開する。
Firebase セクションと同じ `firebase login` の認証をそのまま使う（Vercel CLI は不要）。

```bash
cd "$APPS_DIR"/{AppName}
firebase hosting:sites:create {slug}-lp --project {slug}-app     # → https://{slug}-lp.web.app（グローバル一意。取れなければサフィックス）
firebase target:apply hosting lp {slug}-lp --project {slug}-app  # .firebaserc に target 記録
npm --prefix lp run build                                        # lp/dist を生成
firebase deploy --only hosting:lp --project {slug}-app           # lp/dist を公開
```

リポジトリルートの `firebase.json` に hosting ターゲット `lp` を定義する（`lp/firebase.json` ではなくルートに置く）:

```json
{
  "hosting": [
    {
      "target": "lp",
      "public": "lp/dist",
      "ignore": ["firebase.json", "**/.*", "**/node_modules/**"],
      "rewrites": [{ "source": "**", "destination": "/index.html" }]
    }
  ]
}
```

- `app-ads.txt` / `terms` / `privacy` は **実ファイルが rewrite より優先**されるので、SPA fallback に食われず 200 で返る
  （`app-ads.txt` は `lp/public/` に置けばビルドで `lp/dist/` ルートに出る。`/terms` `/privacy` は SPA ルーティング）
- 失敗しても止めない。手動フォールバックをチェックリストへ:
  `☐ lp/ で npm run build 後、firebase hosting:sites:create {slug}-lp → firebase target:apply hosting lp {slug}-lp → firebase deploy --only hosting:lp`
- 接続確認: `https://{slug}-lp.web.app/app-ads.txt` が 200 を返すこと（広告実装 issue の受け入れ条件にも入れる）
