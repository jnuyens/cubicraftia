"""
Crop 4 rarity borders from user image 45 (1536x1024).

Layout: 2x2 grid of brick-built frames on transparent backdrop.
  Top-left:     common    (grey stone)
  Top-right:    rare      (blue)         -- label printed 'BARE'
  Bottom-left:  epic      (purple)       -- label printed 'EPIE'
  Bottom-right: legendary (gold/orange)

Each frame has a transparent inner cavity for the item portrait to
show through. The bottom name plate is kept (it is part of the frame
design); locale text can be overlaid in-engine if needed.

Output: assets/textures/icons/rarity/border_<tier>.png  (512x512 alpha)
"""

import os, sys
from PIL import Image

SRC = "/Users/jnuyens/.claude/image-cache/35f4cc08-1547-48d0-ac89-2efcf33a7f6f/45.png"
OUT_DIR = "/Users/jnuyens/src/Cubicraftia/assets/textures/icons/rarity"

ITEMS = [
    ("common",    (10,   10,  760,  500)),
    ("rare",      (770,  10,  1530, 500)),
    ("epic",      (10,   510, 760,  1010)),
    ("legendary", (770,  510, 1530, 1010)),
]


def crop_alpha(src_img, bbox, out_size=512, tolerance=10):
    sub = src_img.crop(bbox).convert("RGBA")
    data = sub.getdata()
    new_data = []
    for r, g, b, a in data:
        if r <= tolerance and g <= tolerance and b <= tolerance:
            new_data.append((0, 0, 0, 0))
        else:
            new_data.append((r, g, b, a))
    sub.putdata(new_data)
    bb = sub.getbbox()
    if bb:
        sub = sub.crop(bb)
    sw, sh = sub.size
    target = out_size - 16
    scale = min(target / sw, target / sh)
    nw, nh = max(1, int(sw * scale)), max(1, int(sh * scale))
    sub = sub.resize((nw, nh), Image.LANCZOS)
    canvas = Image.new("RGBA", (out_size, out_size), (0, 0, 0, 0))
    canvas.paste(sub, ((out_size - nw) // 2, (out_size - nh) // 2), sub)
    return canvas


def write_license(p):
    with open(p + ".license", "w") as fh:
        fh.write(
            "SPDX-FileCopyrightText: 2026 Cubicraftia contributors\n"
            "SPDX-License-Identifier: GPL-3.0-or-later\n"
            "Cropped from user-provided rarity-border sheet (image 45) by scripts/triposr/crop_rarity_borders.py\n"
        )


def main():
    if not os.path.exists(SRC):
        sys.exit(f"missing {SRC}")
    os.makedirs(OUT_DIR, exist_ok=True)
    src = Image.open(SRC)
    print(f"opened {SRC} -> {src.size}")
    for tier, bbox in ITEMS:
        out = os.path.join(OUT_DIR, f"border_{tier}.png")
        crop_alpha(src, bbox).save(out, optimize=True)
        write_license(out)
        print(f"  ok border_{tier:9s} {bbox} -> {out}")
    print(f"\nDone -- {len(ITEMS)} rarity borders written.")


if __name__ == "__main__":
    main()
