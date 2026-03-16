#!/usr/bin/env python3
"""
generate_style_previews_ci.py
─────────────────────────────
CI/CD 專用：使用 Gemini image generation 將貓咪圖片轉換為
6 種風格 × 16 種情感 = 96 張示意圖。

命名格式：preview_{style}_{emotionId}.png
例如：preview_chibi_greeting.png、preview_pixel_angry.png

Prompt 格式與 App 實際產圖（_buildSinglePrompt）完全一致，
確保示意圖呈現效果與正式貼圖相符。

若 assets/images/cat_source.png 不存在，腳本會先用 Gemini 文字生成它。

使用方法（GitHub Actions）：
  pip install google-genai
  python3 scripts/generate_style_previews_ci.py

可選環境變數：
  PREVIEW_STYLES="chibi pixel"      # 只產生指定風格（空格分隔）
  PREVIEW_EMOTIONS="greeting happy" # 只產生指定情感（空格分隔）
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

# ── 風格定義（與 StickerStyle enum 同步）─────────────────────────────────────
# characterDesc 與 promptSuffix 直接對應 lib/core/models/sticker_style.dart

STYLES = {
    "chibi": {
        "characterDesc": (
            "Cartoon chibi-style face of the person (cute Q-version)\n"
            "  * Big sparkly eyes, small nose, chubby cheeks\n"
            "  * Clean flat illustration, thick black outlines, no photo-realism\n"
            "  * Face and upper body fill the circle naturally"
        ),
        "promptSuffix": "LINE Friends / Chiikawa quality.",
    },
    "popArt": {
        "characterDesc": (
            "Pop Art portrait inspired by the person in the photo\n"
            "  * Bold simplified face features, vivid high-contrast colors\n"
            "  * Flat colored areas, Ben-Day dot shading, NO black outlines\n"
            "  * Andy Warhol / Roy Lichtenstein aesthetic"
        ),
        "promptSuffix": (
            "Pop Art style — vivid flat colors, Ben-Day dot shading, no gradients, "
            "NO black outlines or borders. Andy Warhol / Roy Lichtenstein aesthetic."
        ),
    },
    "pixel": {
        "characterDesc": (
            "Pixel art sprite rendered on a 32×32 grid upscaled 8×\n"
            "  * Every pixel visibly chunky (each block ≥4 px), limited palette (≤16 colors)\n"
            "  * Hard right-angle edges, no anti-aliasing, no gradients; blocky shapes only\n"
            "  * Nintendo / SNES game sprite aesthetic"
        ),
        "promptSuffix": (
            "Retro 8-bit pixel art style — render as if drawn on a 32×32 canvas then scaled up 8×. "
            "Every pixel must be visibly large and blocky. "
            "Limited palette (≤16 colors), absolutely no anti-aliasing or gradients, "
            "all edges hard right-angles. Nintendo / SNES sprite aesthetic."
        ),
    },
    "sketch": {
        "characterDesc": (
            "Pencil sketch portrait of the person\n"
            "  * Hand-drawn lines capturing the likeness from the photo\n"
            "  * Crosshatching for depth and shading, rough expressive strokes\n"
            "  * Monochrome or sepia tones"
        ),
        "promptSuffix": (
            "Pencil sketch / hand-drawn style — monochrome or sepia tones, "
            "visible pencil strokes and crosshatching for shadows, "
            "rough and expressive line quality."
        ),
    },
    "watercolor": {
        "characterDesc": (
            "Watercolor painting portrait of the person\n"
            "  * Soft rounded face with gentle color washes that bleed at edges\n"
            "  * Translucent layered colors, slight paper texture visible\n"
            "  * Dreamy, cute watercolor quality"
        ),
        "promptSuffix": (
            "Soft watercolor painting style — gentle color washes bleeding at edges, "
            "translucent layered colors, slight paper texture. "
            "Cute and dreamy watercolor quality."
        ),
    },
    "photo": {
        "characterDesc": (
            "Photo-realistic portrait of the person\n"
            "  * Faithful likeness with natural skin tones and sharp features\n"
            "  * Clean, well-lit portrait composition\n"
            "  * Smooth edges, vibrant colours, professional headshot quality\n"
            "  * Subject extracted from background — transparent BG preferred"
        ),
        "promptSuffix": (
            "Photo-realistic style — natural colours, sharp facial features, "
            "professional portrait lighting. "
            "High fidelity; maintain the authentic appearance of the person."
        ),
    },
}

# ── 情感定義（與 kEmotionCategories + _kFallbackSpecs 同步）──────────────────
# emotion 對應 StickerSpec.emotion（promptHint），bgColor 對應預設配色

EMOTIONS = {
    "greeting": {"emotion": "cheerfully waving hello",                "bgColor": "warm peach #F4A261"},
    "praise":   {"emotion": "excited thumbs-up with sparkles",        "bgColor": "sky blue #74C0FC"},
    "surprise": {"emotion": "shocked wide eyes, question marks",      "bgColor": "golden yellow #FFD43B"},
    "awkward":  {"emotion": "embarrassed blushing, sweat drop",       "bgColor": "soft pink #FFB3C6"},
    "angry":    {"emotion": "angry frowning with flames",             "bgColor": "deep red #FF6B6B"},
    "happy":    {"emotion": "joyful laughing, rainbow confetti",      "bgColor": "mint green #63E6BE"},
    "thinking": {"emotion": "thoughtful chin-rubbing, thought bubble","bgColor": "lavender #C084FC"},
    "farewell": {"emotion": "waving goodbye with sunglasses",         "bgColor": "baby blue #ADE8F4"},
    "shy":      {"emotion": "shy blushing, covering face gently",     "bgColor": "blush pink #FFD6E0"},
    "cool":     {"emotion": "smug cool confident sunglasses expression","bgColor": "electric blue #339AF0"},
    "tired":    {"emotion": "tired droopy eyes, yawning heavily",     "bgColor": "warm grey #CED4DA"},
    "cry":      {"emotion": "crying tears flowing dramatically",      "bgColor": "light blue #A5D8FF"},
    "love":     {"emotion": "loving warm smile, heart eyes, rosy cheeks","bgColor": "rose #FF8FAB"},
    "excited":  {"emotion": "star-struck excitement, jumping with joy","bgColor": "bright orange #FF922B"},
    "scared":   {"emotion": "terrified wide eyes, trembling in fear", "bgColor": "pale purple #E5DBFF"},
    "mischief": {"emotion": "playful mischievous wink, sticking out tongue","bgColor": "lime green #94D82D"},
}

DEFAULT_IMAGE_MODEL = "gemini-2.5-flash-image"
MAX_RETRIES = 2


def build_prompt(style_key: str, emotion_key: str) -> str:
    """使用與 App _buildSinglePrompt（圓形模式）完全相同的格式。
    圓形裁切由 Flutter ClipOval 處理，AI 只需產出滿版正方形色塊。
    """
    style = STYLES[style_key]
    emotion = EMOTIONS[emotion_key]
    return (
        "You are a professional LINE sticker illustrator. "
        "Draw ONE square sticker based on the person's face in the reference photo.\n\n"
        "DESIGN REQUIREMENTS:\n"
        f"- Fill the entire square canvas with the background color: {emotion['bgColor']} "
        "(no transparency anywhere, no white corners)\n"
        "- NO transparent pixels; the entire canvas must be fully opaque\n"
        f"- Character expression / pose: {emotion['emotion']}\n"
        f"- {style['characterDesc']}\n"
        "- Place the character in the upper-center of the canvas "
        "(top 65% of height, horizontally centered)\n"
        "- Leave ~10% margin on the left and right sides\n"
        "- DO NOT draw any text or letters inside the image\n"
        "- 2–4 small sparkles / stars clustered around the character (avoid corners)\n"
        "- NO white outline, NO white border\n\n"
        "OUTPUT: A single fully opaque square PNG with solid background color.\n"
        f"STYLE: {style['promptSuffix']}\n"
    )


def _extract_image_bytes(response) -> bytes | None:
    candidates = getattr(response, "candidates", None)
    if not candidates:
        return None
    content = getattr(candidates[0], "content", None)
    if content is None:
        return None
    parts = getattr(content, "parts", None)
    if not parts:
        return None
    for part in parts:
        if part.inline_data is not None:
            data = part.inline_data.data
            if isinstance(data, bytes):
                return data
            return base64.b64decode(data)
    return None


def generate_source_image(client, types, model: str) -> bytes:
    print("🐱 cat_source.png 不存在，正在用 Gemini 生成來源圖片...", flush=True)
    response = client.models.generate_content(
        model=model,
        contents=SOURCE_IMAGE_PROMPT,
        config=types.GenerateContentConfig(
            response_modalities=["image"],
            temperature=0.8,
        ),
    )
    img = _extract_image_bytes(response)
    if img is None:
        raise RuntimeError("Gemini 未回傳圖片 (來源圖生成失敗)")
    return img


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

    # 讀取環境變數：可選只產生部分組合（加速 CI）
    env_styles = os.environ.get("PREVIEW_STYLES", "").split()
    env_emotions = os.environ.get("PREVIEW_EMOTIONS", "").split()
    only_styles = [s for s in env_styles if s in STYLES] or list(STYLES.keys())
    only_emotions = [e for e in env_emotions if e in EMOTIONS] or list(EMOTIONS.keys())

    total = len(only_styles) * len(only_emotions)
    print(f"📋 產生 {len(only_styles)} 風格 × {len(only_emotions)} 情感 = {total} 張\n")

    success_count = 0
    failed = []
    count = 0

    def _generate_one(style_key: str, emotion_key: str) -> bool:
        out_path = ASSETS_DIR / f"preview_{style_key}_{emotion_key}.png"
        prompt = build_prompt(style_key, emotion_key)
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
        img_data = _extract_image_bytes(response)
        if not img_data:
            return False
        out_path.write_bytes(img_data)
        kb = len(img_data) / 1024
        print(f"✅ {kb:.0f}KB → {out_path.name}")
        return True

    for style_key in only_styles:
        for emotion_key in only_emotions:
            count += 1
            combo = f"{style_key}×{emotion_key}"
            print(f"🎨 [{count}/{total}] {combo}...", end=" ", flush=True)
            ok = False
            for attempt in range(1, MAX_RETRIES + 2):
                try:
                    ok = _generate_one(style_key, emotion_key)
                    if ok:
                        break
                    if attempt <= MAX_RETRIES:
                        print(f"⚠️ empty response, retry {attempt}/{MAX_RETRIES}...", end=" ", flush=True)
                except Exception as e:
                    if attempt <= MAX_RETRIES:
                        print(f"⚠️ {e}, retry {attempt}/{MAX_RETRIES}...", end=" ", flush=True)
                    else:
                        print(f"❌ {e}")
            if ok:
                success_count += 1
            else:
                if combo not in failed:
                    print("❌ failed after retries")
                    failed.append(combo)

    print(f"\n✨ Done: {success_count}/{total} images generated")
    if failed:
        print(f"   Failed: {', '.join(failed)}")
    if success_count == 0:
        sys.exit(1)


if __name__ == "__main__":
    main()
