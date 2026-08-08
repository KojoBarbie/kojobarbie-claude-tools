---
name: design-vault
description: "Slack のデザイン収集チャンネルに投げられたアプリのスクリーンショットを取り込み、1枚ずつ「なぜ効くか＋効く条件」まで分析してカード化し、5枚以上溜まった画面種別を横断パターンに帰納して蓄積するデザイン参照庫。トンマナ設計・モック作成・UIレビューのときに実例リファレンスを引く先でもある。Use when: (1) 日次の自動取り込み（launchd経由）、(2)「デザインを取り込んで」「スクショ溜まってるから分析して」「design-vault を回して」と言われたとき、(3) トンマナやモックを作る前に参考リファレンスを引きたいとき（`query` モード）、(4) UIレビューで「この型は他社がどうやっているか」を確認したいとき。アプリのUI/UXの参考事例を集める・引く話ならスキル名が明示されていなくてもこのスキルを使う。"
---

# design-vault — デザイン参照庫

自分が「いいな」と思ったアプリのスクリーンショットを Slack のチャンネルに投げておくだけで、
**再利用できる設計原理**に翻訳して蓄積する。トンマナ・モック・UIレビューはここから引く。

このスキルが存在する理由は1つ。デザインの参照が `app-design-craft` の nemuiasa 1件しか無いと、
どのアプリも同じ方向に寄り、しかも「引き算」を誤解して**ただ何もない画面**になるから。
1件からの演繹を、N件からの帰納に置き換えるのが目的。

## 前提

**最初に `~/.config/app-factory/config.env` を読み込む**（`[ -f ~/.config/app-factory/config.env ] && . ~/.config/app-factory/config.env`）。
続けて `$APP_FACTORY_HOME/.env`（デフォルト `~/dev/others/claude-cron/.env`）を `set -a && . ... && set +a` で読む。

| リソース | 値 |
|---|---|
| vault | `$PRD_VAULT_DIR/design-vault`（デフォルト `~/dev/prd-vault/design-vault`） |
| Slack チャンネルID | `$SLACK_DESIGN_CHANNEL_ID`（`.env` に追記。未設定なら後述の初回セットアップ） |
| Slack Bot token | `$SLACK_BOT_TOKEN`（既存。`channels:history` / `files:read` を保有済み） |
| 収集スクリプト | `python3 ${CLAUDE_PLUGIN_ROOT}/skills/design-vault/scripts/fetch_slack_images.py` |
| 構造仕様 | [references/vault-spec.md](references/vault-spec.md) — ディレクトリ・カード/パターンのスキーマ |
| 分析の作法 | [references/analysis-guide.md](references/analysis-guide.md) — 1枚をどう読むか |

## モード

| モード | 起動条件 | やること |
|---|---|---|
| **collect**（既定） | 日次の自動実行、「デザイン取り込んで」 | Slack取り込み → 分析 → カード化 → パターン集約 → コミット |
| **query** | 他スキル（app-idea-hunt / app-kickoff / app-design-craft）から「〜向けのリファレンスを出して」 | 分析はせず `index.json` と `patterns/` から引いて返すだけ |
| **patterns** | 「パターンを見直して」 | 取り込みをせず、集約だけやり直す |

---

## collect モード

### Step 1: 取り込み

```bash
python3 "${CLAUDE_PLUGIN_ROOT}/skills/design-vault/scripts/fetch_slack_images.py" \
  --vault "$PRD_VAULT_DIR/design-vault"
```

`fetched: 0` なら分析対象が無いということ。ただし **inbox に前回の残り（`analyzed: false`）がある場合は続行する**。
両方とも空なら、コミットも Slack 通知もせず静かに終了する（毎日「0件でした」を通知しない）。

`vault` が存在しなければ、`references/vault-spec.md` の構成で作る（`inbox/` `refs/` `cards/` `patterns/` と
空配列の `index.json`、それに人間向けの `README.md`）。

### Step 2: 分析してカードを作る

`inbox/*.json` のうち `analyzed: false` のものを **最大20件**処理する（残りは次回）。

1件ごとに:

1. **画像を Read ツールで実際に見る**。メタJSON の `message_text`（Slack に添えたコメント）も読む —
   アプリ名や「ここが良い」という着目点が書かれていることが多い
2. [references/analysis-guide.md](references/analysis-guide.md) の手順で読む。
   **「効く条件」を書かないカードは作らない**
3. `cards/{id}.md` を `references/vault-spec.md` のスキーマで書く
4. 画像を `refs/{app_slug}/` へ移動し、inbox からメタJSON を削除する
5. `index.json` にエントリを追記する

