# オンボーディング — アプリをfeature-huntに追加する

対象アプリのリポジトリで一度だけ行う。成果物は次の3つ:

1. `<アプリ>/.claude/feature-hunt.yml`（設定）
2. `<アプリ>/.claude/product-context.md`（製品コンテキスト）
3. `~/dev/others/claude-cron/feature_hunt_apps.txt` への1行追記（週次実行への登録）

## 手順

### 1. アプリを理解する

README・CLAUDE.md・主要画面のコードを読み、「何のアプリで、どんな機能があるか」を掴む。App Storeにリリース済みならストア掲載文も読む。

### 2. App Store IDを特定する

Bundle ID をプロジェクトから取得（iOS: `*.xcodeproj`/`project.yml`/`Info.plist`、Flutter: `ios/Runner.xcodeproj`）し、lookup APIで引く:

```bash
curl -s "https://itunes.apple.com/lookup?bundleId=<BUNDLE_ID>&country=jp" | python3 -m json.tool
```

`resultCount: 0` なら未リリース → `app_store_id: null`（自アプリのレビュー分析はスキップされる）。

### 3. 競合を特定する

アプリの用途から検索語を2〜3語（日本語・英語）作り、検索する:

```bash
bash {skill_dir}/scripts/jp_appstore_search.sh "検索語" 10 jp
```

評価件数と最終更新日から「現役で使われている」競合を**3〜5個**選ぶ。各競合のIDで `appstore_reviews.sh <id>` を1回実行し、レビューが取得できることを確認してから設定に載せる（レビュー0件の競合は情報源にならないので外す）。

### 4. product-context.md を作る（このオンボーディングの核心）

コード・README・ストア情報から下書きを生成する。セクションは:

- **誰向けか** — 想定ユーザーと利用シーン
- **コア体験** — このアプリの価値の中心。1〜2文で
- **ビジネスモデル** — 課金形態と課金ポイント（なければ「未収益化・方針」）
- **やらないこと（non-goals）** — このアプリが意図的に持たない機能・方向性

下書きができたら:

- **対話セッションの場合**: `grill-me` スキルを使い、下書きを叩き台にユーザーをグリルして各セクションを確定させる。特に「コア体験」と「non-goals」はコードからは読み取れないので、ここで必ず本人の言葉を引き出す
- **無人実行の場合**: 下書きの冒頭に `> ⚠️ 自動生成の下書きです。次回の対話でグリルして確定してください` と付けて保存し、Slack通知に確認依頼を含める。未確定でも週次実行は止めない

### 5. feature-hunt.yml を書く

```yaml
app_name:
app_store_id:          # 未リリースなら null
country: jp
competitors:           # 3〜5個
  - id:
    name:
analytics_env_prefix:  # claude-cron/.env の変数プレフィックス。未接続なら null
```

`analytics_env_prefix` は `~/dev/others/claude-cron/.env` に `<APP名>_GCP_PROJECT_ID` が存在する場合のみ設定する（例: AntiScroll → `ANTISCROLL`）。無ければ null にして、Firebase導入済みアプリならオンボーディング報告に「BigQuery連携すればAnalytics情報源が使える」と添える。

### 6. ラベルを作る

```bash
gh label create feature-proposal --color "1D76DB" --description "feature-huntの提案" 2>/dev/null || true
gh label create feature-approved --color "0E8A16" --description "承認済み・sub-issue分割済み" 2>/dev/null || true
gh label create go --color "FBCA04" --description "この提案を承認する" 2>/dev/null || true
```

### 7. コミットして登録する

- `.claude/feature-hunt.yml` `.claude/product-context.md` をデフォルトブランチにコミット・プッシュ
- `~/dev/others/claude-cron/feature_hunt_apps.txt` に `アプリ名<TAB>絶対パス` を1行追記

### 8. 報告

対話ならチャットで、無人実行ならSlackで: 設定した競合・App Store ID・Analytics接続状況・product-contextの確定状況を報告する。
