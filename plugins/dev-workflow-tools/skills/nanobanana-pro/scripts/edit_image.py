#!/usr/bin/env python3
# /// script
# dependencies = ["google-genai", "pillow"]
# ///
"""
Nano Banana Pro Image Editing Script
Google Gemini 3 Pro Image (Nano Banana Pro) API wrapper for image editing.
"""

import argparse
import os
import sys
from pathlib import Path


def edit_image(
    input_path: str,
    prompt: str,
    output_path: str,
    model: str = "gemini-3-pro-image-preview",
) -> str:
    """
    Edit an image using Nano Banana Pro API.

    Args:
        input_path: Path to the input image
        prompt: Text description of edits to make
        output_path: Path to save the edited image
        model: Model ID

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

    # Initialize client
    api_key = os.environ.get("GEMINI_API_KEY") or os.environ.get("GOOGLE_API_KEY")
    if not api_key:
        print("Error: GEMINI_API_KEY or GOOGLE_API_KEY environment variable not set.")
        sys.exit(1)

    client = genai.Client(api_key=api_key)

    # Load input image
    input_file = Path(input_path)
    if not input_file.exists():
        print(f"Error: Input file not found: {input_path}")
        sys.exit(1)

    # Determine mime type
    suffix = input_file.suffix.lower()
    mime_types = {
        ".png": "image/png",
        ".jpg": "image/jpeg",
        ".jpeg": "image/jpeg",
        ".gif": "image/gif",
        ".webp": "image/webp",
    }
    mime_type = mime_types.get(suffix, "image/png")

    # Read image bytes
    with open(input_file, "rb") as f:
        image_bytes = f.read()

    # Create image part
    image_part = types.Part.from_bytes(
        data=image_bytes,
        mime_type=mime_type,
    )

    # Edit image
    response = client.models.generate_content(
        model=model,
        contents=[image_part, prompt],
        config=types.GenerateContentConfig(
            response_modalities=["IMAGE"],
        ),
    )

    # Save edited image
    output = Path(output_path)
    for part in response.parts:
        if part.inline_data is not None:
            image = part.as_image()
            image.save(str(output))
            print(f"Edited image saved to: {output}")
            return str(output)

    print("Error: No image generated in response")
    sys.exit(1)


def main():
    parser = argparse.ArgumentParser(
        description="Edit images using Nano Banana Pro (Gemini 3 Pro Image)"
    )
    parser.add_argument(
        "input",
        help="Input image file path"
    )
    parser.add_argument(
        "prompt",
        help="Text description of edits to make"
    )
    parser.add_argument(
        "-o", "--output",
        default="edited_image.png",
        help="Output file path (default: edited_image.png)"
    )
    parser.add_argument(
        "-m", "--model",
        choices=["gemini-3-pro-image-preview", "gemini-2.5-flash-image"],
        default="gemini-3-pro-image-preview",
        help="Model to use (default: gemini-3-pro-image-preview)"
    )

    args = parser.parse_args()
    edit_image(args.input, args.prompt, args.output, args.model)


if __name__ == "__main__":
    main()
