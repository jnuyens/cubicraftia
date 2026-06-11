"""
Crop the 17 particle sprites from user reference image 29 (1536x1024).

Replaces/extends the first 9 particles from image 13 — most names
overlap (BRICK_DUST, EXPLOSION, SLEEP_Z, etc.) and overwrite the
earlier crops with cleaner versions.

Row 1 (5): brick_dust, wood_chip, stone_shard, explosion, water_drop
Row 2 (5): water_splash_ring, lava_bubble, lantern_glow, mob_death_puff, sleep_z
Row 3 (5): rain_streak, snow_flake, ghost_wisp, vampire_smoke, fire_flame_4f
Row 4 (2): magic_sparkle, heart_pickup

All cropped with white-to-alpha cutout, centred + padded to 256x256.
Output: assets/textures/particles/<name>.png (overwrite where exists).

Usage:
    python3 scripts/triposr/crop_particles_v2.py
"""

import os, sys
from PIL import Image

SRC = "/Users/jnuyens/.claude/image-cache/35f4cc08-1547-48d0-ac89-2efcf33a7f6f/29.png"
OUT_DIR = "/Users/jnuyens/src/Cubicraftia/assets/textures/particles"

# Source: 1536x1024. 4 rows.
ITEMS = [
    # Row 1 — 5 sprites (y ≈ 30..240)
    ("brick_dust",        (40,   30,  290, 240)),
    ("wood_chip",         (340,  30,  570, 240)),
    ("stone_shard",       (620,  30,  840, 240)),
    ("explosion",         (910,  20,  1230, 240)),
    ("water_drop",        (1260, 30,  1480, 250)),

    # Row 2 — 5 sprites (y ≈ 280..510)
    ("water_splash_ring", (10,   280, 290, 510)),
    ("lava_bubble",       (340,  280, 580, 510)),
    ("lantern_glow",      (620,  280, 850, 510)),
    ("mob_death_puff",    (890,  280, 1180, 510)),
    ("sleep_z",           (1230, 280, 1480, 510)),

    # Row 3 — 5 sprites (y ≈ 540..780)
    ("rain_streak",       (10,   540, 290, 780)),
    ("snow_flake",        (340,  540, 600, 780)),
    ("ghost_wisp",        (620,  540, 870, 780)),
    ("vampire_smoke",     (910,  540, 1180, 780)),
    # fire_flame_4f is a 4-frame strip — wider crop, save as one sheet
    ("fire_flame_4f",     (1190, 540, 1500, 780)),

    # Row 4 — 2 sprites (y ≈ 820..960, labels are at y > 970)
    ("magic_sparkle",     (450,  820, 720, 960)),
    ("heart_pickup",      (760,  820, 1000, 960)),
]


def crop_with_alpha(src_img, bbox, out_size=256, tolerance=10):
    sub = src_img.crop(bbox).convert("RGBA")
    data = sub.getdata()
    new_data = []
    for r, g, b, a in data:
        if r >= 255 - tolerance and g >= 255 - tolerance and b >= 255 - tolerance:
            new_data.append((255, 255, 255, 0))
        else:
            new_data.append((r, g, b, a))
    sub.putdata(new_data)
    bbox_tight = sub.getbbox()
    if bbox_tight:
        sub = sub.crop(bbox_tight)
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
    with open(png_path + ".license", "w") as fh:
        fh.write(
            "SPDX-FileCopyrightText: 2026 Cubicraftia contributors\n"
            "SPDX-License-Identifier: GPL-3.0-or-later\n"
            "Cropped from user-provided particle sprite sheet (image 29)\n"
            "by scripts/triposr/crop_particles_v2.py.\n"
        )


def main():
    if not os.path.exists(SRC):
        sys.exit(f"missing source: {SRC}")
    os.makedirs(OUT_DIR, exist_ok=True)
    src = Image.open(SRC)
    print(f"opened {SRC} → {src.size}\n")
    for name, bbox in ITEMS:
        # fire_flame_4f gets a wider canvas to preserve the 4-frame strip
        out_size = 512 if name == "fire_flame_4f" else 256
        out_path = os.path.join(OUT_DIR, f"{name}.png")
        crop_with_alpha(src, bbox, out_size=out_size).save(out_path, optimize=True)
        write_license(out_path)
        print(f"  ✓ {name:24s} {bbox} → {out_path}")
    print(f"\nDone — {len(ITEMS)} particle sprites written.")


if __name__ == "__main__":
    main()
