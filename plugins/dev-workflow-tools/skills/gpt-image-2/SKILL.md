---
name: gpt-image-2
description: Generate and edit images using OpenAI's gpt-image-2 model for general-purpose image creation. Supports flexible sizes (square, landscape, portrait), aspect-ratio presets, multi-image edit, and optional exact-pixel crop. Use when the user asks to create images, illustrations, marketing visuals, thumbnails, product mockups, or edit existing images via OpenAI. Triggers on "OpenAIで画像生成して", "gpt-image-2で…", "create an image (with OpenAI)", "edit this image with gpt-image-2".
---

# gpt-image-2 General-Purpose Image Generation

OpenAI の `gpt-image-2` を使った汎用的な画像生成・編集スキル。
スクリーンショット専用ではなく、用途を問わずさまざまなサイズ／アスペクト比で生成できる。

## When to use which model

| 用途 | おすすめ |
|---|---|
| 写実的・テキストもそこそこ載せたい | `gpt-image-2`（このスキル） |
| アイコン・イラスト・キャラの一貫性 | [[nanobanana-pro]] |
| サムネ・OGP・記事ヘッダー等の汎用画像 | どちらでも可。文字入れが多いなら `gpt-image-2` |

## Setup

```bash
export OPENAI_API_KEY=sk-...
```

依存は PEP 723 でスクリプトに埋め込み済み。`uv run` で実行すれば `openai` / `pillow` は自動で解決される。

## Quick Start

### テキストから生成（正方形 1024×1024）

```bash
uv run .claude/skills/gpt-image-2/scripts/generate.py \
  --prompt "A cozy reading nook with warm lighting, photo style" \
  --output out/reading.png
```

### アスペクト比プリセットで生成

```bash
# 16:9 ランドスケープ（1536×1024）
uv run .claude/skills/gpt-image-2/scripts/generate.py \
  --prompt "Wide cinematic landscape of Tokyo at dusk" \
  --aspect 16:9 \
  --output out/tokyo.png

# 9:16 ポートレート（1024×1536）
uv run .claude/skills/gpt-image-2/scripts/generate.py \
  --prompt "Tall poster of a forest path" \
  --aspect 9:16 \
  --output out/forest.png
```

### 任意サイズで生成（16の倍数のみ）

```bash
uv run .claude/skills/gpt-image-2/scripts/generate.py \
  --prompt "Product mockup banner" \
  --size 1920x1088 \
  --output out/banner.png
```

### ぴったりサイズに切り出す（exact crop）

`gpt-image-2` は両辺が 16 の倍数のサイズしか受け付けない。例えば `1320×2868` (App Store iPhone 6.9") のような端数サイズが必要な場合は、`--exact-size` を指定すると最も近い 16 の倍数サイズで生成 → センタークロップで指定ピクセルに揃える。

```bash
uv run .claude/skills/gpt-image-2/scripts/generate.py \
  --prompt "Hero shot of an iOS app" \
  --exact-size 1320x2868 \
  --output out/appstore.png
```

### 参照画像をもとに編集

```bash
uv run .claude/skills/gpt-image-2/scripts/generate.py \
  --prompt "Repaint as a watercolor illustration" \
  --input-image source.png \
  --aspect 1:1 \
  --output out/watercolor.png

# 複数画像を参照に
uv run .claude/skills/gpt-image-2/scripts/generate.py \
  --prompt "Combine these styles" \
  --input-image a.png --input-image b.png \
  --output out/combo.png
```

## Flags

| Flag | Default | Notes |
|---|---|---|
| `--prompt` | (required) | 画像プロンプト |
| `--output` | (required) | 出力パス。`--n>1` の場合は `<stem>_1.png`, `<stem>_2.png` … |
| `--size WxH` | (none) | 任意ピクセルサイズ。両辺が 16 の倍数である必要あり |
| `--aspect` | `1:1` | プリセット: `1:1` / `16:9` / `9:16` / `4:3` / `3:4` / `3:2` / `2:3`（`--size` 未指定時のみ有効） |
| `--exact-size WxH` | (none) | 端数サイズで欲しい場合。最寄りの 16 倍数で生成→センタークロップ |
| `--input-image PATH` | (none) | 参照画像。複数指定可。指定すると `images.edit` を呼ぶ |
| `--quality` | `high` | `low` / `medium` / `high` / `auto` |
| `--n` | `1` | バリエーション数 |
| `--background` | `auto` | `auto` / `transparent` / `opaque`。`transparent` は PNG/WEBP のみ |
| `--output-format` | `png` | `png` / `jpeg` / `webp`（拡張子に合わせるのが基本） |

## Aspect ratio presets

`--aspect` で指定したときに使われるサイズ（すべて 16 の倍数）。

| Aspect | Size |
|---|---|
| `1:1` | 1024 × 1024 |
| `16:9` | 1536 × 1024 |
| `9:16` | 1024 × 1536 |
| `4:3` | 1280 × 1024 |
| `3:4` | 1024 × 1280 |
| `3:2` | 1536 × 1024 |
| `2:3` | 1024 × 1536 |

任意サイズが必要なときは `--size 2048x1152` のように直接指定する。

## Tips

- **テキスト焼き込み**: 重要な文字情報は後段で Pillow / SwiftUI / Figma 等で重ねるほうが安定する。プロンプトで「写真の上にコピーを載せる」をやらせると誤字が出やすい。
- **高解像度（>2K）**: `gpt-image-2` は experimental 扱いになる。バラつくので `--n 3` で複数出して選ぶのが現実的。
- **透過 PNG**: `--background transparent --output-format png` で透過素材として出せる。アイコンやステッカー用途に。
- **コストと時間**: 解像度・品質が上がるほど高くなる。試行錯誤フェーズは `--quality medium` で十分。

## File layout

```
gpt-image-2/
├── SKILL.md
└── scripts/
    └── generate.py   # CLI entry — see flags above
```
