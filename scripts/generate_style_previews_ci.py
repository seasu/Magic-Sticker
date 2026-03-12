#!/usr/bin/env python3
"""
generate_style_previews_ci.py
─────────────────────────────
CI/CD 專用：使用 Gemini 2.0 Flash Exp Image Generation 將貓咪圖片轉換為 6 種風格示意圖。
在 GitHub Actions 中執行，使用 GEMINI_API_KEY Secret。

若 assets/images/cat_source.png 不存在，腳本會先用 Gemini 文字生成它。

生成完成後此腳本可安全移除（已生成的 PNG 保留在 assets/images/）。

使用方法（GitHub Actions）：
  pip install google-genai
  python3 scripts/generate_style_previews_ci.py
"""

import os
import sys
import base64
from pathlib import Path

SCRIPT_DIR = Path(__file__).parent
PROJECT_DIR = SCRIPT_DIR.parent
ASSETS_DIR = PROJECT_DIR / "assets" / "images"
SOURCE_IMAGE = ASSETS_DIR / "cat_source.png"

SOURCE_IMAGE_PROMPT = (
    "A cute brown tabby cat raising its right paw in a greeting pose, "
    "sitting upright, looking at the camera with big bright eyes. "
    "Clean white background. Square format 512x512px. "
    "Photo-realistic style, natural fur texture."
)

STYLES = {
    "chibi": (
        "Transform this cat into a cute chibi/cartoon LINE sticker style. "
        "Keep the same brown tabby cat with big sparkly eyes raising its paw. "
        "Style: thick black outlines, clean flat illustration, big round eyes with sparkles, "
        "chubby adorable proportions, soft pastel colors, no photo-realism. "
        "White or very light pink background. Square format 512x512px."
    ),
    "popArt": (
        "Transform this cat into a Pop Art style sticker. "
        "Same brown tabby cat pose raising its paw. "
        "Style: bold vivid colors (bright yellow, red, blue), thick black outlines, "
        "flat color areas, Ben-Day dot shading like Roy Lichtenstein / Andy Warhol. "
        "White background. Square format 512x512px."
    ),
    "pixel": (
        "Transform this cat into retro 8-bit pixel art style. "
        "Same brown tabby cat raising its paw as a pixel sprite. "
        "Style: chunky visible pixels (8px+ grid), limited palette of 16 colors max, "
        "no anti-aliasing, blocky rounded shapes, Nintendo/SNES game sprite aesthetic. "
        "White background. Square format 512x512px."
    ),
    "sketch": (
        "Transform this cat into a pencil sketch style drawing. "
        "Same brown tabby cat with raised paw as hand-drawn sketch. "
        "Style: visible pencil strokes, crosshatching for shadows and depth, "
        "monochrome or light sepia tones, rough expressive line quality, "
        "sketch paper texture. White background. Square format 512x512px."
    ),
    "watercolor": (
        "Transform this cat into a soft watercolor painting style sticker. "
        "Same brown tabby cat raising its paw as a watercolor illustration. "
        "Style: gentle soft color washes bleeding at edges, translucent layered colors, "
        "slight paper texture, dreamy and cute quality, warm pastel tones. "
        "White or very light background. Square format 512x512px."
    ),
    "photo": (
        "Transform this cat into a photo-realistic digital painting style. "
        "Same brown tabby cat pose raising its paw. "
        "Style: realistic fur texture with detailed strands, natural lighting, "
        "professional portrait quality, vibrant natural colors, "
        "sharp detailed features. White or light background. Square format 512x512px."
    ),
}


DEFAULT_IMAGE_MODEL = "gemini-2.5-flash-image"


def generate_source_image(client, types, model: str) -> bytes:
    """使用 Gemini 文字生成貓咪來源圖片。"""
    print("🐱 cat_source.png 不存在，正在用 Gemini 生成來源圖片...", flush=True)
    response = client.models.generate_content(
        model=model,
        contents=SOURCE_IMAGE_PROMPT,
        config=types.GenerateContentConfig(
            response_modalities=["image"],
            temperature=0.8,
        ),
    )
    for part in response.candidates[0].content.parts:
        if part.inline_data is not None:
            return base64.b64decode(part.inline_data.data)
    raise RuntimeError("Gemini 未回傳圖片 (來源圖生成失敗)")


def main():
    api_key = os.environ.get("GEMINI_API_KEY", "")
    if not api_key:
        print("❌ GEMINI_API_KEY not set")
        sys.exit(1)

    try:
        from google import genai
        from google.genai import types
    except ImportError:
        print("📦 Installing google-genai...")
        os.system("pip install google-genai -q")
        from google import genai
        from google.genai import types

    image_model = os.environ.get("GEMINI_IMAGE_MODEL", DEFAULT_IMAGE_MODEL)
    print(f"🤖 Image model: {image_model}")

    client = genai.Client(api_key=api_key)

    ASSETS_DIR.mkdir(parents=True, exist_ok=True)
    if not SOURCE_IMAGE.exists():
        source_bytes = generate_source_image(client, types, image_model)
        SOURCE_IMAGE.write_bytes(source_bytes)
        print(f"   ✅ cat_source.png 已生成並儲存 ({len(source_bytes) // 1024}KB)\n")
    else:
        source_bytes = SOURCE_IMAGE.read_bytes()
        print(f"🐱 Source image loaded: {len(source_bytes) // 1024}KB\n")

    source_b64 = base64.b64encode(source_bytes).decode()

    success_count = 0
    failed = []

    for style_key, prompt in STYLES.items():
        out_path = ASSETS_DIR / f"preview_{style_key}.png"
        print(f"🎨 Generating [{style_key}]...", end=" ", flush=True)

        try:
            response = client.models.generate_content(
                model=image_model,
                contents=[
                    types.Content(
                        role="user",
                        parts=[
                            types.Part(
                                inline_data=types.Blob(
                                    mime_type="image/png",
                                    data=source_b64,
                                )
                            ),
                            types.Part(text=prompt),
                        ],
                    )
                ],
                config=types.GenerateContentConfig(
                    response_modalities=["image"],
                    temperature=1.0,
                ),
            )

            img_data = None
            for part in response.candidates[0].content.parts:
                if part.inline_data is not None:
                    img_data = base64.b64decode(part.inline_data.data)
                    break

            if img_data:
                out_path.write_bytes(img_data)
                print(f"✅ {len(img_data) // 1024}KB → {out_path.name}")
                success_count += 1
            else:
                print("❌ no image in response")
                failed.append(style_key)

        except Exception as e:
            print(f"❌ {e}")
            failed.append(style_key)

    print(f"\n✨ Done: {success_count}/{len(STYLES)} images generated")
    if failed:
        print(f"   Failed: {', '.join(failed)}")
        sys.exit(1)


if __name__ == "__main__":
    main()
