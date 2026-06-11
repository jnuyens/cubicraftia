"""
Crop 6 time/weather indicator icons from user image 46 (1536x1024).

Layout: 3 cols x 2 rows on white background.
  Row 1: time_sun,       time_dawn_dusk,    time_moon
  Row 2: weather_rain,   weather_snow,      weather_thunder

Output: assets/textures/icons/weather/<name>.png  (256x256 alpha)
"""

import os, sys
from PIL import Image

SRC = "/Users/jnuyens/.claude/image-cache/35f4cc08-1547-48d0-ac89-2efcf33a7f6f/46.png"
OUT_DIR = "/Users/jnuyens/src/Cubicraftia/assets/textures/icons/weather"

ITEMS = [
    # Row 1 (y ~ 20..500)
    ("time_sun",        (40,   20,  520,  500)),
    ("time_dawn_dusk",  (530,  20,  1010, 500)),
    ("time_moon",       (1020, 20,  1500, 500)),
    # Row 2 (y ~ 520..1010)
    ("weather_rain",    (40,   520, 520,  1010)),
    ("weather_snow",    (530,  520, 1010, 1010)),
    ("weather_thunder", (1020, 520, 1500, 1010)),
]


def crop_alpha(src_img, bbox, out_size=256, tolerance=8):
    sub = src_img.crop(bbox).convert("RGBA")
    data = sub.getdata()
    new_data = []
    for r, g, b, a in data:
        if r >= 255 - tolerance and g >= 255 - tolerance and b >= 255 - tolerance:
            new_data.append((255, 255, 255, 0))
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
            "Cropped from user-provided time/weather sheet (image 46) by scripts/triposr/crop_weather_icons.py\n"
        )


def main():
    if not os.path.exists(SRC):
        sys.exit(f"missing {SRC}")
    os.makedirs(OUT_DIR, exist_ok=True)
    src = Image.open(SRC)
    print(f"opened {SRC} -> {src.size}")
    for name, bbox in ITEMS:
        out = os.path.join(OUT_DIR, f"{name}.png")
        crop_alpha(src, bbox).save(out, optimize=True)
        write_license(out)
        print(f"  ok {name:18s} {bbox} -> {out}")
    print(f"\nDone -- {len(ITEMS)} time/weather icons written.")


if __name__ == "__main__":
    main()
