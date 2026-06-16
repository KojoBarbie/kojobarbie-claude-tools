---
name: ship-issue
allowed-tools: Read, Edit, Write, Glob, Grep, Agent, TodoWrite, Skill(pr-batch-review), Skill(pr-review-unresolved), Skill(pr-comment-reply), Bash(git:*), Bash(gh:*), Bash(*/skills/pr-batch-review/scripts/submit_batch_review.sh:*), Bash(*/skills/pr-review-unresolved/scripts/get_unresolved_comments.sh:*), Bash(*/skills/pr-comment-reply/scripts/reply_to_pr_comment.sh:*)
description: GitHub issue 番号を1つ受け取り、要件読取 → プランモードでの計画承認 → 実装+テスト → PR作成 → サブエージェントによるレビュー(PRインラインコメント) → 修正/返信の1往復 → 停止、までを人手を最小化して自走させる実装オーケストレーター。ユーザーが「issue #42 を実装して」「この issue をやって」「issue から実装して PR まで出して」「ship-issue 42」のように、既存の GitHub issue を起点にコードを書いてレビューまで一気に進めてほしいと言ったら積極的に使う。要件がまだ曖昧でこれから issue を作る段階（feature-planning の領域）ではなく、すでに issue として実装内容が固まっていて、それを実装→PR→セルフレビュー→修正まで回したい局面で力を発揮する。
---

# ship-issue — issue 起点の実装オーケストレーター

## このスキルがやること

1 つの GitHub issue（実装単位）を受け取り、**人が介入するのは実装計画の承認 1 回だけ**で、実装・テスト・PR 作成・セルフレビュー・修正の 1 往復までを自走させる。終わったら「動作確認してください」と人に返す。目的は、人の手数を「計画 OK」と「最後の動作確認」の 2 点に絞ること。

このスキルは**既存スキルの束ね役（オーケストレーター）**であり、レビューと修正の実体は既存スキルを流用する：

- **レビュー投稿**: `pr-batch-review`（PR にインラインコメントを一括投稿）
- **未解決取得**: `pr-review-unresolved`
- **返信**: `pr-comment-reply`
- 修正フローの考え方は `review-fix` コマンドと同じ（このスキル内に内包する）

> Kiro（`.kiro/spec-*`、`/kiro:*` コマンド、steering）は**一切使わない・参照しない**。要件の出どころは issue 本文だけ。

## 前提と中断点

- **唯一の中断点はステップ 2（計画承認）**。ここ以外では原則ユーザーに確認を求めず自走する。
- レビュー → 修正は**必ず 1 往復で止める**。再レビューのループには入らない。残った指摘は未解決コメントとして PR に残し、最後の動作確認で人に委ねる。これは「人が入らず動作確認だけ」を成立させつつ、無限ループと暴走を防ぐための線引き。

---

## ワークフロー

### ステップ 0: 前提チェック

1. **issue 番号**を確認する。引数になければユーザーに尋ねる（このスキルは番号必須）。
2. 環境を確認する：
   ```bash
   gh auth status
   git status --short          # 作業ツリーがクリーンか
   git branch --show-current   # 通常は master にいるはず
   ```
   - 未コミットの変更があれば、続行すると混ざるので**ユーザーに確認**してから進む（stash するか、別作業中でないか）。
3. owner/repo を取得する：
   ```bash
   gh repo view --json owner,name
   ```

### ステップ 1: 要件読取

issue 本文を読み、何を作るのかを把握する：

```bash
gh issue view <N> --json number,title,body,labels,state,url
```

**親 issue（sub-issue を持つ）を渡された場合**は、実装単位が複数あるということ。子 issue 一覧を取得して提示し、「どの子を実装するか」をユーザーに選んでもらう（このスキルは 1 実装単位 = 1 PR を前提とする）：

```bash
gh api /repos/{owner}/{repo}/issues/<N>/sub_issues --jq '.[] | "\(.number) \(.title) [\(.state)]"'
```

