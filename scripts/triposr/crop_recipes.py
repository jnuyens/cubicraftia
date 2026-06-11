"""
Crop 30 crafting recipe diagrams from user image 37 (1774x887).

Layout: 5 columns x 6 rows. Each cell contains a recipe card with
white background showing inputs -> arrow -> output.

Output: assets/textures/crafting/recipes/recipe_<name>.png
Each saved with white-to-alpha cutout so the card can sit on any
inventory background.
"""

import os, sys
from PIL import Image

SRC = "/Users/jnuyens/.claude/image-cache/35f4cc08-1547-48d0-ac89-2efcf33a7f6f/37.png"
OUT_DIR = "/Users/jnuyens/src/Cubicraftia/assets/textures/crafting/recipes"

NAMES = [
    # Row 1 — workstations + first tools
    "crafting_table", "furnace",     "bucket",         "torch",          "sword_diamond",
    # Row 2 — pickaxes (wood/stone/iron/diamond/gold)
    "pickaxe_wood",   "pickaxe_stone", "pickaxe_iron",  "pickaxe_diamond","pickaxe_gold",
    # Row 3 — shovels
    "shovel_wood",    "shovel_stone",  "shovel_iron",   "shovel_diamond", "shovel_gold",
    # Row 4 — block conversions
    "stick",          "stone_block",   "glass_block",   "wood_plank_block","bread",
    # Row 5 — misc + armour
    "sugar",          "chestplate_leather","chestplate_iron","helmet_diamond","helmet_gold",
    # Row 6 — utility
    "campfire",       "coal_block",    "bow",            "flint_and_steel","nether_portal",
]

COLS, ROWS = 5, 6


def crop_with_alpha(src_img, bbox, out_w=1024, out_h=512, tolerance=14):
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
    target_w, target_h = out_w - 32, out_h - 32
    scale = min(target_w / sw, target_h / sh)
    nw, nh = max(1, int(sw * scale)), max(1, int(sh * scale))
    sub = sub.resize((nw, nh), Image.LANCZOS)
    canvas = Image.new("RGBA", (out_w, out_h), (0, 0, 0, 0))
    canvas.paste(sub, ((out_w - nw) // 2, (out_h - nh) // 2), sub)
    return canvas


def write_license(p):
    with open(p + ".license", "w") as fh:
        fh.write(
            "SPDX-FileCopyrightText: 2026 Cubicraftia contributors\n"
            "SPDX-License-Identifier: GPL-3.0-or-later\n"
            "Cropped from user-provided crafting recipe sheet (image 37) by scripts/triposr/crop_recipes.py\n"
        )


def main():
    if not os.path.exists(SRC):
        sys.exit(f"missing {SRC}")
    os.makedirs(OUT_DIR, exist_ok=True)
    src = Image.open(SRC)
    W, H = src.size
    print(f"opened {SRC} -> {W}x{H}")
    cw, ch = W / COLS, H / ROWS
    margin_x, margin_y = 8, 6
    for i, name in enumerate(NAMES):
        r, c = divmod(i, COLS)
        x1 = int(c * cw) + margin_x
        y1 = int(r * ch) + margin_y
        x2 = int((c + 1) * cw) - margin_x
        y2 = int((r + 1) * ch) - margin_y
        out = os.path.join(OUT_DIR, f"recipe_{name}.png")
        crop_with_alpha(src, (x1, y1, x2, y2)).save(out, optimize=True)
        write_license(out)
        print(f"  ok recipe_{name:22s} ({x1},{y1})-({x2},{y2}) -> {out}")
    print(f"\nDone -- {len(NAMES)} recipe diagrams written.")


if __name__ == "__main__":
    main()
