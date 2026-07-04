#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# dependencies = [
#   "openai>=1.0",
#   "pillow",
# ]
# ///
"""General-purpose image generation / editing with OpenAI gpt-image-2.

Supports:
- Aspect-ratio presets (1:1, 16:9, 9:16, 4:3, 3:4, 3:2, 2:3)
- Custom sizes via --size WxH (both edges must be multiples of 16)
- --exact-size WxH for off-grid targets (generates at the nearest valid size
  up and center-crops to the exact pixels)
- Image edit mode when --input-image is given (one or more times)
- Transparent backgrounds and PNG/JPEG/WEBP output
"""

from __future__ import annotations

import argparse
import base64
import os
import sys
import urllib.request
from io import BytesIO
from pathlib import Path

from PIL import Image
from openai import OpenAI


MODEL = "gpt-image-2"
GRID = 16  # gpt-image-2 requires both edges to be multiples of 16

ASPECT_PRESETS: dict[str, tuple[int, int]] = {
    "1:1":  (1024, 1024),
    "16:9": (1536, 1024),
    "9:16": (1024, 1536),
    "4:3":  (1280, 1024),
    "3:4":  (1024, 1280),
    "3:2":  (1536, 1024),
    "2:3":  (1024, 1536),
}


def parse_size(s: str) -> tuple[int, int]:
    try:
        w, h = (int(x) for x in s.lower().split("x"))
    except Exception:
        raise argparse.ArgumentTypeError(f"size must be WxH (e.g. 1024x1024), got: {s!r}")
    if w <= 0 or h <= 0:
        raise argparse.ArgumentTypeError(f"size must be positive: {s!r}")
    return w, h


