---
name: store-release
description: >
  iOS アプリの App Store 提出〜審査追跡を自動化する運用スキル。
  prd-vault の portfolio.yml を起点に、リリースすべきアプリを検出して「リリース列車」issue を起票し、
  PRD からストアメタデータを生成、Xcode Cloud 産のビルドを確保し、人間の明示承認（approved）を経て
  ASC API で審査提出、以後の審査状況を追跡する。
  launchd から毎日 6:00 に起動される無人ジョブ（用がある日だけ claude が起動される）であり、
  ユーザーが「リリース準備して」「ストアに出して」「App Store に提出して」「審査状況を見て」
  「リリース列車を確認して」などと言ったら、スキル名が明示されていなくても必ずこのスキルを使う。
---

# store-release

TestFlight 配信（Xcode Cloud）までは自動だが、その先の App Store 提出（メタデータ・スクショ・審査提出）が
人手のままになっている穴を埋めるスキル。**リリース列車**（`release-train` ラベルの issue）を状態機械として、
「起票 → メタデータ → ビルド → 承認ゲート → 提出 → 審査追跡」を毎日の実行で少しずつ前に進める。

このスキルの価値の中心は規律にある:

1. **待たない** — ビルド処理中・スクショ未着でもジョブは終了し、次回実行で続きから再開する（毎日走るので急がない）
2. **冪等** — 二重起票・二重タグ・二重提出をしない。GitHub と ASC の現状態を毎回照会してから動く
3. **承認ゲート** — App Store への「提出」という外に出る操作は、**人間の明示承認（release-train issue の
   `approved` ラベル or 👍 リアクション）が無い限り実行しない**。默っていても提出されない（＝提出はオプトイン）。
   メタデータ生成・TestFlight 用ビルド確保など提出手前の準備は承認前でも自動で進める
4. **無人時は質問しない** — 判断できないことは issue コメント + Slack に残して次回（または人間）に委ねる

## 前提と認証

**最初に `~/.config/app-factory/config.env` を読み込む**（無ければ各変数はデフォルト値: `APP_FACTORY_HOME=~/dev/others/claude-cron`、`PRD_VAULT_DIR=~/dev/prd-vault`）。

ASC API の認証は `$APP_FACTORY_HOME/.env` の環境変数を使う（xcode-cloud-setup スキルと同一）:

- `APP_STORE_KEY_ID` — API Key ID
- `APP_STORE_ISSUER_ID` — Issuer ID
- `APP_STORE_P8_KEY` — .p8 秘密鍵の内容（literal `\n` 格納。実改行に戻して使う）

JWT 生成（ES256・`aud: appstoreconnect-v1`・有効期限20分・ヘッダ `kid`）は
`${CLAUDE_PLUGIN_ROOT}/skills/xcode-cloud-setup/scripts/asc_cloud.py` の `token()` のパターンに従う。
必要なら同スキルの scripts をそのまま再利用してよい（依存の pyjwt / cryptography / requests は
作者環境では `$APP_FACTORY_HOME/.venv/bin/python3` に導入済み。無い環境では venv を作って導入する）。

```bash
[ -f ~/.config/app-factory/config.env ] && . ~/.config/app-factory/config.env
set -a && source "${APP_FACTORY_HOME:-$HOME/dev/others/claude-cron}/.env" && set +a
```

Slack 通知はすべて `$SLACK_WEBHOOK_URL_PRD` に送る。issue へのコメントは必ず `🤖` プレフィックスを付ける
（自分の書き込みを次回実行で識別するためのマーカー）。

---

## ワークフロー

毎回、以下を上から順に実行する。各ステップは「今日やれる分だけやって先へ」が原則。

### 1. 状態把握

1. `$PRD_VAULT_DIR/portfolio.yml` を読み、全アプリの stage / repo / bundle_id / asc_app_id を把握する
2. 各アプリのリポジトリで進行中のリリース列車を確認する:

```bash
gh issue list --repo "$GITHUB_OWNER"/<repo> --label release-train --state open \
  --json number,title,labels,createdAt,body
```

3. open な列車があるアプリは後続ステップ（3〜6）で前進させる。無いアプリはステップ 2 の起票判定へ

### 2. リリース列車の起票判定

起票条件（いずれか）:

- **初回リリース列車**: stage が `building` で、kickoff 起票の MVP issue が全て closed
- **定期リリース列車**: リリース済みアプリで「前回リリース（直近の `v*` タグ or 前回列車 close）以降の
  マージ済み PR ≥ 5 件」または「前回リリースから6週経過」

判定したら対象アプリのリポジトリに `release-train` ラベルの issue を **1本だけ** 起票する。
**既に open な `release-train` issue があれば何もしない（冪等）**。本文には必ず含める:

