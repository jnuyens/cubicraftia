"""
Crop the 9 fantasy creatures from user reference image 34 (1536x1024).

3x3 grid:
  Row 1: dragon_red, dragon_green, dragon_baby
  Row 2: unicorn, phoenix, griffin
  Row 3: fairy, mimic_chest, pegasus

Usage:
    python3 scripts/triposr/crop_fantasy.py
"""

import os, sys
from PIL import Image

SRC = "/Users/jnuyens/.claude/image-cache/35f4cc08-1547-48d0-ac89-2efcf33a7f6f/34.png"
OUT_DIR = "/tmp/cubicraftia_creature_crops"

ITEMS = [
    # Row 1 — 3 dragons (y ≈ 20..330)
    ("dragon_red",    (10,   20,  510, 330)),
    ("dragon_green",  (490,  20,  1030, 330)),
    ("dragon_baby",   (1080, 80,  1430, 330)),

    # Row 2 — 3 mythics (y ≈ 360..640)
    ("unicorn",       (10,   360, 510, 640)),
    ("phoenix",       (490,  340, 1030, 670)),
    ("griffin",       (1030, 360, 1490, 640)),

    # Row 3 — 3 (y ≈ 680..1000)
    ("fairy",         (60,   680, 410, 1000)),
    ("mimic_chest",   (490,  710, 1010, 1000)),
    ("pegasus",       (1010, 680, 1500, 1000)),
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
    print(f"\nDone — {len(ITEMS)} fantasy creature crops written.")


if __name__ == "__main__":
    main()
