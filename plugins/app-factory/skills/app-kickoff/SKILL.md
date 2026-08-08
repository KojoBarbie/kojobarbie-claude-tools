---
name: app-kickoff
description: "マージされたPRD（prd-vault）から新規iOSアプリの開発環境を一式セットアップする: XcodeGenでのXcodeプロジェクト生成→ビルド確認→GitHub privateリポジトリ作成→MVP機能のissue登録→デザインコンセプトシート（HTML+アーティファクト公開）→Bundle ID登録→remote-controlセッション起動→Slack通知。Use when: (1) prd-vaultのPRがマージされたとき（承認チェックジョブから）、(2)「○○をGoして」「○○の開発を始めて」「キックオフして」と言われたとき、(3) 新規iOSアプリプロジェクトの立ち上げやセットアップを頼まれたとき全般。"
---

# App Kickoff

Goサイン（prd-vaultのPRマージ）が出たPRDを、**スマホからそのまま開発を始められる状態**に変換する。完了時には: ビルドが通るXcodeプロジェクト / GitHubリポジトリ / 着手可能なissue群 / ビジュアルで確認できるデザインコンセプト / 起動済みのremote-controlセッション、が揃っている。

## 前提

**最初に `~/.config/app-factory/config.env` を読み込む**（`[ -f ~/.config/app-factory/config.env ] && . ~/.config/app-factory/config.env`。無ければ各変数は括弧内のデフォルト値を使う）。

| リソース | パス |
|---|---|
| PRDリポジトリ | `$PRD_VAULT_DIR`（デフォルト: `~/dev/prd-vault`。GitHub: `$GITHUB_OWNER/$(basename "$PRD_VAULT_DIR")`、デフォルトブランチ `main`） |
| プロジェクト配置先 | `$APPS_DIR/{AppName}/`（デフォルト: `~/dev/swift`） |
| 雛形生成 | `bash {skill_dir}/scripts/new_project.sh <AppName>`（XcodeGen使用。`APPLE_TEAM_ID`・`BUNDLE_ID_PREFIX` を環境変数から注入） |
| 規約・構成のお手本 | `$APPS_DIR/Hirune/`（CLAUDE.md・docs/・.claude/skills の構成が最新の標準。作者環境の前提 — 無い環境ではお手本参照を省略し、本スキル記載の構成要件だけで書き起こす） |
| Slack webhook / ASC APIキー | `$APP_FACTORY_HOME/.env`（デフォルト: `~/dev/others/claude-cron/.env`。`SLACK_WEBHOOK_URL_PRD`, `APP_STORE_*`） |
| Slack投稿 | `python3 $APP_FACTORY_HOME/.claude/skills/slack-post/scripts/slack_post.py --file <md> --header <題> --webhook-url "$SLACK_WEBHOOK_URL_PRD"`（`slack-post` スキルは作者環境の前提。無い環境では curl で webhook に直接 POST する） |

## Step 1: PRDの特定と熟読

- 承認チェックジョブから呼ばれた場合: 対象のマージ済みPR番号とPRDパス（`prd/{slug}.md`）が指示に含まれる
- 手動（「○○をGoして」）の場合: `$PRD_VAULT_DIR/prd/` とオープン中のPRから該当PRDを特定する。オープン中のPRを指している場合は先に `gh pr merge {番号} --merge` でマージする（それがGoの正式な記録になる）
- PRDを全文読み、MVPスコープ・技術メモ・デザイン方向性を頭に入れる

## Step 2: アプリ名の決定と雛形生成

1. PRDの仮名から **PascalCaseの英語名** を決める（例: `Hirune`）。`$APPS_DIR/` の既存ディレクトリおよび `gh repo list $GITHUB_OWNER` と衝突しないこと
2. `bash {skill_dir}/scripts/new_project.sh {AppName}` で雛形を生成
3. PRDの技術メモに応じて `project.yml` を調整する（HealthKit等のcapabilityが必要なら `entitlements` を、Watch/ウィジェットが必要なら extension target を追加）。調整したら `xcodegen generate` を再実行

## Step 3: ビルド確認

