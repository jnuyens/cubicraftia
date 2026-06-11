"""
Crop title-screen hero set from user reference image 14.

Three crops:
  - title_bg.png       (1536 x ~580) — the brick-world vista (top half)
  - cubicraftia_wordmark.png (~720 x ~400) — designed CUBICRAFTIA logo (bottom-left)
  - title_character.png (~480 x ~520) — hero builder portrait (bottom-right)

The vista is saved opaque (it tiles/panels the title bg shader).
Wordmark + character are saved with transparent backgrounds.

Usage:
    python3 scripts/triposr/crop_hero_set.py
"""

import os
import sys
from PIL import Image

SRC = "/Users/jnuyens/.claude/image-cache/35f4cc08-1547-48d0-ac89-2efcf33a7f6f/14.png"
ICON_DIR = "/Users/jnuyens/src/Cubicraftia/assets/textures/icons"


def write_license(path, note=""):
    with open(path + ".license", "w") as fh:
        fh.write(
            "SPDX-FileCopyrightText: 2026 Cubicraftia contributors\n"
            "SPDX-License-Identifier: GPL-3.0-or-later\n"
            f"Cropped from user-provided hero-set reference (image 14)\n"
            f"by scripts/triposr/crop_hero_set.py.{(' ' + note) if note else ''}\n"
        )


def white_to_alpha(img, tolerance=8):
    img = img.convert("RGBA")
    data = img.getdata()
    new_data = []
    for r, g, b, a in data:
        if r >= 255 - tolerance and g >= 255 - tolerance and b >= 255 - tolerance:
            new_data.append((255, 255, 255, 0))
        else:
            new_data.append((r, g, b, a))
    img.putdata(new_data)
    return img


def main():
    if not os.path.exists(SRC):
        sys.exit(f"missing source: {SRC}")
    src = Image.open(SRC)
    print(f"opened {SRC} → {src.size}\n")
    os.makedirs(ICON_DIR, exist_ok=True)

    # ─── 1. Vista (top half — full width, opaque) ─────────────────────────
    # Top half of 1536x1024 — vista spans ~y=0..580
    vista_box = (0, 0, src.size[0], 580)
    vista = src.crop(vista_box).convert("RGB")
    vista_path = os.path.join(ICON_DIR, "title_bg.png")
    # Save the vista at native resolution (1536x580) — code in title_scene
    # uses STRETCH_TILE / STRETCH_KEEP_ASPECT depending on bg shader path.
    vista.save(vista_path, optimize=True)
    write_license(vista_path, "title vista (top half)")
    print(f"  ✓ title_bg.png            {vista.size}  → {vista_path}")

    # ─── 2. Wordmark (bottom-left) ────────────────────────────────────────
    # Wordmark occupies roughly (0..720, 590..1010)
    wordmark_box = (0, 580, 760, 1015)
    wordmark = src.crop(wordmark_box)
    wordmark = white_to_alpha(wordmark)
    # Tight crop to non-transparent content
    bbox = wordmark.getbbox()
    if bbox:
        wordmark = wordmark.crop(bbox)
    wordmark_path = os.path.join(ICON_DIR, "cubicraftia_wordmark.png")
    wordmark.save(wordmark_path, optimize=True)
    write_license(wordmark_path, "designed CUBICRAFTIA wordmark")
    print(f"  ✓ cubicraftia_wordmark.png {wordmark.size}  → {wordmark_path}")

    # ─── 3. Hero portrait (bottom-right) ─────────────────────────────────
    # Hero crop: right portion of the bottom half, roughly (820..1536, 580..1024)
    hero_box = (810, 580, 1536, 1024)
    hero = src.crop(hero_box)
    hero = white_to_alpha(hero, tolerance=4)   # tighter tolerance — hero has white-ish highlights
    bbox = hero.getbbox()
    if bbox:
        hero = hero.crop(bbox)
    hero_path = os.path.join(ICON_DIR, "title_character.png")
    hero.save(hero_path, optimize=True)
    write_license(hero_path, "hero builder character portrait")
    print(f"  ✓ title_character.png      {hero.size}  → {hero_path}")

    print(f"\nDone — 3 hero assets written.")


if __name__ == "__main__":
    main()
