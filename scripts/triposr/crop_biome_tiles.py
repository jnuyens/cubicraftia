"""
Crop 8 biome minimap tiles from user image 41 (1359x1158).

Layout: 4 cols x 2 rows. Each cell has a top-down brick-built terrain tile
above a small colour swatch + label (label dropped on crop).

  Row 1: grass_plains, dense_forest, desert, snow
  Row 2: jungle,       savannah,     ocean,  lava_cavern

Output: assets/textures/minimap/biome_<name>.png  (square 512x512 RGB, opaque)
Saved as RGB JPG-quality-safe PNG since these are full opaque map textures.
"""

import os, sys
from PIL import Image

SRC = "/Users/jnuyens/.claude/image-cache/35f4cc08-1547-48d0-ac89-2efcf33a7f6f/41.png"
OUT_DIR = "/Users/jnuyens/src/Cubicraftia/assets/textures/minimap"

# Tile area only (excludes swatch + label below)
ITEMS = [
    # Row 1 (y ~ 5..520)
    ("grass_plains", (10,   5,   335,  520)),
    ("dense_forest", (345,  5,   670,  520)),
    ("desert",       (680,  5,   1005, 520)),
    ("snow",         (1015, 5,   1349, 520)),
    # Row 2 (y ~ 595..1110)
    ("jungle",       (10,   595, 335,  1110)),
    ("savannah",     (345,  595, 670,  1110)),
    ("ocean",        (680,  595, 1005, 1110)),
    ("lava_cavern",  (1015, 595, 1349, 1110)),
]


def crop_square(src_img, bbox, out_size=512):
    sub = src_img.crop(bbox).convert("RGB")
    sw, sh = sub.size
    # centre-crop to a square so tile is undistorted
    side = min(sw, sh)
    x = (sw - side) // 2
    y = (sh - side) // 2
    sub = sub.crop((x, y, x + side, y + side))
    return sub.resize((out_size, out_size), Image.LANCZOS)


def write_license(p):
    with open(p + ".license", "w") as fh:
        fh.write(
            "SPDX-FileCopyrightText: 2026 Cubicraftia contributors\n"
            "SPDX-License-Identifier: GPL-3.0-or-later\n"
            "Cropped from user-provided biome-tile sheet (image 41) by scripts/triposr/crop_biome_tiles.py\n"
        )


def main():
    if not os.path.exists(SRC):
        sys.exit(f"missing {SRC}")
    os.makedirs(OUT_DIR, exist_ok=True)
    src = Image.open(SRC)
    print(f"opened {SRC} -> {src.size}")
    for name, bbox in ITEMS:
        out = os.path.join(OUT_DIR, f"biome_{name}.png")
        crop_square(src, bbox).save(out, optimize=True)
        write_license(out)
        print(f"  ok biome_{name:13s} {bbox} -> {out}")
    print(f"\nDone -- {len(ITEMS)} biome minimap tiles written.")


if __name__ == "__main__":
    main()
