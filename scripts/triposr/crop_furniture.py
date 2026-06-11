"""
Crop the 29 furniture / decor items from user reference image 17 (2000x1333).

Row 1 (8): bed_single, bed_double, workbench, furnace, crafting_table_advanced,
           lantern_placed_off, lantern_placed_on, torch_placed
Row 2 (8): sign_blank, sign_with_text, painting_small_1..5, flower_pot
Row 3 (8): pot_red/blue/yellow/white/pink_flower, bookshelf, chair_wood, table_wood
Row 4 (5): bonfire, well, barrel, crate, anvil

Usage:
    python3 scripts/triposr/crop_furniture.py
"""

import os, sys
from PIL import Image

SRC = "/Users/jnuyens/.claude/image-cache/35f4cc08-1547-48d0-ac89-2efcf33a7f6f/17.png"
OUT_DIR = "/tmp/cubicraftia_creature_crops"

# Source: 2000x1333. Each grid slot ≈ 250x310 in row 1, similar elsewhere.
# Approximate bboxes — slight padding included; TripoSR + rembg will tighten.

ITEMS = [
    # Row 1 — 8 items (y ≈ 30..330)
    ("bed_single",              (20,   30,  290, 330)),
    ("bed_double",              (290,  30,  580, 330)),
    ("workbench",               (580,  30,  830, 330)),
    ("furnace",                 (830,  30,  1080, 330)),
    ("crafting_table_advanced", (1080, 30,  1330, 330)),
    ("lantern_placed_off",      (1330, 30,  1530, 330)),
    ("lantern_placed_on",       (1530, 30,  1740, 330)),
    ("torch_placed",            (1750, 30,  1980, 330)),

    # Row 2 — 8 items (y ≈ 380..670)
    ("sign_blank",              (20,   380, 270, 670)),
    ("sign_with_text",          (270,  380, 540, 670)),
    ("painting_small_1",        (540,  380, 770, 670)),
    ("painting_small_2",        (770,  380, 990, 670)),
    ("painting_small_3",        (990,  380, 1210, 670)),
    ("painting_small_4",        (1210, 380, 1430, 670)),
    ("painting_small_5",        (1430, 380, 1640, 670)),
    ("flower_pot",              (1750, 380, 1980, 670)),

    # Row 3 — 8 items (y ≈ 720..1010)
    ("pot_red_flower",          (20,   720, 250, 1010)),
    ("pot_blue_flower",         (250,  720, 480, 1010)),
    ("pot_yellow_flower",       (480,  720, 720, 1010)),
    ("pot_white_flower",        (720,  720, 960, 1010)),
    ("pot_pink_flower",         (960,  720, 1200, 1010)),
    ("bookshelf",               (1200, 720, 1490, 1010)),
    ("chair_wood",              (1500, 720, 1740, 1010)),
    ("table_wood",              (1740, 720, 1990, 1010)),

    # Row 4 — 5 items (y ≈ 1060..1320). Layout shifted, fewer items.
    ("bonfire",                 (130,  1060, 470,  1320)),
    ("well",                    (520,  1060, 830,  1320)),
    ("barrel",                  (880,  1060, 1170, 1320)),
    ("crate",                   (1210, 1060, 1500, 1320)),
    ("anvil",                   (1530, 1060, 1830, 1320)),
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
    print(f"\nDone — {len(ITEMS)} furniture crops written.")


if __name__ == "__main__":
    main()