- チェックリスト: `- [ ] メタデータ → - [ ] ビルド → - [ ] 提出承認（人間） → - [ ] 提出 → - [ ] 審査承認`
- 対象バージョンと**バージョンの決め方の根拠**（初回 v1.0.0 / 機能追加ありでマイナー↑ / バグ修正のみでパッチ↑。
  ステップ4の判定結果をそのまま書く）
- 起票理由（初回 / 前回リリース以降マージ済み PR n件 / 6週経過）
- **人間への依頼を明記した「承認のお願い」ブロック**（オプトイン提出の要）:

```
## 🧑‍✈️ 提出の承認をお願いします
このリリース列車は **approved が付くまで App Store に提出しません**（默っていても提出されません）。
提出してよければ、この issue に `approved` ラベルを付けるか 👍 リアクションしてください。
- 対象バージョン: vX.Y.Z（<マイナー↑/パッチ↑ の理由>）
- 確認してほしい点:
  1. ストアメタデータ（`docs/store-metadata/ja/` のコミット差分）— 名前/説明/キーワード/**著作権**/**カテゴリ**
  2. スクリーンショット（`docs/store-assets/`）が最新か
  3. リリースノート（今回の変更点）
- 止める/延期する場合は `hold` ラベル、やめる場合は close してください。
```

起票したら Slack に、**issue URL・対象バージョンとその理由・「approved を付けると提出されます」**を含めて
「🚂 <アプリ名> vX.Y.Z のリリース列車を用意しました。内容を確認して承認（approved）してください」と通知する
（24時間で自動提出はしない）。

### 3. メタデータ準備

列車が open なアプリについて、アプリリポジトリの `docs/store-metadata/ja/` を確認する。
無ければ PRD（`$PRD_VAULT_DIR/prd/` または `shipped/`）から生成してコミットする（人がレビューできる形で残す）:

| ファイル | 内容 | 制限 |
|---|---|---|
| `name.txt` | アプリ名 | 30字 |
| `subtitle.txt` | サブタイトル | 30字 |
| `description.txt` | 説明文 | 4000字 |
| `keywords.txt` | キーワード（カンマ区切り） | 100字 |
| `promotional-text.txt` | プロモーションテキスト | 170字 |
| `copyright.txt` | 著作権表記（`appStoreVersions.copyright`）。**1行で `<リリース年の西暦> <著作権者名>`**。<br>著作権者名は `.env` の `STORE_COPYRIGHT_HOLDER`、無ければ `GITHUB_OWNER`（例: `2026 KojoBarbie`） | — |
| `categories.txt` | App Store カテゴリ。**1〜2行**: 1行目 `primary: <ID>`（必須）、2行目 `secondary: <ID>`（任意）。<br>ID は ASC の語彙（`GET /v1/appCategories?filter[platforms]=IOS` で取得。例: `UTILITIES` / `HEALTH_AND_FITNESS` / `PRODUCTIVITY` / `FINANCE`）。<br>GAMES・STICKERS を primary にする場合のみサブカテゴリを `primary_sub1: <ID>` / `primary_sub2: <ID>` で追記（他カテゴリにサブは無い） | — |
| `privacy.md` | プライバシー情報（収集データ種別・用途。App Privacy 回答の下書き） | — |

- **著作権（`copyright.txt`）とカテゴリ（`categories.txt`）は必須**。生成漏れがそのままストア提出に穴を開けるため、
  この2ファイルが無い列車は提出条件（ステップ5）を満たさない
- カテゴリは PRD のジャンル・元ネタアプリの App Store カテゴリから決める。迷ったら primary のみ設定し
  secondary は空にする（誤ったカテゴリより無指定が安全）。GAMES/STICKERS 以外はサブカテゴリ行を書かない
- 文字数制限は生成後に必ず数えて確認する（超過は ASC API が 409 を返す）。既にファイルがあれば再生成しない（冪等）

**プライバシーポリシー URL・サポート URL** は kickoff が生成した LP を使う:
`https://{slug}-lp.web.app/privacy` と `https://{slug}-lp.web.app`。提出前に 200 を返すことを
確認し、LP が未デプロイなら release-train issue にタスクとして追記して提出条件に含める。

スクリーンショットは `docs/store-assets/` にあるものを使う。**無ければ**:

- release-train issue に「- [ ] スクリーンショット（人間タスク）」を追記し、
  Slack で **1回だけ** 人間に依頼する（issue に依頼済みマーカー `🤖 スクショ依頼済み` を残し、二重依頼しない）
- スクショ待ちの間も列車は hold しない — ステップ 4 以降を先に進める。ただし提出（ステップ 5）の条件にスクショは必須

### 4. ビルド確保

ビルドは `v*` タグの push で Xcode Cloud の「Tag to TestFlight」ワークフローが作る。

