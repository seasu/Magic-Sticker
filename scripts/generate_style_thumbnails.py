#!/usr/bin/env python3
"""
generate_style_thumbnails.py
─────────────────────────────
專門產生風格選擇畫面用的 9 張縮圖（9 種風格 × 打招呼情緒）。

輸出：assets/images/preview_{style}_greeting.png（共 9 張）

重點：
- Prompt 與 App 實際產圖（_buildSinglePrompt，圓形 + Chroma Key 模式）完全一致
- 額外加入【縮圖一致性規範】，確保 9 張人物大小、構圖比例相同
- 來源：assets/images/seasu-source.jpg（JPEG）

使用方法：
  export GEMINI_API_KEY="your_key_here"
  cd /path/to/Magic-Sticker
  python3 scripts/generate_style_thumbnails.py
"""

import os
import sys
import base64
from pathlib import Path

SCRIPT_DIR  = Path(__file__).parent
PROJECT_DIR = SCRIPT_DIR.parent
ASSETS_DIR  = PROJECT_DIR / "assets" / "images"
SOURCE_IMAGE = ASSETS_DIR / "seasu-source.jpg"

# 正規化人物構圖位置（統一所有縮圖的人物高低、大小）
sys.path.insert(0, str(SCRIPT_DIR))
from normalize_previews import normalize_white_bg  # noqa: E402

DEFAULT_IMAGE_MODEL = "gemini-2.5-flash-image"
MAX_RETRIES = 2

# ── 風格定義（與 StickerStyle enum 同步，使用正體中文）────────────────────────
# characterDesc / promptSuffix 直接對應 lib/core/models/sticker_style.dart

