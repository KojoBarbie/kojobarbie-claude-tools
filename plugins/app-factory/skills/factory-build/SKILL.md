---
name: factory-build
description: >
  App Factory の「手」。ポートフォリオ全体から着手可能な GitHub issue を優先度順に選び、
  計画承認なしで実装 → テスト → PR → セルフレビュー → 条件付き auto-merge まで自走する
  実装オーケストレーター。毎日 5:00 / 23:00 に launchd（com.claude.factory-build）から
  無人実行されるほか、「溜まってる issue を消化して」「ファクトリー回して」と言われたら手動でも使う。
  1回の実行で最大2 issue。auto-merge は機械的な安全条件を全て満たしたときだけ。
---

# factory-build — issue の自律実装ループ

## 前提

**最初に `~/.config/app-factory/config.env` を読み込む**（無ければ各変数はデフォルト値: `APP_FACTORY_HOME=~/dev/others/claude-cron`、`PRD_VAULT_DIR=~/dev/prd-vault`）。

`ship-issue` スキルの弟分。ship-issue が「人が計画を承認して1件やる」のに対し、
factory-build は「**どの issue をやるかの選定から auto-merge まで無人**」で最大2件回す。
実装・レビューの中身は ship-issue の手順を踏襲するが、**プランモードには一切入らない**
（計画は PR 本文に書き、人間の確認は PR とレビューコメントで事後に可能な形で残す）。

## 安全レール（先に全部書く）

1. **1回の実行で最大2 issue**。それ以上は次回（1日2回動く）に回す
2. **auto-merge は段階導入スイッチが ON のときだけ**: `$APP_FACTORY_HOME/data/factory_automerge_enabled`
   というファイルが存在する場合のみ auto-merge を試みる（無ければ条件を満たしても PR を残して人間へ。
   ロールアウト初期はスイッチ OFF で1〜2週様子を見る運用）。ON でも以下を全て満たすときだけ:
   - ローカルの全テストが green
   - PR の CI チェックが全て green（`gh pr checks` で確認。チェックが1つも無いリポジトリでは
     ローカルテスト green を代用条件とする）
   - セルフレビューで severity「高」の指摘がゼロ
   - 差分が 600 行未満（`gh pr diff --name-only` と diffstat で判定）
   - **センシティブ領域を触っていない**: 課金（StoreKit / RevenueCat / Product ID）、
     権限（Info.plist の Usage Description / entitlements）、データ移行（.xcdatamodel /
     マイグレーションコード）、CI 設定（.github/workflows / ci_scripts）、署名設定。
     1ファイルでも該当したら auto-merge しない
3. 条件を満たさない PR は **open のまま残して人間に回す**（Slack 通知 + 週報に載る）
4. **同一 issue で2回失敗**（テストが直らない・実装が完了できない）したら `factory-blocked`
   ラベルを付けて以後スキップ。理由を issue にコメントする（🤖 プレフィックス）
5. 着手時に `factory-wip` ラベルで排他（朝の回と夜の回の二重着手防止）。
   実行の最後に必ず外す（PR が open で残る場合も外す — PR の存在自体が排他になる）
6. main / master への直接 push・force push・テストの削除や skip は禁止

## ステップ 0: 対象の把握

1. `$PRD_VAULT_DIR/portfolio.yml` を読む（無ければ「portfolio-review を先に実行してください」と
   ログ・Slack に残して終了）
2. アプリを **stage 優先度順**に並べる: `building` → `growing` → `validating` → それ以外は対象外
3. 前回の残り物を先に処理する: 各対象リポジトリで自分が過去に作った open PR
   （head ブランチが `factory/` プレフィックス）を確認し、
   **CI が完了していて auto-merge 条件を満たすものがあれば先にマージする**
   （前回「CI 待ちで持ち越し」たものの回収。これは本日の2件にカウントしない）
