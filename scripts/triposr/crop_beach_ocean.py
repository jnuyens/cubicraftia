"""
Crop beach (image 26) + ocean/underwater (image 27) wildlife.

Both source images are 1536x1024.

Beach (image 26 — 10 items):
  Row 1: crab_red, crab_hermit, turtle_sea, flamingo
  Row 2: seagull, dolphin, starfish, seashell
  Row 3: beach_umbrella, beach_ball

Ocean+Underwater (image 27 — 11 items):
  Row 1: shark_great_white, whale_blue, whale_sperm, octopus_red
  Row 2: squid, seahorse, pufferfish
  Row 3: coral_pink, coral_green, anemone_purple, kelp_strand

Usage:
    python3 scripts/triposr/crop_beach_ocean.py
"""

import os, sys
from PIL import Image

SRC_BEACH = "/Users/jnuyens/.claude/image-cache/35f4cc08-1547-48d0-ac89-2efcf33a7f6f/26.png"
SRC_OCEAN = "/Users/jnuyens/.claude/image-cache/35f4cc08-1547-48d0-ac89-2efcf33a7f6f/27.png"
OUT_DIR = "/tmp/cubicraftia_creature_crops"

BEACH_ITEMS = [
    # Row 1 — 4 (y ≈ 50..330)
    ("crab_red",       (20,   50,  390, 330)),
    ("crab_hermit",    (390,  50,  770, 330)),
    ("turtle_sea",     (770,  50,  1140, 330)),
    ("flamingo",       (1140, 30,  1490, 330)),

    # Row 2 — 4 (y ≈ 360..650)
    ("seagull",        (40,   360, 320, 650)),
    ("dolphin",        (350,  360, 780, 650)),
    ("starfish",       (790,  370, 1130, 650)),
    ("seashell",       (1140, 380, 1490, 650)),

    # Row 3 — 2 centred (y ≈ 680..980)
    ("beach_umbrella", (430,  680, 760, 990)),
    ("beach_ball",     (760,  680, 1090, 990)),
]

OCEAN_ITEMS = [
    # Row 1 — 4 (y ≈ 30..310)
    ("shark_great_white", (10,   30,  410, 310)),
    ("whale_blue",        (410,  30,  790, 310)),
    ("whale_sperm",       (790,  30,  1170, 310)),
    ("octopus_red",       (1170, 30,  1500, 310)),

    # Row 2 — 3 centred (y ≈ 360..640)
    ("squid",         (100,  360, 470, 640)),
    ("seahorse",      (520,  360, 850, 640)),
    ("pufferfish",    (920,  360, 1300, 640)),

    # Row 3 — 4 (y ≈ 680..990)
    ("coral_pink",    (20,   680, 380, 990)),
    ("coral_green",   (390,  680, 750, 990)),
    ("anemone_purple",(760,  680, 1130, 990)),
    ("kelp_strand",   (1140, 660, 1490, 990)),
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
    os.makedirs(OUT_DIR, exist_ok=True)
    for src, items, label in [(SRC_BEACH, BEACH_ITEMS, "BEACH"), (SRC_OCEAN, OCEAN_ITEMS, "OCEAN/UNDERWATER")]:
        if not os.path.exists(src):
            sys.exit(f"missing source: {src}")
        img = Image.open(src)
        print(f"\n{label} — {src} → {img.size}\n")
        for name, bbox in items:
            out = os.path.join(OUT_DIR, f"{name}.png")
            crop_with_white_padding(img, bbox).save(out, optimize=True)
            print(f"  ✓ {name:24s} {bbox} → {out}")
    total = len(BEACH_ITEMS) + len(OCEAN_ITEMS)
    print(f"\nDone — {total} aquatic+beach wildlife crops written.")


if __name__ == "__main__":
    main()