```bash
cd "$APPS_DIR"/{AppName}
xcodebuild -project {AppName}.xcodeproj -scheme {AppName} \
  -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5
```

`BUILD SUCCEEDED` を確認してから先へ進む。失敗したら直す — ビルドの通らない雛形を納品しない。

## Step 4: 開発規約（CLAUDE.md）とアーキテクチャ・テスト戦略の明文化

**Kiroは使わない**（廃止済み。steeringやkiroコマンドを作らない）。`Hirune/CLAUDE.md` をお手本に、PRDから書き起こしたシンプルな `CLAUDE.md` を置く:

- プロジェクト概要1〜2行 / ドキュメントの場所（`docs/prd.md`, `docs/design-concept.html`, `docs/architecture.md`, `docs/test-strategy.md`）
- 技術構成（ターゲット構成、使用フレームワーク、XcodeGen運用 =「`.xcodeproj` を直接編集せず `project.yml` → `xcodegen generate`」、マネタイズ実装）
- 開発ルール: issueベース（`ship-issue`）、PRレビューはプラグインのスキル（pr-batch-review / pr-comment-reply / pr-review-unresolved）を使う、`xcodebuild test` 後は `review-ios-test-results` スキルで分析
- **「実装は `docs/architecture.md` と `docs/test-strategy.md` に従う。逸脱する場合は PR で理由を明示し、文書側も同じ PR で更新する」という一文を必ず入れる**

`review-ios-test-results` スキルだけ `Hirune/.claude/skills/` からコピーする（プラグインに含まれないため。コピー元は作者環境の前提 — 無い環境ではこの手順を省略し、CLAUDE.md からも該当の言及を外す）。他のスキルコピーは不要。PRD本体は `docs/prd.md` に配置する。

### docs/architecture.md（アーキテクチャ決定の明文化）

以後の実装（factory-build / ship-issue の無人実装を含む）が**issue ごとに設計判断をやり直してブレる**のを防ぐため、キックオフ時点で決めて書き切る。PRD の技術構成から書き起こし、迷ったら Hirune と同じ構成（全アプリで標準を揃えるのが原則）:

- **レイヤ構成**: SwiftUI + MVVM（View / ViewModel / Service / Model）。各レイヤの責務と依存方向を1行ずつ
- **状態管理**: `@Observable`（iOS 17+）を標準。画面間共有状態の置き場所
- **永続化**: 何を使うか（UserDefaults / SwiftData / ファイル）と、その選定理由1行
- **外部サービスの接続方針**: Firebase（Analytics/Crashlytics）・RevenueCat・AdMob をどの層で扱うか（直接呼び出し禁止の範囲、ラッパーの置き場所）
- **やらないこと**: 外部ライブラリ追加は原則禁止（追加するなら PR で理由必須）、シングルトンの乱用禁止、など禁止事項を明示
- **ディレクトリ構成**: 実ディレクトリツリーを貼る

### docs/test-strategy.md（テスト戦略の明文化）

- **テストの層**: ユニットテスト中心（ViewModel / Service / Model のロジック）。何をテストする/しない（View の見た目・OS 機能そのものはテストしない等）を明示
- **実行コマンド**: このリポジトリでの正式なコマンドを1つに固定（例: `xcodebuild test -scheme {AppName} -destination '...'`）。ship-issue / factory-build / quality-release-cycle はこのコマンドを使う
- **配置と命名**: `{AppName}Tests/` 配下、`<対象クラス>Tests.swift`
- **新機能のルール**: issue の受け入れ条件はテストで固定してから実装する（可能な箇所は）
- **CI**: Xcode Cloud の PR ワークフローが全テストを実行する。ローカル green + CI green が PR マージの条件

どちらも**書き切れない項目を残さない**（「あとで決める」は禁止。決められないなら暫定案を明記して採用する）。

## Step 5: デザインコンセプト（HTML → アーティファクト）

`docs/design-concept.html` を作成する。**Markdownではなく、そのアプリのデザインシステム自身で組んだHTML**にする（配色スウォッチ・タイポ実寸見本・主要画面のCSSモックアップを含め、見た目で判断できるように）。`Hirune/docs/design-concept.html` が構成のお手本。

