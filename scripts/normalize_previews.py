#!/usr/bin/env python3
"""
normalize_previews.py — 統一 preview 圖片人物構圖位置

解決問題：Gemini AI 生成的 preview 圖片（1024×1024 RGB），
即使 prompt 有構圖規範，人物位置仍會隨機偏移（高低、大小不一）。

偵測策略：
  從四角各取 10×10 像素採樣背景色（平均值），
  再找與背景色差距 > BG_DISTANCE_THRESHOLD 的像素 = 人物。
  不依賴 alpha channel，適用所有 RGB 圖片。

目標構圖參數：
  TARGET_SIZE       = 1024 px（保持原圖尺寸）
  CHAR_HEIGHT_RATIO = 0.78（人物高度佔畫布 78%）
  CHAR_TOP_RATIO    = 0.07（人物頂端距上緣 7%）
  CHAR_MAX_W_RATIO  = 0.88（人物寬度上限 88%，防寬型角色溢出）

CLI 用法：
  python3 scripts/normalize_previews.py --all
  python3 scripts/normalize_previews.py --styles chibi pixar3d
  python3 scripts/normalize_previews.py --emotions greeting happy
  python3 scripts/normalize_previews.py --thumbnails
  python3 scripts/normalize_previews.py --all --dry-run

作為 module 使用：
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

TARGET_SIZE = 1024         # 輸出邊長（px）— 保持與原圖相同
CHAR_HEIGHT_RATIO = 0.78   # 人物高度 = 畫布的 78%
CHAR_TOP_RATIO = 0.07      # 人物頂端距上緣 7%
CHAR_MAX_W_RATIO = 0.88    # 人物寬度上限（防寬型角色溢出）

# 角落採樣框大小（px），用於估算背景色
CORNER_SAMPLE = 12

# 像素顏色距離閾值：與背景色差 > 此值視為人物像素
BG_DISTANCE_THRESHOLD = 35

ALL_STYLES = [
    "chibi", "popArt", "pixel", "sketch", "watercolor",
    "webtoon", "celshade", "pixar3d", "plush", "photo",
]

ALL_EMOTIONS = [
    "greeting", "praise", "surprise", "awkward", "angry", "happy",
    "thinking", "farewell", "shy", "cool", "tired", "cry",
    "love", "excited", "scared", "mischief",
]

# ── 核心函式 ──────────────────────────────────────────────────────────────────


def _sample_bg_color(arr: np.ndarray) -> np.ndarray:
    """從四角各取 CORNER_SAMPLE×CORNER_SAMPLE 像素，回傳背景色平均值 [R, G, B]。"""
    h, w = arr.shape[:2]
    n = CORNER_SAMPLE
    rgb = arr[:, :, :3]  # 只取 RGB
    corners = np.concatenate([
        rgb[:n,  :n ].reshape(-1, 3),
        rgb[:n,  w-n:].reshape(-1, 3),
        rgb[h-n:, :n ].reshape(-1, 3),
        rgb[h-n:, w-n:].reshape(-1, 3),
    ], axis=0)
    return corners.mean(axis=0)


def _find_char_bbox(arr: np.ndarray) -> tuple[int, int, int, int] | None:
    """
    偵測人物 bounding box。
    回傳 (left, top, right, bottom)；找不到人物時回傳 None。
    """
    bg = _sample_bg_color(arr)
    rgb = arr[:, :, :3].astype(np.int32)

    # Euclidean distance from background color
    dist = np.sqrt(np.sum((rgb - bg) ** 2, axis=2))
    mask = dist > BG_DISTANCE_THRESHOLD

    rows = np.any(mask, axis=1)
    cols = np.any(mask, axis=0)
    if not rows.any():
        return None

    rmin, rmax = int(np.where(rows)[0][0]), int(np.where(rows)[0][-1])
    cmin, cmax = int(np.where(cols)[0][0]), int(np.where(cols)[0][-1])
    return cmin, rmin, cmax + 1, rmax + 1


def normalize_image(img_path: Path | str, dry_run: bool = False) -> bool:
    """
    統一正規化函式：適用所有 preview 圖片（RGB 或 RGBA）。
    背景色從四角自動偵測，人物縮放後貼到固定構圖位置。
    """
    img_path = Path(img_path)
    try:
        img = Image.open(img_path).convert("RGBA")
    except Exception as e:
        print(f"  ⚠️  無法開啟 {img_path.name}: {e}")
        return False

    arr = np.array(img)

    # 判斷是否有真正的透明背景
    alpha = arr[:, :, 3]
    has_alpha = bool((alpha < 128).any())

    if has_alpha:
        # 透明背景圖：alpha > 8 的像素 = 人物
        mask = alpha > 8
        rows = np.any(mask, axis=1)
        cols = np.any(mask, axis=0)
        if not rows.any():
            print(f"  ⚠️  {img_path.name}: 找不到人物（全透明？）")
            return False
        rmin, rmax = int(np.where(rows)[0][0]), int(np.where(rows)[0][-1])
        cmin, cmax = int(np.where(cols)[0][0]), int(np.where(cols)[0][-1])
        bbox = (cmin, rmin, cmax + 1, rmax + 1)
        bg_fill: tuple = (0, 0, 0, 0)
    else:
        # RGB 圖：從角落採樣背景色，找與背景差異大的像素 = 人物
        bbox = _find_char_bbox(arr)
        if bbox is None:
            print(f"  ⚠️  {img_path.name}: 找不到人物（背景過於複雜？）")
            return False
        bg = _sample_bg_color(arr)
        bg_fill = (int(bg[0]), int(bg[1]), int(bg[2]), 255)

    # 裁切人物
    char = img.crop(bbox)
    char_w, char_h = char.size

    # 計算目標尺寸
    target = TARGET_SIZE
    target_char_h = int(target * CHAR_HEIGHT_RATIO)
    scale = target_char_h / char_h
    target_char_w = int(char_w * scale)

    # 寬度超限時改以寬度為基準縮放
    max_w = int(target * CHAR_MAX_W_RATIO)
    if target_char_w > max_w:
        target_char_w = max_w
        scale = target_char_w / char_w
        target_char_h = int(char_h * scale)

    char_resized = char.resize((target_char_w, target_char_h), Image.LANCZOS)

    # 建立畫布，貼上人物
    canvas = Image.new("RGBA", (target, target), bg_fill)
    paste_x = (target - target_char_w) // 2
    paste_y = int(target * CHAR_TOP_RATIO)

    if has_alpha:
        canvas.paste(char_resized, (paste_x, paste_y), char_resized)
        result = canvas
    else:
        canvas.paste(char_resized, (paste_x, paste_y))
        result = canvas.convert("RGB")  # 保持原本 RGB 格式

    if not dry_run:
        result.save(str(img_path), "PNG")
    return True


# 向下相容舊 API（generate_style_previews_ci.py 用）
def normalize_transparent(img_path: Path | str, dry_run: bool = False) -> bool:
    return normalize_image(img_path, dry_run)


# 向下相容舊 API（generate_style_thumbnails.py 用）
def normalize_white_bg(img_path: Path | str, dry_run: bool = False) -> bool:
    return normalize_image(img_path, dry_run)


# ── CLI ───────────────────────────────────────────────────────────────────────


def _collect_targets(args: argparse.Namespace) -> list[Path]:
    """回傳需要處理的圖片路徑清單。"""
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

    # 去重、保留順序
    seen: set[Path] = set()
    unique: list[Path] = []
    for p in targets:
        if p not in seen:
            seen.add(p)
            unique.append(p)

    return unique


def main() -> None:
    parser = argparse.ArgumentParser(
        description="統一 preview 圖片人物構圖位置",
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

    print(f"{'[DRY RUN] ' if args.dry_run else ''}處理 {len(targets)} 張圖片...\n")

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
