"""
Crop the 26 structures from user reference image 21 (2000x1333, JPEG).

Row 1 (6): cottage_small/medium/large, castle_tower_single, castle_keep, castle_full
Row 2 (7): windmill, lighthouse, market_stall, well_village, bridge_wood,
           bridge_stone, gate_archway_stone
Row 3 (7): watchtower_wood, tent_canvas, sandcastle, treasure_chest_sunken,
           village_snow, village_desert, village_savannah
Row 4 (6): temple_jungle, temple_underwater, shipwreck_surface,
           shipwreck_submerged, dungeon_underground, mineshaft_corridor

Dual output:
  - /tmp/cubicraftia_creature_crops/<name>.png   → TripoSR input (white pad 512x512)
  - assets/textures/structure_previews/<name>.jpg → loading-screen preview
                                                    (cropped + scaled to 256x144 16:9)

Usage:
    python3 scripts/triposr/crop_structures.py
"""

import os, sys
from PIL import Image

SRC = "/Users/jnuyens/.claude/image-cache/35f4cc08-1547-48d0-ac89-2efcf33a7f6f/21.jpeg"
TRIPOSR_DIR = "/tmp/cubicraftia_creature_crops"
PREVIEW_DIR = "/Users/jnuyens/src/Cubicraftia/assets/textures/structure_previews"

# Source: 2000x1333. ~4 rows.
ITEMS = [
    # Row 1 — 6 cottages + castles (y ≈ 30..280, ~333px wide each)
    ("cottage_small_wood",     (20,   30,  340, 280)),
    ("cottage_medium_wood",    (350,  30,  670, 280)),
    ("cottage_large_stone",    (680,  20,  1000, 290)),
    ("castle_tower_single",    (1010, 30,  1330, 290)),
    ("castle_keep",            (1340, 30,  1660, 290)),
    ("castle_full",            (1670, 30,  1990, 290)),

    # Row 2 — 7 items (y ≈ 350..610, ~285px wide)
    ("windmill",               (20,   350, 305, 610)),
    ("lighthouse",             (305,  350, 580, 610)),
    ("market_stall",           (580,  350, 880, 610)),
    ("well_village",           (880,  350, 1140, 610)),
    ("bridge_wood",            (1140, 350, 1430, 610)),
    ("bridge_stone",           (1430, 350, 1730, 610)),
    ("gate_archway_stone",     (1730, 350, 1990, 610)),

    # Row 3 — 7 items (y ≈ 660..930)
    ("watchtower_wood",        (20,   660, 290, 930)),
    ("tent_canvas",            (290,  660, 580, 930)),
    ("sandcastle",             (580,  660, 870, 930)),
    ("treasure_chest_sunken",  (870,  660, 1150, 930)),
    ("village_snow",           (1150, 660, 1440, 930)),
    ("village_desert",         (1440, 660, 1720, 930)),
    ("village_savannah",       (1720, 660, 1990, 930)),

    # Row 4 — 6 items (y ≈ 980..1280)
    ("temple_jungle",          (20,   980, 340, 1280)),
    ("temple_underwater",      (340,  980, 680, 1280)),
    ("shipwreck_surface",      (680,  980, 1010, 1280)),
    ("shipwreck_submerged",    (1010, 980, 1340, 1280)),
    ("dungeon_underground",    (1340, 980, 1670, 1280)),
    ("mineshaft_corridor",     (1670, 980, 1990, 1280)),
]


def crop_with_white_padding(src_img, bbox, out_size=512):
    sub = src_img.crop(bbox).convert("RGB")
    sw, sh = sub.size
    target = out_size - 40
    scale = min(target / sw, target / sh)
    new_w = max(1, int(sw * scale))
    new_h = max(1, int(sh * scale))
    sub = sub.resize((new_w, new_h), Image.LANCZOS)
    canvas = Image.new("RGB", (out_size, out_size), (255, 255, 255))
    x = (out_size - new_w) // 2
    y = (out_size - new_h) // 2
    canvas.paste(sub, (x, y))
    return canvas


def crop_preview_card(src_img, bbox, out_w=256, out_h=144):
    """16:9 preview card for loading screen / world select."""
    sub = src_img.crop(bbox).convert("RGB")
    sw, sh = sub.size
    # Fit into 16:9 with letterbox if needed
    target_ratio = out_w / out_h
    src_ratio = sw / sh
    if src_ratio > target_ratio:
        # Source is wider — scale to width
        scale = out_w / sw
    else:
        scale = out_h / sh
    new_w = max(1, int(sw * scale))
    new_h = max(1, int(sh * scale))
    sub = sub.resize((new_w, new_h), Image.LANCZOS)
    canvas = Image.new("RGB", (out_w, out_h), (27, 44, 86))  # Cubicraftia navy
    x = (out_w - new_w) // 2
    y = (out_h - new_h) // 2
    canvas.paste(sub, (x, y))
    return canvas


def write_license(path):
    with open(path + ".license", "w") as fh:
        fh.write(
            "SPDX-FileCopyrightText: 2026 Cubicraftia contributors\n"
            "SPDX-License-Identifier: GPL-3.0-or-later\n"
            "Cropped from user-provided structure sheet (image 21)\n"
            "by scripts/triposr/crop_structures.py.\n"
        )


def main():
    if not os.path.exists(SRC):
        sys.exit(f"missing source: {SRC}")
    os.makedirs(TRIPOSR_DIR, exist_ok=True)
    os.makedirs(PREVIEW_DIR, exist_ok=True)
    src = Image.open(SRC)
    print(f"opened {SRC} → {src.size}\n")
    for name, bbox in ITEMS:
        triposr_path = os.path.join(TRIPOSR_DIR, f"{name}.png")
        preview_path = os.path.join(PREVIEW_DIR, f"{name}.jpg")
        crop_with_white_padding(src, bbox).save(triposr_path, optimize=True)
        crop_preview_card(src, bbox).save(preview_path, quality=85, optimize=True)
        write_license(preview_path)
        print(f"  ✓ {name:24s} → triposr + preview")
    print(f"\nDone — {len(ITEMS)} structures × 2 outputs = {len(ITEMS) * 2} files written.")


if __name__ == "__main__":
    main()
