"""
Crop the 22 tools from user reference image 16.

Row 1 (9 items): 4 pickaxes + 2 shovels + 3 swords
Row 2 (8 items): dynamite (unlit/lit) + lantern (off/on) + torch + axe + hammer + fishing rod
Row 3 (5 items): compass + map_scroll + 3 buckets (empty/water/lava)

Usage:
    python3 scripts/triposr/crop_tools.py
"""

import os, sys
from PIL import Image

SRC = "/Users/jnuyens/.claude/image-cache/35f4cc08-1547-48d0-ac89-2efcf33a7f6f/16.png"
OUT_DIR = "/tmp/cubicraftia_creature_crops"

# Layout: 1536 wide x 1024 tall
# Row 1: 9 items, ~170px wide each, y ≈ 20..280
# Row 2: 8 items, ~190px wide each, y ≈ 350..620
# Row 3: 5 items, ~290px wide each, y ≈ 650..960

ITEMS = [
    # Row 1 — 9 pickaxes/shovels/swords
    ("pickaxe_wood",       (10,   20,  175, 290)),
    ("pickaxe_bronze",     (175,  20,  345, 290)),
    ("pickaxe_iron",       (345,  20,  515, 290)),
    ("pickaxe_diamond",    (515,  20,  690, 290)),
    ("shovel_wood",        (690,  20,  855, 290)),
    ("shovel_iron",        (855,  20,  1015, 290)),
    ("sword_wood",         (1015, 20,  1180, 290)),
    ("sword_iron",         (1180, 20,  1355, 290)),
    ("sword_diamond",      (1355, 20,  1525, 290)),

    # Row 2 — 8 items
    ("dynamite_unlit",        (10,   340, 200, 630)),
    ("dynamite_lit",          (200,  340, 390, 630)),
    ("lantern_handheld_off",  (390,  340, 600, 630)),
    ("lantern_handheld_on",   (600,  340, 810, 630)),
    ("torch_held",            (810,  340, 990, 630)),
    ("axe_wood",              (990,  340, 1175, 630)),
    ("hammer_wood",           (1175, 340, 1360, 630)),
    ("fishing_rod",           (1360, 340, 1525, 630)),

    # Row 3 — 5 items
    ("compass",     (60,   660, 350,  960)),
    ("map_scroll",  (340,  660, 660,  960)),
    ("bucket_empty",(670,  660, 940,  960)),
    ("bucket_water",(940,  660, 1220, 960)),
    ("bucket_lava", (1230, 660, 1510, 960)),
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
    print(f"\nDone — {len(ITEMS)} tool crops written.")


if __name__ == "__main__":
    main()