**入力は PRD だけではない。先に次の2つを見る**:

1. **`$PRD_VAULT_DIR/showcase/apps.json` の `toneChosen`** — PRD の PR でユーザーが選んだトンマナ案
   （`"A"` / `"B"` / `"C"`）。`null` なら tone ページで「推し」とされていた案を使う。
   **選ばれた案の配色・タイポ・角丸・ボイスをそのまま引き継ぐ**（ここで作り直さない。
   ユーザーは既にその案を見て承認している）。`showcase/app/apps/{slug}/tone/page.tsx` を読めば実値がある
2. **`showcase/app/apps/{slug}/mock/page.tsx`（紙芝居モック）** — 画面構成・遷移・演出・実コピーが
   入っている。**これが実装の目標値**なので、コンセプトシートはこのモックと矛盾してはいけない

- 内容は `app-design-craft` スキルの9レンズに沿って: 世界観（形容詞3つ）/ ライト・ダーク両パレット（HEX）/ タイポ指定 / 唯一の強調装置 / 避けたい表現・禁止語 / ボイス / 主要2〜3画面のレイアウト方針
- **加えて、体験の指定を必ず書く（レンズ7〜9。ここが無いと実装が正常系だけになる）**:
  - **感動する1点**: このアプリで最も気持ちいい瞬間はどこで、何で心が動くか（PRD から引く）。
    ここに他より厚く手間を割くと宣言する
  - **完了・達成の演出**: 何が起きるか、何秒か（0.4〜0.8秒目安）
  - **空状態の設計**: 初回の空に何を出すか。**次の一歩を示す CTA を必ず1つ**
  - **遷移とフィードバック**: 主要な画面遷移の種類、押下フィードバック、触覚を入れる瞬間（絞る）
- 形式: Artifact用フラグメント（`<!DOCTYPE>`や`<html>`タグなし、`<title>`タグはあり）。SF Proは `ui-rounded` / `-apple-system` で参照（閲覧はiPhoneのSafari想定）
- **Artifactツールが使えるなら**このファイルを公開し、URLを控える（favicon はアプリの世界観に合う絵文字、以後の再公開でも同じものを使う）。ヘッドレス実行などでArtifactツールがない場合は公開をスキップし、Slack通知に「アーティファクト未公開（`docs/design-concept.html` 参照）」と書く

## Step 5.5: LP（`lp/` + app-ads.txt + 規約ページ）

AdMob の app-ads.txt 配信と、設定画面・ストア提出が参照する利用規約/プライバシーポリシーの
置き場所として、**LP をアプリリポジトリの `lp/` に React プロジェクト（Vite + React + TS の SPA）で生成する**。
命名・URL 規約と Firebase Hosting での LP 公開は `${CLAUDE_PLUGIN_ROOT}/skills/app-kickoff/references/external-services.md` に従う:

- `/`: LP 本体（アプリ名・タグライン・特徴3つ・主要画面のモック画像・DL バッジ枠（リリース後に差し替え）・
  フッターに問い合わせ mailto / 利用規約 / プライバシーポリシー）。トンマナは showcase の tone ページ
  （PRD の PR に含まれる）に従う
- `/terms` と `/privacy`: PRD の収集データ・使用 SDK（Firebase Analytics / Crashlytics / RevenueCat / AdMob）を
  反映して生成。個人開発者名義・準拠法（日本法）・改定日を含む
- `lp/public/app-ads.txt`: `.env` の `ADMOB_PUBLISHER_ID` から生成（`google.com, {ID}, DIRECT, f08c47fec0942fa0`）
- 問い合わせ先は `.env` の `SUPPORT_EMAIL`（未設定ならチェックリストに追記依頼を入れ、プレースホルダーで生成）
- SPA の直 URL（/terms 等）が 404 にならないよう、**リポジトリルートの `firebase.json`** に hosting
  ターゲット `lp`（`public: "lp/dist"` + SPA rewrites）を置く（Vercel は使わない。詳細は external-services.md）
