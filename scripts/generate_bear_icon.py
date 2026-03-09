#!/usr/bin/env python3
"""Generate a pink bear app icon (full-bleed, no white border)."""

from PIL import Image, ImageDraw
import math, os

SIZE = 1024

def draw_bear_icon(size=1024):
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    s = size

    # ── Background: pink/coral solid fill ──────────────────────────
    BG = "#F06292"
    d.rectangle([0, 0, s, s], fill=BG)

    # ── Helper ────────────────────────────────────────────────────
    def ellipse(cx, cy, rx, ry, fill, outline=None, width=0):
        bbox = [cx - rx, cy - ry, cx + rx, cy + ry]
        if outline:
            d.ellipse(bbox, fill=fill, outline=outline, width=width)
        else:
            d.ellipse(bbox, fill=fill)

    # ── Ears (behind head) ────────────────────────────────────────
    ear_r = s * 0.155
    ear_inner_r = s * 0.09
    ear_y = s * 0.32
    ear_lx = s * 0.30
    ear_rx = s * 0.70

    ellipse(ear_lx, ear_y, ear_r, ear_r, "#5D3A1A")   # left outer
    ellipse(ear_rx, ear_y, ear_r, ear_r, "#5D3A1A")   # right outer
    ellipse(ear_lx, ear_y, ear_inner_r, ear_inner_r, "#C1663A")  # left inner
    ellipse(ear_rx, ear_y, ear_inner_r, ear_inner_r, "#C1663A")  # right inner

    # ── Head ──────────────────────────────────────────────────────
    head_cx, head_cy = s * 0.5, s * 0.52
    head_r = s * 0.35
    ellipse(head_cx, head_cy, head_r, head_r, "#7B4A2D")

    # ── Face (lighter muzzle area) ─────────────────────────────────
    face_cx, face_cy = s * 0.5, s * 0.55
    face_rx, face_ry = s * 0.28, s * 0.25
    ellipse(face_cx, face_cy, face_rx, face_ry, "#C17A50")

    # ── Eyes ──────────────────────────────────────────────────────
    eye_y = s * 0.46
    eye_lx = s * 0.40
    eye_rx = s * 0.60
    eye_r = s * 0.055

    ellipse(eye_lx, eye_y, eye_r, eye_r, "#1A0A00")   # left
    ellipse(eye_rx, eye_y, eye_r, eye_r, "#1A0A00")   # right
    # eye shine
    shine_r = eye_r * 0.30
    ellipse(eye_lx - eye_r*0.25, eye_y - eye_r*0.25, shine_r, shine_r, "white")
    ellipse(eye_rx - eye_r*0.25, eye_y - eye_r*0.25, shine_r, shine_r, "white")

    # ── Nose ──────────────────────────────────────────────────────
    nose_cx, nose_cy = s * 0.5, s * 0.565
    nose_rx, nose_ry = s * 0.045, s * 0.030
    ellipse(nose_cx, nose_cy, nose_rx, nose_ry, "#1A0A00")

    # ── Mouth (smile) ─────────────────────────────────────────────
    lw = max(3, int(s * 0.013))
    # Single arc: bottom half of ellipse = smile
    mouth_box = [s*0.385, s*0.575, s*0.615, s*0.660]
    d.arc(mouth_box, start=10, end=170, fill="#1A0A00", width=lw)

    # ── Blush ─────────────────────────────────────────────────────
    blush_r_x, blush_r_y = s * 0.075, s * 0.040
    blush_alpha = 120
    blush_col = (255, 150, 170, blush_alpha)

    for bx in [s*0.295, s*0.705]:
        blush = Image.new("RGBA", (size, size), (0,0,0,0))
        bd = ImageDraw.Draw(blush)
        bd.ellipse([bx - blush_r_x, s*0.555 - blush_r_y,
                    bx + blush_r_x, s*0.555 + blush_r_y], fill=blush_col)
        img = Image.alpha_composite(img, blush)
        d = ImageDraw.Draw(img)

    return img


os.makedirs("assets", exist_ok=True)
icon = draw_bear_icon(SIZE)
icon.save("assets/app_icon.png")
print("✅ assets/app_icon.png saved")
