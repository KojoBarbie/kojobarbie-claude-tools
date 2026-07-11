---
name: store-release
description: >
  iOS アプリの App Store 提出〜審査追跡を自動化する運用スキル。
  prd-vault の portfolio.yml を起点に、リリースすべきアプリを検出して「リリース列車」issue を起票し、
  PRD からストアメタデータを生成、Xcode Cloud 産のビルドを確保し、24時間の拒否権ウィンドウを経て
  ASC API で審査提出、以後の審査状況を追跡する。
  launchd から毎日 6:00 に起動される無人ジョブ（用がある日だけ claude が起動される）であり、
  ユーザーが「リリース準備して」「ストアに出して」「App Store に提出して」「審査状況を見て」
  「リリース列車を確認して」などと言ったら、スキル名が明示されていなくても必ずこのスキルを使う。
---

# store-release

TestFlight 配信（Xcode Cloud）までは自動だが、その先の App Store 提出（メタデータ・スクショ・審査提出）が
人手のままになっている穴を埋めるスキル。**リリース列車**（`release-train` ラベルの issue）を状態機械として、
「起票 → メタデータ → ビルド → veto ウィンドウ → 提出 → 審査追跡」を毎日の実行で少しずつ前に進める。

このスキルの価値の中心は規律にある:

1. **待たない** — ビルド処理中・スクショ未着でもジョブは終了し、次回実行で続きから再開する（毎日走るので急がない）
2. **冪等** — 二重起票・二重タグ・二重提出をしない。GitHub と ASC の現状態を毎回照会してから動く
3. **拒否権ウィンドウ** — ストア提出という「外に出る」操作は、起票から24時間の人間の veto 猶予を必ず挟む
4. **無人時は質問しない** — 判断できないことは issue コメント + Slack に残して次回（または人間）に委ねる

## 前提と認証

ASC API の認証は `~/dev/others/claude-cron/.env` の環境変数を使う（xcode-cloud-setup スキルと同一）:

- `APP_STORE_KEY_ID` — API Key ID
- `APP_STORE_ISSUER_ID` — Issuer ID
- `APP_STORE_P8_KEY` — .p8 秘密鍵の内容（literal `\n` 格納。実改行に戻して使う）

JWT 生成（ES256・`aud: appstoreconnect-v1`・有効期限20分・ヘッダ `kid`）は
`${CLAUDE_PLUGIN_ROOT}/skills/xcode-cloud-setup/scripts/asc_cloud.py` の `token()` のパターンに従う。
必要なら同スキルの scripts をそのまま再利用してよい（依存の pyjwt / cryptography / requests は
`~/dev/others/claude-cron/.venv/bin/python3` に導入済み）。

```bash
set -a && source ~/dev/others/claude-cron/.env && set +a
```

Slack 通知はすべて `$SLACK_WEBHOOK_URL_PRD` に送る。issue へのコメントは必ず `🤖` プレフィックスを付ける
（自分の書き込みを次回実行で識別するためのマーカー）。

---

## ワークフロー

毎回、以下を上から順に実行する。各ステップは「今日やれる分だけやって先へ」が原則。

### 1. 状態把握

1. `~/dev/prd-vault/portfolio.yml` を読み、全アプリの stage / repo / bundle_id / asc_app_id を把握する
2. 各アプリのリポジトリで進行中のリリース列車を確認する:

```bash
gh issue list --repo KojoBarbie/<repo> --label release-train --state open \
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

- チェックリスト: `- [ ] メタデータ → - [ ] ビルド → - [ ] veto ウィンドウ通過 → - [ ] 提出 → - [ ] 審査承認`
- 対象バージョン・起票理由（初回 / PR n件 / 6週経過）
- **「24時間後の実行で自動提出します。止める場合はこの issue に `hold` ラベルを付けるか close してください」**

起票したら Slack に「🚂 <アプリ名> のリリース列車を発車させました（24h 後に自動提出）」と issue URL を通知する。

### 3. メタデータ準備

列車が open なアプリについて、アプリリポジトリの `docs/store-metadata/ja/` を確認する。
無ければ PRD（`~/dev/prd-vault/prd/` または `shipped/`）から生成してコミットする（人がレビューできる形で残す）:

| ファイル | 内容 | 制限 |
|---|---|---|
| `name.txt` | アプリ名 | 30字 |
| `subtitle.txt` | サブタイトル | 30字 |
| `description.txt` | 説明文 | 4000字 |
| `keywords.txt` | キーワード（カンマ区切り） | 100字 |
| `promotional-text.txt` | プロモーションテキスト | 170字 |
| `privacy.md` | プライバシー情報（収集データ種別・用途。App Privacy 回答の下書き） | — |

文字数制限は生成後に必ず数えて確認する（超過は ASC API が 409 を返す）。既にファイルがあれば再生成しない（冪等）。

**プライバシーポリシー URL・サポート URL** は kickoff が生成した LP を使う:
`https://{slug}-lp.vercel.app/privacy` と `https://{slug}-lp.vercel.app`。提出前に 200 を返すことを
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