4. **人間からの修正指示（PR コメント）を拾う**: 上記の open PR にある**人間のコメント**
   （bot の投稿は `🤖` プレフィックスで判別・除外）があれば、それが修正指示のチャネル。
   **インラインの単発レビューコメント**（`gh api repos/<owner>/<repo>/pulls/<n>/comments`）と
   **PR 全体コメント**（`gh api repos/<owner>/<repo>/issues/<n>/comments`）の**両方**を拾う
   （このリポジトリ運用では全アカウントが同一名義のため、人間は正式 Review = approve/request-changes を
   自分の PR に付けられない。普通のコメントが唯一の修正指示チャネルになる）。
   マージ判定より先に **ship-issue のステップ6と同じ1往復**を行う:
   コメントごとに「修正 → テスト → コミット → 返信」または「対応しない理由を返信」。
   返信は必ず `🤖` プレフィックスを付ける。
   往復は1回で打ち切り（返信への再反応は次回実行に委ねる — 無限ループ防止）。
   往復後に auto-merge 条件を再評価する。**人間のコメントが1件でも残っている PR は、
   全コメント解決（resolved）まで auto-merge しない**（人間の意見が機械条件より優先）。
   **返信したら必ず Slack に「返信したよ」通知を出す**（下記）:

   > ⚠️ 重要（同一名義問題）: bot も人間も同じ GitHub アカウントなので、bot が返信・修正しても
   > **人間には GitHub 通知が飛ばない**。放置すると「返してくれたのか分からない」でループが閉じない。
   > そのため、人間コメントに対応した PR は **1本ごとに** `SLACK_WEBHOOK_URL_FACTORY`
   > （無ければ `SLACK_WEBHOOK_URL`）へ次の内容を投稿する:
   > 「💬 <アプリ名> PR #N のコメントに対応しました（修正 X 件 / 返信 Y 件）→ <PR URL>。
   > 　内容を確認して、OK なら merge、まだなら PR にコメントを追記してください（次回実行で拾います）」

## ステップ 1: issue の選定（最大2件）

各アプリのリポジトリで open issue を取得し、以下の優先度で候補を並べる:

```bash
gh issue list -R <owner/repo> --state open --limit 100 \
  --json number,title,labels,body,createdAt
```

**優先度（上から）**:

1. `building` アプリの MVP issue（app-kickoff が起票したもの）。`measurement` ラベル
   （計測実装）を最優先、残りは番号昇順
2. `feature-approved` の親を持つ sub-issue（feature-hunt / growth-advisor 承認済み機能の子）
3. 監査 issue（quality-release-cycle 起票）。優先度「高」→「中」の順
4. `measurement` ラベルの計測実装 issue（validating / growing アプリ）

**除外**:

- ラベル: `factory-blocked` / `factory-wip` / `feature-proposal`（未承認の提案）/
  `release-train` / `[Tracking]` 系 / `app-review-rejected`
- open な sub-issue を持つ親 issue（親は分割結果であって実装単位ではない）
- 本文に「Blocked by #N」があり #N が open のもの、GitHub の blocked-by 関係が未解決のもの
- 本文が曖昧で受け入れ条件が読み取れないもの → `needs-clarification` ラベルを付けて
  コメントで不明点を書き、人間に回す（無理に実装しない）

選定した issue に `factory-wip` ラベルを付ける。

## ステップ 2: issue ごとの実装（ship-issue 踏襲・計画承認なし）

**ユーザーの作業コピーを汚さないため、使い捨て worktree で作業する**:

```bash
cd <アプリの絶対パス>
git fetch origin
DEFAULT=$(gh repo view --json defaultBranchRef -q .defaultBranchRef.name)
WT=$(mktemp -d /tmp/factory_<App>_<issue>.XXXX)
git worktree add "$WT" "origin/$DEFAULT"
cd "$WT" && git switch -c factory/<type>-<short-desc>
```

以降は **ship-issue の「無人モード」**（ship-issue SKILL.md 冒頭の実行モード参照）と同じ契約で進める。
プランモード（EnterPlanMode / ExitPlanMode）は使わないが、**計画→実装の順序は必ず守る**:

1. **計画を最初に書き出す**（承認は求めない・省略もしない）: ship-issue のステップ2と同じ5項目
   （アプローチ / 変更ファイル一覧 / テスト方針 / ブランチ名と PR タイトル案 /
   受け入れ条件の解釈と未確定の仮説）を文章化し、**実装開始前に issue へ `🤖 実装計画:` コメント
   として投稿**する。同じ内容を PR 本文の「実装計画」セクションにも載せる
   （人間が朝、計画と差分を突き合わせて事後レビューできる状態を作る）。
   **計画は対象リポジトリの `docs/architecture.md` / `docs/test-strategy.md`（あれば）に必ず整合させる**:
   レイヤ配置・禁止事項・テストコマンドはそこに従い、逸脱が必要な issue は自動実装せず
   `needs-clarification` で人間に回す（無人実装がアーキテクチャを勝手に曲げない）
2. 実装 + テスト。テストランナーは CLAUDE.md / `.claude/quality-cycle.md` の規約に従う
3. テストが直らない場合はそこで打ち切り: worktree を片付け、失敗回数を issue コメントに記録
   （2回目なら `factory-blocked`）
4. push して PR 作成。本文に実装計画 + `Closes #<N>` + 冒頭に
   `🤖 factory-build による自動実装` を明記
5. **セルフレビュー**: ship-issue と同じくレビュー専任サブエージェントを起動し、
   `ship-issue/references/review-criteria.md` の観点で `pr-batch-review` により
   インラインコメントを投稿させる
