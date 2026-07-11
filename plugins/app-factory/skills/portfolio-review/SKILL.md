---
name: portfolio-review
description: >
  App Factory の「脳」。全アプリのメトリクス（Firebase Analytics / ASC / RevenueCat / AdMob）を取得し、
  PRD の KPI マイルストーン（M1〜M3）に対する達成状況でステージゲートを判定、
  prd-vault/portfolio.yml を更新して、翌週の横断ジョブ割当表（factory_schedule.tsv）を生成し、
  人間の要判断事項を集約した週報を Slack に1通投稿する。
  毎週金曜 17:00 に launchd（com.claude.portfolio-review）から無人実行されるほか、
  「ポートフォリオレビューして」「週報を作って」「アプリの状況をまとめて」「ステージ判定して」
  と言われたら手動でも使う。portfolio.yml が無ければ既存資産から自動ブートストラップする。
---

# portfolio-review — 計測 → ステージ判定 → 週報

App Factory サイクルの意思決定を担う週次スキル。役割は4つ:

1. **計測**: 全アプリの KPI を実データで観測する（取れない指標は「未計測」と明示）
2. **判定**: PRD のマイルストーン（M1〜M3）とステージゲートを機械的に適用する
3. **配車**: 翌週の横断ジョブ（feature-hunt / audit / growth-advisor）を1日1リポジトリに割り当てる
4. **報告**: 人間の要判断をすべて集約した週報を Slack に1通出す

このスキルだけが portfolio.yml の `stage` を書き換えてよい（人間の手動編集は別）。

## 前提パス・環境

**最初に `~/.config/app-factory/config.env` を読み込む**（無ければ各変数は括弧内のデフォルト値を使う）。

- prd-vault: `$PRD_VAULT_DIR`（デフォルト: `~/dev/prd-vault`。リポジトリ `$GITHUB_OWNER/$(basename "$PRD_VAULT_DIR")`、状態ファイル `portfolio.yml`）
- ジョブ実行環境: `$APP_FACTORY_HOME`（デフォルト: `~/dev/others/claude-cron`。`.env`、`data/`、`logs/`。firebase-bigquery / slack-post スキルは作者環境の前提 — 無い環境では該当計測を unmeasured 扱い / curl で直接 POST）
- `.env` から読む: `SLACK_WEBHOOK_URL_FACTORY`（無ければ `SLACK_WEBHOOK_URL`）、GA/BigQuery 認証、
  `REVENUECAT_API_KEY`（未設定なら収益は未計測扱い）、`APP_STORE_*`（ASC API）

## ステップ 0: portfolio.yml の読み込み（無ければブートストラップ）

`$PRD_VAULT_DIR/portfolio.yml` を読む。**無ければ初回ブートストラップ**:

1. スキーマは `${CLAUDE_PLUGIN_ROOT}/assets/portfolio.yml.template` に従う
2. アプリの列挙: prd-vault の `prd/`・`shipped/` の PRD frontmatter（開発リポジトリ URL・キックオフ日）、
   `$APP_FACTORY_HOME/data/feature_hunt_apps.txt`、`$APPS_DIR/`（デフォルト: `~/dev/swift`。作者環境では
   `~/dev/flutter/` も）の git remote が `$GITHUB_OWNER/` のリポジトリを突き合わせる
3. 初期ステージの推定: MVP issue が open で未リリース → `building`、
   App Store 掲載済み（`asc_cloud.py status` や daily-report の対象）→ リリース日不明なら `validating` とし
   週報で人間に確認を出す。実験・旧作（git 整備が薄い）はポートフォリオに **入れない**
   （対象は App Factory で運用するアプリだけ。迷ったら週報で人間に確認）
4. 生成した portfolio.yml は prd-vault の main に直接コミット & push
   （コミットメッセージに `🤖 portfolio-review: 初回ブートストラップ` と明記）

## ステップ 1: メトリクス取得（アプリごと）

**実データのみ。推測で数字を埋めることを禁止する。** 取れない指標は `unmeasured` のまま残す。

