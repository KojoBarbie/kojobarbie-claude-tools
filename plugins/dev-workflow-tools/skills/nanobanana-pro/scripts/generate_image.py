#!/usr/bin/env python3
# /// script
# dependencies = ["google-genai", "pillow"]
# ///
"""
Nano Banana Pro Image Generation Script
Google Gemini 3 Pro Image (Nano Banana Pro) API wrapper for high-quality image generation.
"""

import argparse
import os
import sys
from pathlib import Path


def generate_image(
    prompt: str,
    output_path: str,
    model: str = "gemini-3-pro-image-preview",
    aspect_ratio: str = "1:1",
) -> str:
    """
    Generate an image using Nano Banana Pro API.

    Args:
        prompt: Text description of the image to generate
        output_path: Path to save the generated image
        model: Model ID (gemini-3-pro-image-preview for Pro, gemini-2.5-flash-image for fast)
        aspect_ratio: Aspect ratio (1:1, 16:9, 9:16, 4:3, 3:4)

    Returns:
        Path to the saved image
    """
    try:
        from google import genai
        from google.genai import types
    except ImportError:
        print("Error: google-genai package not installed.")
        print("Install with: pip install google-genai")
        sys.exit(1)

    # Initialize client (uses GEMINI_API_KEY or GOOGLE_API_KEY env var)
    api_key = os.environ.get("GEMINI_API_KEY") or os.environ.get("GOOGLE_API_KEY")
    if not api_key:
        print("Error: GEMINI_API_KEY or GOOGLE_API_KEY environment variable not set.")
        sys.exit(1)

    client = genai.Client(api_key=api_key)

    # Generate image
    response = client.models.generate_content(
        model=model,
        contents=[prompt],
        config=types.GenerateContentConfig(
            response_modalities=["IMAGE"],
            image_config=types.ImageConfig(
                aspect_ratio=aspect_ratio,
            ),
        ),
    )

    # Save image
    output = Path(output_path)
    for part in response.parts:
        if part.inline_data is not None:
            image = part.as_image()
            image.save(str(output))
            print(f"Image saved to: {output}")
            return str(output)

    print("Error: No image generated in response")
    sys.exit(1)


def main():
    parser = argparse.ArgumentParser(
        description="Generate images using Nano Banana Pro (Gemini 3 Pro Image)"
    )
    parser.add_argument(
        "prompt",
        help="Text description of the image to generate"
    )
    parser.add_argument(
        "-o", "--output",
        default="generated_image.png",
        help="Output file path (default: generated_image.png)"
    )
    parser.add_argument(
        "-m", "--model",
        choices=["gemini-3-pro-image-preview", "gemini-2.5-flash-image"],
        default="gemini-3-pro-image-preview",
        help="Model to use (default: gemini-3-pro-image-preview)"
    )
    parser.add_argument(
        "-a", "--aspect-ratio",
        choices=["1:1", "16:9", "9:16", "4:3", "3:4"],
        default="1:1",
        help="Aspect ratio (default: 1:1)"
    )

    args = parser.parse_args()
    generate_image(args.prompt, args.output, args.model, args.aspect_ratio)


if __name__ == "__main__":
    main()
