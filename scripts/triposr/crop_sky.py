"""
Crop the 14 sky / weather assets from user reference image 30 (2000x1333).

Row 1 (4 panoramas, OPAQUE — saved as JPG, no alpha cutout, used as skybox):
  sky_dawn_panorama, sky_day_panorama, sky_dusk_panorama, sky_night_panorama

Row 2 (6 sprites — alpha cutout, 256x256):
  cloud_card_1, cloud_card_2, cloud_card_3, cloud_card_4,
  moon_crescent, moon_full

Row 3 (4 mixed — alpha cutout):
  sun_sprite, aurora_sheet (wide — 512x256), rainbow_after_rain, xp_orb

Outputs:
  Panoramas + aurora_sheet → assets/textures/sky/<name>.jpg
  Cloud / moon / sun / rainbow / xp_orb → assets/textures/sky/<name>.png with alpha

Usage:
    python3 scripts/triposr/crop_sky.py
"""

import os, sys
from PIL import Image

SRC = "/Users/jnuyens/.claude/image-cache/35f4cc08-1547-48d0-ac89-2efcf33a7f6f/30.png"
SKY_DIR = "/Users/jnuyens/src/Cubicraftia/assets/textures/sky"
PARTICLE_DIR = "/Users/jnuyens/src/Cubicraftia/assets/textures/particles"

# Source: 2000x1333. Layout:
#   Row 1: 4 panoramas (y ≈ 20..380), each ~470 wide
#   Row 2: 4 clouds + 2 moons (y ≈ 480..760), each ~250 wide
#   Row 3: sun + aurora + rainbow + xp_orb (y ≈ 820..1230)

# Panoramas — opaque, fit aspect, output as JPG
PANORAMAS = [
    ("sky_dawn_panorama",  (10,   20,  490, 410)),
    ("sky_day_panorama",   (500,  20,  980, 410)),
    ("sky_dusk_panorama",  (990,  20,  1470, 410)),
    ("sky_night_panorama", (1480, 20,  1990, 410)),
]

# Cloud + moon — alpha cutout, 256x256
CLOUDS = [
    ("cloud_card_1",   (10,   500, 270, 760)),
    ("cloud_card_2",   (280,  500, 530, 760)),
    ("cloud_card_3",   (560,  500, 810, 760)),
    ("cloud_card_4",   (830,  500, 1080, 760)),
    ("moon_crescent",  (1330, 500, 1570, 760)),
    ("moon_full",      (1620, 500, 1880, 760)),
]

# Row 3 mixed — alpha cutout
ROW3 = [
    ("sun_sprite",         (40,   820, 350,  1220)),
    ("rainbow_after_rain", (1050, 900, 1500, 1180)),
    ("xp_orb",             (1530, 900, 1840, 1200)),
]

# Aurora — wide aspect, opaque (sky effect overlay)
AURORA = ("aurora_sheet", (370, 800, 1010, 1230))


def crop_opaque(src_img, bbox, out_w, out_h):
    """Crop + scale to exact target dimensions (opaque JPG)."""
    sub = src_img.crop(bbox).convert("RGB")
    return sub.resize((out_w, out_h), Image.LANCZOS)


def crop_with_alpha(src_img, bbox, out_size=256, tolerance=10):
    """Crop + white→alpha + centred padding."""
    sub = src_img.crop(bbox).convert("RGBA")
    data = sub.getdata()
    new_data = []
    for r, g, b, a in data:
        if r >= 255 - tolerance and g >= 255 - tolerance and b >= 255 - tolerance:
            new_data.append((255, 255, 255, 0))
        else:
            new_data.append((r, g, b, a))
    sub.putdata(new_data)
    bbox_tight = sub.getbbox()
    if bbox_tight:
        sub = sub.crop(bbox_tight)
    target = out_size - 16
    sw, sh = sub.size
    scale = min(target / sw, target / sh)
    new_w = max(1, int(sw * scale))
    new_h = max(1, int(sh * scale))
    sub = sub.resize((new_w, new_h), Image.LANCZOS)
    canvas = Image.new("RGBA", (out_size, out_size), (0, 0, 0, 0))
    x = (out_size - new_w) // 2
    y = (out_size - new_h) // 2
    canvas.paste(sub, (x, y), sub)
    return canvas


def write_license(path, label="crop_sky.py"):
    with open(path + ".license", "w") as fh:
        fh.write(
            "SPDX-FileCopyrightText: 2026 Cubicraftia contributors\n"
            "SPDX-License-Identifier: GPL-3.0-or-later\n"
            f"Cropped from user-provided sky/weather sheet (image 30) by scripts/triposr/{label}\n"
        )


def main():
    if not os.path.exists(SRC):
        sys.exit(f"missing source: {SRC}")
    os.makedirs(SKY_DIR, exist_ok=True)
    os.makedirs(PARTICLE_DIR, exist_ok=True)
    src = Image.open(SRC)
    print(f"opened {SRC} → {src.size}\n")

    # Panoramas — 2048×1024 equirectangular target (per art-direction-brief)
    for name, bbox in PANORAMAS:
        out_path = os.path.join(SKY_DIR, f"{name}.jpg")
        crop_opaque(src, bbox, 2048, 1024).save(out_path, quality=85, optimize=True)
        write_license(out_path)
        print(f"  ✓ {name:24s} (panorama 2048x1024) → {out_path}")

    # Clouds + moons
    for name, bbox in CLOUDS:
        out_path = os.path.join(SKY_DIR, f"{name}.png")
        crop_with_alpha(src, bbox).save(out_path, optimize=True)
        write_license(out_path)
        print(f"  ✓ {name:24s} (sprite 256x256 alpha) → {out_path}")

    # Sun + rainbow → sky/, xp_orb → particles/
    for name, bbox in ROW3:
        if name == "xp_orb":
            out_path = os.path.join(PARTICLE_DIR, f"{name}.png")
        else:
            out_path = os.path.join(SKY_DIR, f"{name}.png")
        crop_with_alpha(src, bbox).save(out_path, optimize=True)
        write_license(out_path)
        print(f"  ✓ {name:24s} (sprite 256x256 alpha) → {out_path}")

    # Aurora — opaque wide PNG (used as sky overlay)
    name, bbox = AURORA
    out_path = os.path.join(SKY_DIR, f"{name}.jpg")
    crop_opaque(src, bbox, 1024, 512).save(out_path, quality=85, optimize=True)
    write_license(out_path)
    print(f"  ✓ {name:24s} (overlay 1024x512) → {out_path}")

    print(f"\nDone — 14 sky/weather assets written.")


if __name__ == "__main__":
    main()
