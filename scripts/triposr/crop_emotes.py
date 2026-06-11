"""
Crop 8 player emote sprites from user image 43 (1536x1024).

Layout: 4 cols x 2 rows on transparent/black backdrop.
  Row 1: wave,  sit,   dance, point
  Row 2: cheer, shrug, sleep, laugh

Labels at top of each cell are dropped (rendered in-engine via tr()).

Output: assets/textures/icons/emotes/emote_<name>.png  (256x256 alpha)
"""

import os, sys
from PIL import Image

SRC = "/Users/jnuyens/.claude/image-cache/35f4cc08-1547-48d0-ac89-2efcf33a7f6f/43.png"
OUT_DIR = "/Users/jnuyens/src/Cubicraftia/assets/textures/icons/emotes"

# y starts at ~60 (below label), each cell ~384 wide
ITEMS = [
    ("wave",  (10,   60,  384, 510)),
    ("sit",   (390,  60,  768, 510)),
    ("dance", (775,  60,  1150,510)),
    ("point", (1155, 60,  1530,510)),
    ("cheer", (10,   570, 384, 1014)),
    ("shrug", (390,  570, 768, 1014)),
    ("sleep", (775,  570, 1150,1014)),
    ("laugh", (1155, 570, 1530,1014)),
]


def crop_alpha(src_img, bbox, out_size=256, tolerance=10):
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
            "Cropped from user-provided emote sheet (image 43) by scripts/triposr/crop_emotes.py\n"
        )


def main():
    if not os.path.exists(SRC):
        sys.exit(f"missing {SRC}")
    os.makedirs(OUT_DIR, exist_ok=True)
    src = Image.open(SRC)
    print(f"opened {SRC} -> {src.size}")
    for name, bbox in ITEMS:
        out = os.path.join(OUT_DIR, f"emote_{name}.png")
        crop_alpha(src, bbox).save(out, optimize=True)
        write_license(out)
        print(f"  ok emote_{name:6s} {bbox} -> {out}")
    print(f"\nDone -- {len(ITEMS)} emote sprites written.")


if __name__ == "__main__":
    main()
