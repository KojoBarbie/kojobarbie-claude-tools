# GitHub Issue 作成・sub-issue リンク手順

このスキルが Issue を作成・リンクするときの具体コマンド集。リポジトリ固有の値は一切ハードコードせず、すべて `gh` から取得する。

## 0. 環境確認

```bash
gh auth status                          # 認証されているか
gh repo view --json owner,name          # owner / repo を特定（git リポジトリ内である必要）
```

`gh repo view` が失敗する場合は git リポジトリ外か、リモートが未設定。ユーザーに伝えて止める。

## 1. ラベル取得

```bash
gh label list --limit 100
```

出力されたラベルから、機能の性質に合うものを選ぶ（例: 新機能なら `enhancement`、特定プラットフォーム向けならそのラベル）。
**新規ラベルは作成しない。** 適切なものが無ければラベル無しで作る。

## 2. 親 Issue の作成

本文は長くなるのでヒアドキュメントかファイル経由で渡す。

```bash
gh issue create \
  --title "<親 Issue のタイトル>" \
  --label "enhancement" \
  --body "$(cat <<'EOF'
## ユーザーストーリー
...
## 受け入れ条件
- [ ] ...
EOF
)"
```

`gh issue create` は作成した Issue の **URL を stdout に返す**。その URL 末尾が Issue 番号なので、返り値を変数で受けて番号を抽出するのが最も確実:

```bash
parent_url=$(gh issue create --title "<タイトル>" --label "enhancement" --body "...")
parent_number="${parent_url##*/}"
echo "Created parent issue #${parent_number}"
```

`gh issue list --limit 1` で「直近の Issue」を取りに行く方法は使わない。`create` と `list` の間に別の Issue（CI・別セッション等）が作られると最新がすり替わり、複数 Issue を連続作成するこのスキルでは**リンク先が入れ替わる深刻なバグ**になる。必ず `create` の返り値 URL から番号を取ること。

複数 Issue をまとめて作るときは、作成のたびに返ってくる番号を変数に確実に対応付けて記録する。取り違えるとリンクがぐちゃぐちゃになる。

## 3. サブ Issue の作成

親と同じ要領で 1 件ずつ作成し、返り値 URL からそれぞれの番号を控える。

```bash
child_url=$(gh issue create --title "<サブ Issue タイトル>" --label "enhancement" --body "$(cat <<'EOF'
## 概要
...
親 Issue: #<親番号>
EOF
)")
child_number="${child_url##*/}"
echo "Created sub issue #${child_number}"
```

## 4. sub-issue としてリンク（GitHub ネイティブ）

GitHub の sub-issue 機能は REST API で操作する。子 Issue の **database id（数値の `id`、Issue 番号ではない点に注意）** を親に紐づける。
この手順は fiddly なので、同梱の `link_sub_issue.sh` を使う。スクリプトは**プラグインルートからの絶対パスで呼ぶ**（`${CLAUDE_PLUGIN_ROOT}` はプラグイン実行時にこのプラグインのルートへ自動展開される）:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/feature-planning/scripts/link_sub_issue.sh <親番号> <子番号>
```

スクリプトは内部で以下を行う:

```bash
owner_repo=$(gh repo view --json owner,name --jq '"\(.owner.login)/\(.name)"')
child_id=$(gh api "repos/$owner_repo/issues/<子番号>" --jq '.id')   # database id
gh api -X POST "repos/$owner_repo/issues/<親番号>/sub_issues" -F sub_issue_id="$child_id"
```

### sub-issue API が失敗する場合

組織の設定やプレビュー機能の状態によっては 404/403 になることがある。その場合の代替:

1. **親本文のタスクリストで代用** — 親 Issue の本文に `- [ ] #<子番号>` を並べる。GitHub はこれを「tracked tasks」として認識し、進捗バーも出る。
2. リンクできなかった子 Issue を報告に明記する。

`gh issue edit --body` は本文を**全置換**する。既存本文を取得せずに渡すと内容が消えるので、必ず現在の本文を読み出してから追記する:

```bash
# 1. 既存の本文を取得
existing_body=$(gh issue view <親番号> --json body --jq .body)

# 2. サブタスクを追記して更新（既存本文を保持）
gh issue edit <親番号> --body "${existing_body}

## 実装サブタスク
- [ ] #<子番号1>
- [ ] #<子番号2>"
```

## 5. 親本文にチェックリストを追記（任意・推奨）

ネイティブ sub-issue でリンクしていても、本文に `- [ ] #子番号` のチェックリストを併記しておくと一覧性が上がる。`gh issue edit <親番号> --body ...` で更新する。

## トラブルシュート早見表

| 症状 | 原因 | 対処 |
| --- | --- | --- |
| `gh: command not found` | gh 未インストール | ユーザーに `brew install gh` を案内 |
| `gh auth status` が NG | 未認証 | `gh auth login` を案内して止める |
| `gh repo view` が失敗 | git リポジトリ外 / リモート未設定 | カレントディレクトリを確認 |
| sub_issues API が 404/403 | 機能未対応・権限不足 | タスクリストで代替（上記） |
| ラベル付与でエラー | そのラベルが存在しない | `gh label list` で再確認、無ければラベル無しで作成 |
