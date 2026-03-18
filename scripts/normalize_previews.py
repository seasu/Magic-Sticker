#!/usr/bin/env python3
"""
normalize_previews.py — 統一 preview 圖片人物構圖位置

解決問題：Gemini AI 生成的 preview 圖片，即使 prompt 有構圖規範，
人物位置仍會隨機偏移（高低、大小不一）。本腳本以 PIL 偵測人物
bounding box，並重新縮放、置中貼到固定位置，確保所有圖片人物位置統一。

支援兩種圖片類型：
  - 透明背景（preview_*.png，alpha=0）：偵測 alpha>8 的像素
  - 白底縮圖（background #FFFFFF）：偵測 R<240 or G<240 or B<240 的像素

目標構圖參數：
  TARGET_SIZE       = 800 px（正方形邊長）
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
  from normalize_previews import normalize_transparent, normalize_white_bg
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

import numpy as np
from PIL import Image

# ── 常數 ─────────────────────────────────────────────────────────────────────

ASSETS_DIR = Path(__file__).parent.parent / "assets" / "images"

TARGET_SIZE = 800       # 輸出邊長（px）
CHAR_HEIGHT_RATIO = 0.78  # 人物高度 = 畫布的 78%
CHAR_TOP_RATIO = 0.07     # 人物頂端距上緣 7%
CHAR_MAX_W_RATIO = 0.88   # 人物寬度上限（防寬型角色溢出）

ALPHA_THRESHOLD = 8     # alpha > 此值視為人物像素（透明背景圖）
WHITE_THRESHOLD = 240   # R/G/B < 此值視為人物像素（白底縮圖）

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


def _find_content_bbox(arr: np.ndarray, mode: str) -> tuple[int, int, int, int] | None:
    """回傳 (left, top, right, bottom) 人物 bounding box；找不到時回傳 None。"""
    if mode == "transparent":
        alpha = arr[:, :, 3]
        mask = alpha > ALPHA_THRESHOLD
    else:  # white_bg
        r, g, b = arr[:, :, 0], arr[:, :, 1], arr[:, :, 2]
        mask = (r < WHITE_THRESHOLD) | (g < WHITE_THRESHOLD) | (b < WHITE_THRESHOLD)

    rows = np.any(mask, axis=1)
    cols = np.any(mask, axis=0)
    if not rows.any():
        return None

    rmin, rmax = int(np.where(rows)[0][0]), int(np.where(rows)[0][-1])
    cmin, cmax = int(np.where(cols)[0][0]), int(np.where(cols)[0][-1])
    return cmin, rmin, cmax + 1, rmax + 1


def _build_normalized(img: Image.Image, bbox: tuple[int, int, int, int],
                       bg_color: tuple) -> Image.Image:
    """裁切人物、縮放至目標構圖、貼到新畫布上。"""
    char = img.crop(bbox)
    char_w, char_h = char.size

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

    canvas = Image.new("RGBA", (target, target), bg_color)
    paste_x = (target - target_char_w) // 2
    paste_y = int(target * CHAR_TOP_RATIO)

    if bg_color[3] == 0:
        # 透明背景：需要 alpha mask
        canvas.paste(char_resized, (paste_x, paste_y), char_resized)
    else:
        # 白底：直接貼
        canvas.paste(char_resized, (paste_x, paste_y))

    return canvas


def normalize_transparent(img_path: Path | str, dry_run: bool = False) -> bool:
    """
    正規化透明背景 preview 圖（alpha=0 背景）。
    Returns True 表示成功處理，False 表示找不到人物或失敗。
    """
    img_path = Path(img_path)
    try:
        img = Image.open(img_path).convert("RGBA")
    except Exception as e:
        print(f"  ⚠️  無法開啟 {img_path.name}: {e}")
        return False

    arr = np.array(img)
    bbox = _find_content_bbox(arr, "transparent")
    if bbox is None:
        print(f"  ⚠️  {img_path.name}: 找不到人物（全透明？）")
        return False

    result = _build_normalized(img, bbox, (0, 0, 0, 0))

    if not dry_run:
        result.save(str(img_path), "PNG")
    return True


def normalize_white_bg(img_path: Path | str, dry_run: bool = False) -> bool:
    """
    正規化白底縮圖（background #FFFFFF）。
    Returns True 表示成功處理，False 表示找不到人物或失敗。
    """
    img_path = Path(img_path)
    try:
        img = Image.open(img_path).convert("RGBA")
    except Exception as e:
        print(f"  ⚠️  無法開啟 {img_path.name}: {e}")
        return False

    arr = np.array(img)
    bbox = _find_content_bbox(arr, "white_bg")
    if bbox is None:
        print(f"  ⚠️  {img_path.name}: 找不到人物（全白？）")
        return False

    result = _build_normalized(img, bbox, (255, 255, 255, 255))
    # 轉回 RGB 儲存（白底縮圖不需要 alpha channel）
    result_rgb = result.convert("RGB")

    if not dry_run:
        result_rgb.save(str(img_path), "PNG")
    return True


# ── CLI ───────────────────────────────────────────────────────────────────────


def _collect_targets(args: argparse.Namespace) -> list[tuple[Path, str]]:
    """回傳 [(path, mode), ...] 的清單，mode = 'transparent' | 'white_bg'。"""
    targets: list[tuple[Path, str]] = []

    if args.all or args.thumbnails:
        # 9 張白底縮圖：preview_{style}_greeting.png
        for style in ALL_STYLES:
            p = ASSETS_DIR / f"preview_{style}_greeting.png"
            if p.exists():
                targets.append((p, "white_bg"))

    if args.all or args.styles or args.emotions:
        styles = args.styles if args.styles else ALL_STYLES
        emotions = args.emotions if args.emotions else ALL_EMOTIONS
        for style in styles:
            for emotion in emotions:
                p = ASSETS_DIR / f"preview_{style}_{emotion}.png"
                if p.exists():
                    # greeting 是白底縮圖，但這裡處理的是透明版本
                    # 確認是否真的是透明背景（由副檔名無法判斷，用 alpha 嘗試）
                    targets.append((p, "auto"))

    # 去重
    seen = set()
    unique: list[tuple[Path, str]] = []
    for path, mode in targets:
        if path not in seen:
            seen.add(path)
            unique.append((path, mode))

    return unique


def _detect_mode(img_path: Path) -> str:
    """自動判斷圖片是透明背景還是白底。"""
    try:
        img = Image.open(img_path).convert("RGBA")
        arr = np.array(img)
        alpha = arr[:, :, 3]
        # 如果 alpha channel 有任何真正透明的像素（< 128），視為透明背景
        if (alpha < 128).any():
            return "transparent"
        return "white_bg"
    except Exception:
        return "transparent"


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

    # 若未指定任何選項，顯示說明
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
    for path, mode in targets:
        if mode == "auto":
            mode = _detect_mode(path)

        prefix = "  [skip]" if args.dry_run else "  "
        print(f"{prefix}{path.name} ({mode})", end="")

        if args.dry_run:
            print()
            ok += 1
            continue

        if mode == "transparent":
            success = normalize_transparent(path, dry_run=False)
        else:
            success = normalize_white_bg(path, dry_run=False)

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
