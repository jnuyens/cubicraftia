"""
Crop the master app icon + refined wordmark from user image 36 (1536x1024).

Layout:
  Top-left:    APP_ICON_1024  (master 1024×1024 — used by macOS/iOS to derive all sizes)
  Bottom-left: CUBICRAFTIA wordmark (refined 3D bricked logo)
  Centre/right panels: visualisations only (size-grid previews) — IGNORE.

Outputs:
  assets/icons/app_icon_1024.png   (master, opaque RGB, 1024×1024)
  assets/textures/icons/cubicraftia_wordmark_v2.png  (alpha cutout)
"""

import os, sys
from PIL import Image

SRC = "/Users/jnuyens/.claude/image-cache/35f4cc08-1547-48d0-ac89-2efcf33a7f6f/36.png"
ICON_DIR = "/Users/jnuyens/src/Cubicraftia/assets/icons"
TEX_DIR = "/Users/jnuyens/src/Cubicraftia/assets/textures/icons"


def crop_opaque(src, bbox, out_w, out_h):
    sub = src.crop(bbox).convert("RGB")
    return sub.resize((out_w, out_h), Image.LANCZOS)


def crop_with_alpha(src, bbox, out_size, tolerance=10):
    sub = src.crop(bbox).convert("RGBA")
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
    target = out_size - 16
    scale = min(target / sw, target / sh)
    nw, nh = max(1, int(sw * scale)), max(1, int(sh * scale))
    sub = sub.resize((nw, nh), Image.LANCZOS)
    canvas = Image.new("RGBA", (out_size, out_size), (0, 0, 0, 0))
    canvas.paste(sub, ((out_size - nw) // 2, (out_size - nh) // 2), sub)
    return canvas


def write_license(path):
    with open(path + ".license", "w") as fh:
        fh.write(
            "SPDX-FileCopyrightText: 2026 Cubicraftia contributors\n"
            "SPDX-License-Identifier: GPL-3.0-or-later\n"
            "Cropped from user-provided app icon master sheet (image 36) by scripts/triposr/crop_app_icon.py\n"
        )


def main():
    if not os.path.exists(SRC):
        sys.exit(f"missing {SRC}")
    os.makedirs(ICON_DIR, exist_ok=True)
    os.makedirs(TEX_DIR, exist_ok=True)
    src = Image.open(SRC)
    print(f"opened {SRC} → {src.size}")

    # Master app icon — square crop top-left
    icon_path = os.path.join(ICON_DIR, "app_icon_1024.png")
    crop_opaque(src, (20, 20, 460, 560), 1024, 1024).save(icon_path, optimize=True)
    write_license(icon_path)
    print(f"  ✓ app_icon_1024 → {icon_path}")

    # Also keep one as PNG inside assets/textures/icons for in-game About panel
    in_game = os.path.join(TEX_DIR, "app_icon.png")
    crop_opaque(src, (20, 20, 460, 560), 512, 512).save(in_game, optimize=True)
    write_license(in_game)
    print(f"  ✓ app_icon (512) → {in_game}")

    # Refined wordmark — bottom-left tile (~40..420 x, 660..960 y)
    wm_path = os.path.join(TEX_DIR, "cubicraftia_wordmark_v2.png")
    crop_with_alpha(src, (20, 640, 480, 980), 1024).save(wm_path, optimize=True)
    write_license(wm_path)
    print(f"  ✓ cubicraftia_wordmark_v2 → {wm_path}")

    print("\nDone — 3 files written. macOS/iOS will derive every size from the 1024 master at packaging time.")


if __name__ == "__main__":
    main()