把握すべきは「ユーザーストーリー」「受け入れ条件」「対象範囲（やらないことも）」。曖昧な点があっても、ここでは止めずに次の計画ステップで仮説として明示し、計画承認の場で人に判断してもらう。

### ステップ 2: プランモードで計画 → 承認（唯一の中断点）

プランモードに入り、実装計画を提示してユーザーの承認を得る。承認後はステップ 3 以降を自走する。

計画に必ず含めるもの：

- **アプローチ**: どの層をどう変えるか（1〜3 文）
- **変更ファイル一覧**: 新規/修正の見込み
- **テスト方針**: どのテストを追加/更新するか
- **ブランチ名と PR タイトル案**: Conventional Commits 準拠（例 `feat/diary-favorites`、`fix:` `feat:` `chore:` `ci:` を issue 種別から選ぶ）
- **受け入れ条件の解釈と未確定の仮説**: issue が曖昧だった点をここで言語化する

承認されなければ計画を直して再提示する。**承認されるまでコードは書かない。**

### ステップ 3: 実装 + テスト

承認された計画に沿って実装する。

1. ブランチを切る（master を基点に）：
   ```bash
   git switch master && git pull --ff-only
   git switch -c <type>/<short-desc>
   ```
2. 実装する。テストを先に書ける箇所はテストから書く（TDD は推奨だが厳格な儀式は不要。要は「振る舞いをテストで固定してから実装」できる箇所はそうする）。
3. **テストを実行する。ここは絶対厳守**：プロジェクトのテストランナーで全テストを走らせ、デグレが無いことを確認する。
   - テスト実行コマンドはプロジェクトに合わせる（例: `npm test` / `pytest` / `go test ./...` / `cargo test` / `flutter test` など）。
   - `CLAUDE.md` や README などにテスト実行の規約（使うべきコマンド・避けるべきコマンド）があれば、**必ずそれに従う**。規約が無ければ、そのリポジトリで標準的なランナーを使う。
4. テストが落ちたら直す。直しきれない／設計上の判断が要る場合は、**自走を止めて状況を報告**する（暴走させない）。
5. コミットは Conventional Commits + 日本語本文で、論理単位ごとに分ける：
   ```bash
   git add <files>
   git commit -m "feat: <要約>

   <変更の意図・内容>
   Refs #<N>"
   ```

### ステップ 4: PR 作成

```bash
git push -u origin HEAD
gh pr create --title "<type>: <タイトル>" --body "$(cat <<'EOF'
## 概要
<このPRで何をしたか>

## 変更内容
- <箇条書き>

## テスト
- 全テストが green であることを確認

Closes #<N>
EOF
)"
```

- PR 本文に **`Closes #<N>`** を入れて issue と紐付ける（親の子を実装した場合も、その子番号を Closes する）。
- 作成された **PR 番号を返り値の URL から控える**（以降のステップで使う）。

### ステップ 5: サブエージェントによるレビュー（PR インラインコメント）

GitHub Actions のレビューには頼らず、**ローカルのサブエージェントにレビューさせ**、結果を PR 上のインラインコメントとして残す。記録が PR に残るので、後で人も追える。

`Agent` ツールでレビュー専任のサブエージェントを 1 体起動し、次を渡す：

- 対象 PR 番号・owner・repo
- レビュー観点 → **`references/review-criteria.md` を読ませる**
- 投稿方法 → **`pr-batch-review` スキルを使い、`log/review_<pr>.json` を書いて `submit_batch_review.sh` で一括投稿**するよう指示

サブエージェントへの依頼テンプレート（要旨）：

