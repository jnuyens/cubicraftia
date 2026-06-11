"""
Crop the 45 biome-themed avatar variants from user reference image 12 (2000x1333).

Image 12 is a 3×3 grid of biome panels (~666×444 each). Each panel has a
header label, a row of humanoid avatars (top), and a row of wildlife
(bottom — covered by other crop scripts).

This script crops only the AVATAR row from each panel — 45 humanoid
figures total across 9 biomes:

  Savannah (6), Snow (4), Desert (5), Beach (5), Jungle (5),
  Ocean (5), Underwater (5), Fantasy (5), Hostile (5) = 45

Naming: <biome>_<role>. See docs/art-catalogue-full.md §P for full list.

Usage:
    python3 scripts/triposr/crop_avatars.py
"""

import os, sys
from PIL import Image

SRC = "/Users/jnuyens/.claude/image-cache/35f4cc08-1547-48d0-ac89-2efcf33a7f6f/12.png"
OUT_DIR = "/tmp/cubicraftia_creature_crops"

# Source: 2000×1333. Panel grid:
#   Col 1 x: 0..666     Col 2 x: 666..1333    Col 3 x: 1333..2000
#   Row 1 y: 50..400    Row 2 y: 500..850     Row 3 y: 920..1280
# Within each panel, the avatar row occupies roughly the top 60% of panel
# height (skipping label band).

ITEMS = [
    # ─── Row 1, Col 1: SAVANNAH (6 figures across ~666px) ────────────────
    ("savannah_safari_male",     (20,   60,  120, 300)),
    ("savannah_safari_female",   (120,  60,  220, 300)),
    ("savannah_tribal_male",     (220,  60,  340, 300)),
    ("savannah_tribal_female",   (340,  60,  460, 300)),
    ("savannah_photographer",    (460,  60,  570, 300)),
    ("savannah_ranger",          (570,  60,  680, 300)),

    # ─── Row 1, Col 2: SNOW (4 figures across ~666px) ────────────────────
    ("snow_explorer_male",       (700,  60,  860, 300)),
    ("snow_explorer_female",     (860,  60,  1020, 300)),
    ("snow_skier",               (1020, 60,  1170, 300)),
    ("snow_fisherman",           (1170, 60,  1330, 300)),

    # ─── Row 1, Col 3: DESERT (5 figures across ~666px) ──────────────────
    ("desert_bedouin",           (1340, 60,  1470, 300)),
    ("desert_princess",          (1470, 60,  1600, 300)),
    ("desert_turban_guard",      (1600, 60,  1740, 300)),
    ("desert_ranger",            (1740, 60,  1870, 300)),
    ("desert_wizard",            (1870, 60,  2000, 300)),

    # ─── Row 2, Col 1: BEACH (5 figures across ~666px) ───────────────────
    ("beach_surfer",             (10,   500, 150, 750)),
    ("beach_woman",              (150,  500, 280, 750)),
    ("beach_lifeguard",          (280,  500, 410, 750)),
    ("beach_photographer",       (410,  500, 540, 750)),
    ("beach_sailor",             (540,  500, 680, 750)),

    # ─── Row 2, Col 2: JUNGLE (5 figures) ────────────────────────────────
    ("jungle_hunter",            (700,  500, 830, 750)),
    ("jungle_ranger_female",     (830,  500, 970, 750)),
    ("jungle_tribal_chief",      (970,  500, 1100, 750)),
    ("jungle_botanist",          (1100, 500, 1230, 750)),
    ("jungle_adventurer",        (1230, 500, 1340, 750)),

    # ─── Row 2, Col 3: OCEAN (5 figures) ─────────────────────────────────
    ("ocean_captain",            (1340, 500, 1480, 750)),
    ("ocean_pirate",             (1480, 500, 1610, 750)),
    ("ocean_sailor",             (1610, 500, 1740, 750)),
    ("ocean_old_diver",          (1740, 500, 1870, 750)),
    ("ocean_lighthouse_keeper",  (1870, 500, 2000, 750)),

    # ─── Row 3, Col 1: UNDERWATER (5 figures) ────────────────────────────
    ("underwater_modern_diver",  (10,   920, 150, 1180)),
    ("underwater_scuba_diver",   (150,  920, 290, 1180)),
    ("underwater_marine_biologist",(290, 920, 430, 1180)),
    ("underwater_mermaid",       (430,  920, 570, 1180)),
    ("underwater_neptune",       (570,  920, 700, 1180)),

    # ─── Row 3, Col 2: FANTASY (5 figures) ───────────────────────────────
    ("fantasy_wizard",           (700,  920, 840, 1180)),
    ("fantasy_knight",           (840,  920, 980, 1180)),
    ("fantasy_elf_archer",       (980,  920, 1110, 1180)),
    ("fantasy_dwarf_warrior",    (1110, 920, 1230, 1180)),
    ("fantasy_robot",            (1230, 920, 1340, 1180)),

    # ─── Row 3, Col 3: HOSTILE (5 figures) ───────────────────────────────
    ("hostile_zombie",           (1340, 920, 1480, 1180)),
    ("hostile_skeleton",         (1480, 920, 1610, 1180)),
    ("hostile_goblin",           (1610, 920, 1740, 1180)),
    ("hostile_orc",              (1740, 920, 1870, 1180)),
    ("hostile_vampire",          (1870, 920, 2000, 1180)),
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


def main():
    if not os.path.exists(SRC):
        sys.exit(f"missing source: {SRC}")
    os.makedirs(OUT_DIR, exist_ok=True)
    src = Image.open(SRC)
    print(f"opened {SRC} → {src.size}\n")
    for name, bbox in ITEMS:
        out = os.path.join(OUT_DIR, f"{name}.png")
        crop_with_white_padding(src, bbox).save(out, optimize=True)
        print(f"  ✓ {name:32s} {bbox} → {out}")
    print(f"\nDone — {len(ITEMS)} avatar variants cropped.")


if __name__ == "__main__":
    main()
