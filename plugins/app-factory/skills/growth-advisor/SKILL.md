---
name: growth-advisor
description: "growing ステージのアプリ1本に対し、コード探索＋製品コンテキスト（PRDのジョブ分析・KPI実績・過去の却下履歴）＋実メトリクスを統合して「もっと売れる/成長するため」の施策を多軸（新機能/収益化・価格/ASO・ストア導線/リテンション/PMF仮説）で主体的に提案し、feature-hunt と同形式の GitHub Issue として起票するスキル。Use when: (1) factory-dispatch（launchd）経由の月次ローテ実行、(2)「グロース施策を提案して」「もっと売れるようにするには？」「growth-advisor を実行して」と言われたとき、(3) growing ステージのアプリの収益・成長の伸ばし方を相談されたとき。対象リポジトリのルートを cwd として実行する。"
---

# Growth Advisor

growing ステージ（マイルストーン通過＝有望）と判定されたアプリに対し、「このアプリがもっと売れる/成長するには」を**主体的に**考えて提案するスキル。feature-hunt（週次の新機能提案）の姉妹スキルで、機能に限らず収益化・ASO・リテンション・PMF 仮説まで軸を広げるのが違い。

**成果物は最大3件の提案 Issue（feature-hunt と完全に同形式）+ Slack 通知**。承認後の sub-issue 分割は feature-hunt の approve モードに委ねる。**このスキルの責務は提案まで**。

## スコープ

- **提案する**: 新機能 / 収益化・価格 / ASO・ストア導線 / リテンション施策 / PMF 仮説の5軸。コード変更にならない施策（ストア文言・価格変更など）も、Issue として作業手順が書けるなら提案してよい
- **提案しない**: バグ修正・パフォーマンス・品質系（quality-release-cycle の領分）
- **汎用SaaS機能の垂れ流しを禁止**: 通知センター・ダッシュボード・アクティビティフィード・オンボーディングウィザードのような「どのアプリにも付けられるが誰の課題も解いていない」提案は出さない。根拠が「一般論・ベストプラクティス」しかない案は捨てる
- 基準を満たす案がなければ無理に3件出さず、その旨を Slack に報告する

## 前提リソース

**最初に `~/.config/app-factory/config.env` を読み込む**（無ければ各変数は括弧内のデフォルト値を使う）。

| リソース | パス |
|---|---|
| ポートフォリオ状態 | `$PRD_VAULT_DIR/portfolio.yml`（`PRD_VAULT_DIR` のデフォルト: `~/dev/prd-vault`。stage / kpi=M1〜M3達成状況 / metrics） |
| 該当 PRD | portfolio.yml の `prd` が指すファイル（`$PRD_VAULT_DIR/` 配下） |
| 製品コンテキスト | `<cwd>/.claude/product-context.md`（**毎回必読**） |
| 提案・却下の履歴 | `<cwd>/.claude/feature-hunt-log.md`（却下理由＝好みの学習データ） |
| 環境変数 | `$APP_FACTORY_HOME/.env`（`APP_FACTORY_HOME` のデフォルト: `~/dev/others/claude-cron`。`set -a && source && set +a` で読み込む） |
| Slack投稿 | `python3 $APP_FACTORY_HOME/.claude/skills/slack-post/scripts/slack_post.py --file <md> --header <題> --webhook-url "$WEBHOOK"`。webhook は `SLACK_WEBHOOK_URL_FEATURE` があればそれ、なければ `SLACK_WEBHOOK_URL`（`slack-post` スキルは作者環境の前提。無い環境では curl で webhook に直接 POST する） |
| Issue/ログ書式 | feature-hunt スキルの `references/proposal-format.md`（**この書式に完全に合わせる**） |
| Analytics | `$APP_FACTORY_HOME` の `firebase-bigquery` スキル（portfolio.yml に `analytics_env_prefix` がある場合のみ。作者環境の前提 — 無い環境ではスキップ） |

## モード判定

1. **無人実行** — factory-dispatch（launchd）経由の月次ローテ。ユーザーへの質問は一切せず、このスキルの基準で自分で判断する。判断に迷った点は Slack 報告に書き添える
2. **手動実行** — 「グロース施策を提案して」等。提案の方向性や絞り込みをユーザーと対話しながら調整してよい。Step 0 のステージガードも確認の上で緩められる

どちらのモードでも、作業ディレクトリは対象アプリのリポジトリルート。最初に最新化する:

```bash
[ -f ~/.config/app-factory/config.env ] && . ~/.config/app-factory/config.env
git pull
git -C "${PRD_VAULT_DIR:-$HOME/dev/prd-vault}" pull
set -a && source "${APP_FACTORY_HOME:-$HOME/dev/others/claude-cron}/.env" && set +a
```

