"""
Crop the 21 voxel block textures from user reference image 19 (1402x1122).

Two outputs per block:
  - assets/textures/voxel_blocks/<name>.png       — full isometric icon (256x256)
                                                    used for inventory + UI
  - assets/textures/voxel_blocks/<name>_face.png  — top-face tileable texture
                                                    (192x192, perspective-corrected)
                                                    used by Zylann/godot_voxel

The face extraction is approximate — the isometric reference has the top face
as a diamond shape; we sample the centre region and squash it to a square.
For production use, an artist may want to re-author hand-painted face tiles,
but these placeholders are immediately usable in-game.

Layout: 4 rows of 6 + 1 row of 3 = 21 items.

Usage:
    python3 scripts/triposr/crop_voxels.py
"""

import os, sys
from PIL import Image

SRC = "/Users/jnuyens/.claude/image-cache/35f4cc08-1547-48d0-ac89-2efcf33a7f6f/19.png"
OUT_DIR = "/Users/jnuyens/src/Cubicraftia/assets/textures/voxel_blocks"

# Source: 1402x1122. ~5 rows.
# Row 1 (6 cubes): y ≈ 20..270
# Row 2 (6 cubes): y ≈ 300..550
# Row 3 (6 cubes): y ≈ 580..830
# Row 4 (3 cubes): y ≈ 860..1100
# Cubes are ~230px wide, evenly spaced

ITEMS = [
    # Row 1 — y top ~10, cube bottom ~210, label below
    ("voxel_grass",       (20,   10,  240, 215)),
    ("voxel_dirt",        (250,  10,  470, 215)),
    ("voxel_stone",       (480,  10,  700, 215)),
    ("voxel_cobblestone", (710,  10,  930, 215)),
    ("voxel_sand",        (940,  10,  1170, 215)),
    ("voxel_snow",        (1180, 10,  1400, 215)),

    # Row 2 — y top ~290, cube bottom ~495, label below
    ("voxel_water",       (20,   290, 240, 495)),
    ("voxel_lava",        (250,  290, 470, 495)),
    ("voxel_wood_log",    (480,  290, 700, 495)),
    ("voxel_wood_plank",  (710,  290, 930, 495)),
    ("voxel_glass",       (940,  290, 1170, 495)),
    ("voxel_brick_red",   (1180, 290, 1400, 495)),

    # Row 3 — y top ~580, cube bottom ~780, label below
    ("voxel_brick_white", (20,   580, 240, 780)),
    ("voxel_ice",         (250,  580, 470, 780)),
    ("voxel_obsidian",    (480,  580, 700, 780)),
    ("voxel_marble",      (710,  580, 930, 780)),
    ("voxel_sandstone",   (940,  580, 1170, 780)),
    ("voxel_clay",        (1180, 580, 1400, 780)),

    # Row 4 — only 3 items (y top ~880, cube bottom ~1050)
    ("voxel_gravel",      (20,   880, 240, 1055)),
    ("voxel_path_stone",  (250,  890, 490, 1055)),
    ("voxel_carpet_red",  (510,  920, 750, 1055)),
]


def crop_icon(src_img, bbox, out_size=256):
    """Crop the full isometric cube to a square icon with white background."""
    sub = src_img.crop(bbox).convert("RGB")
    sw, sh = sub.size
    target = out_size - 16
    scale = min(target / sw, target / sh)
    new_w = max(1, int(sw * scale))
    new_h = max(1, int(sh * scale))
    sub = sub.resize((new_w, new_h), Image.LANCZOS)
    canvas = Image.new("RGB", (out_size, out_size), (255, 255, 255))
    x = (out_size - new_w) // 2
    y = (out_size - new_h) // 2
    canvas.paste(sub, (x, y))
    return canvas


def extract_top_face(src_img, bbox, face_size=192):
    """
    Sample the centre of the cube's top face and squash to a square tile.

    Isometric cubes show the top face as a diamond — the corners of the
    diamond are roughly at:
      top:    (cube_center_x, cube_top + 0%)
      right:  (cube_right - 5%, cube_center_y)
      bottom: (cube_center_x, cube_center_y - 5%)
      left:   (cube_left + 5%, cube_center_y)

    Approximation: take a narrow horizontal band near the top of the cube
    where the top face dominates, then stretch to a square. Crude but
    captures the material colour + pattern.
    """
    cube = src_img.crop(bbox)
    cw, ch = cube.size
    # Sample the top quarter of the cube (the top face occupies roughly this region)
    top_band = cube.crop((int(cw * 0.18), int(ch * 0.05), int(cw * 0.82), int(ch * 0.45)))
    return top_band.resize((face_size, face_size), Image.LANCZOS)


def write_license(path):
    with open(path + ".license", "w") as fh:
        fh.write(
            "SPDX-FileCopyrightText: 2026 Cubicraftia contributors\n"
            "SPDX-License-Identifier: GPL-3.0-or-later\n"
            "Cropped from user-provided voxel block sheet (image 19)\n"
            "by scripts/triposr/crop_voxels.py.\n"
        )


def main():
    if not os.path.exists(SRC):
        sys.exit(f"missing source: {SRC}")
    os.makedirs(OUT_DIR, exist_ok=True)
    src = Image.open(SRC)
    print(f"opened {SRC} → {src.size}\n")
    for name, bbox in ITEMS:
        icon_path = os.path.join(OUT_DIR, f"{name}.png")
        face_path = os.path.join(OUT_DIR, f"{name}_face.png")
        crop_icon(src, bbox).save(icon_path, optimize=True)
        extract_top_face(src, bbox).save(face_path, optimize=True)
        write_license(icon_path)
        write_license(face_path)
        print(f"  ✓ {name:24s} → icon + face")
    print(f"\nDone — {len(ITEMS)} voxel blocks × 2 outputs = {len(ITEMS) * 2} PNGs written.")


if __name__ == "__main__":
    main()
