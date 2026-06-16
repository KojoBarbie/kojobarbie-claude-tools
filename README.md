# kojobarbie-claude-tools

KojoBarbie 個人開発用の [Claude Code](https://docs.claude.com/en/docs/claude-code) プラグイン マーケットプレイス。

GitHub issue から PR・セルフレビューまでの開発ワークフローを支援するスキルをまとめている。
特定のプロジェクトに依存しないよう作ってあるので、別リポジトリにそのまま導入して使える。

## 導入

```
/plugin marketplace add KojoBarbie/kojobarbie-claude-tools
/plugin install dev-workflow-tools@kojobarbie-tools
```

- `marketplace add` は**1マシンにつき1回**でよい（登録はユーザー単位）。2つ目以降のプロジェクトでは `install` だけで済む。
- インストール後、各スキルは `/dev-workflow-tools:<skill-name>` の名前空間付きで呼べる（自動トリガーも有効）。

## 収録プラグイン

### `dev-workflow-tools`

GitHub issue/PR の開発ワークフロー用スキル集。「アイデア → Issue 化 → 実装 → PR → セルフレビュー → 修正」を一気通貫で支援する。

| スキル | 役割 |
|---|---|
| **feature-planning** | ふわっとした機能アイデアを 1 問ずつ対話的に深掘りし、ユーザーストーリー＋受け入れ条件の親 Issue を作成。実装単位のサブ Issue に分割して GitHub ネイティブの sub-issue としてリンクするところまでを一気通貫で行う。 |
| **ship-issue** | GitHub issue 番号を1つ受け取り、要件読取 → プランモードでの計画承認 → 実装＋テスト → PR 作成 → サブエージェントによるレビュー（PR インラインコメント）→ 修正/返信の1往復 → 停止、までを人手最小で自走させる実装オーケストレーター。`pr-batch-review` / `pr-review-unresolved` / `pr-comment-reply` を内部で利用する。 |
| **pr-batch-review** | 複数のインラインレビューコメントを 1 つの GitHub PR レビューとしてまとめて投稿し、通知ノイズを減らす。 |
| **pr-review-unresolved** | 現在のブランチの PR から未解決のインラインレビューコメントを取得して一覧表示する。 |
| **pr-comment-reply** | comment ID を指定して、特定のインラインレビューコメントに返信を投稿する。 |

#### 標準的な使い方

1. `feature-planning` でアイデアを Issue 群に落とし込む
2. `ship-issue <issue番号>` で実装 → PR → セルフレビュー → 修正まで自走させる
   （`ship-issue` がレビュー投稿・未解決取得・返信に他の 3 スキルを自動で使う）

### 前提

- [GitHub CLI (`gh`)](https://cli.github.com/) がインストール済み・認証済み（`gh auth status`）であること
- `jq` がインストール済みであること（`pr-batch-review` が使用）

## 日常運用

- **スキルを更新**: このリポジトリで `SKILL.md` を編集して push → 利用側で `/plugin marketplace update kojobarbie-tools`
- **スキルを追加**: `plugins/dev-workflow-tools/skills/` 配下にディレクトリを追加して push するだけ
- **バージョン**: `plugin.json` に `version` を書いていないため、git のコミット SHA がバージョン扱いになり、push のたびに更新が配信される

## ライセンス / 注意

個人運用のツール集です。スクリプトは `gh` CLI の認証情報を利用しますが、リポジトリ内にトークン等の機密情報は含みません。