同じアプリの画像が複数あるときは**まとめて見る**。1枚ずつ見るより一貫性（Coherence）が読めるので、
カードは1枚ずつ作りつつ、気づいた横断点は各カードの「使いどころ」に書く。

### Step 3: パターンの集約

`index.json` を `screen` で集計する。

- 同一 `screen` のカードが **5枚以上**あり、対応する `patterns/{name}.md` が無い → **新規作成**
- 既存パターンの `sample_size` より **5枚以上**増えている → **更新**（結論が変わったか必ず検証する）

書き方は `references/vault-spec.md` のパターン節に従う。特に:

- **「何例中何例」で書く**。印象で書かない
- **「効かない場面」を必ず書く**。ここが無いと辞書化して誤用される
- 既存パターンの更新では、増えた例が既存の結論を**否定していないか**を先に確認する。
  否定していたら型を書き換える（例を足すだけで結論を据え置かない）

### Step 4: コミット

```bash
cd "$PRD_VAULT_DIR"
git add design-vault/ && git commit -m "design-vault: カード{N}件追加、パターン{M}件更新"
git push origin main
```

main に直接コミットしてよい（PRD と違い承認を要さない資料であり、PR にすると溜まって死ぬ）。

### Step 5: Slack 通知（新規パターンができたときだけ）

カードが増えただけでは通知しない。**新しいパターンができた／既存パターンの結論が変わったときだけ**、
収集チャンネルに短く投稿する（`$SLACK_DESIGN_CHANNEL_ID` へ `chat.postMessage`）。

```
:card_index_dividers: 新しいパターンができました
*完了の瞬間をどう祝うか*（12例から）
→ 12例中9例が成果を1つの数字に集約。演出は0.4〜0.8秒に集中
design-vault/patterns/completion-moment.md
```

---

## query モード

他スキルから「このアプリ向けのリファレンスを出して」と呼ばれたときの動作。**分析も取り込みもしない**。

1. `index.json` を読み、依頼の条件（カテゴリ / mood / screen）で絞る
2. 該当する `patterns/*.md` があれば**それを最優先で返す**（個別カードより型のほうが移植可能）
3. 個別カードは、方向性が**異なる**ものを混ぜて返す。同系統ばかり返すと参照が1件だった頃と同じ症状に戻る
4. 返す形式:
   - パターン名と「N例から見えたこと」の要点
   - カードごとに: アプリ名 / 画像の**リポジトリ相対パス** / 効いている理由1〜2行 / 効く条件
   - `verdict: anti` のカードがあれば「避けるべき例」として別枠で

**vault が空、または該当0件のときは、無理に何か返さずそう言う。**
`app-design-craft` の原則だけで進めればよく、それは劣化ではない。

---

## 初回セットアップ（`SLACK_DESIGN_CHANNEL_ID` が未設定のとき）

Slack App の設定変更は**不要**（既存 bot が `channels:history` と `files:read` を保有済み）。
人間にやってもらうのは2つだけなので、そのまま伝える:

```
☐ 1. Slack で #design-inbox チャンネルを作る（名前は任意）
☐ 2. そのチャンネルで /invite @<bot名> を実行する
```

その後、チャンネルIDを取得して `.env` に追記する:

```bash
curl -s -H "Authorization: Bearer $SLACK_BOT_TOKEN" \
  "https://slack.com/api/conversations.list?types=public_channel,private_channel&limit=1000" \
  | python3 -c "import json,sys; [print(c['id'], c['name']) for c in json.load(sys.stdin)['channels']]"
echo 'SLACK_DESIGN_CHANNEL_ID=C0XXXXXXX' >> "$APP_FACTORY_HOME/.env"
```

## 使い方（人間向け・README.md に書く内容）

- スクショは**そのままチャンネルに投げるだけ**でよい。1回に何枚でも、まとめてでもよい
- アプリ名や「ここが良い」を一言添えると分析精度が上がる（添えなくても動く）
- **競合アプリの雑な画面も歓迎**。`verdict: anti` として貯まり、「UXで勝てる」の証拠になる
- スレッドに貼っても拾う

## 品質の線引き

- **カードを増やすことは目的ではない**。パターンに昇華されて初めて価値になる。
  カードだけ増えてパターンが更新されない状態が続いたら、それは失敗している
- 1回の実行で20枚まで。雑な50枚より丁寧な10枚
- **「洗練されている」「モダン」の類は書かない**（`references/analysis-guide.md` の禁止表）。
  再現できない言葉はカードに載せない
- 集める量の目安: 1ジャンル **5〜10アプリ × 5〜10枚**でパターンが立つ。
  全ジャンルを網羅しようとすると続かないので、**これから作るジャンルと競合**から埋める