def round_up_to_grid(n: int) -> int:
    return ((n + GRID - 1) // GRID) * GRID


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    p.add_argument("--prompt", required=True, help="Image generation prompt")
    p.add_argument(
        "--output",
        required=True,
        help="Output path. With --n>1, files become <stem>_1.<ext>, <stem>_2.<ext>, ...",
    )
    p.add_argument(
        "--size",
        type=parse_size,
        default=None,
        metavar="WxH",
        help="Exact size to request (both edges must be multiples of 16).",
    )
    p.add_argument(
        "--aspect",
        choices=list(ASPECT_PRESETS),
        default="1:1",
        help="Aspect-ratio preset (used when --size and --exact-size are not given).",
    )
    p.add_argument(
        "--exact-size",
        type=parse_size,
        default=None,
        metavar="WxH",
        help=(
            "Final pixel size you want. If it is not on the 16px grid, "
            "the image is generated at the nearest valid size up and "
            "center-cropped to these exact dimensions."
        ),
    )
    p.add_argument(
        "--input-image",
        action="append",
        default=[],
        metavar="PATH",
        help="Reference image. Repeat for multiple. Switches to images.edit endpoint.",
    )
    p.add_argument(
        "--quality",
        choices=["low", "medium", "high", "auto"],
        default="high",
        help="gpt-image-2 quality (default: high)",
    )
    p.add_argument(
        "--background",
        choices=["auto", "transparent", "opaque"],
        default="auto",
        help="Background mode (transparent requires png/webp output).",
    )
    p.add_argument(
        "--output-format",
        choices=["png", "jpeg", "webp"],
        default=None,
        help="Force output format. If omitted, inferred from --output extension.",
    )
    p.add_argument("--n", type=int, default=1, help="Number of variations (default 1)")
    return p.parse_args()


def resolve_sizes(args: argparse.Namespace) -> tuple[tuple[int, int], tuple[int, int] | None]:
    """Return (gen_size, crop_target).

    - gen_size: size we ask the API for (must be on 16px grid).
    - crop_target: if not None, center-crop the result to this size after generation.
    """
    if args.exact_size is not None:
        target_w, target_h = args.exact_size
        gen_w = round_up_to_grid(target_w)
        gen_h = round_up_to_grid(target_h)
        crop = (target_w, target_h) if (gen_w, gen_h) != (target_w, target_h) else None
        return (gen_w, gen_h), crop

    if args.size is not None:
        w, h = args.size
        if w % GRID != 0 or h % GRID != 0:
            print(
                f"error: --size {w}x{h} is not on the {GRID}px grid. "
                f"Use --exact-size if you want auto-cropping.",
                file=sys.stderr,
            )
            sys.exit(2)
        return (w, h), None

    return ASPECT_PRESETS[args.aspect], None


def _bytes_from_data(d) -> bytes:
    if getattr(d, "b64_json", None):
        return base64.b64decode(d.b64_json)
    if getattr(d, "url", None):
        with urllib.request.urlopen(d.url) as r:
            return r.read()
    raise RuntimeError("API returned neither b64_json nor url")


def _api_kwargs(
    prompt: str,
    n: int,
    size: tuple[int, int],
    quality: str,
    background: str,
    output_format: str,
) -> dict:
    kwargs: dict = {
        "model": MODEL,
        "prompt": prompt,
        "size": f"{size[0]}x{size[1]}",
        "quality": quality,
        "n": n,
    }
    if background != "auto":
        kwargs["background"] = background
    if output_format:
        kwargs["output_format"] = output_format
    return kwargs


def generate(
    prompt: str,
    n: int,
    size: tuple[int, int],
    quality: str,
    background: str,
    output_format: str,
) -> list[bytes]:
    print(
        f"[gpt-image-2 generate] size={size[0]}x{size[1]}, quality={quality}, "
        f"background={background}, format={output_format or 'auto'}, n={n}",
        file=sys.stderr,
    )
    client = OpenAI()
    result = client.images.generate(
        **_api_kwargs(prompt, n, size, quality, background, output_format)
    )
    return [_bytes_from_data(d) for d in result.data]


def edit(
    prompt: str,
    n: int,
    size: tuple[int, int],
    quality: str,
    background: str,
    output_format: str,
    image_paths: list[str],
) -> list[bytes]:
    print(
        f"[gpt-image-2 edit] size={size[0]}x{size[1]}, quality={quality}, "
        f"background={background}, format={output_format or 'auto'}, n={n}, "
        f"inputs={len(image_paths)}",
        file=sys.stderr,
    )
    client = OpenAI()
    files = [open(p, "rb") for p in image_paths]
    try:
        result = client.images.edit(
            image=files[0] if len(files) == 1 else files,
            **_api_kwargs(prompt, n, size, quality, background, output_format),
        )
    finally:
        for f in files:
            f.close()
    return [_bytes_from_data(d) for d in result.data]


def crop_to(img_bytes: bytes, target: tuple[int, int]) -> Image.Image:
    img = Image.open(BytesIO(img_bytes))
    tw, th = target
    if img.width < tw or img.height < th:
        raise RuntimeError(
            f"Generated image {img.size} is smaller than crop target ({tw}x{th})"
        )
    left = (img.width - tw) // 2
    top = (img.height - th) // 2
    return img.crop((left, top, left + tw, top + th))


def save(img_or_bytes, path: Path, fmt_hint: str | None) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)

    if isinstance(img_or_bytes, (bytes, bytearray)):
        img = Image.open(BytesIO(img_or_bytes))
    else:
        img = img_or_bytes

    ext = (fmt_hint or path.suffix.lstrip(".") or "png").lower()
    if ext == "jpg":
        ext = "jpeg"

    if ext == "jpeg":
        img.convert("RGB").save(path, format="JPEG", quality=95)
    elif ext == "webp":
        img.save(path, format="WEBP", quality=95)
    else:
        img.save(path, format="PNG")
    print(f"  → {path} ({img.width}x{img.height})", file=sys.stderr)


def infer_format(args: argparse.Namespace) -> str:
    if args.output_format:
        return args.output_format
    ext = Path(args.output).suffix.lstrip(".").lower()
    if ext == "jpg":
        return "jpeg"
    if ext in ("png", "jpeg", "webp"):
        return ext
    return "png"


def main() -> int:
    args = parse_args()
    if not os.getenv("OPENAI_API_KEY"):
        print("error: OPENAI_API_KEY is not set", file=sys.stderr)
        return 1

    for p in args.input_image:
        if not Path(p).is_file():
            print(f"error: input image not found: {p}", file=sys.stderr)
            return 1

    output_format = infer_format(args)
    if args.background == "transparent" and output_format not in ("png", "webp"):
        print(
            "error: --background transparent requires png or webp output",
            file=sys.stderr,
        )
        return 2

    gen_size, crop_target = resolve_sizes(args)

    if args.input_image:
        images = edit(
            args.prompt, args.n, gen_size, args.quality,
            args.background, output_format, args.input_image,
        )
    else:
        images = generate(
            args.prompt, args.n, gen_size, args.quality,
            args.background, output_format,
        )

    out = Path(args.output)
    for i, raw in enumerate(images, start=1):
        processed = crop_to(raw, crop_target) if crop_target else raw
        if args.n == 1:
            dest = out
        else:
            suffix = out.suffix or f".{output_format}"
            dest = out.with_name(f"{out.stem}_{i}{suffix}")
        save(processed, dest, output_format)
    return 0


if __name__ == "__main__":
    sys.exit(main())
