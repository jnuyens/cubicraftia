"""
Crop the 9 savannah wildlife from user reference image 22 (1536x1024).

Row 1 (4): lion_male, lioness, cheetah, zebra
Row 2 (4): hippo, rhino, warthog, vulture
Row 3 (1): giraffe (centred — overrides the v1 silhouette-derived giraffe)

Usage:
    python3 scripts/triposr/crop_savannah.py
"""

import os, sys
from PIL import Image

SRC = "/Users/jnuyens/.claude/image-cache/35f4cc08-1547-48d0-ac89-2efcf33a7f6f/22.png"
OUT_DIR = "/tmp/cubicraftia_creature_crops"

# Source: 1536x1024. 3 rows.
ITEMS = [
    # Row 1 — 4 cats + zebra (y ≈ 30..330)
    ("lion_male",   (10,   30,  400, 330)),
    ("lioness",     (390,  30,  770, 330)),
    ("cheetah",     (760,  30,  1140, 330)),
    ("zebra",       (1130, 30,  1530, 330)),

    # Row 2 — 4 (y ≈ 360..650)
    ("hippo",       (10,   360, 400, 650)),
    ("rhino",       (390,  360, 770, 650)),
    ("warthog",     (760,  360, 1140, 650)),
    ("vulture",     (1190, 350, 1480, 650)),

    # Row 3 — 1 centred (y ≈ 670..980)
    ("giraffe",     (560,  670, 920, 980)),
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
    print(f"\nDone — {len(ITEMS)} savannah wildlife crops written.")


if __name__ == "__main__":
    main()
