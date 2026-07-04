---
name: nanobanana-pro
description: Generate and edit images using Google's Nano Banana Pro (Gemini 3 Pro Image) API. This is the DEFAULT image generator — use when the user asks to create images, illustrations, or artwork, or to edit images, WITHOUT naming a provider ("generate an image of...", "画像を生成して"), or when Google / Gemini / Nano Banana is named ("Nano Bananaで", "Geminiで画像生成して"). When the user explicitly asks for OpenAI / gpt-image-2, use the gpt-image-2 skill instead.
---

# Nano Banana Pro Image Generation

Generate high-quality images and edit photos using Google's Nano Banana Pro API.

## Setup

Ensure the environment has:
1. `google-genai` package installed: `uv add google-genai pillow`
2. API key set: `export GEMINI_API_KEY=your_key`

## Quick Start

### Text-to-Image Generation

```python
from google import genai
from google.genai import types

client = genai.Client(api_key="YOUR_API_KEY")  # or use GEMINI_API_KEY env var

response = client.models.generate_content(
    model="gemini-3-pro-image-preview",
    contents=["A serene mountain landscape at sunset"],
    config=types.GenerateContentConfig(
        response_modalities=["IMAGE"],
        image_config=types.ImageConfig(aspect_ratio="16:9"),
    ),
)

for part in response.parts:
    if part.inline_data:
        part.as_image().save("output.png")
```

### Image Editing

```python
from google import genai
from google.genai import types
from pathlib import Path

client = genai.Client()

# Load existing image
image_data = Path("input.png").read_bytes()
image_part = types.Part.from_bytes(data=image_data, mime_type="image/png")

response = client.models.generate_content(
    model="gemini-3-pro-image-preview",
    contents=[image_part, "Add a rainbow in the sky"],
    config=types.GenerateContentConfig(response_modalities=["IMAGE"]),
)

for part in response.parts:
    if part.inline_data:
        part.as_image().save("edited.png")
```

## Models

| Model | ID | Use Case |
|-------|-----|----------|
| Nano Banana Pro | `gemini-3-pro-image-preview` | High-quality, professional images |
| Nano Banana | `gemini-2.5-flash-image` | Fast generation, lower latency |

## Aspect Ratios

Supported: `1:1`, `16:9`, `9:16`, `4:3`, `3:4`

## Scripts

Use bundled scripts for quick image operations. Both scripts declare `google-genai` and `pillow` as [PEP 723](https://peps.python.org/pep-0723/) inline dependencies, so `uv run` resolves them automatically — no project setup required.

**Generate image:**
```bash
uv run .claude/skills/nanobanana-pro/scripts/generate_image.py "A futuristic city at night" -o city.png -a 16:9
```

**Edit image:**
```bash
uv run .claude/skills/nanobanana-pro/scripts/edit_image.py input.png "Make it look like watercolor painting" -o watercolor.png
```

If running outside `uv` (e.g. a manually managed venv), install the deps yourself: `pip install google-genai pillow`.

## Tips

- Be specific and descriptive in prompts for better results
- For text in images, specify font style and placement
- Use reference images for consistent character generation (up to 14 images)
- Generated images include invisible SynthID watermarks

## アプリ素材生成の指針

このスキルはアプリのアイコンや素材画像を作るために使う。生成時は以下を意識する。

- **アスペクト比は用途に合わせる** - App Icon は `1:1`、起動画面やヘッダーは `16:9` / `9:16`
- **背景は単色か、ごく薄いグラデーション** - アイコンは縁まで意味のある絵にする(Apple HIG 準拠)
- **過度な装飾を避ける** - シャドウ・グロウ・派手な色面は避け、シルエットで意味が伝わる構図を優先
- **テキストを焼き込まない** - アイコンに文字や数字を入れない。意味は形と色で伝える
- **解像度** - App Icon 用は 1024×1024 で生成し、後段で必要なサイズに縮小
