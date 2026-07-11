# showcase サイト仕様（prd-vault/showcase）

アイデア段階のトンマナ＋モックを1か所で確認するための静的サイト。prd-vault リポジトリの `showcase/` に置き、Vercel（Root Directory=`showcase`）でデプロイする。

- Next.js App Router。全ページ静的（Server Component のみ、ビルド時に JSON を読む）。API 呼び出し・シークレットなし
- **ダークモード禁止**（アプリ全体の規約）。全ページ明るい背景
- Note: prd-vault は private リポジトリなので showcase に何を置いてもよいが、Vercel の公開 URL は誰でも開けるため、**推測されにくいプロジェクト名**（ランダムなサフィックス付き等）を使う

## ディレクトリ構成

```
showcase/
├── package.json
├── tsconfig.json        # 初回 next build が自動生成したものをコミット
├── .gitignore           # node_modules / .next
├── apps.json            # アプリ一覧（下記スキーマ）
└── app/
    ├── layout.tsx       # 共通レイアウト（明るい背景・システムフォント・簡素なヘッダー）
    ├── page.tsx         # 一覧ページ（apps.json を読んで表示）
    └── apps/
        └── {slug}/
            ├── tone/page.tsx
            └── mock/page.tsx
```

`{slug}` は動的ルートではなく、PRD ごとに実ディレクトリを作る（完全静的にするため）。

## apps.json スキーマ

```json
[
  {
    "slug": "sleep-streak",
    "name": "Sleep Streak（仮）",
    "status": "proposed",
    "prd": "prd/sleep-streak.md",
    "createdAt": "2026-07-10"
  }
]
```

- `status` は起票時 `"proposed"`。後続ステージ（キックオフ・リリース等）が更新してよい
- `app/page.tsx` は `import apps from "../apps.json"` で読み込み、name / status / createdAt と `/apps/{slug}/tone`・`/apps/{slug}/mock` へのリンクを一覧表示する。空配列なら「まだありません」と出す

## tone ページに含める要素

- **カラーパレット**: primary / secondary / accent / background / text 等のスウォッチ（色付き四角）＋ hex 値の表記
- **タイポグラフィ**: 見出し・本文のフォント方針とサイズ/ウェイトの実例
- **余白・角丸の方針**: 基準値（例: 余白は8の倍数、角丸16px）と適用例
- **ムードキーワード**: 3〜5語
- **Do / Don't**: 各2〜3項目
- 配色は明るく（ダークモード禁止）。PRD の「デザイン方向性メモ」と一致させる

## mock ページに含める要素

- CSS だけで描く iPhone フレーム（角丸の外枠＋Dynamic Island＋ホームインジケータ程度で十分）。画像は使わない
- フレーム内にコア画面 **1〜2枚**（PRD の「コア行動」が起きる画面を優先。オンボーディングは不要）
- 配色・角丸・タイポは tone ページの定義に従う
- 静的でよい（onClick 等の interactivity 不要 = Server Component のまま）。スタイルはインライン style か同ファイル内の `<style>` で完結させ、CSS フレームワーク・外部フォント・外部画像は使わない

## 初回ブートストラップ（showcase/ が無いとき）

`create-next-app` は使わず、以下を手で生成する。

1. `showcase/package.json` — dependencies は **next / react / react-dom のみ**。`.tsx` をビルドするため devDependencies に **typescript / @types/react / @types/node**（これ以外の依存は追加しない）

   ```json
   {
     "name": "showcase",
     "private": true,
     "scripts": { "dev": "next dev", "build": "next build", "start": "next start" },
     "dependencies": { "next": "latest", "react": "latest", "react-dom": "latest" },
     "devDependencies": { "typescript": "latest", "@types/react": "latest", "@types/node": "latest" }
   }
   ```

2. `showcase/apps.json` — `[]` で作る
3. `showcase/app/layout.tsx` — html/body と最小のインラインスタイル（明るい背景・システムフォント）、サイト名ヘッダー
4. `showcase/app/page.tsx` — apps.json を import して一覧表示
5. `showcase/.gitignore` — `node_modules` と `.next`
6. `cd showcase && npm install && npx next build` が通ることを確認する（tsconfig.json / next-env.d.ts が自動生成されるので tsconfig.json はコミットする）
7. **Vercel 接続は1回だけ人間の作業**。Slack にチェックリストで依頼する:
   - [ ] vercel.com で `prd-vault` リポジトリを import
   - [ ] Root Directory を `showcase` に設定
   - [ ] プロジェクト名は推測されにくいものにする（公開 URL になるため）

## 運用ルール

- ページを作るのは **PRD 化する案のみ**。`ideas/` 止まりの案には作らない
- showcase の変更は PRD と**同じブランチ・同じ PR** に含める
- 変更のたびに `npx next build` で確認する（`node_modules` が無ければ先に `npm install`）
