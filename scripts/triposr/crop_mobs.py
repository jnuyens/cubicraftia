"""
Crop 9 hostile mobs from user reference image 28 (1536x1024).

3x3 grid:
  Row 1: zombie, skeleton, goblin
  Row 2: orc, wolf_hostile, mummy
  Row 3: evil_wizard, lava_golem, ghoul

Note: zombie/skeleton/goblin/orc overlap names with avatar variants in
image 12 (hostile_*). These mob crops are the canonical mob meshes;
the avatar variants are player-cosmetic-only and get a separate enum
entry in the avatar system. No code collision.

Usage:
    python3 scripts/triposr/crop_mobs.py
"""

import os, sys
from PIL import Image

SRC = "/Users/jnuyens/.claude/image-cache/35f4cc08-1547-48d0-ac89-2efcf33a7f6f/28.png"
OUT_DIR = "/tmp/cubicraftia_creature_crops"

ITEMS = [
    # Row 1 — 3 (y ≈ 20..340)
    ("zombie",       (60,   20,  450, 340)),
    ("skeleton",     (500,  20,  950, 340)),
    ("goblin",       (980,  20,  1430, 340)),

    # Row 2 — 3 (y ≈ 360..640)
    ("orc",          (60,   360, 510, 640)),
    ("wolf_hostile", (500,  360, 950, 640)),
    ("mummy",        (980,  360, 1430, 640)),

    # Row 3 — 3 (y ≈ 670..1000)
    ("evil_wizard",  (60,   670, 510, 1000)),
    ("lava_golem",   (500,  670, 950, 1000)),
    ("ghoul",        (980,  670, 1430, 1000)),
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
    print(f"\nDone — {len(ITEMS)} hostile mob crops written.")


if __name__ == "__main__":
    main()
