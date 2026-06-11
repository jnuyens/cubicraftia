"""
Crop the 12 chest + key items from user reference image 15.

Row 1 — 5 chest tiers:
  chest_regular, chest_bronze, chest_silver, chest_gold, chest_diamond
Row 2 — 3 chest variants:
  chest_double_wood, chest_double_bronze, chest_mimic
Row 3 — 4 keys:
  key_bronze, key_silver, key_gold, key_diamond

Each crop saved to /tmp/cubicraftia_creature_crops/ (reuses TripoSR pipeline
crop folder) with white background preserved (TripoSR-friendly).

Usage:
    python3 scripts/triposr/crop_chests.py
"""

import os, sys
from PIL import Image

SRC = "/Users/jnuyens/.claude/image-cache/35f4cc08-1547-48d0-ac89-2efcf33a7f6f/15.png"
OUT_DIR = "/tmp/cubicraftia_creature_crops"

# (name, bbox in source pixels) — source is 1536x1024
ITEMS = [
    # Row 1 — chest tiers (y ~50..280, evenly spaced across full width)
    ("chest_regular",       (30,   30,  300, 290)),
    ("chest_bronze",        (310,  20,  590, 290)),
    ("chest_silver",        (610,  30,  870, 290)),
    ("chest_gold",          (890,  20,  1170, 290)),
    ("chest_diamond",       (1190, 20,  1500, 290)),

    # Row 2 — double + mimic (y ~380..640, 3 wider items)
    ("chest_double_wood",   (40,   370, 540, 630)),
    ("chest_double_bronze", (570,  370, 1080, 630)),
    ("chest_mimic",         (1100, 350, 1500, 640)),

    # Row 3 — 4 keys (y ~700..960, evenly spaced)
    ("key_bronze",          (200,  700, 410, 960)),
    ("key_silver",          (510,  700, 700, 960)),
    ("key_gold",            (810,  700, 1000, 960)),
    ("key_diamond",         (1110, 700, 1330, 960)),
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
    print(f"\nDone — {len(ITEMS)} chest/key crops written.")


if __name__ == "__main__":
    main()
