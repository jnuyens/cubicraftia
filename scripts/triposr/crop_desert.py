"""
Crop the 7 desert wildlife from user reference image 24 (1536x1024).

Row 1 (4): camel, fennec_fox, scorpion, desert_snake
Row 2 (3): lizard, meerkat, vulture (overrides savannah vulture)

Usage:
    python3 scripts/triposr/crop_desert.py
"""

import os, sys
from PIL import Image

SRC = "/Users/jnuyens/.claude/image-cache/35f4cc08-1547-48d0-ac89-2efcf33a7f6f/24.png"
OUT_DIR = "/tmp/cubicraftia_creature_crops"

ITEMS = [
    # Row 1 — 4 (y ≈ 20..470)
    ("camel",         (10,   20,  450, 470)),
    ("fennec_fox",    (450,  130, 750, 470)),
    ("scorpion",      (750,  140, 1130, 470)),
    ("desert_snake",  (1130, 220, 1530, 470)),

    # Row 2 — 3 (y ≈ 600..950)
    ("lizard",        (10,   600, 620, 950)),
    ("meerkat",       (700,  570, 1000, 950)),
    ("vulture",       (1090, 540, 1430, 950)),
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
    print(f"\nDone — {len(ITEMS)} desert wildlife crops written.")


if __name__ == "__main__":
    main()
