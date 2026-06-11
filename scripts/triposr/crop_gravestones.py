"""
Crop 3 gravestone variants from user image 39 (1024x1024).

Single row of 3 brick-built gravestones on a transparent backdrop:
  gravestone_stone   - classic grey stone slab, red flowers at base
  gravestone_mossy   - mossy/overgrown grey stone, candle + bottle
  gravestone_snowcap - snow-capped grey stone, blue flowers

Each gets staged for TripoSR (white-padded RGB at /tmp) AND a
direct-to-game alpha PNG for inventory/death-marker UI.
"""

import os, sys
from PIL import Image

SRC = "/Users/jnuyens/.claude/image-cache/35f4cc08-1547-48d0-ac89-2efcf33a7f6f/39.png"
TRIPOSR_DIR = "/tmp/cubicraftia_creature_crops"
ICON_DIR = "/Users/jnuyens/src/Cubicraftia/assets/textures/icons"

ITEMS = [
    # Slight overlap; image has 3 stones spread across the width
    ("gravestone_stone",   (10,  150, 360,  860)),
    ("gravestone_mossy",   (340, 100, 700,  860)),
    ("gravestone_snowcap", (680, 150, 1020, 860)),
]


def crop_white_padded(src_img, bbox, out_size=512):
    sub = src_img.crop(bbox).convert("RGBA")
    # composite onto white so TripoSR sees opaque RGB
    bg = Image.new("RGBA", sub.size, (255, 255, 255, 255))
    sub = Image.alpha_composite(bg, sub).convert("RGB")
    sw, sh = sub.size
    target = out_size - 40
    scale = min(target / sw, target / sh)
    nw, nh = max(1, int(sw * scale)), max(1, int(sh * scale))
    sub = sub.resize((nw, nh), Image.LANCZOS)
    canvas = Image.new("RGB", (out_size, out_size), (255, 255, 255))
    canvas.paste(sub, ((out_size - nw) // 2, (out_size - nh) // 2))
    return canvas


def crop_alpha(src_img, bbox, out_size=256, tolerance=8):
    """Already alpha PNG — just crop + key out near-black background."""
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
            "Cropped from user-provided gravestone sheet (image 39) by scripts/triposr/crop_gravestones.py\n"
        )


def main():
    if not os.path.exists(SRC):
        sys.exit(f"missing {SRC}")
    os.makedirs(TRIPOSR_DIR, exist_ok=True)
    os.makedirs(ICON_DIR, exist_ok=True)
    src = Image.open(SRC)
    print(f"opened {SRC} -> {src.size}")
    for name, bbox in ITEMS:
        # TripoSR-ready
        tri = os.path.join(TRIPOSR_DIR, f"{name}.png")
        crop_white_padded(src, bbox).save(tri, optimize=True)
        # In-game icon
        ico = os.path.join(ICON_DIR, f"icon_{name}.png")
        crop_alpha(src, bbox).save(ico, optimize=True)
        write_license(ico)
        print(f"  ok {name:22s} -> {tri}  +  {ico}")
    print("\nDone -- 3 gravestones cropped (TripoSR + UI icons).")


if __name__ == "__main__":
    main()