## Step 0: ステージガードと事前チェック

1. portfolio.yml から対象アプリのエントリ（stage / kpi / metrics / prd / analytics_env_prefix）を読む。対象アプリの特定は cwd のリポジトリ名（`gh repo view --json nameWithOwner` または `git remote`）と portfolio.yml の `repo` の突き合わせで行う
2. **stage が `growing` でなければ**:
   - 無人実行（factory-dispatch 経由）→ 「対象外（stage=xxx）」とログに出して**即終了**。Issue も Slack 通知も出さない
   - 手動実行 → ユーザーに「stage は xxx ですが続行しますか？」と確認し、了承があれば続行
3. **未反応の提案が溜まっていないかチェック**（feature-hunt と同じルール）:

```bash
gh issue list --label feature-proposal --state open --limit 30 --json number,title,labels
# 各 open 提案の 👍 有無を確認
gh api repos/{owner}/{repo}/issues/N/reactions --jq '[.[] | select(.content == "+1")] | length'
```

   `go` ラベルも 👍 リアクションも付いていない open の feature-proposal が**6件を超えていたら、新規提案はせず** Slack で「提案がたまっています（N件）。👍/go か close をお願いします」とだけ通知して終了する

## Step 1: 2段階入力（コード探索 + 製品コンテキスト）

コードだけ読んでも製品は分からず、製品文書だけ読んでも実装の現在地は分からない。**必ず両方**集めてから提案する。

### ❶ コード探索（Explore サブエージェント）

Explore サブエージェントに機能棚卸しをさせる。指示に含める観点:

- 画面一覧（何ができるアプリか、主要フローは何か）
- データモデル（どんなデータが既に貯まっているか。既存データを活かす提案の種）
- **収益化実装の有無**（IAP/サブスク/ペイウォール/広告は実装済みか、どの体験が有料か）
- **計測イベントの実装状況**（Firebase Analytics のイベント名を実装から列挙。PRD の計測計画との差分を取るため）

### ❷ 製品コンテキスト

以下を自分で読む（サブエージェント不要）:

1. **PRD**（prd-vault の該当ファイル）— 特に「**ジョブ分析**」（誰がどんな状況で何の代わりに雇うアプリか）と「**KPIと計測計画**」（KPI ツリー・コア行動・計測イベント一覧・M1〜M3）
2. `.claude/product-context.md` — コア体験と「やらないこと」
3. **portfolio.yml の kpi / metrics** — M1〜M3 の達成状況、DL/DAU/D1/アクティベーション率/収益の実数と傾向。`unmeasured` の指標はどれかを控えておく
4. `.claude/feature-hunt-log.md` — 過去の提案と**却下理由**。却下理由はユーザーの好みの最重要学習データ。同系統の再提案を避け、好みの方向に寄せる
5. `analytics_env_prefix` があれば firebase-bigquery スキルでファネル・離脱箇所を取得（無ければスキップし、Slack 報告に「Analytics未接続」と一言添える）

## Step 2: 多軸で候補を出す

❶❷を突き合わせ、**5軸それぞれで**候補を挙げてから、全体で最大3件に絞る:

1. **新機能** — ジョブ分析のジョブを深く/広く片付ける機能。既存データ・基盤で安く作れるものを優先
2. **収益化・価格** — ペイウォール位置・価格・トライアル設計・有料限定機能。収益化が未実装なら「最初の収益化」自体が最有力候補
3. **ASO・ストア導線** — キーワード・スクショ・サブタイトル・レビュー促進。DL が KPI ツリーのボトルネックのときに効く
4. **リテンション施策** — D1/D7 が弱いときの、コア行動への再訪導線（安易なプッシュ通知乱発ではなくジョブに根ざした理由付け）
5. **PMF 仮説** — メトリクスがジョブ分析と食い違うとき（例: 想定と違う使われ方）の、ポジショニング・コア体験の仮説転換

絞り込みの基準: **KPI ツリー上のボトルネック（M1〜M3 で未達・伸び悩みの指標）に直接効く軸を優先**する。複数の情報源（コード観察 × メトリクス × レビュー/却下履歴）が同じ方向を指す案を上位に。カテゴリと規模（S/M/L）を付ける。

## Step 3: 空想機能フィルタ

各提案に以下3点セットを**必須化**する。1つでも書けない案は捨てる:

- **根拠**: 「このアプリの」実物への言及であること — このコード（`path/to/file` に基盤がある）、このメトリクス（D1 が 12% で M1 基準 15% 未達）、この却下履歴（過去に×だった○○系を避けて△△に寄せた）。**一般論しか書けない案は不合格**
- **前提**: この提案が成立する条件。外れていたら見送るべきこと
- **検証方法**: **KPI ツリーのどの指標が、どれだけ動けば成功か**を数値で書く。その指標の計測イベントが実装済みかを❶の棚卸し結果で確認して明記する
- **未計測の指標に依存する提案は、「まず計測実装」を提案の子タスク先頭に含める**（数字が取れないまま施策だけ打たない）

## Step 4: Issue 起票と学習ログ

1. **重複排除**: `gh issue list --state all --limit 100` の全タイトルと `feature-hunt-log.md` に対して照合。既存 issue（open/closed とも）・過去に却下された案と同じ提案は出さない
2. feature-hunt の `references/proposal-format.md` と**完全に同じフォーマット**で 1提案 = 1 Issue を作成。タイトルは `[カテゴリ/規模] 施策名`、本文は 概要 / なぜ（根拠）/ 前提 / 検証方法・成功指標 / 子タスク分割ドラフト + 末尾の承認方法1行
3. ラベルは `feature-proposal` **に加えて `growth`** を付ける（`growth` ラベルが無ければ `gh label create growth` で作成）

```bash
gh issue create --title "[収益化/M] ..." --body-file /tmp/proposal.md --label feature-proposal --label growth
```

4. `feature-hunt-log.md` に1行追記してコミット・プッシュする。書式は feature-hunt の references に従い（`日付 | Issue# | タイトル | カテゴリ | 結果 | 却下理由メモ`）、**カテゴリ欄は `growth-収益化` のように `growth-` プレフィックスを付ける**（feature-hunt の提案と出所を区別するため）。例:

```
2026-07-10 | #42 | トライアル開始前の価値提示画面 | growth-収益化 | 提案中 |
```

## Step 5: Slack 通知

各提案のタイトル・カテゴリ・規模・根拠の要約・Issue URL と、「どの KPI ボトルネックを狙ったか」を1行で添えて投稿する。「👍 or `go` ラベルで承認 / close で見送り」の操作方法を毎回一行添える。

```bash
WEBHOOK="${SLACK_WEBHOOK_URL_FEATURE:-$SLACK_WEBHOOK_URL}"
python3 "${APP_FACTORY_HOME:-$HOME/dev/others/claude-cron}"/.claude/skills/slack-post/scripts/slack_post.py \
  --file /tmp/growth_report.md --header "growth-advisor: <アプリ名> の施策提案" \
  --webhook-url "$WEBHOOK"
```

（`slack_post.py` は作者環境の前提。無い環境では curl で `$WEBHOOK` に直接 POST する）

## 承認フロー（このスキルの外）

承認の検知と sub-issue 分割は **feature-hunt の approve モードに委ねる**。growth-advisor の提案 Issue は `feature-proposal` ラベルを共有しているため、feature-hunt の週次実行（Step 1）や「#N を Go」で自然に拾われ、sub-issue 化されて factory-build の川に流れる。このスキル自身は承認処理を実装しない。

## 規律（必ず守る）

- **無人実行時はユーザーに質問しない**。このスキルの基準で自分で判断し、判断に迷う点は Slack 報告に書く
- 対象が growing 以外なら無人実行では即終了（Step 0）
- 未反応 feature-proposal が6件超なら新規提案しない（Step 0）
- 根拠・前提・検証方法の3点セットが揃わない提案は出さない（Step 3）
- 未計測指標に依存する提案は「まず計測実装」を含める（Step 3）
- 汎用SaaS機能の垂れ流し禁止。product-context.md の「コア体験を深めるか？」の自問は毎回行う

---

## 設計メモ

- **feature-hunt と Issue 形式・ラベル・ログを完全共有**しているのは意図的: 承認 UI（👍/go）・approve モードの分割・factory-build の巡回という下流をそのまま再利用でき、人間の操作が1種類で済む。`growth` ラベルと ログの `growth-` プレフィックスだけで出所を区別する
- **2段階入力**（コード探索＋製品コンテキスト）は docs/growth-advisor-research.md の中核知見: コードだけ読ませると汎用SaaS機能を返す失敗（uxdesign.cc）を、PRD のジョブ分析・KPI 実績・却下履歴の注入で回避する
- **3点セット必須化**は ASE 2024（arXiv:2408.17404）の「LLM の機能提案は強力だが空想的な案が混じり人間レビュー前提」への対策。検証方法を KPI ツリーに紐付けることで、portfolio-review の週次判定がそのまま施策の成否判定になる
- 月次ローテ・1回1アプリなのは app-factory 全体の「トークン消費を割当表で平準化する」原則（factory-dispatch）に従うため