2. 未タグならバージョンを決めてタグを push する。初回リリースは `v1.0.0`、以降は最新 `v*` タグから
   semver のマイナーを上げる（例: `v1.2.0` → `v1.3.0`）。**同名タグが既にあれば push しない（冪等）**
3. ASC API でそのビルドの処理状態を確認する（`GET /v1/builds?filter[app]=<asc_app_id>` で
   最新ビルドの `processingState` が `VALID` になっているか）
4. **処理中・ビルド未出現でも待ち続けない。** issue に `🤖 ビルド待ち（vX.Y.Z）` とコメントして今日は終了し、
   次回実行で続きから再開する。3日以上ビルドが出現しない場合のみ Slack に異常として通知する

### 5. veto チェックと提出

以下が **全て** 揃ったときだけ提出に進む:

- release-train issue が open のまま、`hold` ラベルなしで、**起票から24時間以上経過**している
- `docs/store-metadata/ja/` のメタデータ一式がコミット済み
- `docs/store-assets/` にスクリーンショットがある
- 処理完了（`VALID`）したビルドが ASC にある

提出手順（ASC API。各操作の前に現状態を照会し、済んでいる工程はスキップする）:

1. **バージョン作成**: `appStoreVersions` に対象バージョンが無ければ `POST /v1/appStoreVersions` で作成
2. **メタデータ投入**: `appStoreVersionLocalizations`（ja）に description / keywords / promotionalText 等を PATCH。
   スクリーンショットをアップロード
3. **ビルド紐付け**: バージョンの `relationships/build` に確保済みビルドを PATCH
4. **審査提出**: `reviewSubmissions` を作成 → バージョンを item として追加 → `submitted: true` に PATCH。
   **既に `WAITING_FOR_REVIEW` / `IN_REVIEW` のバージョンがあれば提出しない（二重提出防止）**

**初回は人間併走**: そのアプリで ASC API による提出操作が初めての場合（過去の release-train issue に
`🤖 提出しました` コメントが無い場合）、手順 4 の直前で止めて Slack に通知する:

> 🧑‍✈️ <アプリ名> は初回提出です。提出直前まで準備済み。ASC で内容を確認して提出ボタンを人間が押すか、
> 「store-release で提出して」と指示してください。

2回目以降のアプリは全自動で提出してよい。

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
- 「store-release で提出して」と明示されたら、初回併走の停止点・24時間ウィンドウを人間の指示として通過してよい
  （hold ラベルが付いている場合だけは、外していいか確認する）

## 禁止事項・スコープ外

- 無人実行時にユーザーへ質問しない。判断保留は issue コメント + Slack に残す
- アプリの実装内容（ダークモード禁止・課金は RevenueCat 等のプロジェクト規約）には触れない — それは実装側
  （factory-build / ship-issue）の領分。このスキルはストア提出のパイプラインだけを扱う
- リジェクト後の自動再提出はしない（人間の判断を挟む）

## 設計メモ — なぜこの形か

- **リリース列車 = issue 1本**にしたのは、状態（どこまで進んだか）・人間の拒否権（hold / close）・
  監査ログ（🤖 コメント）を1箇所に集約するため。ジョブ自体は状態を持たず、毎回 issue と ASC を読んで再開する
- **24時間 veto** は「提出される」がデフォルト（設計書 §6: 人間が何もしなくてもサイクルが進む）としつつ、
  外に出る操作にだけ機械的なブレーキを付けるため
- **初回だけ人間併走**は設計書のロールアウト方針（Phase 4〜5）そのもの。ASC API の提出系は
  アプリ固有の落とし穴（App Privacy 未回答・輸出コンプラ等）が初回に集中するため、2回目以降とリスクが非対称
- **「待たない」原則**は、毎日 6:00 に必ず走るジョブだから成立する。ポーリングで claude を占有するより、
  次回実行に持ち越す方がトークンも安全性も安くつく
