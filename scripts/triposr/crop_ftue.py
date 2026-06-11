"""
Crop 10 FTUE tutorial panels from user image 42 (1448x1086).

Layout: 3 cols x 4 rows, last row has only 1 panel.
  Row 1: 1 builder_lands_on_island, 2 breaks_first_block, 3 opens_inventory
  Row 2: 4 places_block,            5 crafts_a_tool,      6 eats_food
  Row 3: 7 sleeps_through_night,    8 crafts_a_chest,     9 meets_friend
  Row 4: 10 sails_away

Each panel kept with its numbered badge + label bar intact (they are
part of the panel composition and read as a poster). The in-engine
FTUE system overlays a translucent fade + locale string if needed.

Output: assets/textures/ftue/panel_<N>_<name>.png  (1024x576, 16:9)
"""

import os, sys
from PIL import Image

SRC = "/Users/jnuyens/.claude/image-cache/35f4cc08-1547-48d0-ac89-2efcf33a7f6f/42.png"
OUT_DIR = "/Users/jnuyens/src/Cubicraftia/assets/textures/ftue"

# (filename, bbox) -- bboxes hand-tuned around the white gutters
ITEMS = [
    ("01_builder_lands_on_island", (10,   8,   485, 275)),
    ("02_breaks_first_block",      (490,  8,   965, 275)),
    ("03_opens_inventory",         (970,  8,   1448,275)),

    ("04_places_block",            (10,   285, 485, 552)),
    ("05_crafts_a_tool",           (490,  285, 965, 552)),
    ("06_eats_food",               (970,  285, 1448,552)),

    ("07_sleeps_through_night",    (10,   562, 485, 828)),
    ("08_crafts_a_chest",          (490,  562, 965, 828)),
    ("09_meets_friend",            (970,  562, 1448,828)),

    ("10_sails_away",              (10,   838, 720, 1085)),
]


def crop_panel(src_img, bbox, out_w=1024, out_h=576):
    sub = src_img.crop(bbox).convert("RGB")
    sw, sh = sub.size
    src_ar = sw / sh
    tgt_ar = out_w / out_h
    # centre-crop to 16:9 to avoid stretching
    if src_ar > tgt_ar:
        # too wide -- crop sides
        new_w = int(sh * tgt_ar)
        x = (sw - new_w) // 2
        sub = sub.crop((x, 0, x + new_w, sh))
    else:
        # too tall -- crop top/bottom
        new_h = int(sw / tgt_ar)
        y = (sh - new_h) // 2
        sub = sub.crop((0, y, sw, y + new_h))
    return sub.resize((out_w, out_h), Image.LANCZOS)


def write_license(p):
    with open(p + ".license", "w") as fh:
        fh.write(
            "SPDX-FileCopyrightText: 2026 Cubicraftia contributors\n"
            "SPDX-License-Identifier: GPL-3.0-or-later\n"
            "Cropped from user-provided FTUE storyboard (image 42) by scripts/triposr/crop_ftue.py\n"
        )


def main():
    if not os.path.exists(SRC):
        sys.exit(f"missing {SRC}")
    os.makedirs(OUT_DIR, exist_ok=True)
    src = Image.open(SRC)
    print(f"opened {SRC} -> {src.size}")
    for name, bbox in ITEMS:
        out = os.path.join(OUT_DIR, f"panel_{name}.png")
        crop_panel(src, bbox).save(out, optimize=True)
        write_license(out)
        print(f"  ok panel_{name:30s} {bbox} -> {out}")
    print(f"\nDone -- {len(ITEMS)} FTUE panels written.")


if __name__ == "__main__":
    main()