- `npm run build` が通ることを確認してからコミットに含める

## Step 6: GitHubリポジトリ作成とpush

```bash
cd "$APPS_DIR"/{AppName}
git init && git add -A && git commit -m "プロジェクト初期構成（app-kickoffによる自動生成）"
gh repo create "$GITHUB_OWNER"/{AppName} --private --source . --push
```

## Step 7: MVP機能のissue登録

PRDのコア機能を分解し、下記の**必須issueセット**と合わせて **7〜9件のissue** を登録する。各issueは `ship-issue` スキルでそのまま着手できる粒度にする:

- タイトル: 実装単位で具体的に。実装順が分かるよう先頭に `[1]` `[2]` を付ける
- 本文: ユーザーストーリー＋受け入れ条件（チェックボックス）＋PRD該当セクションへの言及
- **画面を作る issue には、受け入れ条件に体験の項目を必ず入れる**（無いと正常系だけ実装されて終わる）:
  - [ ] 空状態が設計されている（「次の一歩」を示す CTA が1つある）
  - [ ] 読込中・エラー時の表示がある
  - [ ] `docs/design-concept.html` の配色・余白・強調装置に従っている
  - [ ] 紙芝居モック（showcase）と画面構成・遷移が矛盾しない
  - コア行動の完了画面を含む issue には加えて: [ ] 完了時の演出がある（0.4〜0.8秒）
- **順序**: コア機能1本目 → スクリーンショット巡回テスト → 残りのコア機能 → 計測 → オンボーディング → ペイウォール → 設定画面 → （広告実装※PRDが広告収益化の場合）→ 最後に「App Store提出準備」

**必須issue（どのアプリでも必ず作る。コア機能以外はこの6本）**:

1. **計測実装**（ラベル `measurement` — 無ければ作成。factory-build が最優先で拾う）:
   PRD 10.2 の計測イベント一覧（イベント名・発火タイミング・対応KPI）をそのまま転記 /
   SDK導入・初期化（FirebaseプロジェクトはStep 8で作成済み・plist配置済み）/
   BigQueryエクスポート有効化（コンソール操作）/ 「`analytics_env_prefix` を `$APP_FACTORY_HOME/.env` に追加し、
   prd-vault/portfolio.yml の該当アプリに記入する」という仕上げタスク
2. **オンボーディング実装**: 本文の冒頭に
   **「実装時は必ず `onboarding-advisor` スキルを起動し、設計（初回起動フロー・コア行動への最短経路・
   許可リクエストのタイミング・アンチパターン検査）のレビューを受けてから実装すること」**と明記する
   （factory-build の無人実装でもスキルが起動されるよう、issue 本文に指示を埋め込むのが目的）。
   受け入れ条件: 初回セッションでコア行動（PRD 10.1）に到達する導線がある / `onboarding_completed`
   イベントが計測される / スキップ可能
3. **ペイウォール実装（RevenueCat）**: PRD「6. 収益化」と 10.1 の収益化ファネルに従い、配置
   （どの体験の直後か）・価格・トライアル設計を本文に明記。RevenueCat の public API key
   （Step 8 で作成済みならコメントに記載）を設定1箇所に集約 / `paywall_viewed` 等の計測イベント連携 /
   サンドボックスでの購入・リストアのテスト手順をチェックリスト化
4. **設定画面**: どのアプリでも必ず設定画面（または設定タブ）を作り、**最低限この3項目を必ず入れる**:
   問い合わせ（`mailto:` — `.env` の `SUPPORT_EMAIL`）/ 利用規約（`https://{slug}-lp.web.app/terms`）/
   プライバシーポリシー（`https://{slug}-lp.web.app/privacy`）。加えてアプリバージョン表示。
   リンク先は Step 5.5 の LP に配置済み