STYLES = {
    "chibi": {
        "characterDesc": (
            "根據照片人物繪製卡通 Q 版臉型（可愛 Chibi 風格）\n"
            "  * 大閃亮眼睛、小鼻子、圓潤臉頰\n"
            "  * 乾淨平面插畫、粗黑色描邊、非寫實風格\n"
            "  * 臉部與上半身自然填滿畫面"
        ),
        "promptSuffix": "LINE Friends / Chiikawa 畫質水準。",
    },
    "popArt": {
        "characterDesc": (
            "根據照片人物繪製普普藝術人物肖像\n"
            "  * 大膽簡化的臉部特徵、鮮豔高對比色彩\n"
            "  * 平塗色塊、Ben-Day 網點陰影、無黑色描邊\n"
            "  * Andy Warhol / Roy Lichtenstein 美術風格"
        ),
        "promptSuffix": "普普藝術風格——鮮豔平塗色彩、Ben-Day 網點陰影、無漸層、無黑色描邊。Andy Warhol / Roy Lichtenstein 美術風格。",
    },
    "pixel": {
        "characterDesc": (
            "根據照片人物繪製像素藝術角色\n"
            "  * 整張圖以 32×32 格子構成再放大，每格至少 4px，強制可見方塊感\n"
            "  * 限制色盤（≤16 色）、無任何反鋸齒或漸層\n"
            "  * 所有邊緣皆為直角硬邊；任天堂 / SNES 遊戲像素風"
        ),
        "promptSuffix": "復古 8-bit 像素風格——整張圖如同在 32×32 畫布上繪製再放大 8 倍，每個像素必須明顯呈現方塊感、限制色盤（≤16 色）、絕對無反鋸齒或漸層、所有邊緣皆為直角方塊。任天堂 / SNES 像素風。",
    },
    "sketch": {
        "characterDesc": (
            "根據照片人物繪製鉛筆素描肖像\n"
            "  * 手繪線條捕捉照片人物神韻\n"
            "  * 交叉線條表現深度與陰影、粗糙有力的筆觸\n"
            "  * 單色或深褐色調"
        ),
        "promptSuffix": "鉛筆素描／手繪風格——單色或深褐色調、可見的鉛筆筆觸與交叉線條陰影、粗糙且富有表現力的線條品質。",
    },
    "watercolor": {
        "characterDesc": (
            "根據照片人物繪製水彩畫肖像\n"
            "  * 柔和圓潤的臉部、邊緣暈染的溫柔色調\n"
            "  * 透明疊色、隱約可見的紙張紋理\n"
            "  * 夢幻可愛的水彩質感"
        ),
        "promptSuffix": "柔和水彩風格——邊緣暈染的溫柔色塊、透明疊色、隱約紙張紋理。可愛夢幻的水彩質感。",
    },
    "webtoon": {
        "characterDesc": (
            "根據照片人物繪製韓式 Webtoon 扁平插畫\n"
            "  * 乾淨圓滑的黑色輪廓線、均勻平塗色彩\n"
            "  * 明亮柔和的大眼睛、Q 版可愛比例\n"
            "  * 接近 LINE Friends / NAVER Webtoon 的插畫風格"
        ),
        "promptSuffix": "韓系 Webtoon 插畫風格——乾淨流暢線條、均勻平塗、明亮眼睛。LINE Friends / NAVER Webtoon 畫質水準。",
    },
    "celshade": {
        "characterDesc": (
            "根據照片人物繪製日系動漫賽璐璐厚塗插畫\n"
            "  * 清晰的厚黑邊輪廓線、硬邊陰影分層（2–3 階，無漸層邊緣）\n"
            "  * 飽和鮮豔色彩、強烈光澤反光點\n"
            "  * 日本動漫賽璐璐作畫風格"
        ),
        "promptSuffix": "日系動漫賽璐璐風格——粗黑輪廓線、硬邊分層陰影（無漸層邊緣）、飽和鮮豔色彩、明顯的高光反光點。",
    },
    "pixar3d": {
        "characterDesc": (
            "根據照片人物繪製 Pixar / Disney 3D 渲染風格角色\n"
            "  * 精緻的 subsurface scattering 膚色、圓潤卡通比例\n"
            "  * 柔和的環境光遮蔽（AO）、明亮的鏡面高光點\n"
            "  * Pixar 動畫電影的 3D 渲染質感"
        ),
        "promptSuffix": "Pixar 3D 動畫風格——圓潤立體卡通造型、精緻打光（主光源＋補光）、subsurface 膚色、鏡面高光。3D 渲染質感。",
    },
    "plush": {
        "characterDesc": (
            "根據照片人物繪製毛絨布偶玩具風格角色（2D 插畫貼圖，非照片）\n"
            "  * 模擬短絨毛質感（細小筆觸表現毛流）\n"
            "  * 圓胖可愛比例、柔和邊緣輪廓\n"
            "  * 豐富的深淺毛色層次，外觀質感像手工布偶\n"
            "  * 角色為 2D 平面插圖，無任何攝影背景、地板、環境陰影或真實場景元素"
        ),
        "promptSuffix": "毛絨玩偶插畫風格——以 2D 插圖形式模擬短絨毛材質、圓胖可愛比例、柔和邊緣輪廓、豐富毛色深淺層次。角色為純 2D 插圖貼圖，無攝影背景、無地面倒影、無環境投影，角色本體以外區域維持純技術背景色。",
    },
}

# 固定使用「打招呼」情緒（對應 App 的 greeting spec）
GREETING_EMOTION = "開心地揮手打招呼，面帶笑容"


