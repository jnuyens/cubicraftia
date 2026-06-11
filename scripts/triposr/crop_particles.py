"""
Crop the 9 user-provided particle sprites from reference image 13.

Each cropped sprite is exported as a transparent PNG (white background
removed by tolerance threshold), centred + padded to 256x256. These
become Godot ParticleProcessMaterial textures (billboard sprites).

Bounding boxes were measured from the 1536x1024 reference sheet.

Usage:
    python3 scripts/triposr/crop_particles.py
"""

import os
import sys
from PIL import Image

SRC = "/Users/jnuyens/.claude/image-cache/35f4cc08-1547-48d0-ac89-2efcf33a7f6f/13.png"
OUT_DIR = "/Users/jnuyens/src/Cubicraftia/assets/textures/particles"

# (name, bbox in source image — left, top, right, bottom)
# Source image is 1536x1024, particles arranged in 2 rows of 4-5 items each.
PARTICLES = [
    # Top row (4 sprites)
    ("brick_dust",   (40,  140, 320,  430)),
    ("explosion",    (340, 80,  670,  450)),
    ("water_splash", (680, 80,  1020, 460)),
    ("lava_burst",   (1100, 110, 1480, 450)),

    # Bottom row (5 sprites)
    ("sleep_z",      (110,  560, 320,  790)),
    ("rain_cloud",   (340,  530, 600,  830)),
    ("snow_cloud",   (610,  530, 920,  830)),
    ("ghost_wisp",   (960,  570, 1180, 820)),
    ("fire_flame",   (1230, 570, 1450, 820)),
]


def crop_with_alpha(src_img, bbox, out_size=256, tolerance=10):
    """Crop bbox, convert white-ish pixels to transparent, centre on out_size canvas."""
    sub = src_img.crop(bbox).convert("RGBA")
    # White→transparent
    data = sub.getdata()
    new_data = []
    for r, g, b, a in data:
        if r >= 255 - tolerance and g >= 255 - tolerance and b >= 255 - tolerance:
            new_data.append((255, 255, 255, 0))
        else:
            new_data.append((r, g, b, a))
    sub.putdata(new_data)

    # Find tight bounding box of non-transparent content
    bbox_tight = sub.getbbox()
    if bbox_tight:
        sub = sub.crop(bbox_tight)

    # Fit into out_size with 8 px padding
    target = out_size - 16
    sw, sh = sub.size
    scale = min(target / sw, target / sh)
    new_w = max(1, int(sw * scale))
    new_h = max(1, int(sh * scale))
    sub = sub.resize((new_w, new_h), Image.LANCZOS)

    canvas = Image.new("RGBA", (out_size, out_size), (0, 0, 0, 0))
    x = (out_size - new_w) // 2
    y = (out_size - new_h) // 2
    canvas.paste(sub, (x, y), sub)
    return canvas


def write_license(png_path):
    lic = png_path + ".license"
    with open(lic, "w") as fh:
        fh.write(
            "SPDX-FileCopyrightText: 2026 Cubicraftia contributors\n"
            "SPDX-License-Identifier: GPL-3.0-or-later\n"
            "Cropped from user-provided particle sprite sheet (image 13)\n"
            "by scripts/triposr/crop_particles.py.\n"
        )


def main():
    if not os.path.exists(SRC):
        sys.exit(f"missing source image: {SRC}")
    os.makedirs(OUT_DIR, exist_ok=True)
    src_img = Image.open(SRC)
    print(f"opened {SRC} → {src_img.size}\n")
    print(f"Cropping {len(PARTICLES)} particles → {OUT_DIR}\n")
    for name, bbox in PARTICLES:
        out_path = os.path.join(OUT_DIR, f"{name}.png")
        crop = crop_with_alpha(src_img, bbox)
        crop.save(out_path, optimize=True)
        write_license(out_path)
        print(f"  ✓ {name:16s} {bbox} → {out_path}")
    print(f"\nDone — {len(PARTICLES)} particle sprites written.")


if __name__ == "__main__":
    main()
