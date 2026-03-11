#!/usr/bin/env python3
"""立即執行：用 Gemini 產生 6 種風格貓咪示意圖"""

import os, sys, base64, json
from pathlib import Path
from google import genai
from google.genai import types

API_KEY = os.environ["GEMINI_API_KEY"]
OUT_DIR = Path(__file__).parent.parent / "assets" / "images"
OUT_DIR.mkdir(parents=True, exist_ok=True)

client = genai.Client(api_key=API_KEY)

BASE = (
    "A cute brown tabby cat with big sparkly eyes, raising one paw in a "
    "friendly waving gesture, smiling happily. LINE sticker style. "
    "Square image 512x512, centered subject, white or very light background."
)

STYLES = {
    "chibi": BASE + (
        " Style: chibi Q-version cartoon, thick black outlines, "
        "flat clean illustration, big round sparkly eyes, chubby adorable proportions, "
        "soft warm colors. Kawaii sticker quality."
    ),
    "popArt": BASE + (
        " Style: Pop Art, bold vivid colors (bright pink, yellow, cyan), "
        "thick black outlines, flat color areas, Ben-Day dot shading, "
        "Andy Warhol / Roy Lichtenstein aesthetic. High contrast."
    ),
    "pixel": BASE + (
        " Style: retro 8-bit pixel art, chunky visible pixels at least 8px grid, "
        "limited palette of 12 colors, no anti-aliasing, "
        "Nintendo SNES game sprite aesthetic. Blocky cute shapes."
    ),
    "sketch": BASE + (
        " Style: pencil sketch drawing, hand-drawn lines, "
        "crosshatching for shadows, monochrome sepia tones, "
        "rough expressive strokes, sketch paper feel."
    ),
    "watercolor": BASE + (
        " Style: soft watercolor painting, gentle color washes bleeding at edges, "
        "translucent layered colors, slight paper texture, "
        "dreamy pastel quality, warm pinks and oranges."
    ),
    "photo": BASE + (
        " Style: photo-realistic digital painting, detailed realistic fur, "
        "natural lighting, professional portrait quality, "
        "vibrant natural colors, sharp features."
    ),
}

print("🐱 Generating 6 style preview images with Gemini...\n")
results = {}

for style_key, prompt in STYLES.items():
    print(f"  🎨 {style_key}...", end=" ", flush=True)
    try:
        response = client.models.generate_content(
            model="gemini-2.0-flash-preview-image-generation",
            contents=prompt,
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
            out_path = OUT_DIR / f"preview_{style_key}.png"
            with open(out_path, "wb") as f:
                f.write(img_data)
            kb = len(img_data) // 1024
            print(f"✅ {kb}KB → {out_path.name}")
            results[style_key] = True
        else:
            print("❌ no image in response")
            results[style_key] = False
    except Exception as e:
        print(f"❌ {e}")
        results[style_key] = False

success = sum(results.values())
print(f"\n✨ Done: {success}/{len(STYLES)} images generated")
print(f"   Output: {OUT_DIR}")