5. **スクリーンショット巡回テスト**（実装順は**早め** — コア機能1本目の直後に置く）:
   XCUITest で主要画面（起動直後・コア行動・完了・空状態）を巡回し、各画面を
   `XCTAttachment`（`lifetime = .keepAlways`）として保存するテストを1本作る。
   以後の**全 PR でビジュアル回帰レビューが機能する**ようになるのが目的（これが無いと
   起動直後の1枚しか撮れず、UI 品質が実質ノーチェックのまま自動マージされ得る）。
   受け入れ条件: `-only-testing:{App}UITests/ScreenshotTests` で単独実行できる /
   `xcrun xcresulttool export attachments` で画像が取り出せる /
   画面を追加したときにテストへ1行足すだけで巡回対象を増やせる
6. **App Store提出準備**（最後）: アイコン・スクショ・審査メタデータ・プライバシー表記・
   **App Store カテゴリ（メイン/サブ）**・**著作権表記（`<西暦> <著作権者名>`）**
   （メタデータ・カテゴリ・著作権は store-release が `docs/store-metadata/ja/` に生成・投入する）

PRDの収益化が広告を含む場合は **広告実装 issue** も追加（AdMob アプリID は Step 8 のチェックリストで
人間が登録後にコメントされる。受け入れ条件に「`https://{slug}-lp.web.app/app-ads.txt` が 200」を含める）。

## Step 8: 外部サービス準備（ASC / Firebase / RevenueCat / AdMob / LP公開 を一気通貫で）

自動化できる部分はここで全部やり、できない部分は正確なチェックリストに落とす。
Firebase / RevenueCat / AdMob / Firebase Hosting（LP）の具体的なコマンド・API・フォールバックは
**`${CLAUDE_PLUGIN_ROOT}/skills/app-kickoff/references/external-services.md` に従う**（命名規約もそこで固定）。

1. **Bundle IDの登録（自動）**: `xcode-cloud-setup` スキルのスクリプトで `${BUNDLE_ID_PREFIX}.{slug}` をASCに登録する:
   ```bash
   python3 ${CLAUDE_PLUGIN_ROOT}/skills/xcode-cloud-setup/scripts/asc_cloud.py register-bundle-id "${BUNDLE_ID_PREFIX}.{slug}" {AppName}
   ```
2. **オンボーディング待ちリストに登録（自動）**: 承認チェックジョブ（毎日9時/21時）がASC APIでオンボーディング完了をポーリングし、検知したらTestFlightワークフロー2本を自動作成してSlack通知する:
   ```bash
   mkdir -p "$APP_FACTORY_HOME"/.data
   printf '%s\t%s\t0\n' {AppName} "$(date +%s)" >> "$APP_FACTORY_HOME"/.data/pending_xcode_cloud.txt
   ```
   （タブ区切り: アプリ名・登録epoch・最終リマインドepoch。3日以上未完了だと3日おきにチェックリストがSlackに再送される）
3. **Firebase プロジェクト作成と紐付け（自動）**: `{slug}-app` を作成 → iOS アプリ登録 →
   `GoogleService-Info.plist` を取得してターゲット直下に配置・コミット（references 参照。
   firebase CLI 未認証なら諦めてチェックリスト行き）
4. **RevenueCat プロジェクト作成と紐付け（自動を試行）**: API v2 でプロジェクト + iOS アプリを作成し、
   public API key をペイウォール issue にコメント、プロジェクト ID を portfolio.yml の
   `revenuecat_project` に記入（API 不可ならチェックリスト行き）
5. **Firebase Hosting へ LP を公開（自動を試行）**: アプリの Firebase プロジェクト内に `{slug}-lp`
   Hosting サイトを作成 → `lp/dist` をビルドして `firebase deploy --only hosting:lp`。
   `https://{slug}-lp.web.app/app-ads.txt` の 200 を確認（`.web.app` は取れた実サイト名で読み替え。
   firebase CLI 未認証ならチェックリスト行き）
6. **手動ステップ**（Step 11 でチェックリストとしてSlackに送る）:
   - App Store Connectでアプリレコード作成（登録済みBundle IDを選ぶだけ、約2分）
   - Xcodeで一度だけXcode Cloudをオンボーディング（Product > Xcode Cloud、初回ワークフロー作成とGitHub接続）
   - **AdMob でアプリ追加 + 広告ユニット作成 + デベロッパーサイト登録**（アプリ作成 API が存在しないため必ず人力。
     約5分。references のチェックリスト文面を使う）
   - 上記 3〜5 で自動化に失敗したものがあれば、そのフォールバック手順