1. アプリリポジトリの最新 main コミットに `v*` タグが付いているか確認する:

```bash
git -C <repo> fetch --tags && git -C <repo> tag --points-at origin/main "v*"
```

2. 未タグなら**バージョンを semver ルールで決めて**タグを push する。**同名タグが既にあれば push しない（冪等）**。
   バージョンの上げ幅は「前回リリース（直近の `v*` タグ）以降の変更の中身」で機械的に決める:

   - **初回リリース** → `v1.0.0`
   - **前回リリース以降に機能追加が1件でも含まれる** → **マイナーを上げる**（例 `v1.2.0` → `v1.3.0`、パッチは 0 に戻す）
   - **バグ修正・小改善のみ**（機能追加なし） → **パッチを上げる**（例 `v1.2.1` → `v1.2.2`）
   - **メジャーは自動で上げない**。メジャー更新は「よほどのとき」であり、人間が release-train issue に
     `major` ラベルを付ける／明示指示したときだけ `vX.0.0` にする（無ければ絶対にメジャーを触らない）

   機能追加かバグ修正かは、前回タグ以降のマージ済み PR / closed issue の**ラベルとタイトル**で分類する:

   ```bash
   PREV=$(git -C <repo> tag --list 'v*' --sort=-v:refname | head -1)   # 直近リリースタグ
   git -C <repo> log --oneline "$PREV"..origin/main                     # 変更の全体像
   gh pr list -R <owner/repo> --state merged --search "merged:>=<PREVのタグ日>" \
     --json number,title,labels                                         # 分類の材料
   ```

   - 機能追加とみなす合図: `feature-proposal`/`feature-approved`/`enhancement`/`feat` 由来、
     PRD の MVP コア機能実装、タイトルが `feat:`/「〜機能」「追加」など
   - パッチとみなす合図: `bug`/`fix`/監査（quality-release-cycle）由来、タイトルが `fix:`/「修正」「改善」のみ
   - 判定に迷う（材料が取れない・混在で機能追加の有無が曖昧）→ **安全側に倒してマイナー**を上げ、
     判定根拠を release-train issue に `🤖 バージョン判定:` コメントで残す
   - 決めたバージョンとその理由（マイナー↑/パッチ↑ とその根拠）は起票済み issue 本文の「承認のお願い」にも反映する
3. ASC API でそのビルドの処理状態を確認する（`GET /v1/builds?filter[app]=<asc_app_id>` で
   最新ビルドの `processingState` が `VALID` になっているか）
4. **処理中・ビルド未出現でも待ち続けない。** issue に `🤖 ビルド待ち（vX.Y.Z）` とコメントして今日は終了し、
   次回実行で続きから再開する。3日以上ビルドが出現しない場合のみ Slack に異常として通知する

### 5. 承認チェックとメタデータ投入・提出

**提出は人間の明示承認が要る（オプトイン）。** 以下が **全て** 揃ったときだけ提出に進む:

- release-train issue が open のまま、`hold` ラベルなしで、**承認済み**である。承認の判定は次のいずれか:
  - issue に **`approved` ラベル**が付いている、または
  - issue 本文に **👍 リアクション**が付いている（`gh api repos/<owner>/<repo>/issues/<n>/reactions` で
    `content == "+1"` を確認。bot 自身のリアクションは数えない）
- `docs/store-metadata/ja/` のメタデータ一式がコミット済み（**`copyright.txt` と `categories.txt` を含む**）
- `docs/store-assets/` にスクリーンショットがある
- 処理完了（`VALID`）したビルドが ASC にある

**承認がまだ無いときは提出しない。** メタデータ投入・ビルド紐付け（下記1〜4、外に出ない準備）は
承認前でも進めてよいが、審査提出（5）だけは承認まで実行しない。承認待ちの列車は issue を open のまま残し、
`🤖 提出承認待ち（vX.Y.Z）` コメントが無ければ1回だけ付けて次回に持ち越す（Slack への再依頼はしない
＝日次リマインダー／週報の担当）。

提出手順（ASC API。各操作の前に現状態を照会し、済んでいる工程はスキップする）:

1. **バージョン作成**: `appStoreVersions` に対象バージョンが無ければ `POST /v1/appStoreVersions` で作成。
   このとき `attributes.versionString`（vX.Y.Z）と **`attributes.copyright`（`copyright.txt` の内容）** を設定する。
   既存バージョンで copyright が空／古ければ PATCH で `copyright` を更新する
2. **カテゴリ投入**: 対象アプリの編集可能な `appInfos` の `relationships.primaryCategory` に `categories.txt` の
   `primary` を、`secondaryCategory` に `secondary`（あれば）を PATCH で紐付ける（値は `appCategories` の ID）。
   GAMES/STICKERS のときのみ `primarySubcategoryOne` / `primarySubcategoryTwo` も同様に紐付ける。
   既に正しいカテゴリが設定済みなら何もしない（冪等）
