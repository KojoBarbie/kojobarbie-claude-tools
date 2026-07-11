---
name: feature-hunt
description: "既存アプリ（swift/flutter配下）の新機能を週次で提案するパイプライン。競合レビュー・コードベース考察・Firebase Analyticsの3情報源から最大3件の提案をGitHub Issueとして起票し、承認（goラベル/👍）されたらship-issueに投げられる粒度のsub-issueに分割する。Use when: (1) launchd経由の週次自動実行、(2)「新機能を提案して」「feature-huntを実行して」と言われたとき、(3)「このアプリをfeature-huntに追加して」「オンボーディングして」と言われたとき、(4) 提案Issueの承認を検知して子タスクに分割するとき。既存アプリへの機能追加のアイデア出しなら、スキル名が明示されていなくてもこのスキルを使う。"
---

# Feature Hunt

既存アプリの「次に作る新機能」を継続的に提案するパイプライン。app-idea-hunt（新規アプリのネタ探し）の姉妹スキル。

**成果物は最大3件の提案Issue + Slack通知**。ユーザーは各Issueに 👍リアクション or `go`ラベル（=承認）か、close（=見送り）で応えるだけでよい。承認された提案は「1タスク=1PR、そのままship-issueに投げれば実装完了できる」粒度のsub-issueに分割する。

## スコープ（何を提案し、何を提案しないか）

- **提案する**: 新機能・既存機能の改善・収益化に直結する機能（ペイウォール改善、有料限定機能など）。小さな追加でも大きな機能でもよい（規模タグ S/M/L で明示）
- **提案しない**: バグ修正・パフォーマンス・品質系（`quality-release-cycle` スキルの領分）。マーケ・ASO・GTM施策（PRにならないため）
- **汎用機能の横付けを弾く**: 提案前に必ず `.claude/product-context.md` を読み、「この提案はコア体験を深めるか？ それともどのアプリにも付けられる汎用機能か？」を自問する。通知センター・ダッシュボード・アクティビティフィードのような「それっぽいが誰の課題も解いていない」提案は出さない
- 空想的な提案を弾くため、**すべての提案に根拠（実データ・実レビュー・実コードの引用）と検証方法をセットで付ける**。根拠が書けない案は出さない
- 基準を満たす案がなければ無理に3件出さず、その旨をSlackに報告する

## 前提リソース

| リソース | パス |
|---|---|
| アプリごとの設定 | `<アプリ>/.claude/feature-hunt.yml`（オンボーディングで生成） |
| 製品コンテキスト | `<アプリ>/.claude/product-context.md`（同上。**毎回必読**） |
| 提案・却下の履歴 | `<アプリ>/.claude/feature-hunt-log.md` |
| 週次実行の対象リスト | `~/dev/others/claude-cron/feature_hunt_apps.txt` |
| 環境変数 | `~/dev/others/claude-cron/.env`（`set -a && source && set +a` で読み込む） |
| Slack投稿 | `python3 ~/dev/others/claude-cron/.claude/skills/slack-post/scripts/slack_post.py --file <md> --header <題> --webhook-url "$WEBHOOK"`。webhookは `SLACK_WEBHOOK_URL_FEATURE` があればそれ、なければ `SLACK_WEBHOOK_URL` |
| 競合検索 | `bash {skill_dir}/scripts/jp_appstore_search.sh "検索語" [limit] [country]` |
| レビュー取得 | `bash {skill_dir}/scripts/appstore_reviews.sh <app_id> [country]`（最新50件） |
| sub-issueリンク | `bash {skill_dir}/scripts/link_sub_issue.sh <親番号> <子番号>` |
| Analytics | claude-cron の `firebase-bigquery` スキル（`analytics_env_prefix` 設定時のみ） |

## モード判定

1. **onboard** — `.claude/feature-hunt.yml` が無い、または「このアプリを追加して」と言われた → [references/onboarding.md](references/onboarding.md) に従う
2. **run** — 週次実行、または「実行して」「新機能を提案して」 → 下記 Step 0〜5
3. **approve** — 「#N をGo」と言われた、またはStep 1で承認を検知 → 「承認後の分割」へ

週次実行（無人）ではユーザーへの質問はせず、このスキルの基準で自分で判断する。対話セッションでは粒度や方向性をユーザーと調整してよい。

## Run: 週次実行

作業ディレクトリは対象アプリのリポジトリルート。`git pull` してから始める。

### Step 0: 設定読み込み

