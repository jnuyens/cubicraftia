"""
Crop the 10 snow wildlife from user reference image 23 (1536x1024).

Row 1 (5): polar_bear, husky_dog, snowy_owl, walrus, seal
Row 2 (5): caribou, arctic_fox, snow_rabbit, arctic_wolf, penguin_atmospheric

Usage:
    python3 scripts/triposr/crop_snow.py
"""

import os, sys
from PIL import Image

SRC = "/Users/jnuyens/.claude/image-cache/35f4cc08-1547-48d0-ac89-2efcf33a7f6f/23.png"
OUT_DIR = "/tmp/cubicraftia_creature_crops"

ITEMS = [
    # Row 1 — 5 (y ≈ 20..360, ~307px per slot)
    ("polar_bear",          (10,   20,  320,  360)),
    ("husky_dog",           (320,  20,  620,  360)),
    ("snowy_owl",           (620,  20,  920,  360)),
    ("walrus",              (920,  20,  1230, 360)),
    ("seal",                (1230, 20,  1530, 360)),

    # Row 2 — 5 (y ≈ 420..800)
    ("caribou",             (10,   420, 320,  800)),
    ("arctic_fox",          (320,  420, 620,  800)),
    ("snow_rabbit",         (620,  420, 920,  800)),
    ("arctic_wolf",         (920,  420, 1230, 800)),
    ("penguin_atmospheric", (1230, 420, 1530, 800)),
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
    print(f"\nDone — {len(ITEMS)} snow wildlife crops written.")


if __name__ == "__main__":
    main()