| 指標 | 取得元 | 条件 |
|---|---|---|
| downloads_7d / ストアCVR | ASC API — `$APP_FACTORY_HOME` の **app-store-analytics** スキルを再利用（作者環境の前提。無ければ ASC API を直接叩く） | `asc_app_id` があるもの |
| dau_avg / activation_rate / d1_retention | **firebase-bigquery** スキル（`$APP_FACTORY_HOME` 内。作者環境の前提 — 無ければ unmeasured 扱い） | `analytics_env_prefix` 設定済みのもの |
| crash_free | Crashlytics（BigQuery エクスポート） | 同上 |
| revenue_7d_jpy | **RevenueCat API v2（課金）+ AdMob API（広告）の合算** | それぞれ `revenuecat_project` / `.env` の `ADMOB_*` OAuth 設定済みのもの。片方しか取れない場合は取れた分を計上し、欠けを内訳に明記 |

- 収益は必ず**内訳付き**で記録する（`revenue_7d_jpy: 1200 (iap: 800, ads: 400)` 形式）。
  課金と広告で打ち手が違うため、合算だけにしない
- AdMob API はレポート専用の OAuth（`ADMOB_CLIENT_ID` / `ADMOB_CLIENT_SECRET` / `ADMOB_REFRESH_TOKEN`）。
  未設定なら広告収益は `unmeasured`（広告実装済みのアプリでのみ計測の穴として扱う）

- activation_rate は PRD の `core_action` に対応する計測イベント（例 `core_action_completed`）の
  初回セッション完了率。イベントが実装されていなければ `unmeasured`
- `trend` は前週スナップショット（git 履歴の前回 portfolio.yml）との比較で up / flat / down
- **計測の穴は Issue にする**: `unmeasured` の原因が実装不足（イベント未実装・SDK 未導入）なら、
  対象アプリのリポジトリに `measurement` ラベルで計測実装 Issue を起票する
  （既に同ラベルの open Issue があれば起票しない。1アプリ1回の実行で最大1件）。
  この Issue は factory-build が自動で拾う

## ステップ 2: KPI 判定とステージゲート

アプリごとに、**PRD の「KPIと計測計画」セクションのマイルストーン定義を第一**に、
無ければ portfolio.yml の `gates:` を使って判定する:

- `released` からの経過週数で M1（+4週）/ M2（+8週）/ M3（+16週）の判定期日を計算
- 期日到来済みのマイルストーンを passed / failed で確定し、`kpi:` を更新
- ステージ遷移:
  - `validating → growing`: M1 かつ M2 が passed
  - `validating → maintain`: `validating_fail_weeks` 経過で M1 failed
  - `growing → maintain`: `growing_stall_weeks` の間、収益・DAU とも横ばい以下
  - `maintain → sunset`: `sunset_after_weeks` の間 DAU ほぼゼロ
  - 指標が回復していれば逆方向（maintain → growing 等）も可
- **判定に必要な指標が unmeasured のときは自動で降格しない**。「要判断」として週報に出す
  （例: 「Analytics 未接続のため M1 判定不能。接続するか、感覚で判断してください」）
- `building → review` はこのスキルでは行わない（store-release が MVP 完了検知で扱う）。
  ただし MVP issue が全て closed の building アプリを見つけたら週報で言及する

ステージを変更したら `stage_since` を更新し、変更理由を portfolio.yml のコミットメッセージに書く。

## ステップ 3: portfolio.yml の更新とコミット

- `updated`・各アプリの `metrics`・`kpi`・`stage`・`last_jobs`
  （`$APP_FACTORY_HOME/logs/factory_dispatch_history.tsv` から各ジョブの最終実行日を転記）を更新
- prd-vault の main にコミット & push。メッセージ例:
  `🤖 portfolio-review 2026-07-17: Hirune validating→growing (M1/M2達成), 3アプリ計測更新`

## ステップ 4: 翌週の割当表（factory_schedule.tsv）の生成

