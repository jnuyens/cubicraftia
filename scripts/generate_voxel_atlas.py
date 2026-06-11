"""
Cubicraftia voxel block atlas generator.

Generates FLAT, tileable pixel-art block-face textures (classic voxel style) and
packs them into a single atlas PNG used by VoxelBlockyModelCube atlas UV mapping.

IMPORTANT: the source `voxel_*.png` art in this directory are 3/4-view isometric
CUBE ICONS (thumbnails), NOT flat block faces. Using them as face textures puts a
tiny rendered cube on every face. This script instead PROCEDURALLY GENERATES flat
per-face pixel-art textures (16x16, upscaled to the tile size with NEAREST) so each
cube face shows a proper grass/dirt/stone/etc. surface.

Layout (unchanged — must match _VOXEL_TILES in src/world/main_scene.gd):
    5 columns x 4 rows = 20 tile slots, each 256x256 px -> 1280x1024 px total.
    Slot (col, row), index = row * COLS + col.
    Row 0: grass_top, grass_face, sand_top, sand_face, snow_top
    Row 1: snow_face, stone_top, stone_face, sandstone_top, sandstone_face
    Row 2: ice_top, ice_face, water_top, water_face, wood_log_top
    Row 3: wood_log_face, dirt_top, dirt_face, leaves_top, leaves_face

Usage:  python3 scripts/generate_voxel_atlas.py
License: GPL-3.0-or-later.
"""

import os
import random
from PIL import Image

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TEX_DIR = os.path.join(REPO, "assets", "textures", "voxel_blocks")
OUT_PATH = os.path.join(TEX_DIR, "voxel_atlas.png")
LICENSE_PATH = OUT_PATH + ".license"

PX = 16            # native pixel-art resolution per face
TILE_SIZE = 256    # upscaled px per atlas tile side
COLS = 5
ROWS = 4
ATLAS_W = TILE_SIZE * COLS   # 1280
ATLAS_H = TILE_SIZE * ROWS   # 1024


def _noisy(base, jitter, seed):
    """A PXxPX flat texture: base colour with per-pixel brightness jitter."""
    rnd = random.Random(seed)
    img = Image.new("RGBA", (PX, PX), (0, 0, 0, 255))
    px = img.load()
    for y in range(PX):
        for x in range(PX):
            d = rnd.randint(-jitter, jitter)
            px[x, y] = (
                max(0, min(255, base[0] + d)),
                max(0, min(255, base[1] + d)),
                max(0, min(255, base[2] + d)),
                255,
            )
    return img


def _dirt(seed):
    return _noisy((134, 96, 67), 20, seed)


def _grass_side(seed):
    """Dirt with a green strip along the top + a few green drips."""
    img = _dirt(seed)
    px = img.load()
    rnd = random.Random(seed + 1)
    strip = 4
    for y in range(PX):
        for x in range(PX):
            if y < strip or (y < strip + 3 and rnd.random() < 0.35):
                d = rnd.randint(-22, 22)
                px[x, y] = (max(0, min(255, 96 + d)), max(0, min(255, 168 + d)),
                            max(0, min(255, 58 + d)), 255)
    return img


def _wood_top(seed):
    """End grain: concentric rings."""
    img = _noisy((150, 111, 71), 10, seed)
    px = img.load()
    c = (PX - 1) / 2.0
    for y in range(PX):
        for x in range(PX):
            r = ((x - c) ** 2 + (y - c) ** 2) ** 0.5
            if int(r) % 3 == 0:
                px[x, y] = (110, 78, 48, 255)
    return img


def _wood_side(seed):
    """Bark: vertical stripes."""
    img = _noisy((120, 84, 52), 14, seed)
    px = img.load()
    for x in range(PX):
        if x % 4 == 0:
            for y in range(PX):
                px[x, y] = (92, 62, 38, 255)
    return img


