"""
Crop 3 menu backdrop panoramas from user image 51 (2000x1126).

Three stacked 16:9 vistas of the same hero island in different
lighting:
  Row 1: dawn  (warm pink/gold, low sun rising on right)
  Row 2: dusk  (deep orange/red sunset, sun touching horizon)
  Row 3: night (cool blue, full moon over reflective sea)

Output: assets/textures/sky/menu_backdrop_<time>.jpg  (2048x1152, q88)
"""

import os, sys
from PIL import Image

SRC = "/Users/jnuyens/.claude/image-cache/35f4cc08-1547-48d0-ac89-2efcf33a7f6f/51.png"
OUT_DIR = "/Users/jnuyens/src/Cubicraftia/assets/textures/sky"

NAMES = ["dawn", "dusk", "night"]
OUT_W, OUT_H = 2048, 1152


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
            "Cropped from user-provided menu-backdrop sheet (image 51) by scripts/triposr/crop_menu_backdrops.py\n"
        )


def main():
    if not os.path.exists(SRC):
        sys.exit(f"missing {SRC}")
    os.makedirs(OUT_DIR, exist_ok=True)
    src = Image.open(SRC)
    W, H = src.size
    print(f"opened {SRC} -> {W}x{H}")
    panel_h = H / 3
    for i, name in enumerate(NAMES):
        y1 = int(i * panel_h) + 2
        y2 = int((i + 1) * panel_h) - 2
        out = os.path.join(OUT_DIR, f"menu_backdrop_{name}.jpg")
        crop_panel(src, (0, y1, W, y2)).save(out, quality=88, optimize=True)
        write_license(out)
        print(f"  ok menu_backdrop_{name:5s} (y {y1}..{y2})")
    print(f"\nDone -- {len(NAMES)} menu backdrops written.")


if __name__ == "__main__":
    main()