`$APP_FACTORY_HOME/data/factory_schedule.tsv` を**翌週分で丸ごと書き換える**（TSV は
dispatcher が bash で読むための形式。列: `日付<TAB>アプリ名<TAB>絶対パス<TAB>ジョブ`。
パスは portfolio.yml の `path` をそのまま使う）。例:

```
# App Factory 割当表（portfolio-review が毎週金曜に生成。手編集可）
# date	app	path	job   （job: audit | feature-hunt | growth-advisor）
2026-07-20	ExampleFlutterApp	~/dev/flutter/ExampleFlutterApp	audit
2026-07-21	ExampleApp	~/dev/swift/ExampleApp	feature-hunt
```

生成ルール:

- 頻度は portfolio.yml の `schedule_rules` × 各アプリの `last_jobs`（前回実行日）から
  「今週やるべきジョブ」を列挙する
- スロットは月〜金の1日1件。溢れたら優先度順（growing > validating > maintain、
  同率なら前回実行が古い順）に詰め、残りは翌週へ（次回生成時に `last_jobs` の古さで自然に優先される）
- `data/factory_apps.tsv` も同時に更新する（bash ゲート用のミラー。
  列: `アプリ名<TAB>絶対パス<TAB>owner/repo<TAB>stage`）

## ステップ 5: 週報を Slack に1通

`slack_post.py`（`$APP_FACTORY_HOME` の slack-post スキル。作者環境の前提 — 無い環境では
curl で webhook に直接 POST）で `SLACK_WEBHOOK_URL_FACTORY`
（無ければ `SLACK_WEBHOOK_URL`）へ投稿する。構成（この順で・全部入れる）:

1. **今週の動き**: 生まれた PRD / kickoff されたアプリ / マージされた PR 数 / リリース・提出
2. **アプリ別サマリ表**: name / stage / 主要指標（DL・DAU・D1・収益）/ trend / KPI 達成状況。
   unmeasured は `—` ではなく `未計測` と書く
3. **ステージ変更**: 今週の昇格・降格と理由
4. **収益と外挿**: 全アプリ収益合計（週次・月次換算）と、現在の通過率での1年後見込み。
   目標（月5〜10万円）に対するボトルネック（本数 / 通過率 / 単価）を1行で指摘
5. **要アクション（人間向け）**: 未マージの PRD PR / 未承認の feature-proposal（件数と経過日数）/
   veto ウィンドウ中の release-train / `factory-blocked` の issue / ASC・Xcode 未オンボーディング /
   スクリーンショット依頼 / 判定不能だった「要判断」項目。**それぞれ「放置した場合のデフォルト動作」を添える**
6. **来週の割当表**: ステップ4の内容を曜日順に

## エッジケース

- **メトリクス取得の一部失敗**（API エラー等）: その指標だけ前週値を `(stale)` 注記付きで残し、
  週報のヘッダに取得失敗を明記。全滅でも週報は必ず出す（数字なしでも要アクションは出せる）
- **無人実行で判断に迷う**: 何も変更せず「要判断」に回す。ユーザーへの質問はしない
- **手動実行**（対話セッション）: ユーザーと相談しながらゲート閾値や対象アプリの追加・除外を調整してよい。
  調整結果は portfolio.yml に反映する

## 設計メモ（なぜこの形か）

- **stage の書き換えをこのスキルに独占させる**のは、複数ジョブが同じ状態を触ると
  「誰がいつ何を根拠に変えたか」が追えなくなるため。git 履歴＝意思決定ログとして機能させる
- **unmeasured を 0 と区別する**のは、「数字が悪い」と「数字が無い」で打ち手が正反対だから
  （前者は改善、後者は計測実装）。計測の穴を Issue 化して factory-build に流すことで、
  計測基盤も他の機能と同じ川で自動整備される
- **割当表を TSV にする**のは、dispatcher が claude を起動せず bash だけで当日分を判定するため
  （空スロットの日はトークン消費ゼロ）
