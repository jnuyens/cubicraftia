"""
Crop the 8 fence + path items from user reference image 20 (1402x1122).

Row 1 (3): fence_straight_wood, fence_corner_wood, fence_gate_wood
Row 2 (2): fence_stone, fence_iron_bar
Row 3 (3): path_stone_straight, path_stone_corner, archway_stone

Usage:
    python3 scripts/triposr/crop_fences.py
"""

import os, sys
from PIL import Image

SRC = "/Users/jnuyens/.claude/image-cache/35f4cc08-1547-48d0-ac89-2efcf33a7f6f/20.png"
OUT_DIR = "/tmp/cubicraftia_creature_crops"

# Source: 1402x1122. 3 rows.
ITEMS = [
    # Row 1 — 3 wood fences (y ≈ 20..330)
    ("fence_straight_wood", (30,   20,  450, 330)),
    ("fence_corner_wood",   (460,  20,  920, 330)),
    ("fence_gate_wood",     (930,  20,  1380, 330)),

    # Row 2 — 2 fences (y ≈ 380..690), wider slots since only 2 items
    ("fence_stone",         (50,   380, 670, 690)),
    ("fence_iron_bar",      (680,  380, 1330, 690)),

    # Row 3 — 3 paths/archway (y ≈ 720..1050)
    ("path_stone_straight", (40,   720, 460, 1050)),
    ("path_stone_corner",   (470,  720, 920, 1050)),
    ("archway_stone",       (930,  720, 1380, 1050)),
]


def crop_with_white_padding(src_img, bbox, out_size=512):
    sub = src_img.crop(bbox).convert("RGB")
    sw, sh = sub.size
    target = out_size - 40
    scale = min(target / sw, target / sh)
    new_w = max(1, int(sw * scale))
    new_h = max(1, int(sh * scale))
    sub = sub.resize((new_w, new_h), Image.LANCZOS)
    canvas = Image.new("RGB", (out_size, out_size), (255, 255, 255))
    x = (out_size - new_w) // 2
    y = (out_size - new_h) // 2
    canvas.paste(sub, (x, y))
    return canvas


def main():
    if not os.path.exists(SRC):
        sys.exit(f"missing source: {SRC}")
    os.makedirs(OUT_DIR, exist_ok=True)
    src = Image.open(SRC)
    print(f"opened {SRC} → {src.size}\n")
    for name, bbox in ITEMS:
        out = os.path.join(OUT_DIR, f"{name}.png")
        crop_with_white_padding(src, bbox).save(out, optimize=True)
        print(f"  ✓ {name:24s} {bbox} → {out}")
    print(f"\nDone — {len(ITEMS)} fence/path crops written.")


if __name__ == "__main__":
    main()
