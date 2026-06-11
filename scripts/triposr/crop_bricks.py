"""
Crop 90 brick-SKU hero renders from user image 44 (1254x1254).

Layout: 10 rows (colours) x 9 cols (sizes), top header row + left label
column to be skipped.

  Colours: red, blue, yellow, green, white, black, grey, tan, brown, orange
  Sizes:   1x1, 1x2, 1x4, 1x8, 2x2, 2x4, 2x8, 4x4, 4x8

Output: assets/textures/bricks/brick_<colour>_<size>.png  (512x512 alpha)
"""

import os, sys
from PIL import Image

SRC = "/Users/jnuyens/.claude/image-cache/35f4cc08-1547-48d0-ac89-2efcf33a7f6f/44.png"
OUT_DIR = "/Users/jnuyens/src/Cubicraftia/assets/textures/bricks"

COLOURS = ["red", "blue", "yellow", "green", "white", "black", "grey", "tan", "brown", "orange"]
SIZES   = ["1x1", "1x2", "1x4", "1x8", "2x2", "2x4", "2x8", "4x4", "4x8"]

# Header / label margins (header ~ y 0..60, label col ~ x 0..100)
HEADER_H = 60
LABEL_W  = 100
TOTAL_W, TOTAL_H = 1254, 1254


def crop_alpha(src_img, bbox, out_size=512, tolerance=8):
    sub = src_img.crop(bbox).convert("RGBA")
    data = sub.getdata()
    new_data = []
    for r, g, b, a in data:
        # key out near-white grid background
        if r >= 255 - tolerance and g >= 255 - tolerance and b >= 255 - tolerance:
            new_data.append((255, 255, 255, 0))
        else:
            new_data.append((r, g, b, a))
    sub.putdata(new_data)
    bb = sub.getbbox()
    if bb:
        sub = sub.crop(bb)
    sw, sh = sub.size
    target = out_size - 24
    scale = min(target / sw, target / sh)
    nw, nh = max(1, int(sw * scale)), max(1, int(sh * scale))
    sub = sub.resize((nw, nh), Image.LANCZOS)
    canvas = Image.new("RGBA", (out_size, out_size), (0, 0, 0, 0))
    canvas.paste(sub, ((out_size - nw) // 2, (out_size - nh) // 2), sub)
    return canvas


def write_license(p):
    with open(p + ".license", "w") as fh:
        fh.write(
            "SPDX-FileCopyrightText: 2026 Cubicraftia contributors\n"
            "SPDX-License-Identifier: GPL-3.0-or-later\n"
            "Cropped from user-provided brick-SKU matrix (image 44) by scripts/triposr/crop_bricks.py\n"
        )


def main():
    if not os.path.exists(SRC):
        sys.exit(f"missing {SRC}")
    os.makedirs(OUT_DIR, exist_ok=True)
    src = Image.open(SRC)
    W, H = src.size
    print(f"opened {SRC} -> {W}x{H}")

    grid_w = W - LABEL_W
    grid_h = H - HEADER_H
    cell_w = grid_w / len(SIZES)
    cell_h = grid_h / len(COLOURS)

    total = 0
    for r, colour in enumerate(COLOURS):
        for c, size in enumerate(SIZES):
            x1 = int(LABEL_W + c * cell_w) + 2
            y1 = int(HEADER_H + r * cell_h) + 2
            x2 = int(LABEL_W + (c + 1) * cell_w) - 2
            y2 = int(HEADER_H + (r + 1) * cell_h) - 2
            out = os.path.join(OUT_DIR, f"brick_{colour}_{size}.png")
            crop_alpha(src, (x1, y1, x2, y2)).save(out, optimize=True)
            write_license(out)
            total += 1
        print(f"  ok {colour:7s} 9 sizes")
    print(f"\nDone -- {total} brick SKUs written.")


if __name__ == "__main__":
    main()
