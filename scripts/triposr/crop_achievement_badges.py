"""
Crop 20 achievement badges from user image 48 (1536x1024).

Layout: 5 cols x 4 rows of hexagonal brick-built medallions on
white background. Each medallion has its English name baked into
the bottom plate.

  Row 1: first_block, first_craft, first_sleep, first_tame, first_trade
  Row 2: first_friend, builder_100, miner_100, explorer_100, fisher_100
  Row 3: farmer_100, sailor_100, dragon_slayer, ocean_master, mountain_climber
  Row 4: biome_collector, structure_finder, treasure_hunter, night_survivor, master_builder

Output: assets/textures/icons/achievements/badge_<name>.png  (512x512 alpha)
"""

import os, sys
from PIL import Image

SRC = "/Users/jnuyens/.claude/image-cache/35f4cc08-1547-48d0-ac89-2efcf33a7f6f/48.png"
OUT_DIR = "/Users/jnuyens/src/Cubicraftia/assets/textures/icons/achievements"

NAMES = [
    "first_block", "first_craft", "first_sleep", "first_tame", "first_trade",
    "first_friend", "builder_100", "miner_100", "explorer_100", "fisher_100",
    "farmer_100", "sailor_100", "dragon_slayer", "ocean_master", "mountain_climber",
    "biome_collector", "structure_finder", "treasure_hunter", "night_survivor", "master_builder",
]

COLS, ROWS = 5, 4


def crop_alpha(src_img, bbox, out_size=512, tolerance=8):
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
            "Cropped from user-provided achievement-badge sheet (image 48) by scripts/triposr/crop_achievement_badges.py\n"
        )


def main():
    if not os.path.exists(SRC):
        sys.exit(f"missing {SRC}")
    os.makedirs(OUT_DIR, exist_ok=True)
    src = Image.open(SRC)
    W, H = src.size
    print(f"opened {SRC} -> {W}x{H}")
    cw, ch = W / COLS, H / ROWS
    margin = 6
    for i, name in enumerate(NAMES):
        r, c = divmod(i, COLS)
        x1 = int(c * cw) + margin
        y1 = int(r * ch) + margin
        x2 = int((c + 1) * cw) - margin
        y2 = int((r + 1) * ch) - margin
        out = os.path.join(OUT_DIR, f"badge_{name}.png")
        crop_alpha(src, (x1, y1, x2, y2)).save(out, optimize=True)
        write_license(out)
        print(f"  ok badge_{name:18s} ({x1},{y1})-({x2},{y2})")
    print(f"\nDone -- {len(NAMES)} achievement badges written.")


if __name__ == "__main__":
    main()
