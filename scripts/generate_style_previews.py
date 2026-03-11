#!/usr/bin/env python3
"""
generate_style_previews.py
──────────────────────────
使用 Gemini Imagen 3 或 Gemini 2.0 Flash 將貓咪來源圖片
轉換為 6 種貼圖風格的示意圖，儲存到 assets/images/。

使用方法：
  1. 確認來源圖片存在：assets/images/cat_source.png
  2. 設定 API Key：
       export GEMINI_API_KEY="your_key_here"
  3. 安裝依賴：
       pip3 install google-genai pillow
  4. 執行：
       cd /path/to/Magic-Morning
       python3 scripts/generate_style_previews.py
"""

import os
import sys
import base64
from pathlib import Path

# ── 路徑設定 ─────────────────────────────────────────────────────────────────

SCRIPT_DIR = Path(__file__).parent
PROJECT_DIR = SCRIPT_DIR.parent
ASSETS_DIR = PROJECT_DIR / "assets" / "images"
SOURCE_IMAGE = ASSETS_DIR / "cat_source.png"

# ── 風格定義 ─────────────────────────────────────────────────────────────────

STYLES = {
    "chibi": {
        "label": "Q版卡通",
        "prompt": (
            "Transform this cat into a cute chibi/cartoon LINE sticker style. "
            "Keep the same brown tabby cat with big sparkly eyes raising its paw. "
            "Style: thick black outlines, clean flat illustration, big round eyes with sparkles, "
            "chubby adorable proportions, soft pastel colors, no photo-realism. "
            "White or very light pink background. Square format 512×512px."
        ),
    },
    "popArt": {
        "label": "普普風",
        "prompt": (
            "Transform this cat into a Pop Art style sticker. "
            "Same brown tabby cat pose raising its paw. "
            "Style: bold vivid colors (bright yellow, red, blue), thick black outlines, "
            "flat color areas, Ben-Day dot shading like Roy Lichtenstein / Andy Warhol. "
            "White background. Square format 512×512px."
        ),
    },
    "pixel": {
        "label": "像素風",
        "prompt": (
            "Transform this cat into retro 8-bit pixel art style. "
            "Same brown tabby cat raising its paw as a pixel sprite. "
            "Style: chunky visible pixels (≥8px grid), limited palette of 16 colors max, "
            "no anti-aliasing, blocky rounded shapes, Nintendo/SNES game sprite aesthetic. "
            "White background. Square format 512×512px."
        ),
    },
    "sketch": {
        "label": "素描",
        "prompt": (
            "Transform this cat into a pencil sketch style drawing. "
            "Same brown tabby cat with raised paw as hand-drawn sketch. "
            "Style: visible pencil strokes, crosshatching for shadows and depth, "
            "monochrome or light sepia tones, rough expressive line quality, "
            "sketch paper texture. White background. Square format 512×512px."
        ),
    },
    "watercolor": {
        "label": "水彩",
        "prompt": (
            "Transform this cat into a soft watercolor painting style sticker. "
            "Same brown tabby cat raising its paw as a watercolor illustration. "
            "Style: gentle soft color washes bleeding at edges, translucent layered colors, "
            "slight paper texture, dreamy and cute quality, warm pastel tones. "
            "White or very light background. Square format 512×512px."
        ),
    },
    "photo": {
        "label": "寫實風",
        "prompt": (
            "Transform this cat into a photo-realistic digital painting style. "
            "Same brown tabby cat pose raising its paw. "
            "Style: realistic fur texture with detailed strands, natural lighting, "
            "professional portrait quality, vibrant natural colors, "
            "sharp detailed features. White or light background. Square format 512×512px."
        ),
    },
}

# ─────────────────────────────────────────────────────────────────────────────


def load_source_image() -> bytes:
    if not SOURCE_IMAGE.exists():
        print(f"❌ 找不到來源圖片：{SOURCE_IMAGE}")
        print("   請將貓咪圖片存成 assets/images/cat_source.png 後再執行")
        sys.exit(1)
    with open(SOURCE_IMAGE, "rb") as f:
        return f.read()