def _sandstone(seed):
    """Tan with horizontal banding."""
    img = _noisy((214, 196, 150), 10, seed)
    px = img.load()
    for y in range(PX):
        if y % 5 == 0:
            for x in range(PX):
                px[x, y] = (190, 170, 124, 255)
    return img


def _leaves(seed):
    """Dense green foliage — darker and more varied than grass top."""
    rnd = random.Random(seed)
    img = Image.new("RGBA", (PX, PX), (0, 0, 0, 255))
    px = img.load()
    # Base: darker forest green with strong per-pixel variation
    for y in range(PX):
        for x in range(PX):
            d = rnd.randint(-28, 28)
            # Base colour: (62, 128, 36) — darker/richer than grass (96, 168, 58)
            px[x, y] = (
                max(0, min(255, 62 + d)),
                max(0, min(255, 128 + d)),
                max(0, min(255, 36 + d)),
                255,
            )
    # Scatter a few darker "shadow" pixels to break up the pattern
    for _ in range(PX * PX // 4):
        x = rnd.randint(0, PX - 1)
        y = rnd.randint(0, PX - 1)
        r, g, b, a = px[x, y]
        px[x, y] = (max(0, r - 20), max(0, g - 20), max(0, b - 10), a)
    return img


# tile_name -> generator(seed)
GEN = {
    "grass_top":      lambda s: _noisy((96, 168, 58), 22, s),
    "grass_face":     _grass_side,
    "sand_top":       lambda s: _noisy((216, 194, 140), 16, s),
    "sand_face":      lambda s: _noisy((210, 188, 132), 14, s),
    "snow_top":       lambda s: _noisy((238, 244, 250), 8, s),
    "snow_face":      lambda s: _noisy((232, 238, 246), 8, s),
    "stone_top":      lambda s: _noisy((124, 128, 134), 18, s),
    "stone_face":     lambda s: _noisy((118, 122, 128), 18, s),
    "sandstone_top":  _sandstone,
    "sandstone_face": _sandstone,
    "ice_top":        lambda s: _noisy((169, 212, 240), 12, s),
    "ice_face":       lambda s: _noisy((160, 204, 236), 12, s),
    "water_top":      lambda s: _noisy((58, 111, 201), 14, s),
    "water_face":     lambda s: _noisy((52, 102, 190), 14, s),
    "wood_log_top":   _wood_top,
    "wood_log_face":  _wood_side,
    "dirt_top":       _dirt,
    "dirt_face":      _dirt,
    "leaves_top":     _leaves,
    "leaves_face":    _leaves,
}

# Ordered slots (left-to-right, top-to-bottom) — MUST match the layout above.
TILES = [
    "grass_top", "grass_face", "sand_top", "sand_face", "snow_top",
    "snow_face", "stone_top", "stone_face", "sandstone_top", "sandstone_face",
    "ice_top", "ice_face", "water_top", "water_face", "wood_log_top",
    "wood_log_face", "dirt_top", "dirt_face",
    "leaves_top", "leaves_face",
]


def main():
    atlas = Image.new("RGBA", (ATLAS_W, ATLAS_H), (0, 0, 0, 0))
    for idx, name in enumerate(TILES):
        col = idx % COLS
        row = idx // COLS
        tile = GEN[name](hash(name) & 0xFFFF).resize((TILE_SIZE, TILE_SIZE), Image.NEAREST)
        atlas.paste(tile, (col * TILE_SIZE, row * TILE_SIZE))
    atlas.save(OUT_PATH)
    print("wrote", OUT_PATH, atlas.size)
    if not os.path.exists(LICENSE_PATH):
        with open(LICENSE_PATH, "w") as f:
            f.write("SPDX-FileCopyrightText: 2026 Cubicraftia contributors\n")
            f.write("SPDX-License-Identifier: GPL-3.0-or-later\n")
            f.write("Procedurally generated flat voxel block-face atlas.\n")


if __name__ == "__main__":
    main()
