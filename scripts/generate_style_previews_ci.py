#!/usr/bin/env python3
"""
generate_style_previews_ci.py
─────────────────────────────
CI/CD 專用：使用 Gemini image generation 將人物照片轉換為
12 種風格 × 16 種情感 = 192 張示意圖。

命名格式：preview_{style}_{emotionId}.png
例如：preview_chibi_greeting.png、preview_webtoon_happy.png

Prompt 格式與 App 實際產圖（_buildSinglePrompt，圓形 + Chroma Key 模式）完全一致：
- 正體中文 prompt 結構
- 背景：Chroma Key 純白 #FFFFFF（非透明）
- characterDesc / promptSuffix 直接對應 lib/core/models/sticker_style.dart

若 assets/images/cat_source.png 不存在，腳本會先用 Gemini 文字生成它。

使用方法（GitHub Actions）：
  pip install google-genai
  python3 scripts/generate_style_previews_ci.py

可選環境變數：
  PREVIEW_STYLES="chibi webtoon"    # 只產生指定風格（空格分隔）
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

# 正規化人物構圖位置（統一所有 preview 圖片的人物高低、大小）
sys.path.insert(0, str(SCRIPT_DIR))
from normalize_previews import normalize_transparent  # noqa: E402

SOURCE_IMAGE_PROMPT = (
    "A cute brown tabby cat raising its right paw in a greeting pose, "
    "sitting upright, looking at the camera with big bright eyes. "
    "Clean white background. Square format 512x512px. "
    "Photo-realistic style, natural fur texture."
)

# ── 風格定義（與 StickerStyle enum 同步，使用正體中文）────────────────────────
# characterDesc / promptSuffix 直接對應 lib/core/models/sticker_style.dart

STYLES = {
    "chibi": {
        "characterDesc": (
            "根據照片人物繪製卡通 Q 版臉型（可愛 Chibi 風格）\n"
            "  * 大閃亮眼睛、小鼻子、圓潤臉頰\n"
            "  * 乾淨平面插畫、粗黑色描邊、非寫實風格\n"
            "  * 臉部與上半身自然填滿圓形"
        ),
        "promptSuffix": "LINE Friends / Chiikawa 畫質水準。",
    },
    "popArt": {
        "characterDesc": (
            "根據照片人物繪製普普藝術風格的完整 Q 版卡通人物（非肖像、非半身，頭頂至腳底完整呈現）\n"
            "  * 大膽簡化的臉部特徵、鮮豔高對比色彩\n"
            "  * 平塗色塊、Ben-Day 網點陰影、無黑色描邊\n"
            "  * Andy Warhol / Roy Lichtenstein 美術風格\n"
            "  * 完整身形不被任何畫布邊緣截斷"
        ),
        "promptSuffix": (
            "普普藝術風格——鮮豔平塗色彩、Ben-Day 網點陰影、無漸層、無黑色描邊。"
            "Andy Warhol / Roy Lichtenstein 美術風格。"
        ),
    },
    "pixel": {
        "characterDesc": (
            "根據照片人物繪製像素藝術角色\n"
            "  * 整張圖以 32×32 格子構成再放大，每格至少 4px，強制可見方塊感\n"
            "  * 限制色盤（≤16 色）、無任何反鋸齒或漸層\n"
            "  * 所有邊緣皆為直角硬邊；任天堂 / SNES 遊戲像素風"
        ),
        "promptSuffix": (
            "復古 8-bit 像素風格——整張圖如同在 32×32 畫布上繪製再放大 8 倍，"
            "每個像素必須明顯呈現方塊感、限制色盤（≤16 色）、絕對無反鋸齒或漸層、所有邊緣皆為直角方塊。"
            "任天堂 / SNES 像素風。"
        ),
    },
    "sketch": {
        "characterDesc": (
            "根據照片人物繪製鉛筆素描風格的完整 Q 版卡通人物（非肖像、非半身，頭頂至腳底完整呈現）\n"
            "  * 手繪線條捕捉照片人物神韻\n"
            "  * 交叉線條表現深度與陰影、粗糙有力的筆觸\n"
            "  * 單色或深褐色調\n"
            "  * 完整身形不被任何畫布邊緣截斷"
        ),
        "promptSuffix": (
            "鉛筆素描／手繪風格——單色或深褐色調、可見的鉛筆筆觸與交叉線條陰影、粗糙且富有表現力的線條品質。"
        ),
    },
    "watercolor": {
        "characterDesc": (
            "根據照片人物繪製水彩風格的完整 Q 版卡通人物（非肖像、非半身，頭頂至腳底完整呈現）\n"
            "  * 柔和圓潤的臉部、邊緣暈染的溫柔色調\n"
            "  * 透明疊色、隱約可見的紙張紋理\n"
            "  * 夢幻可愛的水彩質感\n"
            "  * 完整身形不被任何畫布邊緣截斷"
        ),
        "promptSuffix": (
            "柔和水彩風格——邊緣暈染的溫柔色塊、透明疊色、隱約紙張紋理。可愛夢幻的水彩質感。"
        ),
    },
    "webtoon": {
        "characterDesc": (
            "根據照片人物繪製韓式 Webtoon 扁平插畫\n"
            "  * 乾淨圓滑的黑色輪廓線、均勻平塗色彩\n"
            "  * 明亮柔和的大眼睛、Q 版可愛比例\n"
            "  * 接近 LINE Friends / NAVER Webtoon 的插畫風格"
        ),
        "promptSuffix": (
            "韓系 Webtoon 插畫風格——乾淨流暢線條、均勻平塗、明亮眼睛。"
            "LINE Friends / NAVER Webtoon 畫質水準。"
        ),
    },
    "celshade": {
        "characterDesc": (
            "根據照片人物繪製日系動漫賽璐璐厚塗插畫\n"
            "  * 清晰的厚黑邊輪廓線、硬邊陰影分層（2–3 階，無漸層邊緣）\n"
            "  * 飽和鮮豔色彩、強烈光澤反光點\n"
            "  * 日本動漫賽璐璐作畫風格"
        ),
        "promptSuffix": (
            "日系動漫賽璐璐風格——粗黑輪廓線、硬邊分層陰影（無漸層邊緣）、飽和鮮豔色彩、明顯的高光反光點。"
        ),
    },
    "pixar3d": {
        "characterDesc": (
            "根據照片人物繪製 Pixar / Disney 3D 渲染風格角色\n"
            "  * 精緻的 subsurface scattering 膚色、圓潤卡通比例\n"
            "  * 柔和的環境光遮蔽（AO）、明亮的鏡面高光點\n"
            "  * Pixar 動畫電影的 3D 渲染質感"
        ),
        "promptSuffix": (
            "Pixar 3D 動畫風格——圓潤立體卡通造型、精緻打光（主光源＋補光）、subsurface 膚色、鏡面高光。"
            "3D 渲染質感。"
        ),
    },
    "plush": {
        "characterDesc": (
            "根據照片人物繪製毛絨布偶玩具風格角色（2D 插畫貼圖，非照片）\n"
            "  * 模擬短絨毛質感（細小筆觸表現毛流）\n"
            "  * 圓胖可愛比例、柔和邊緣輪廓\n"
            "  * 豐富的深淺毛色層次，外觀質感像手工布偶\n"
            "  * 角色為 2D 平面插圖，無任何攝影背景、地板、環境陰影或真實場景元素"
        ),
        "promptSuffix": (
            "毛絨玩偶插畫風格——以 2D 插圖形式模擬短絨毛材質、圓胖可愛比例、柔和邊緣輪廓、豐富毛色深淺層次。"
            "角色為純 2D 插圖貼圖，無攝影背景、無地面倒影、無環境投影，角色本體以外區域維持純技術背景色。"
        ),
    },
    "yuruDoodle": {
        "characterDesc": (
            "根據照片人物繪製「ゆるい（鬆散可愛）」塗鴉風格的完整 Q 版角色（頭頂至腳底完整呈現）\n"
            "  * 刻意歪扭的不均勻輪廓線、五官大小不對稱（一大一小的眼睛等）\n"
            "  * 粗糙肥厚的黑色手繪線條、面部簡化但身體四肢完整可見\n"
            "  * 整體散漫自然、像小孩亂畫卻帶有獨特個性與溫度\n"
            "  * 完整身形不被任何畫布邊緣截斷"
        ),
        "promptSuffix": (
            "日本「下手上手（heta-uma）」ゆるキャラ 風格——刻意不精緻的歪扭線條與不對稱五官，散漫卻充滿個性，像地方吉祥物的手繪質感。"
        ),
    },
    "showaManga": {
        "characterDesc": (
            "根據照片人物繪製昭和復古漫畫風格的完整 Q 版卡通人物（非肖像、非半身，頭頂至腳底完整呈現）\n"
            "  * 黑白為主（可有限度使用 1–2 種強調色）、手繪網點（スクリーントーン）陰影\n"
            "  * 粗獷有力的黑色輪廓線、誇張的速度線與動感線條僅集中於角色周邊，不延伸至畫布邊緣\n"
            "  * 大而明亮的 60 年代漫畫風眼睛、誇張表情框線\n"
            "  * 完整身形不被任何畫布邊緣截斷"
        ),
        "promptSuffix": (
            "昭和復古漫畫風格——黑白手繪、スクリーントーン 網點陰影、粗獷輪廓線、60 年代日本漫畫質感。手塚治虫 / 藤子不二雄 風格。"
        ),
    },
    "claymation": {
        "characterDesc": (
            "根據照片人物繪製黏土捏塑風格的完整 Q 版角色（2D 插畫貼圖，非照片，頭頂至腳底完整呈現）\n"
            "  * 模擬手工黏土材質——可見輕微指痕、不均勻的表面起伏\n"
            "  * 圓潤厚重的造型比例、柔和的邊緣與輪廓\n"
            "  * 豐富的黏土色澤高光與陰影，外觀像手工捏製的玩偶\n"
            "  * 角色為 2D 平面插圖，無任何攝影背景、地板或真實場景元素\n"
            "  * 完整身形不被任何畫布邊緣截斷"
        ),
        "promptSuffix": (
            "黏土捏塑插畫風格——以 2D 插圖形式模擬手工黏土材質、圓潤厚重比例、可見指痕與不均勻表面起伏。"
            "Aardman（笑笑羊）/ 定格動畫黏土玩偶風格。"
        ),
    },
}

# ── 情感定義（與 kEmotionCategories + _kFallbackSpecs 同步）──────────────────
# emotion 對應 StickerSpec.emotion（promptHint），bgColor 對應預設配色

EMOTIONS = {
    "greeting": {"emotion": "cheerfully waving hello",                 "bgColor": "warm peach #F4A261"},
    "praise":   {"emotion": "excited thumbs-up with sparkles",         "bgColor": "sky blue #74C0FC"},
    "surprise": {"emotion": "shocked wide eyes, question marks",       "bgColor": "golden yellow #FFD43B"},
    "awkward":  {"emotion": "embarrassed blushing, sweat drop",        "bgColor": "soft pink #FFB3C6"},
    "angry":    {"emotion": "angry frowning with flames",              "bgColor": "deep red #FF6B6B"},
    "happy":    {"emotion": "joyful laughing, rainbow confetti",       "bgColor": "mint green #63E6BE"},
    "thinking": {"emotion": "thoughtful chin-rubbing, thought bubble", "bgColor": "lavender #C084FC"},
    "farewell": {"emotion": "waving goodbye with sunglasses",          "bgColor": "baby blue #ADE8F4"},
    "shy":      {"emotion": "shy blushing, covering face gently",      "bgColor": "blush pink #FFD6E0"},
    "cool":     {"emotion": "smug cool confident sunglasses expression","bgColor": "electric blue #339AF0"},
    "tired":    {"emotion": "tired droopy eyes, yawning heavily",      "bgColor": "warm grey #CED4DA"},
    "cry":      {"emotion": "crying tears flowing dramatically",       "bgColor": "light blue #A5D8FF"},
    "love":     {"emotion": "loving warm smile, heart eyes, rosy cheeks","bgColor": "rose #FF8FAB"},
    "excited":  {"emotion": "star-struck excitement, jumping with joy", "bgColor": "bright orange #FF922B"},
    "scared":   {"emotion": "terrified wide eyes, trembling in fear",  "bgColor": "pale purple #E5DBFF"},
    "mischief": {"emotion": "playful mischievous wink, sticking out tongue","bgColor": "lime green #94D82D"},
}

DEFAULT_IMAGE_MODEL = "gemini-2.5-flash-image"
MAX_RETRIES = 2


def build_prompt(style_key: str, emotion_key: str) -> str:
    """使用與 App _buildSinglePrompt（圓形 + Chroma Key 模式，kStickerBgChromaKey=true）
    完全相同的格式與語言（正體中文）。
    """
    style = STYLES[style_key]
    emotion = EMOTIONS[emotion_key]
    return f"""\
