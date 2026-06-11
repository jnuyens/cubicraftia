"""
Crop 21 HUD / UI sprites from user reference image 35 (1536x1024).

Row 1 (5):  health_heart_full/half/empty, hotbar_slot_selected/empty
Row 2 (4):  crosshair_default, crosshair_can_break, tooltip_bg_panel, achievement_badge_template
Row 3 (2):  xp_bar_fill, minimap_compass_n
Row 4 (11): keybind_icon_e, q, tab, shift, ctrl, alt, space, 1, 2, f, esc

All saved with alpha cutout, direct to assets/textures/icons/.
"""

import os, sys
from PIL import Image

SRC = "/Users/jnuyens/.claude/image-cache/35f4cc08-1547-48d0-ac89-2efcf33a7f6f/35.png"
OUT_DIR = "/Users/jnuyens/src/Cubicraftia/assets/textures/icons"

ITEMS = [
    # Row 1 — 5 (y ≈ 30..240)
    ("health_heart_full",          (10,   30,  290, 240)),
    ("health_heart_half",          (290,  30,  570, 240)),
    ("health_heart_empty",         (570,  30,  840, 240)),
    ("hotbar_slot_selected",       (870,  20,  1170, 240)),
    ("hotbar_slot_empty",          (1190, 20,  1490, 240)),

    # Row 2 — 4 (y ≈ 280..500)
    ("crosshair_default",          (30,   280, 240, 500)),
    ("crosshair_can_break",        (310,  280, 580, 500)),
    ("tooltip_bg_panel",           (590,  280, 1110, 470)),
    ("achievement_badge_template", (1190, 250, 1490, 540)),

    # Row 3 — 2 (y ≈ 580..760)
    ("xp_bar_fill",                (20,   580, 620, 760)),
    ("minimap_compass_n",          (700,  560, 880, 770)),

    # Row 4 — 11 keybind icons (y ≈ 830..990)
    ("keybind_icon_e",     (40,   830, 170, 990)),
    ("keybind_icon_q",     (180,  830, 310, 990)),
    ("keybind_icon_tab",   (320,  830, 450, 990)),
    ("keybind_icon_shift", (460,  830, 590, 990)),
    ("keybind_icon_ctrl",  (600,  830, 730, 990)),
    ("keybind_icon_alt",   (740,  830, 870, 990)),
    ("keybind_icon_space", (880,  830, 1010, 990)),
    ("keybind_icon_1",     (1020, 830, 1140, 990)),
    ("keybind_icon_2",     (1150, 830, 1270, 990)),
    ("keybind_icon_f",     (1280, 830, 1400, 990)),
    ("keybind_icon_esc",   (1410, 830, 1530, 990)),
]


def crop_with_alpha(src_img, bbox, out_size=256, tolerance=10):
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


def write_license(p):
    with open(p + ".license", "w") as fh:
        fh.write(
            "SPDX-FileCopyrightText: 2026 Cubicraftia contributors\n"
            "SPDX-License-Identifier: GPL-3.0-or-later\n"
            "Cropped from user-provided HUD sheet (image 35) by scripts/triposr/crop_hud.py\n"
        )


def main():
    if not os.path.exists(SRC):
        sys.exit(f"missing {SRC}")
    os.makedirs(OUT_DIR, exist_ok=True)
    src = Image.open(SRC)
    print(f"opened {SRC} → {src.size}\n")
    for name, bbox in ITEMS:
        # xp_bar_fill + tooltip_bg_panel are wider — use 512 to preserve aspect
        out_size = 512 if name in ("xp_bar_fill", "tooltip_bg_panel") else 256
        out = os.path.join(OUT_DIR, f"{name}.png")
        crop_with_alpha(src, bbox, out_size=out_size).save(out, optimize=True)
        write_license(out)
        print(f"  ✓ {name:32s} → {out}")
    print(f"\nDone — {len(ITEMS)} HUD sprites written.")


if __name__ == "__main__":
    main()