def build_prompt(style_key: str) -> str:
    """
    與 App _buildSinglePrompt（圓形 + Chroma Key 模式）完全一致的 Prompt，
    額外加入縮圖一致性規範，確保 9 種風格的人物大小與構圖比例相同。
    """
    style = STYLES[style_key]
    return f"""\
你是一位專業的 LINE 貼圖插畫師。請根據參考照片，繪製一張正方形貼圖。

【畫布規格 — Chroma Key 去背模式】
背景是純技術用遮罩色，與插畫風格完全無關，必須嚴格遵守以下規則：
- 所有背景區域（角色與裝飾以外的全部畫面）一律以電腦純色平塗填充為純白色 #FFFFFF（R=255, G=255, B=255）
- 背景禁止任何藝術加工：無光暈、無漸層、無反光、無筆觸、無紋理、無陰影投射、無霧感
- 角色或裝飾的陰影禁止落在背景上
- 四個角落像素必須為精確的 #FFFFFF

【縮圖一致性規範 — 必須嚴格遵守，確保 9 種風格縮圖視覺統一】
- 角色構圖：臉部＋上半身正面或微 3/4 側面，頭部佔畫布高度的上方約 65%，水平置中
- 角色頭頂距上緣保留 8%，下半身截止於畫布下緣約 20% 處（約到胸口/上腹部）
- 角色左右各留 10% 邊距，人物寬度約佔畫布寬度 80%
- 此構圖比例在所有風格中必須完全一致，不得因風格不同而改變人物大小或位置

【角色設計】
- 根據參考照片，繪製可愛 Q 版卡通人物
- 表情 / 動作：{GREETING_EMOTION}
- {style['characterDesc']}
- 嚴禁角色的任何部位（頭頂、耳朵、手臂）被畫布邊緣截斷
- 禁止出現任何文字、英文字母或數字

【裝飾】在角色周圍點綴 2–3 個小閃光或星星（集中在角色周邊，不接觸背景邊緣）

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
            return data if isinstance(data, bytes) else base64.b64decode(data)
    return None


def main():
    api_key = os.environ.get("GEMINI_API_KEY", "")
    if not api_key:
        print("❌ GEMINI_API_KEY not set")
        sys.exit(1)

    if not SOURCE_IMAGE.exists():
        print(f"❌ 找不到來源圖片：{SOURCE_IMAGE}")
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
    client = genai.Client(api_key=api_key)

    source_bytes = SOURCE_IMAGE.read_bytes()
    source_b64   = base64.b64encode(source_bytes).decode()
    print(f"📷 來源：{SOURCE_IMAGE.name}（{len(source_bytes) // 1024} KB）")
    print(f"🤖 模型：{image_model}")
    print(f"🎯 目標：9 種風格 × greeting = 9 張縮圖\n")

    ASSETS_DIR.mkdir(parents=True, exist_ok=True)
    success, failed = 0, []

    for i, style_key in enumerate(STYLES.keys(), 1):
        out_path = ASSETS_DIR / f"preview_{style_key}_greeting.png"
        print(f"🎨 [{i}/9] {style_key}...", end=" ", flush=True)

        ok = False
        for attempt in range(1, MAX_RETRIES + 2):
            try:
                response = client.models.generate_content(
                    model=image_model,
                    contents=[
                        types.Content(
                            role="user",
                            parts=[
                                types.Part(
                                    inline_data=types.Blob(
                                        mime_type="image/jpeg",
                                        data=source_b64,
                                    )
                                ),
                                types.Part(text=build_prompt(style_key)),
                            ],
                        )
                    ],
                    config=types.GenerateContentConfig(
                        response_modalities=["image"],
                        temperature=1.0,
                    ),
                )
                img_data = _extract_image_bytes(response)
                if img_data:
                    out_path.write_bytes(img_data)
                    # 正規化人物構圖位置（裁切並統一排版）
                    normalize_white_bg(out_path)
                    print(f"✅ {len(img_data) // 1024} KB → {out_path.name}")
                    ok = True
                    break
                if attempt <= MAX_RETRIES:
                    print(f"⚠️ empty, retry {attempt}...", end=" ", flush=True)
            except Exception as e:
                if attempt <= MAX_RETRIES:
                    print(f"⚠️ {e}, retry {attempt}...", end=" ", flush=True)
                else:
                    print(f"❌ {e}")

        if ok:
            success += 1
        else:
            failed.append(style_key)
            print(f"❌ failed after {MAX_RETRIES + 1} attempts")

    print(f"\n✨ 完成：{success}/9 張成功")
    if failed:
        print(f"   失敗：{', '.join(failed)}")
    if success == 0:
        sys.exit(1)


if __name__ == "__main__":
    main()