你是一位專業的 LINE 貼圖插畫師。請根據參考照片，繪製一張正方形貼圖。

【畫布規格 — Chroma Key 去背模式】
背景是純技術用遮罩色，與插畫風格完全無關，必須嚴格遵守以下規則：
- 所有背景區域（角色與裝飾以外的全部畫面）一律以電腦純色平塗填充為純白色 #FFFFFF（R=255, G=255, B=255）
- 背景禁止任何藝術加工：無光暈、無漸層、無反光、無筆觸、無紋理、無陰影投射、無霧感
- 角色或裝飾的陰影禁止落在背景上
- 四個角落像素必須為精確的 #FFFFFF

【角色設計】
- 根據參考照片，繪製可愛 Q 版卡通人物
- 表情 / 動作：{emotion['emotion']}
- {style['characterDesc']}
- 將角色完整置於畫布中央偏上（約佔畫布高度的上方 65%，水平置中）
- 角色頭頂保留至少 5% 的上邊距，雙腳或身體下緣保留至少 5% 的下邊距，確保角色不被任何邊緣裁切
- 角色左右兩側保留約 10% 邊距
- 嚴禁角色的任何部位（頭頂、耳朵、手臂、腳等）被畫布邊緣截斷
- 禁止出現任何文字、英文字母或數字

【裝飾】在角色周圍點綴 2–4 個小閃光或星星（集中在角色周邊，不接觸背景邊緣）

【輸出】單一正方形 PNG，背景為純平塗 #FFFFFF，無任何光影處理。
風格：{style['promptSuffix']}
"""


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
        # 正規化人物構圖位置（裁切並統一排版）
        normalize_transparent(out_path)
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