3. **メタデータ投入**: `appStoreVersionLocalizations`（ja）に description / keywords / promotionalText 等を PATCH。
   スクリーンショットをアップロード
4. **ビルド紐付け**: バージョンの `relationships/build` に確保済みビルドを PATCH
5. **審査提出**: `reviewSubmissions` を作成 → バージョンを item として追加 → `submitted: true` に PATCH。
   **既に `WAITING_FOR_REVIEW` / `IN_REVIEW` のバージョンがあれば提出しない（二重提出防止）**

**初回はさらに慎重に**: そのアプリで ASC API による提出操作が初めての場合（過去の release-train issue に
`🤖 提出しました` コメントが無い場合）、`approved` が付いていても手順 5 の直前でもう一度止め、
App Privacy・輸出コンプラなど初回特有の落とし穴を Slack で確認依頼する:

> 🧑‍✈️ <アプリ名> は初回提出です。承認済みですが提出直前で一旦止めています。ASC で App Privacy 回答・
> 輸出コンプラ・カテゴリ・著作権を確認し、問題なければ「store-release で提出して」と指示してください。

2回目以降のアプリは、承認（approved）さえ付いていれば全自動で提出してよい。

提出したら issue に `🤖 提出しました（vX.Y.Z）` とコメントし、チェックリストを更新する。
**issue は close せず「審査中」状態として open のまま残す**。Slack に「📮 <アプリ名> vX.Y.Z を審査提出しました」と通知する。

### 6. 審査追跡

審査中（提出済みで open）の列車があるアプリは、毎回 `appStoreVersions` の状態を確認する
（`GET /v1/apps/<asc_app_id>/appStoreVersions` の `appVersionState`）。

- **承認**（`PENDING_DEVELOPER_RELEASE` / `READY_FOR_DISTRIBUTION` / `ACCEPTED`）:
  1. release-train issue に `🤖 審査承認` とコメントして close
  2. prd-vault の portfolio.yml で該当アプリの stage を `validating` に更新してコミット・push
  3. Slack に「🎉 <アプリ名> vX.Y.Z が App Store 審査を通過しました」
- **リジェクト**（`REJECTED` / `METADATA_REJECTED` / `DEVELOPER_REJECTED`）:
  1. Resolution Center の内容（取得できる範囲）を要約して issue に `🤖` コメント
  2. issue に `app-review-rejected` ラベルを付ける（列車は open のまま）
  3. Slack に **即時** 通知する。対応は人間、または人間からの個別指示で行う（このジョブは自動で再提出しない）
- **審査中のまま**（`WAITING_FOR_REVIEW` / `IN_REVIEW`）: 何もしない。次回に持ち越す

---

## 手動起動時の振る舞い

「リリース準備して」「ストアに出して」と人間から呼ばれた場合も同じワークフローを実行するが、
対話できるので以下だけ変える:

- 対象アプリが指定されていればそのアプリだけ処理する
- 「store-release で提出して」と明示されたら、それが承認そのものなので初回併走の停止点・approved 未付与も
  人間の指示として通過してよい（hold ラベルが付いている場合だけは、外していいか確認する）

## 禁止事項・スコープ外

- 無人実行時にユーザーへ質問しない。判断保留は issue コメント + Slack に残す
- アプリの実装内容（ダークモード禁止・課金は RevenueCat 等のプロジェクト規約）には触れない — それは実装側
  （factory-build / ship-issue）の領分。このスキルはストア提出のパイプラインだけを扱う
- リジェクト後の自動再提出はしない（人間の判断を挟む）

## 設計メモ — なぜこの形か

- **リリース列車 = issue 1本**にしたのは、状態（どこまで進んだか）・人間の承認/拒否（approved / hold / close）・
  監査ログ（🤖 コメント）を1箇所に集約するため。ジョブ自体は状態を持たず、毎回 issue と ASC を読んで再開する
- **承認ゲート（approved オプトイン）** は、ストア提出という取り消しにくい外向き操作を「默っていても出る」に
  しないため。提出手前（メタデータ・ビルド）は自動で全部用意し、人間の判断は「出してよいか」の1点に絞る。
  以前は24時間 veto（オプトアウト＝默っていると出る）だったが、承認を要件（オプトイン）に反転した
- **初回だけ人間併走**は設計書のロールアウト方針（Phase 4〜5）そのもの。ASC API の提出系は
  アプリ固有の落とし穴（App Privacy 未回答・輸出コンプラ等）が初回に集中するため、2回目以降とリスクが非対称
- **「待たない」原則**は、毎日 6:00 に必ず走るジョブだから成立する。ポーリングで claude を占有するより、
  次回実行に持ち越す方がトークンも安全性も安くつく
