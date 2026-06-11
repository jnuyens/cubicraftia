"""
Crop 5 map markers from user image 47 (1536x1024).

Single row of 5 pin-shaped brick markers on black backdrop:
  waypoint (yellow flag), player (blue arrow), friend (green ring),
  hostile (red skull), spawn (white house)

Output: assets/textures/icons/map/marker_<name>.png  (256x256 alpha)
"""

import os, sys
from PIL import Image

SRC = "/Users/jnuyens/.claude/image-cache/35f4cc08-1547-48d0-ac89-2efcf33a7f6f/47.png"
OUT_DIR = "/Users/jnuyens/src/Cubicraftia/assets/textures/icons/map"

# 5 cells across 1536px, vertically centred (y ~ 260..760)
ITEMS = [
    ("waypoint", (50,   260, 360,  760)),
    ("player",   (360,  260, 670,  760)),
    ("friend",   (670,  260, 980,  760)),
    ("hostile",  (980,  260, 1280, 760)),
    ("spawn",    (1280, 260, 1530, 760)),
]


def crop_alpha(src_img, bbox, out_size=256, tolerance=14):
    sub = src_img.crop(bbox).convert("RGBA")
    data = sub.getdata()
    new_data = []
    for r, g, b, a in data:
        if r <= tolerance and g <= tolerance and b <= tolerance:
            new_data.append((0, 0, 0, 0))
        else:
            new_data.append((r, g, b, a))
    sub.putdata(new_data)
    bb = sub.getbbox()
    if bb:
        sub = sub.crop(bb)
    sw, sh = sub.size
    target = out_size - 12
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
            "Cropped from user-provided map-marker sheet (image 47) by scripts/triposr/crop_map_markers.py\n"
        )


def main():
    if not os.path.exists(SRC):
        sys.exit(f"missing {SRC}")
    os.makedirs(OUT_DIR, exist_ok=True)
    src = Image.open(SRC)
    print(f"opened {SRC} -> {src.size}")
    for name, bbox in ITEMS:
        out = os.path.join(OUT_DIR, f"marker_{name}.png")
        crop_alpha(src, bbox).save(out, optimize=True)
        write_license(out)
        print(f"  ok marker_{name:8s} {bbox} -> {out}")
    print(f"\nDone -- {len(ITEMS)} map markers written.")


if __name__ == "__main__":
    main()
