# showcase サイト仕様（prd-vault/showcase）

アイデア段階の **トンマナ3案 ＋ 触れる紙芝居モック ＋ PRD 本文** を1か所で確認するための静的サイト。
prd-vault リポジトリの `showcase/` に置き、**Vercel** でデプロイする。
スマホ（iPhone Safari）で読む前提。

**接続済み（2026-08-05）**: Vercel プロジェクト `pv-showcase-12ced869`（Root Directory=`showcase`・Production Branch=`main`）が prd-vault の GitHub リポジトリに接続済み。**PR を上げると自動でプレビューがデプロイされ、PR にプレビュー URL がコメントされる**ので、以後の人間作業は不要。

- 本番 URL: `https://pv-showcase-12ced869.vercel.app`
- プレビュー URL: PR ごとに自動生成（PR コメントを見る）

> **なぜ Vercel か（LP との使い分け）**: Vercel の Hobby プランは非商用に限られるが、[Fair Use Guidelines](https://vercel.com/docs/limits/fair-use-guidelines) が列挙する商用の条件（決済・広告・製品やサービスの販売の宣伝・アフィリエイト・ホスティングの対価）に showcase はどれも当たらない（PRD のモックを本人が見るだけの内部ツール）。
> 一方 **LP は「製品やサービスの販売を宣伝」に当たるため Vercel を使わず Firebase Hosting のまま**（app-kickoff の external-services.md 参照）。この使い分けを崩さないこと。

- Next.js App Router を **静的エクスポート**（`next.config.mjs` に `output: 'export'`）。データ取得はビルド時のみ（`apps.json` と `../prd/*.md` を fs で読む）。API 呼び出し・シークレットなし。`next build` で `out/` が生成される
- **ダークモード禁止**（アプリ全体の規約）。全ページ明るい背景
- **Deployment Protection**: Vercel Authentication + Standard Protection（Hobby でも利用可）。プレビュー URL とデプロイ URL は Vercel ログイン必須になる。ただし **Standard Protection では本番 URL は保護されない**（保護には Pro が必要）ため、prd-vault が private でも本番 URL は誰でも開ける前提で考える。だからプロジェクト名に推測されにくいランダムサフィックスを付けている（`pv-showcase-12ced869`）。プロジェクト名を変えると本番 URL も変わるので、むやみに変えない

## ディレクトリ構成

```
showcase/
├── package.json
├── next.config.mjs      # output: 'export'（静的エクスポート）
├── tsconfig.json        # 初回 next build が自動生成したものをコミット
├── .gitignore           # node_modules / .next / out
├── apps.json            # アプリ一覧（下記スキーマ）
├── lib/
│   ├── proto.tsx        # 紙芝居プロトタイプの共通部品（全アプリ共用）
│   └── prd.ts           # ../prd/{slug}.md を読んで frontmatter を剥がす
└── app/
    ├── layout.tsx       # 共通レイアウト（明るい背景・システムフォント・簡素なヘッダー）
    ├── page.tsx         # 一覧ページ（apps.json を読んで表示）
    └── apps/
        └── {slug}/
            ├── page.tsx        # このアプリのハブ（3案 / モック / PRD への導線）
            ├── tone/page.tsx   # トンマナ3案
            ├── mock/page.tsx   # 触れる紙芝居モック
            └── prd/page.tsx    # PRD 本文（Markdown をそのまま描画）
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
    "createdAt": "2026-07-10",
    "toneChosen": null
  }
]
```

- `status` は起票時 `"proposed"`。後続ステージ（キックオフ・リリース等）が更新してよい
- `toneChosen` はユーザーが PR コメントで選んだトンマナ案（`"A"` / `"B"` / `"C"`）。未選択は `null`。
  改訂モードで選択を受け取ったらここに記録し、`app-kickoff` はこれを読んでコンセプトシートを作る
- `app/page.tsx` は `import apps from "../apps.json"` で読み込み、name / status / createdAt と
  `/apps/{slug}` へのリンクを一覧表示する。空配列なら「まだありません」と出す

---

## tone ページ — トンマナ**3案**

**1案だけ出さない。** 1案しか出さないと、それが自動的に正解になり、毎回同じ方向のデザインに寄る。
**方向性が明確に異なる3案**を並べ、ユーザーが PR コメントに「Bで」と1語返すだけで決まる形にする。

### 3案の作り方

1. まず `app-factory:design-vault` の **query モード**で、このアプリのカテゴリ・気分に近い実例を引く
   （「学習アプリ・達成感を出したい・リファレンスを出して」のように依頼する）。
   vault が空／該当なしなら `app-design-craft` の原則だけで作る（それは劣化ではない）
2. **軸をずらして3案作る**。色違いの3案は3案ではない。
   ずらすのは「世界観の核」そのもの。例:
   - A: 静謐ミニマル（余白最大・無彩色＋1色・小さく静かな動き）
   - B: 温かみクラフト（手書き感・生成りの色・柔らかい角丸・親しみのあるコピー）
   - C: 大胆エディトリアル（特大タイポ・高コントラスト・非対称レイアウト・きびきびした動き）
   ※ この3つは例。**アプリのジョブに合う軸**で毎回考えること（機械的にA/B/Cを再利用しない）
3. 各案に**採用した実例の根拠**を付ける。design-vault から引いたなら画像を実際に表示する（下記）

### 各案に含める要素

- **一言の世界観**（形容詞3つ、または1フレーズ）
- **カラーパレット**: primary / accent / background / text 等のスウォッチ（色付き四角）＋ hex 値
- **タイポグラフィ**: 見出し・本文のサイズ/ウェイトを**実寸で**見せる（説明でなく現物）
- **余白・角丸の方針**: 基準値（例: 余白は8の倍数、角丸16px）
- **唯一の強調装置**: 最重要をどう光らせるか（塗りpill / 下線 / 特大数字 など）を実物で1つ
- **ボイス**: 同じUI文言を3案それぞれの言い回しで書き比べる（例: 保存ボタン、空状態の一文）
- **この案が向くジョブ / 向かないジョブ**を1行ずつ
- **参照した実例**（design-vault から引いた場合）: 画像を `<img>` で表示し、
  「どこを取ったか」を1行添える。パスは showcase から見た相対パス
  （例: `../../../../design-vault/refs/duolingo/xxx.jpg` — ビルド時に `public/` へコピーするより、
  `next.config.mjs` の `images: { unoptimized: true }` の下で通常の `<img src>` を使うほうが単純。
  `out/` に含めるため、**参照画像は `showcase/public/refs/` にコピーして参照する**）

配色は明るく（ダークモード禁止）。PRD の「デザイン方向性メモ」は**3案のうち推しの案**と一致させ、
どれを推すかをページ上で明示する（「PRD は A 案で書いています」）。

---

## mock ページ — **触れる紙芝居**

ここが従来「CSSで描くiPhoneフレームに主要1〜2画面・静的でよい」だった箇所。
**その仕様が最低限の完成品を生む原因だったので、以下に置き換える。**

> このモックは「確認用の簡易表示」ではなく、**実装が目指す目標値**である。
> モックが最低限なら、完成品は必ずそれ以下になる。

### 必須要件

1. **画面数は4〜6枚**。単なる画面数ではなく、以下の「体験の山場」を必ず含める:
   - **初回起動の第一印象**（まだデータが0件の状態）
   - **コア行動が起きる画面**（PRD の「コア行動」）
   - **完了・達成の瞬間**（コア行動をやり切った直後。ここが感情の山場）
   - **空状態**（初回の空と、消化しきった空は意味が違う。どちらか一方でよい）
   - 収益化が要件にあれば**ペイウォール**
2. **触れる紙芝居であること（最重要）**。ボタンを押すと実際に次の画面へ遷移する。
   「押す → こう遷移する → ここでこれが記録される」を指で辿れること。
   `useState` で画面インデックスを持つだけでよい（静的エクスポートでも Client Component は
   ビルド時にプリレンダされるので問題ない）。
   **mock ページの先頭には `"use client"` を必ず書く** — 画面定義に関数（`render`）を渡すため、
   Server Component のままだと `Functions cannot be passed directly to Client Components` で
   ビルドが落ちる。**tone / prd ページは Server Component のまま**（prd は fs を使うので Server 必須）
3. **遷移にアニメーションを付ける**（0.25〜0.35秒）。押した瞬間の押下フィードバックも入れる。
   気持ちよさは静止画に写らないので、**静止画だけのモックからは絶対に気持ちいいアプリは生まれない**
4. **達成の瞬間には演出を入れる**（0.4〜0.8秒。紙吹雪・数字のカウントアップ・スケールイン等）。
   ここを省略したモックは、実装でも必ず省略される
5. **コピーは実物を書く**。「タイトル」「テキストテキスト」などのダミー禁止。
   ボタン文言・空状態の一文・完了時のメッセージまで、tone ページのボイスに従って本番想定で書く
6. **データもリアルに**。「サンプルデータ1」ではなく実際にありそうな記録を入れる。
   ダミーデータでしか成立しないレイアウトはここで露見させる
7. 配色・角丸・タイポは **tone ページで推した案**に従う（3案すべてのモックは作らない。1案でよい）
8. 画像は使わず CSS で描く（アイコンは絵文字か CSS 図形で代替）。外部フォント・CSSフレームワークは使わない

### 実装

共通部品は `lib/proto.tsx` にまとめ、全アプリで共用する（毎回ゼロから書くと品質がぶれる）。
雛形コードは [prototype-kit.md](prototype-kit.md) にある。初回はそこからコピーして作る。

画面下部に**画面名のチップ**（「① 初回起動 → ② 記録 → ③ 完了」）を置き、
紙芝居のどこにいるか分かるようにする。チップを直接タップして飛べるようにもする。

---

## prd ページ — PRD 本文

トンマナ・モックと同じ場所で PRD が読めるようにする（スマホで GitHub の Markdown を読むのは辛い）。
**PRD の実体は `prd/{slug}.md` のまま**で、このページはそれを描画するだけ。二重管理しない。

```tsx
// app/apps/{slug}/prd/page.tsx
import { loadPrd } from "../../../../lib/prd";
import ReactMarkdown from "react-markdown";
import remarkGfm from "remark-gfm";

export default function Page() {
  const body = loadPrd("sleep-streak");
  return (
    <article className="prd">
      <ReactMarkdown remarkPlugins={[remarkGfm]}>{body}</ReactMarkdown>
    </article>
  );
}
```

```ts
// lib/prd.ts
import fs from "node:fs";
import path from "node:path";

/** ../prd/{slug}.md を読み、frontmatter を剥がして本文だけ返す。無ければ案内文を返す。 */
export function loadPrd(slug: string): string {
  // Vercel は Root Directory を showcase にしてもリポジトリ全体を clone するので、
  // ビルド時に process.cwd()（= showcase）から見た ../prd/ を読める
  const file = path.join(process.cwd(), "..", "prd", `${slug}.md`);
  if (!fs.existsSync(file)) return `# PRD が見つかりません\n\n\`prd/${slug}.md\` を確認してください。`;
  return fs.readFileSync(file, "utf8").replace(/^---\r?\n[\s\S]*?\r?\n---\r?\n/, "");
}
```

- `react-markdown` と `remark-gfm` を dependencies に追加する（PRD は GFM の表を多用するので
  `remark-gfm` は必須）。**依存追加はこの2つまで**
- 読みやすさのため `layout.tsx` に `.prd` のスタイルを置く: 本文 17px / 行間 1.8 /
  見出しの上マージン大きめ / 表は横スクロール可（`overflow-x: auto`）/ 最大幅 42em。
  スマホで読む前提なので、この typography は手を抜かない
- ハブページ（`app/apps/{slug}/page.tsx`）から「トンマナ3案 / モック / PRD」の3つへ導線を張る

---

## 初回ブートストラップ（showcase/ が無いとき）

`create-next-app` は使わず、以下を手で生成する。

1. `showcase/package.json` — 依存は next / react / react-dom **＋ react-markdown / remark-gfm** のみ。
   devDependencies は typescript / @types/react / @types/node（これ以外は追加しない）

   ```json
   {
     "name": "showcase",
     "private": true,
     "scripts": { "dev": "next dev", "build": "next build", "start": "next start" },
     "dependencies": {
       "next": "latest", "react": "latest", "react-dom": "latest",
       "react-markdown": "latest", "remark-gfm": "latest"
     },
     "devDependencies": { "typescript": "latest", "@types/react": "latest", "@types/node": "latest" }
   }
   ```

2. `showcase/apps.json` — `[]` で作る
3. `showcase/next.config.mjs` — 静的エクスポート設定:

   ```js
   /** @type {import('next').NextConfig} */
   const nextConfig = { output: 'export', images: { unoptimized: true } };
   export default nextConfig;
   ```

4. `showcase/app/layout.tsx` — html/body と最小のインラインスタイル（明るい背景・システムフォント）、
   サイト名ヘッダー、`.prd` の typography
5. `showcase/app/page.tsx` — apps.json を import して一覧表示
6. `showcase/lib/proto.tsx` と `showcase/lib/prd.ts` — [prototype-kit.md](prototype-kit.md) からコピー
7. `showcase/public/refs/` — design-vault から参照画像をコピーする先（`.gitkeep` を置く）
8. `showcase/.gitignore` — `node_modules` / `.next` / `out` / `tsconfig.tsbuildinfo`
9. `cd showcase && npm install && npx next build` が通り、`out/` が生成されることを確認する
   （tsconfig.json / next-env.d.ts が自動生成されるので tsconfig.json はコミットする）
10. Vercel プロジェクトは**接続済み**（冒頭参照）なので、接続作業は不要。万一作り直す場合のみ:

    ```bash
    vercel api /v11/projects -X POST --input proj.json
    # proj.json: {"name":"pv-showcase-{ランダム}","framework":"nextjs","rootDirectory":"showcase",
    #             "gitRepository":{"type":"github","repo":"KojoBarbie/prd-vault"}}
    ```

    作成後、`ssoProtection` が `{"deploymentType":"all_except_custom_domains"}`（= Vercel Authentication + Standard Protection）になっていることを確認する

## 運用ルール

- ページを作るのは **PRD 化する案のみ**。`ideas/` 止まりの案には作らない
- showcase の変更は PRD と**同じブランチ・同じ PR** に含める
- 変更のたびに `npx next build` で確認する（`node_modules` が無ければ先に `npm install`）
- **モックを「最低限」に落とさない。** 4〜6画面・遷移・達成演出・実コピーは削れる項目ではない。
  時間が無いなら画面数を4に減らす（山場を削るのではなく、周辺を削る）
