"""
Crop the 22 plants + flowers from user reference image 18 (1402x1122).

Row 1 (5 flowers): red_tulip, yellow_daisy, blue_forget_me_not, purple_violet, pink_rose
Row 2 (4 ground): grass_short, grass_tall, bush_small, bush_large
Row 3 (5 trees): oak, pine, palm, jungle_dense, dead
Row 4 (5 trees+cacti): sapling, acacia, palm_coconut, cactus_saguaro, cactus_barrel
Row 5 (3 misc): mushroom_red, mushroom_brown, vine_hanging

Usage:
    python3 scripts/triposr/crop_plants.py
"""

import os, sys
from PIL import Image

SRC = "/Users/jnuyens/.claude/image-cache/35f4cc08-1547-48d0-ac89-2efcf33a7f6f/18.png"
OUT_DIR = "/tmp/cubicraftia_creature_crops"

# Source: 1402x1122. ~5 rows.
ITEMS = [
    # Row 1 — 5 flowers (y ≈ 20..220)
    ("flower_red_tulip",         (40,   20,  300, 220)),
    ("flower_yellow_daisy",      (300,  20,  570, 220)),
    ("flower_blue_forget_me_not",(570,  20,  840, 220)),
    ("flower_purple_violet",     (840,  20,  1100, 220)),
    ("flower_pink_rose",         (1100, 20,  1360, 220)),

    # Row 2 — 4 ground (y ≈ 250..420) — only 4 items, wider slots
    ("grass_tuft_short",         (40,   250, 290, 420)),
    ("grass_tuft_tall",          (290,  240, 560, 430)),
    ("bush_small_green",         (560,  260, 820, 420)),
    ("bush_large_green",         (820,  240, 1130, 430)),

    # Row 3 — 5 trees (y ≈ 460..710)
    ("tree_oak",                 (40,   460, 290, 710)),
    ("tree_pine",                (290,  450, 560, 710)),
    ("tree_palm",                (560,  470, 830, 710)),
    ("tree_jungle_dense",        (830,  460, 1140, 720)),
    ("tree_dead",                (1140, 450, 1390, 720)),

    # Row 4 — 5 trees+cacti (y ≈ 750..1000)
    ("tree_sapling",             (40,   750, 290, 1000)),
    ("acacia_tree",              (290,  740, 580, 1000)),
    ("palm_coconut",             (580,  750, 840, 1000)),
    ("cactus_saguaro",           (840,  750, 1130, 1010)),
    ("cactus_barrel",            (1130, 770, 1390, 1010)),

    # Row 5 — 3 misc (y ≈ 1040..1120) — narrower
    ("mushroom_red",             (60,   1020, 270, 1120)),
    ("mushroom_brown",           (300,  1030, 530, 1120)),
    ("vine_hanging",             (560,  1010, 920,  1120)),
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
        print(f"  ✓ {name:28s} {bbox} → {out}")
    print(f"\nDone — {len(ITEMS)} plant crops written.")


if __name__ == "__main__":
    main()
