"""
Crop 8 toast / empty-state icons from user image 49 (1024x1024).

Layout: 4 cols x 2 rows on transparent backdrop.
  Row 1: success_check, warning_triangle, error_cross,  info_i
  Row 2: network_offline, save_failed,    empty_inventory, empty_friend_list

Output: assets/textures/icons/state/<name>.png  (256x256 alpha)
"""

import os, sys
from PIL import Image

SRC = "/Users/jnuyens/.claude/image-cache/35f4cc08-1547-48d0-ac89-2efcf33a7f6f/49.png"
OUT_DIR = "/Users/jnuyens/src/Cubicraftia/assets/textures/icons/state"

ITEMS = [
    # Row 1 (y ~ 180..480)
    ("success_check",     (40,   180, 280,  470)),
    ("warning_triangle",  (260,  180, 510,  470)),
    ("error_cross",       (515,  180, 770,  470)),
    ("info_i",            (770,  180, 1020, 470)),
    # Row 2 (y ~ 530..820)
    ("network_offline",   (10,   530, 270,  820)),
    ("save_failed",       (270,  530, 510,  820)),
    ("empty_inventory",   (505,  530, 800,  820)),
    ("empty_friend_list", (775,  530, 1020, 820)),
]


def crop_alpha(src_img, bbox, out_size=256, tolerance=18):
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
            "Cropped from user-provided toast/empty-state sheet (image 49) by scripts/triposr/crop_toasts.py\n"
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
        print(f"  ok {name:20s} {bbox} -> {out}")
    print(f"\nDone -- {len(ITEMS)} toast/empty-state icons written.")


if __name__ == "__main__":
    main()
