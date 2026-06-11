"""
Crop 10 locale flag icons from user image 40 (1024x1024).

Layout:
  Row 1 (y ~ 10..290):  EN-US, EN-GB, FR, DE
  Row 2 (y ~ 360..640): ES,   IT,    PT-BR, NL
  Row 3 (y ~ 700..960): JA,   ZH    (centred)

Each crop excludes the printed label below the flag (text is rendered
in-engine per active locale).

Output: assets/textures/icons/flags/flag_<code>.png  (256x256 alpha)
"""

import os, sys
from PIL import Image

SRC = "/Users/jnuyens/.claude/image-cache/35f4cc08-1547-48d0-ac89-2efcf33a7f6f/40.png"
OUT_DIR = "/Users/jnuyens/src/Cubicraftia/assets/textures/icons/flags"

ITEMS = [
    # Row 1 -- cells ~256 wide
    ("en_us", (10,   10,  260, 280)),
    ("en_gb", (260,  10,  510, 280)),
    ("fr",    (510,  10,  760, 280)),
    ("de",    (760,  10,  1014,280)),
    # Row 2
    ("es",    (10,   360, 260, 640)),
    ("it",    (260,  360, 510, 640)),
    ("pt_br", (510,  360, 760, 640)),
    ("nl",    (760,  360, 1014,640)),
    # Row 3 (centred -- 2 cells)
    ("ja",    (260,  700, 510, 960)),
    ("zh",    (510,  700, 760, 960)),
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
            "Cropped from user-provided locale-flag sheet (image 40) by scripts/triposr/crop_flags.py\n"
        )


def main():
    if not os.path.exists(SRC):
        sys.exit(f"missing {SRC}")
    os.makedirs(OUT_DIR, exist_ok=True)
    src = Image.open(SRC)
    print(f"opened {SRC} -> {src.size}")
    for code, bbox in ITEMS:
        out = os.path.join(OUT_DIR, f"flag_{code}.png")
        crop_alpha(src, bbox).save(out, optimize=True)
        write_license(out)
        print(f"  ok flag_{code:6s} {bbox} -> {out}")
    print(f"\nDone -- {len(ITEMS)} locale flags written.")


if __name__ == "__main__":
    main()
