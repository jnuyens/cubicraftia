"""
Crop individual creatures from the user-provided art reference sheets.

Three sheets shipped: aquatic + hostiles + wildlife. Total of 20 distinct
creatures. Crops are saved with a white-padded background (TripoSR-friendly)
and uniform 512x512 framing.

Run after the user updates the reference sheets in /tmp/user_art/.

Usage:
    python3 scripts/triposr/crop_user_art.py
"""

import os
import sys
import shutil
from PIL import Image

OUT_DIR = "/tmp/cubicraftia_creature_crops"
os.makedirs(OUT_DIR, exist_ok=True)

# (source_image, creature_name, (left, top, right, bottom) bbox in source pixels)
# Source images are 1536x1024 each.

SRC_9 = "/Users/jnuyens/.claude/image-cache/35f4cc08-1547-48d0-ac89-2efcf33a7f6f/9.png"
SRC_10 = "/Users/jnuyens/.claude/image-cache/35f4cc08-1547-48d0-ac89-2efcf33a7f6f/10.png"
SRC_11 = "/Users/jnuyens/.claude/image-cache/35f4cc08-1547-48d0-ac89-2efcf33a7f6f/11.png"

CROPS = [
    # ─── Image 9 — aquatic + wildlife ──────────────────────────────────────
    (SRC_9, "panda",        (40, 290, 320, 660)),
    (SRC_9, "elephant",     (340, 280, 720, 670)),
    (SRC_9, "orca",         (700, 320, 1090, 630)),
    (SRC_9, "fish_orange",  (1080, 320, 1330, 620)),
    (SRC_9, "jellyfish",    (1300, 270, 1530, 680)),

    # ─── Image 10 — hostiles ────────────────────────────────────────────────
    (SRC_10, "bat",              (30, 230, 360, 600)),
    (SRC_10, "cube_slime_medium",(340, 380, 600, 630)),
    (SRC_10, "ghost",            (610, 200, 900, 620)),
    (SRC_10, "laser_penguin",    (900, 220, 1180, 640)),
    (SRC_10, "vampire_humanoid", (1180, 220, 1500, 660)),

    # ─── Image 11 — top row wildlife ────────────────────────────────────────
    (SRC_11, "desert_mouse",  (10, 190, 280, 470)),
    (SRC_11, "reindeer",      (270, 80, 590, 490)),
    (SRC_11, "snowman",       (570, 50, 870, 510)),
    (SRC_11, "monkey",        (850, 110, 1130, 510)),
    (SRC_11, "toucan",        (1180, 110, 1520, 480)),

    # ─── Image 11 — bottom row wildlife ─────────────────────────────────────
    (SRC_11, "giraffe",    (10, 480, 290, 890)),
    (SRC_11, "gnu",        (270, 520, 620, 890)),
    (SRC_11, "manta",      (590, 580, 1010, 870)),
    (SRC_11, "fish_blue",  (990, 610, 1300, 850)),
    (SRC_11, "fish_yellow",(1270, 610, 1530, 850)),
]


def crop_with_white_padding(img, bbox, out_size=512):
    """Crop bbox, paste on a centred white square at out_size."""
    sub = img.crop(bbox).convert("RGB")
    sw, sh = sub.size
    # Scale to fit within (out_size - 20)px box with 10px margin all sides
    target = out_size - 40
    scale = min(target / sw, target / sh)
    new_w = max(1, int(sw * scale))
    new_h = max(1, int(sh * scale))
    sub = sub.resize((new_w, new_h), Image.LANCZOS)
    # White canvas
    canvas = Image.new("RGB", (out_size, out_size), (255, 255, 255))
    x = (out_size - new_w) // 2
    y = (out_size - new_h) // 2
    canvas.paste(sub, (x, y))
    return canvas


def main():
    # Open each source image once
    sources = {}
    for src, name, _ in CROPS:
        if src not in sources:
            if not os.path.exists(src):
                sys.exit(f"missing source: {src}")
            sources[src] = Image.open(src)
            print(f"opened {src} → {sources[src].size}")

    print(f"\nCropping {len(CROPS)} creatures → {OUT_DIR}\n")
    for src, name, bbox in CROPS:
        crop = crop_with_white_padding(sources[src], bbox)
        out = os.path.join(OUT_DIR, f"{name}.png")
        crop.save(out, optimize=True)
        print(f"  ✓ {name:24s} {bbox} → {out}")

    # Tier-share for cube_slime: large + small use the same crop as medium
    for tier in ("large", "small"):
        src_path = os.path.join(OUT_DIR, "cube_slime_medium.png")
        dst_path = os.path.join(OUT_DIR, f"cube_slime_{tier}.png")
        shutil.copyfile(src_path, dst_path)
        print(f"  ✓ cube_slime_{tier:8s} ← (copy of cube_slime_medium)")

    # Bat → vampire_bat (same art, role-distinct in game)
    shutil.copyfile(os.path.join(OUT_DIR, "bat.png"),
                    os.path.join(OUT_DIR, "vampire_bat.png"))
    print(f"  ✓ vampire_bat            ← (copy of bat)")

    total = len(CROPS) + 3
    print(f"\nDone — {total} crops written ({len(CROPS)} unique + 3 reuses).")


if __name__ == "__main__":
    main()