```
あなたはこの PR の独立したレビュアーです。甘くせず、実装者とは別の視点で指摘してください。

- 対象: <owner>/<repo> PR #<pr>
- 差分の取得: gh pr diff <pr> / gh pr view <pr>
- レビュー観点: ${CLAUDE_PLUGIN_ROOT}/skills/ship-issue/references/review-criteria.md を読んで従う
- 投稿: pr-batch-review スキルの手順で log/review_<pr>.json を作成し、
        ${CLAUDE_PLUGIN_ROOT}/skills/pr-batch-review/scripts/submit_batch_review.sh --input log/review_<pr>.json で投稿する
- インラインは「結論を1行 → 理由 → 具体的な修正案」。全体所感は JSON の body に集約。
- 指摘が無ければ投稿せず「指摘なし」と報告する。
- 最後に、投稿した指摘の一覧（ファイル:行 と要点）を簡潔に返す。
```

サブエージェントが「指摘なし」を返したら、修正は不要。ステップ 7 へ進む。

### ステップ 6: 修正 / 返信の 1 往復

メインエージェントに戻り、PR に付いた未解決コメントへ対応する。考え方は `review-fix` コマンドと同じ。

1. **未解決コメントを取得**：
   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/skills/pr-review-unresolved/scripts/get_unresolved_comments.sh
   ```
   各コメントの path / line / **Comment ID** / body を控える。
2. **対応方針を判断**（コメントごとに）：
   - 対応する: バグ・セキュリティ・明確な改善・正しく動かない箇所
   - 対応しない: 現状の設計に正当性がある／スコープ外／トレードオフ上あえて現状維持 — この場合は**理由を用意**する（議論として返信する）
3. **修正 → テスト → コミット**：対応するコメントごとに修正し、**プロジェクトのテストランナーで全テストを実行**してデグレ無しを確認し、1 コメント 1 コミットで積む。
4. **まとめて push**：
   ```bash
   git push origin HEAD
   ```
5. **各コメントに返信**（`pr-comment-reply`）：
   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/skills/pr-comment-reply/scripts/reply_to_pr_comment.sh <owner> <repo> <comment_id> "<body>"
   ```
   - 対応した: 「修正しました。修正内容: … / 修正コミット: <hash>」
   - 対応しない: 「検討の結果、現状を維持します。理由: …」

**ここで往復は終了。再レビューはしない。** 新たに生じた論点や対応保留は、未解決コメント／PR 本文の TODO として残す。

### ステップ 7: 停止して人に渡す

最後に、人が動作確認だけで済むようサマリを提示する：

- PR の URL とタイトル
- 実装した内容（要点）
- レビュー指摘と、その対応／非対応（理由つき）
- 残課題・未確認事項（あれば）
- 一言：「ローカルでの動作確認をお願いします。OK ならマージしてください」

CI（`.github/workflows/` のテスト等）は PR 上で走るので、その結果も確認して言及する。

---

## エッジケースの扱い

- **レビュー指摘ゼロ**: ステップ 6 を飛ばしてステップ 7 へ。
- **テストが直らない / 設計判断が必要**: 自走を止め、現状・原因・選択肢を報告して指示を仰ぐ。勝手にテストを削る・skip するのは禁止。
- **作業ツリーが汚れている**: ステップ 0 で止めて確認。
- **親 issue を渡された**: 子 issue を提示して 1 つ選んでもらう。
- **既に PR が存在するブランチ**: 新規 PR を作らず、既存 PR に対してステップ 5 以降を回す。

## 設計メモ（なぜこの形か）

- **計画承認を 1 点に絞る**のは、方向ミスを最も安く（実装前に）止められる場所だから。実装後の手戻りより計画段階の数十秒の方が圧倒的に軽い。
- **レビューをローカルのサブエージェントに寄せた**のは、「PR 作成 → Actions 待ち → 人が修正コマンドを起動」という分断を消し、1 コマンドで 1 往復まで完結させるため。Actions の `claude-code-review.yml` と二重レビューになるので、Actions 側は `@claude` 手動トリガー専用に格下げしておくと衝突しない。
- **1 往復で止める**のは、AI 同士の指摘・修正が延々と続いて収束しない事態と、無人での暴走を避けるため。最終判断は人の動作確認に必ず通す。
