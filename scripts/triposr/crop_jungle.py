"""
Crop 9 jungle wildlife from user reference image 25 (1536x1024).

Row 1 (3): jaguar, crocodile, gorilla
Row 2 (4): tree_frog_red, tree_frog_blue, parrot_red, parrot_blue
Row 3 (2): snake_green, sloth

Usage:
    python3 scripts/triposr/crop_jungle.py
"""

import os, sys
from PIL import Image

SRC = "/Users/jnuyens/.claude/image-cache/35f4cc08-1547-48d0-ac89-2efcf33a7f6f/25.png"
OUT_DIR = "/tmp/cubicraftia_creature_crops"

ITEMS = [
    # Row 1 — 3 large (y ≈ 20..310)
    ("jaguar",        (10,   20,  500, 310)),
    ("crocodile",     (450,  50,  1000, 310)),
    ("gorilla",       (1000, 20,  1490, 310)),

    # Row 2 — 4 (y ≈ 340..640)
    ("tree_frog_red", (40,   340, 400, 640)),
    ("tree_frog_blue",(400,  340, 760, 640)),
    ("parrot_red",    (760,  340, 1140, 640)),
    ("parrot_blue",   (1140, 340, 1530, 640)),

    # Row 3 — 2 centred (y ≈ 670..980)
    ("snake_green",   (300,  670, 700, 990)),
    ("sloth",         (800,  670, 1280, 990)),
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
    print(f"\nDone — {len(ITEMS)} jungle wildlife crops written.")


if __name__ == "__main__":
    main()