def generate_with_gemini_flash(api_key: str, style_key: str, style_info: dict, source_bytes: bytes) -> bytes | None:
    """使用 Gemini 2.0 Flash (image generation) 產生風格圖。"""
    try:
        from google import genai
        from google.genai import types

        client = genai.Client(api_key=api_key)

        source_b64 = base64.b64encode(source_bytes).decode()

        response = client.models.generate_content(
            model="gemini-2.0-flash-preview-image-generation",
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
                        types.Part(text=style_info["prompt"]),
                    ],
                )
            ],
            config=types.GenerateContentConfig(
                response_modalities=["image"],
                temperature=1.0,
            ),
        )

        for part in response.candidates[0].content.parts:
            if part.inline_data is not None:
                return base64.b64decode(part.inline_data.data)

        print(f"   ⚠️  {style_key}: 回應中無圖片資料")
        return None

    except Exception as e:
        print(f"   ⚠️  {style_key} (flash) 失敗: {e}")
        return None


def generate_with_imagen(api_key: str, style_key: str, style_info: dict) -> bytes | None:
    """備用：使用 Imagen 3 純文字生成（無來源圖片）。"""
    try:
        import google.generativeai as genai

        genai.configure(api_key=api_key)

        base_prompt = (
            "A cute brown tabby cat with big sparkly eyes, raising one paw, "
            "sticker style. " + style_info["prompt"].split("Style:")[1] if "Style:" in style_info["prompt"]
            else style_info["prompt"]
        )

        imagen = genai.ImageGenerationModel("imagen-3.0-generate-002")
        result = imagen.generate_images(
            prompt=base_prompt,
            number_of_images=1,
            aspect_ratio="1:1",
            safety_filter_level="block_few",
        )
        if result.images:
            return result.images[0]._pil_image.tobytes() if hasattr(result.images[0], '_pil_image') else None
        return None

    except Exception as e:
        print(f"   ⚠️  {style_key} (imagen) 失敗: {e}")
        return None


def save_image(style_key: str, data: bytes):
    output_path = ASSETS_DIR / f"preview_{style_key}.png"
    with open(output_path, "wb") as f:
        f.write(data)
    size_kb = len(data) / 1024
    print(f"   ✅ 儲存：{output_path.name} ({size_kb:.0f} KB)")


def main():
    api_key = os.environ.get("GEMINI_API_KEY", "")
    if not api_key:
        print("❌ 請設定環境變數 GEMINI_API_KEY")
        print("   export GEMINI_API_KEY='your_api_key_here'")
        print("   可至 https://aistudio.google.com/app/apikey 取得免費 API Key")
        sys.exit(1)

    print("🐱 Magic Sticker — 風格示意圖產生器")
    print(f"   來源圖片：{SOURCE_IMAGE}")
    print(f"   輸出目錄：{ASSETS_DIR}")
    print()

    source_bytes = load_source_image()
    print(f"✅ 已載入來源圖片（{len(source_bytes) / 1024:.0f} KB）\n")

    # 嘗試安裝依賴
    try:
        from google import genai  # noqa: F401
    except ImportError:
        print("📦 安裝 google-genai...")
        os.system("pip3 install google-genai -q")

    success_count = 0
    for style_key, style_info in STYLES.items():
        print(f"🎨 產生 [{style_info['label']}] ({style_key})...")

        data = generate_with_gemini_flash(api_key, style_key, style_info, source_bytes)

        if data:
            save_image(style_key, data)
            success_count += 1
        else:
            print(f"   ❌ {style_key} 產生失敗，跳過")

    print(f"\n🎉 完成！成功產生 {success_count}/{len(STYLES)} 張示意圖")

    if success_count < len(STYLES):
        print("\n💡 提示：部分圖片產生失敗可能因為：")
        print("   - API Key 無效或額度用盡")
        print("   - Gemini image generation 模型尚未開放")
        print("   - 請至 https://aistudio.google.com 確認帳號狀態")


if __name__ == "__main__":
    main()