## Step 9: prd-vault側の後処理

1. マージ済みPRDのfrontmatter表に開発リポジトリURL・キックオフ日・デザインアーティファクトURLを追記し、mainにコミット & push
2. `$PRD_VAULT_DIR/portfolio.yml` に新アプリのエントリを追記する（`stage: building`、PRDから転記した prd パス・`bundle_id`・`core_action`）。portfolio.yml がまだ無ければ何もしない — portfolio-review のブートストラップに任せる
3. 対象PRに `processed` ラベルを付与し、`🤖 キックオフ完了: https://github.com/$GITHUB_OWNER/{AppName}` とコメント（🤖始まりが再処理防止マーカー）

## Step 10: remote-controlセッション起動

スマホから即開発を始められるよう、プロジェクトディレクトリでRemote Control付きセッションを起動し、セッションURLを取得する:

```bash
cd "$APPS_DIR"/{AppName}
RC_LOG=/tmp/rc_{AppName}.log
(script -q "$RC_LOG" "${CLAUDE_BIN:-claude}" --remote-control {AppName} &)
# セッションURLがログに出るまで少し待ってから抽出
until grep -qo 'https://claude.ai/code/session_[A-Za-z0-9]*' "$RC_LOG"; do sleep 2; done
grep -o 'https://claude.ai/code/session_[A-Za-z0-9]*' "$RC_LOG" | head -1
```

起動済みの同名セッションが残っていないか `pgrep -f "remote-control {AppName}"` で先に確認する。URLが取れなくても失敗にはせず、Slackに「スマホのClaudeアプリのセッション一覧から `{AppName}` を開いてください」と書く。

## Step 11: Slack通知

以下を含む短い完了報告を `$SLACK_WEBHOOK_URL_PRD` に投稿する:

- アプリ名とリポジトリURL
- デザインコンセプトのアーティファクトURL（:art: 絵文字付きで目立たせる）
- 作成したissueの一覧（番号＋タイトル）
- remote-controlセッションのURL（「タップしてそのまま開発を始められます」）
- **手動タスクのチェックリスト**。必ず以下の形式（`☐` プレフィックス）で、自動検知されることも添える:

```
:clipboard: *手動でやること*
☐ 1. App Store Connectでアプリを作成（Bundle ID `${BUNDLE_ID_PREFIX}.{slug}` は登録済み・選ぶだけ）
☐ 2. Xcodeで {AppName} を開き Product > Xcode Cloud からオンボーディング（GitHub接続込み）
☐ 3. AdMobで「アプリを追加」→ 広告ユニット作成 → デベロッパーサイトに https://{slug}-lp.web.app を登録
     → アプリID (ca-app-pub-…) を広告実装issueにコメント

1と2は完了したら自動検知（毎日9時/21時）され、PR→TestFlightとタグ(v*)→TestFlightの
ワークフロー2本が自動作成されてSlackに通知が届きます。合言葉は不要です。
```

Firebase / RevenueCat / Firebase Hosting（LP）の自動セットアップに失敗したものがあれば、そのフォールバック手順
（references/external-services.md の該当チェックリスト）もここに追記する。成功したものは
「✅ Firebase: {slug}-app 作成済み」「✅ LP: https://{slug}-lp.web.app 公開済み」のように結果だけ1行で報告する。

## 品質基準

- **ビルドが通らない状態で完了報告しない**
- issueを読めばPRDを開かなくても実装に入れる粒度で書く
- デザインコンセプトは「その通りに作れば世界観が揃う」具体性（HEX・数値・実寸見本）まで落とし、必ず見た目で確認できる形（HTML/アーティファクト）で届ける
- **コンセプトシートに「感動する1点」「完了の演出」「空状態」が書かれていない状態で完了報告しない。**
  ここが空欄のまま実装に流すと、正常系だけが実装された無味乾燥なアプリになる（最も起きやすい失敗）