6. **修正の1往復**: 指摘に対応（コメントごとに修正コミット + 返信）。往復は1回で打ち切り

## ステップ 3: auto-merge 判定

安全レール2の条件を上から機械的に確認する:

```bash
gh pr checks <PR番号> --watch --interval 60   # 最大30分待つ。タイムアウトしたら持ち越し
gh pr diff <PR番号> --name-only               # センシティブ領域の判定
```

- **全条件クリア** → `gh pr merge <PR番号> --merge --delete-branch`。issue は Closes で自動 close
- **CI 待ちタイムアウト** → PR を open のまま持ち越し（次回実行のステップ0で回収）
- **条件不成立**（高指摘あり / 差分過大 / センシティブ領域）→ PR に理由をコメントし open のまま人間へ

最後に worktree を削除し（`git worktree remove`）、`factory-wip` ラベルを外す。

## ステップ 4: 報告

**実行のたびに、その回の活動サマリを必ず Slack に1通出す**（`SLACK_WEBHOOK_URL_FACTORY`、
無ければ `SLACK_WEBHOOK_URL`）。人間が放置していても「今回 factory が何をして・どの PR になったか」を
毎回追える状態を作るのが目的。**触れた PR は1本残らず URL を添える**（PR 名だけで URL 無しは禁止）。

ヘッダに実行時刻と1行サマリ（例:「🏭 factory-build 07-26 05:00 — 作成2 / マージ1 / コメント対応1」）、
続けて以下を**該当があるものだけ**、各行に PR URL 付きで:

- **新規作成した PR**: `アプリ名 #issue 1行説明 → <PR URL>`（auto-merge したか / 人間待ちか も1語で添える）
- **マージした PR**: `アプリ名 #issue → <PR URL>`
- **人間コメントに対応した PR**（ステップ0 #4 の「返信したよ」）: `アプリ名 #PR 修正X/返信Y → <PR URL>`
  「確認して merge か追記コメントを」。同一名義で GitHub 通知が飛ばないため省略しない
- **人間に回した PR とその理由**（auto-merge 条件を満たさなかった等）: `アプリ名 #PR 理由 → <PR URL>`
- **`factory-blocked` にした issue**: `アプリ名 #issue 理由 → <issue URL>`
- **着手を見送った理由**（`needs-clarification` 化・依存待ち等、あれば1行）

各 PR/issue の URL は `gh pr view <n> --json url -q .url` / `gh issue view <n> --json url -q .url` で取得する。

**着手できる issue が1件も無かった回**だけは例外で、`🏭 factory-build <時刻> — 着手可能な issue なし（異常なし）`
の1行だけを出す（活動ゼロでも「動いたこと」は毎回伝える。ただし1行に圧縮してノイズを抑える）。

## エッジケース

- **対象 issue ゼロ**: 正常。ステップ4 の「着手可能な issue なし（異常なし）」1行だけを出して終了
- **リポジトリのテストコマンド不明**: `xcodebuild test` / `fvm flutter test` を自動検出で試し、
  それでも不明なら実装せず `needs-clarification` で人間へ
- **コンフリクト**（同じファイルを触る issue が並んだ場合）: 2件目の実装前に必ず
  `git fetch` して最新の default branch から worktree を切り直す
- **手動実行**: 件数上限をユーザーが指定できる（「5件やって」）。auto-merge 条件は変えない。
  **PR にコメント/修正依頼したものを今すぐ拾わせたい**ときも「ファクトリー回して」で手動起動できる
  （定時の 5:00 / 23:00 を待たなくてよい）

## 設計メモ（なぜこの形か）

- **計画承認を外せる**のは、上流（PRD 承認・機能👍・監査の裏取り）で「やる価値」が既に
  人間/規律を通過しており、issue 単位の実装方針ミスは PR + レビューコメントで事後検出できるため。
  方向ミスのコストは auto-merge 条件（小さい差分・センシティブ領域除外）で上限が抑えられている
- **使い捨て worktree** は audit ジョブと同じパターン。深夜実行がユーザーの作業中ブランチと
  衝突しないための必須条件
- **1回2件 × 1日2回**は、トークン消費と「壊れたとき人間が追える量」のバランス。
  増やすときは上限を上げるのではなく実行回数を増やす（1回の失敗の影響範囲を保つ）
- **人間コメントの往復に Slack「返信したよ」通知を必ず添える**のは、この運用では bot も人間も同一
  GitHub アカウントで、bot の返信・修正コミットに対して人間へ GitHub 通知が飛ばないため。
  通知が無いと「返してくれたのか分からない」で往復が死ぬ。GitHub 上で内容をやり取りし（監査ログは
  PR に残る）、「見に来てほしい」合図だけを Slack で出す、という役割分担にしている
