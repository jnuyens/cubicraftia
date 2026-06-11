"""
Crop 12 loading-screen hint vignettes from user image 50 (2000x1126).

Layout: 4 cols x 3 rows of cinematic painterly 16:9 panels.
  Row 1: digging,  crafting, sailing,  taming
  Row 2: sleeping, mining,   planting, fishing
  Row 3: building, trading,  falling,  swimming

Each saved as a 1920x1080 JPG (quality 88) -- PNG would balloon to ~60MB
total whereas JPG keeps the whole set under ~6MB while still being
visually indistinguishable for a fullscreen loading background.

Output: assets/textures/loading/hint_<name>.jpg
"""

import os, sys
from PIL import Image

SRC = "/Users/jnuyens/.claude/image-cache/35f4cc08-1547-48d0-ac89-2efcf33a7f6f/50.jpeg"
OUT_DIR = "/Users/jnuyens/src/Cubicraftia/assets/textures/loading"

NAMES = [
    "digging",  "crafting", "sailing",  "taming",
    "sleeping", "mining",   "planting", "fishing",
    "building", "trading",  "falling",  "swimming",
]

COLS, ROWS = 4, 3
OUT_W, OUT_H = 1920, 1080


def crop_panel(src_img, bbox):
    sub = src_img.crop(bbox).convert("RGB")
    sw, sh = sub.size
    src_ar = sw / sh
    tgt_ar = OUT_W / OUT_H
    if src_ar > tgt_ar:
        new_w = int(sh * tgt_ar)
        x = (sw - new_w) // 2
        sub = sub.crop((x, 0, x + new_w, sh))
    else:
        new_h = int(sw / tgt_ar)
        y = (sh - new_h) // 2
        sub = sub.crop((0, y, sw, y + new_h))
    return sub.resize((OUT_W, OUT_H), Image.LANCZOS)


def write_license(p):
    with open(p + ".license", "w") as fh:
        fh.write(
            "SPDX-FileCopyrightText: 2026 Cubicraftia contributors\n"
            "SPDX-License-Identifier: GPL-3.0-or-later\n"
            "Cropped from user-provided loading-hint sheet (image 50) by scripts/triposr/crop_loading_hints.py\n"
        )


def main():
    if not os.path.exists(SRC):
        sys.exit(f"missing {SRC}")
    os.makedirs(OUT_DIR, exist_ok=True)
    src = Image.open(SRC)
    W, H = src.size
    print(f"opened {SRC} -> {W}x{H}")
    cw, ch = W / COLS, H / ROWS
    margin = 4
    for i, name in enumerate(NAMES):
        r, c = divmod(i, COLS)
        x1 = int(c * cw) + margin
        y1 = int(r * ch) + margin
        x2 = int((c + 1) * cw) - margin
        y2 = int((r + 1) * ch) - margin
        out = os.path.join(OUT_DIR, f"hint_{name}.jpg")
        crop_panel(src, (x1, y1, x2, y2)).save(out, quality=88, optimize=True)
        write_license(out)
        print(f"  ok hint_{name:9s} ({x1},{y1})-({x2},{y2})")
    print(f"\nDone -- {len(NAMES)} loading hints written.")


if __name__ == "__main__":
    main()
