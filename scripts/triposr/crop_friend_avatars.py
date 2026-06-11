"""
Crop 6 default friend avatars from user image 38 (1536x1024).

3x2 grid of circular portraits with coloured rings:
  Row 1: red, blue, yellow
  Row 2: green, purple, orange

Output: assets/textures/icons/friend_avatar_<colour>.png (alpha, 512x512)
Background black/dark is keyed to transparent so only the ring + portrait remain.
"""

import os, sys
from PIL import Image

SRC = "/Users/jnuyens/.claude/image-cache/35f4cc08-1547-48d0-ac89-2efcf33a7f6f/38.png"
OUT_DIR = "/Users/jnuyens/src/Cubicraftia/assets/textures/icons"

ITEMS = [
    # Row 1 (y ~ 30..490)
    ("red",    (60,   30,  520, 490)),
    ("blue",   (540,  30,  1000, 490)),
    ("yellow", (1020, 30,  1480, 490)),
    # Row 2 (y ~ 510..990)
    ("green",  (60,   510, 520, 990)),
    ("purple", (540,  510, 1000, 990)),
    ("orange", (1020, 510, 1480, 990)),
]


def crop_circular(src_img, bbox, out_size=512, tolerance=18):
    sub = src_img.crop(bbox).convert("RGBA")
    data = sub.getdata()
    new_data = []
    for r, g, b, a in data:
        # key out near-black background
        if r <= tolerance and g <= tolerance and b <= tolerance:
            new_data.append((0, 0, 0, 0))
        else:
            new_data.append((r, g, b, a))
    sub.putdata(new_data)
    bb = sub.getbbox()
    if bb:
        sub = sub.crop(bb)
    sw, sh = sub.size
    target = out_size - 16
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
            "Cropped from user-provided default friend-avatar sheet (image 38)\n"
            "by scripts/triposr/crop_friend_avatars.py\n"
        )


def main():
    if not os.path.exists(SRC):
        sys.exit(f"missing {SRC}")
    os.makedirs(OUT_DIR, exist_ok=True)
    src = Image.open(SRC)
    print(f"opened {SRC} -> {src.size}")
    for colour, bbox in ITEMS:
        out = os.path.join(OUT_DIR, f"friend_avatar_{colour}.png")
        crop_circular(src, bbox).save(out, optimize=True)
        write_license(out)
        print(f"  ok friend_avatar_{colour:7s} {bbox} -> {out}")
    print(f"\nDone -- {len(ITEMS)} friend avatars written.")


if __name__ == "__main__":
    main()