`.claude/feature-hunt.yml` と `.claude/product-context.md` と `.claude/feature-hunt-log.md` を読む。yml が無ければ onboard モードを先に実行する（無人実行時も自動で行い、その旨をSlack報告に含める）。

### Step 1: 前回提案の承認・却下チェック

```bash
gh issue list --label feature-proposal --state all --limit 30 --json number,title,state,labels
```

- **open + `go` ラベル or 👍リアクション**（`gh api repos/{owner}/{repo}/issues/N/reactions` で `+1` を確認）→ 承認。「承認後の分割」を実行
- **closed（`feature-approved` が付いていないもの）** → 見送り。closeコメントがあれば理由として読み取り、`feature-hunt-log.md` に記録する。**却下理由はユーザーの好みの学習データとして最重要** — 次回以降の選定に反映する
- open のまま反応が無いものは触らない（先週の提案が残っていても今週の提案は出してよいが、未反応が6件を超えていたら新規提案を休み、Slackで「たまっています」とだけ伝える）

### Step 2: 並列リサーチ（サブエージェント3系統）

3つのサブエージェントを**同時に**起動する。各エージェントには product-context.md の内容を渡す。

1. **レビュー分析** — `appstore_reviews.sh` で自アプリ（リリース済みなら）と競合各社（yml の `competitors`）のレビューを取得。★1〜3の不満、「〜だったらいいのに」系の要望を抽出し、頻出テーマと具体的な引用をまとめる
2. **コードベース考察** — Explore系エージェントがコードを読み、既存機能の棚卸しと「既にあるデータ・基盤で安く作れて効きそうな機能」を挙げる。実装コストの見積もり（S/M/L）付き
3. **Analytics分析** — yml に `analytics_env_prefix` があるときのみ。claude-cron の `firebase-bigquery` スキルの手順でファネル・エンゲージメントを取得し、「離脱が集中している箇所」「使われていない既存機能」を特定する。未設定ならスキップし、Slack報告に「Analytics未接続」と一言添える

### Step 3: 統合・選定（最大3件）

- 3系統の材料を突き合わせ、複数の情報源が同じ方向を指す案を優先する
- **重複チェック**: `gh issue list --state all --limit 100` の全タイトルと `feature-hunt-log.md` に対して行う。過去に却下された案・既存issueと同じ案は出さない
- **コア体験フィルタ**（上記スコープ参照）を通す
- **収益化観点を毎回必ず1回は検討する**（採用しなくてもよいが、検討した形跡をSlack報告に残す）
- カテゴリ（新機能/改善/収益化）と規模（S/M/L）を付ける

### Step 4: Issue起票

[references/proposal-format.md](references/proposal-format.md) のフォーマットで1提案=1 Issueを作成。ラベル `feature-proposal` を付ける。作成後、`feature-hunt-log.md` に提案履歴を追記してコミット・プッシュする。

### Step 5: Slack通知

各提案のタイトル・カテゴリ・規模・根拠の要約と、Issue URLを投稿する。「👍 or `go`ラベルで承認 / closeで見送り」の操作方法を毎回一行添える。

## 承認後の分割（approve）

1. 提案Issue本文の「子タスク分割ドラフト」を精査し、**それぞれが独立した1つのPRとして完結・レビューできる**単位に切り直す。複数レイヤーが混ざる塊はレイヤーごとに分ける。判断基準はfeature-planningスキルと同じ: 半日〜1日で終わらない・PRが肥大化しそうなら分割
2. 各sub-issueは **ship-issueに番号を渡すだけで実装が始められる**ように書く: 目的 / 変更内容 / 受け入れ条件（観測可能な形で）/ 対象ファイルの見当 / 依存関係（着手順）
3. `gh issue create` で作成し（返り値URLから番号を取る）、`link_sub_issue.sh <親> <子>` でネイティブsub-issueとしてリンク。スクリプトが失敗したら親本文のタスクリスト（`- [ ] #N`）で代替
4. 親Issueのラベルを `feature-proposal` → `feature-approved` に付け替え、`go` ラベルは外す。親本文に着手順のチェックリストを追記
5. `feature-hunt-log.md` に承認を記録し、Slackに「#N を分割しました（sub-issue: #a #b #c、推奨着手順つき）」と通知
6. 対話セッション中なら、分割の粒度をユーザーと相談しながら進めてよい

## 学習ログ（feature-hunt-log.md）

1行1提案の表形式: `日付 | Issue# | タイトル | カテゴリ | 結果(提案中/承認/見送り) | 却下理由メモ`。重複回避とユーザーの好みの学習に使う。リポジトリにコミットして残す。
