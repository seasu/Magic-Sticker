#!/usr/bin/env python3
"""
normalize_previews.py — 統一 preview 圖片人物構圖位置 + 去背

解決問題：Gemini AI 生成的 preview 圖片（1024×1024 RGB），
即使 prompt 有構圖規範，人物位置仍會隨機偏移（高低、大小不一），
且帶有彩色背景（各情緒對應色）。

處理流程：
  1. 從四角採樣估算背景色
  2. 找人物 bounding box（與背景色差 > BG_DISTANCE_THRESHOLD 的像素）
  3. 裁切人物，縮放至目標構圖（高度 CHAR_HEIGHT_RATIO，頂端 CHAR_TOP_RATIO）
  4. 貼到新畫布（背景填充採樣色）
  5. 去背：對畫布背景色做精確 alpha 遮罩（含羽化），輸出 RGBA 透明 PNG

目標構圖參數：
  TARGET_SIZE       = 1024 px（保持與原圖相同）
  CHAR_HEIGHT_RATIO = 0.78（人物高度佔畫布 78%）
  CHAR_TOP_RATIO    = 0.07（人物頂端距上緣 7%）
  CHAR_MAX_W_RATIO  = 0.88（人物寬度上限 88%，防寬型角色溢出）

去背參數：
  REMOVE_THRESHOLD  = 28（與背景色差 < 28 的像素設為全透明）
  FEATHER_WIDTH     = 22（過渡羽化帶寬度，讓邊緣平滑）

CLI 用法：
  python3 scripts/normalize_previews.py --all
  python3 scripts/normalize_previews.py --styles chibi pixar3d
  python3 scripts/normalize_previews.py --emotions greeting happy
  python3 scripts/normalize_previews.py --thumbnails
  python3 scripts/normalize_previews.py --all --dry-run

作為 module 使用（供生成腳本呼叫）：
  from normalize_previews import normalize_transparent, normalize_white_bg, normalize_image
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

import numpy as np
from PIL import Image

# ── 常數 ─────────────────────────────────────────────────────────────────────

ASSETS_DIR = Path(__file__).parent.parent / "assets" / "images"

TARGET_SIZE = 1024          # 輸出邊長（px）— 保持與原圖相同
CHAR_HEIGHT_RATIO = 0.78    # 人物高度 = 畫布的 78%
CHAR_TOP_RATIO = 0.07       # 人物頂端距上緣 7%
CHAR_MAX_W_RATIO = 0.88     # 人物寬度上限（防寬型角色溢出）

CORNER_SAMPLE = 12          # 採樣角落框大小（px）
BG_DISTANCE_THRESHOLD = 35  # 偵測人物用：色差 > 此值 = 人物像素

REMOVE_THRESHOLD = 28       # 去背用：色差 < 此值 → 全透明
FEATHER_WIDTH = 22          # 去背羽化帶寬度，讓邊緣自然過渡

ALL_STYLES = [
    "chibi", "popArt", "pixel", "sketch", "watercolor",
    "webtoon", "celshade", "pixar3d", "plush", "photo",
]

ALL_EMOTIONS = [
    "greeting", "praise", "surprise", "awkward", "angry", "happy",
    "thinking", "farewell", "shy", "cool", "tired", "cry",
    "love", "excited", "scared", "mischief",
]

# ── 背景偵測 ──────────────────────────────────────────────────────────────────


def _sample_bg_color(arr: np.ndarray) -> np.ndarray:
    """從四角各取 CORNER_SAMPLE×CORNER_SAMPLE 像素，回傳背景色平均值 [R, G, B]。"""
    h, w = arr.shape[:2]
    n = CORNER_SAMPLE
    rgb = arr[:, :, :3]
    corners = np.concatenate([
        rgb[:n,   :n  ].reshape(-1, 3),
        rgb[:n,   w-n:].reshape(-1, 3),
        rgb[h-n:, :n  ].reshape(-1, 3),
        rgb[h-n:, w-n:].reshape(-1, 3),
    ], axis=0)
    return corners.mean(axis=0)


def _find_char_bbox(arr: np.ndarray) -> tuple[int, int, int, int] | None:
    """
    從背景色找人物 bounding box。
    回傳 (left, top, right, bottom)；找不到時回傳 None。
    """
    bg = _sample_bg_color(arr)
    rgb = arr[:, :, :3].astype(np.int32)
    dist = np.sqrt(np.sum((rgb - bg) ** 2, axis=2))
    mask = dist > BG_DISTANCE_THRESHOLD

    rows = np.any(mask, axis=1)
    cols = np.any(mask, axis=0)
    if not rows.any():
        return None

    rmin, rmax = int(np.where(rows)[0][0]), int(np.where(rows)[0][-1])
    cmin, cmax = int(np.where(cols)[0][0]), int(np.where(cols)[0][-1])
    return cmin, rmin, cmax + 1, rmax + 1

# ── 去背（精確：針對已知純色背景）────────────────────────────────────────────


def _apply_bg_removal(canvas: Image.Image, bg_color: tuple) -> Image.Image:
    """
    對畫布做去背：將接近 bg_color 的像素設為透明（含羽化邊緣）。
    bg_color 必須是畫布的已知純色背景（在 _build_normalized 中填充的顏色）。
    Returns RGBA Image.
    """
    rgba = canvas.convert("RGBA")
    arr = np.array(rgba, dtype=np.float32)

    bg = np.array(bg_color[:3], dtype=np.float32)
    rgb = arr[:, :, :3]
    dist = np.sqrt(np.sum((rgb - bg) ** 2, axis=2))

    # 羽化：dist < REMOVE_THRESHOLD → alpha=0；
    #        dist > REMOVE_THRESHOLD + FEATHER_WIDTH → alpha=255；中間線性插值
    alpha = np.clip(
        (dist - REMOVE_THRESHOLD) / FEATHER_WIDTH * 255,
        0, 255
    ).astype(np.uint8)

    arr[:, :, 3] = alpha
    return Image.fromarray(arr.astype(np.uint8), "RGBA")


# ── 主要正規化函式 ─────────────────────────────────────────────────────────────


def normalize_image(img_path: Path | str, dry_run: bool = False) -> bool:
    """
    統一正規化函式：
      1. 偵測背景色（四角採樣）
      2. 裁切人物、縮放至目標構圖
      3. 貼到新畫布（純色背景）
      4. 去背（背景轉透明）→ 輸出 RGBA PNG

    適用所有 preview 圖片（RGB 彩色背景 或 RGBA 透明背景）。
    """
    img_path = Path(img_path)
    try:
        img = Image.open(img_path).convert("RGBA")
    except Exception as e:
        print(f"  ⚠️  無法開啟 {img_path.name}: {e}")
        return False

    arr = np.array(img)
    alpha_ch = arr[:, :, 3]
    has_alpha = bool((alpha_ch < 128).any())

    if has_alpha:
        # 已是透明背景：只做位置正規化，不需去背
        mask = alpha_ch > 8
        rows = np.any(mask, axis=1)
        cols = np.any(mask, axis=0)
        if not rows.any():
            print(f"  ⚠️  {img_path.name}: 找不到人物（全透明？）")
            return False
        rmin = int(np.where(rows)[0][0])
        rmax = int(np.where(rows)[0][-1])
        cmin = int(np.where(cols)[0][0])
        cmax = int(np.where(cols)[0][-1])
        bbox = (cmin, rmin, cmax + 1, rmax + 1)
        bg_fill: tuple = (0, 0, 0, 0)
        remove_bg = False
    else:
        # RGB 彩色背景：偵測背景色後找人物、再去背
        bbox = _find_char_bbox(arr)
        if bbox is None:
            print(f"  ⚠️  {img_path.name}: 找不到人物（背景過於複雜？）")
            return False
        bg = _sample_bg_color(arr)
        bg_fill = (int(bg[0]), int(bg[1]), int(bg[2]), 255)
        remove_bg = True

    # 裁切人物
    char = img.crop(bbox)
    char_w, char_h = char.size

    # 計算目標尺寸
    target = TARGET_SIZE
    target_char_h = int(target * CHAR_HEIGHT_RATIO)
    scale = target_char_h / char_h
    target_char_w = int(char_w * scale)

    max_w = int(target * CHAR_MAX_W_RATIO)
    if target_char_w > max_w:
        target_char_w = max_w
        scale = target_char_w / char_w
        target_char_h = int(char_h * scale)

    char_resized = char.resize((target_char_w, target_char_h), Image.LANCZOS)

    # 建立畫布、貼上人物
    canvas = Image.new("RGBA", (target, target), bg_fill)
    paste_x = (target - target_char_w) // 2
    paste_y = int(target * CHAR_TOP_RATIO)

    if has_alpha:
        canvas.paste(char_resized, (paste_x, paste_y), char_resized)
        result = canvas
    else:
        canvas.paste(char_resized, (paste_x, paste_y))
        # 去背：對畫布背景色做精確 alpha 遮罩
        result = _apply_bg_removal(canvas, bg_fill)

    if not dry_run:
        result.save(str(img_path), "PNG")
    return True


# 向下相容舊 API（generate_style_previews_ci.py / generate_style_thumbnails.py 用）
def normalize_transparent(img_path: Path | str, dry_run: bool = False) -> bool:
    return normalize_image(img_path, dry_run)


def normalize_white_bg(img_path: Path | str, dry_run: bool = False) -> bool:
    return normalize_image(img_path, dry_run)


# ── CLI ───────────────────────────────────────────────────────────────────────


def _collect_targets(args: argparse.Namespace) -> list[Path]:
    targets: list[Path] = []

    if args.all or args.thumbnails:
        for style in ALL_STYLES:
            p = ASSETS_DIR / f"preview_{style}_greeting.png"
            if p.exists():
                targets.append(p)

    if args.all or args.styles or args.emotions:
        styles = args.styles if args.styles else ALL_STYLES
        emotions = args.emotions if args.emotions else ALL_EMOTIONS
        for style in styles:
            for emotion in emotions:
                p = ASSETS_DIR / f"preview_{style}_{emotion}.png"
                if p.exists():
                    targets.append(p)

    seen: set[Path] = set()
    unique: list[Path] = []
    for p in targets:
        if p not in seen:
            seen.add(p)
            unique.append(p)
    return unique


def main() -> None:
    parser = argparse.ArgumentParser(
        description="統一 preview 圖片人物構圖位置 + 去背（輸出 RGBA 透明 PNG）",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
範例：
  python3 scripts/normalize_previews.py --all
  python3 scripts/normalize_previews.py --thumbnails
  python3 scripts/normalize_previews.py --styles chibi pixar3d --emotions greeting happy
  python3 scripts/normalize_previews.py --all --dry-run
        """,
    )
    group = parser.add_mutually_exclusive_group()
    group.add_argument("--all", action="store_true", help="處理全部 preview 圖")
    group.add_argument("--thumbnails", action="store_true",
                       help="只處理白底縮圖（preview_*_greeting.png）")
    parser.add_argument("--styles", nargs="+", metavar="STYLE",
                        help=f"指定風格（可多選），可選值：{', '.join(ALL_STYLES)}")
    parser.add_argument("--emotions", nargs="+", metavar="EMOTION",
                        help=f"指定情緒（可多選），可選值：{', '.join(ALL_EMOTIONS)}")
    parser.add_argument("--dry-run", action="store_true",
                        help="只顯示會處理哪些檔案，不實際儲存")

    args = parser.parse_args()

    if not args.all and not args.thumbnails and not args.styles and not args.emotions:
        parser.print_help()
        sys.exit(0)

    targets = _collect_targets(args)
    if not targets:
        print("找不到符合條件的圖片。")
        sys.exit(0)

    print(f"{'[DRY RUN] ' if args.dry_run else ''}處理 {len(targets)} 張圖片（正規化 + 去背）...\n")

    ok = 0
    fail = 0
    for path in targets:
        print(f"  {path.name}", end="", flush=True)

        if args.dry_run:
            print()
            ok += 1
            continue

        success = normalize_image(path)
        if success:
            print(" ✅")
            ok += 1
        else:
            print(" ❌")
            fail += 1

    print(f"\n完成：{ok} 成功，{fail} 失敗。")
    if fail > 0:
        sys.exit(1)


if __name__ == "__main__":
    main()
