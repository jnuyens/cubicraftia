"""
Crop the 45 avatar variants from three numbered hero sheets (images 31, 32, 33).

Replaces the earlier crop_avatars.py which used image 12 with too-tight
bboxes. These three sheets give one figure per cell on a clean white
background with the numbered label below — perfect for TripoSR.

Image 33 (1536x1024) — 1..15: savannah (6) + snow (4) + desert (5)
Image 32 (1536x1024) — 16..30: beach (5) + jungle (5) + ocean (5)
Image 31 (1536x1024) — 31..45: underwater (5) + fantasy (5) + hostile (5)

Output: /tmp/cubicraftia_creature_crops/<name>.png (overwrites earlier v1).

Usage:
    python3 scripts/triposr/crop_avatars_v2.py
"""

import os, sys
from PIL import Image

CACHE = "/Users/jnuyens/.claude/image-cache/35f4cc08-1547-48d0-ac89-2efcf33a7f6f"
OUT_DIR = "/tmp/cubicraftia_creature_crops"

SHEETS = {
    "33.png": [
        # Row 1 — 6 SAVANNAH (y ≈ 20..330, ~256px per slot)
        ("savannah_safari_male",     (10,   20,  260, 330)),
        ("savannah_safari_female",   (270,  20,  520, 330)),
        ("savannah_tribal_male",     (530,  20,  780, 330)),
        ("savannah_tribal_female",   (790,  20,  1030, 330)),
        ("savannah_photographer",    (1040, 20,  1280, 330)),
        ("savannah_ranger",          (1290, 20,  1530, 330)),

        # Row 2 — 4 SNOW (y ≈ 350..670, ~384px per slot)
        ("snow_explorer_male",       (10,   350, 400, 670)),
        ("snow_explorer_female",     (400,  350, 800, 670)),
        ("snow_skier",               (800,  350, 1180, 670)),
        ("snow_fisherman",           (1180, 350, 1530, 670)),

        # Row 3 — 5 DESERT (y ≈ 700..990, ~306px per slot)
        ("desert_bedouin",           (10,   700, 320, 990)),
        ("desert_princess",          (320,  700, 620, 990)),
        ("desert_turban_guard",      (620,  700, 920, 990)),
        ("desert_ranger",            (920,  700, 1220, 990)),
        ("desert_wizard",            (1220, 700, 1530, 990)),
    ],
    "32.png": [
        # Row 1 — 5 BEACH (y ≈ 20..320)
        ("beach_surfer",             (10,   20,  320, 320)),
        ("beach_woman",              (320,  20,  620, 320)),
        ("beach_lifeguard",          (620,  20,  920, 320)),
        ("beach_photographer",       (920,  20,  1230, 320)),
        ("beach_sailor",             (1230, 20,  1530, 320)),

        # Row 2 — 5 JUNGLE (y ≈ 350..670)
        ("jungle_hunter",            (10,   350, 320, 670)),
        ("jungle_ranger_female",     (320,  350, 620, 670)),
        ("jungle_tribal_chief",      (620,  350, 920, 670)),
        ("jungle_botanist",          (920,  350, 1230, 670)),
        ("jungle_adventurer",        (1230, 350, 1530, 670)),

        # Row 3 — 5 OCEAN (y ≈ 700..990)
        ("ocean_captain",            (10,   700, 320, 990)),
        ("ocean_pirate",             (320,  700, 620, 990)),
        ("ocean_sailor",             (620,  700, 920, 990)),
        ("ocean_old_diver",          (920,  700, 1230, 990)),
        ("ocean_lighthouse_keeper",  (1230, 700, 1530, 990)),
    ],
    "31.png": [
        # Row 1 — 5 UNDERWATER (y ≈ 20..320)
        ("underwater_modern_diver",  (10,   20,  320, 320)),
        ("underwater_scuba_diver",   (320,  20,  620, 320)),
        ("underwater_marine_biologist",(620, 20, 920, 320)),
        ("underwater_mermaid",       (920,  20,  1230, 320)),
        ("underwater_neptune",       (1230, 20,  1530, 320)),

        # Row 2 — 5 FANTASY (y ≈ 350..670)
        ("fantasy_wizard",           (10,   350, 320, 670)),
        ("fantasy_knight",           (320,  350, 620, 670)),
        ("fantasy_elf_archer",       (620,  350, 920, 670)),
        ("fantasy_dwarf_warrior",    (920,  350, 1230, 670)),
        ("fantasy_robot",            (1230, 350, 1530, 670)),

        # Row 3 — 5 HOSTILE (y ≈ 700..990)
        ("hostile_zombie",           (10,   700, 320, 990)),
        ("hostile_skeleton",         (320,  700, 620, 990)),
        ("hostile_goblin",           (620,  700, 920, 990)),
        ("hostile_orc",              (920,  700, 1230, 990)),
        ("hostile_vampire",          (1230, 700, 1530, 990)),
    ],
}


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


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    total = 0
    for sheet, items in SHEETS.items():
        src_path = os.path.join(CACHE, sheet)
        if not os.path.exists(src_path):
            print(f"  ✗ MISSING sheet {src_path}")
            continue
        src = Image.open(src_path)
        print(f"\n{sheet} → {src.size}\n")
        for name, bbox in items:
            out = os.path.join(OUT_DIR, f"{name}.png")
            crop_with_white_padding(src, bbox).save(out, optimize=True)
            print(f"  ✓ {name:32s} {bbox} → {out}")
            total += 1
    print(f"\nDone — {total} avatar crops (replaces image-12-based v1).")


if __name__ == "__main__":
    main()
