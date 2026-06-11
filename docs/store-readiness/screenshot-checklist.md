<!-- SPDX-FileCopyrightText: 2026 Cubicraftia contributors -->
<!-- SPDX-License-Identifier: GPL-3.0-or-later -->

# Screenshot Checklist

**Product:** Cubicraftia v1.0
**Locale:** English (EN-US) — v1 launch locale
**Required:** 6 screenshots per device type per locale

---

## Required Sizes by Platform

### App Store (iOS)

| Device | Required | Resolution (pixels) | Scale | Orientation |
|--------|----------|---------------------|-------|-------------|
| iPhone 6.9" (iPhone 16 Pro Max) | **Required** | 1320 × 2868 | @3x | Portrait |
| iPhone 6.5" (iPhone 11 Pro Max / 12/13/14 Plus) | **Required** | 1242 × 2688 | @3x | Portrait |
| iPad Pro 13" (M4) | **Required** | 2064 × 2752 | @2x | Portrait or Landscape |
| iPhone 5.5" (iPhone 8 Plus) | Optional | 1242 × 2208 | @3x | Portrait |
| iPad Pro 11" | Optional | 1668 × 2388 | @2x | Portrait or Landscape |

> Apple requires at minimum screenshots for iPhone 6.9" (or 6.5") and iPad 13". Submitting only one iPhone size applies it to all iPhone sizes.

### Google Play (Android)

| Device | Required | Resolution (pixels) | Orientation |
|--------|----------|---------------------|-------------|
| Phone | **Required** (min 2, max 8) | min 1080 × 1920; preferred 1080 × 2340 (9:20) | Portrait |
| 7" Tablet | Optional | 1200 × 1920 | Portrait |
| 10" Tablet | Optional | 1920 × 1200 | Landscape |
| Feature graphic | **Required** | 1024 × 500 | Landscape (JPEG or PNG, no alpha) |

---

## Suggested Shot Sequence (6 shots)

Capture all 6 scenes. Adapt framing to each device's aspect ratio. Avoid UI clutter that obscures the gameplay. Ensure the game name or logo is visible in at least shot 1.

### Shot 1 — Title Screen

**Scene:** Title screen or main menu
**Objective:** Brand recognition. Show the Cubicraftia logo, tagline, and the brick-world aesthetic.
**What to show:** Logo centred, brick-world background scene visible, "Build worlds. With friends." tagline.
**UI elements to hide:** Debug overlays, FPS counter, any dev tools.

### Shot 2 — World Exploration (Aerial)

**Scene:** Walking through a biome boundary — e.g., snow field meeting a forest.
**Objective:** Convey the infinite procedural world and visual variety.
**What to show:** Dramatic terrain transition, at least 2 biome types visible, natural lighting.
**UI elements:** Hotbar visible at bottom. Hide chat overlay.

### Shot 3 — Brick Building

**Scene:** Player placing a coloured brick — e.g., building a small house wall.
**Objective:** Show the core brick-building mechanic.
**What to show:** Ghost preview of a brick in position, hotbar with palette visible, 3–4 already-placed bricks of different colours visible.
**UI elements:** Ghost preview active, hotbar, block palette open if space permits.

### Shot 4 — Friends Session Panel

**Scene:** Friends list / session panel open, showing 2–3 invited friends.
**Objective:** Communicate the multiplayer premise and friends-only design.
**What to show:** Friends panel UI with 2–3 player names listed, session "host" indicator, invite button.
**Notes:** Use placeholder friend names — no real user data. Names should look plausible (e.g., "PixelPete", "BuilderBea").

### Shot 5 — Chat Overlay (Multiplayer Session)

**Scene:** In-session chat overlay with a short friendly exchange between players.
**Objective:** Show that multiplayer is text-based chat within a friends session.
**What to show:** Chat messages from 2–3 players, the player's own input area, a corner of the world visible behind.
**Notes:** Write the example chat messages in advance; make them playful and illustrative. Nothing that implies strangers (e.g., "Hey guys, let's build the castle on the hill!").

### Shot 6 — Hostile Creature Encounter

**Scene:** Night scene with one or two hostile creatures visible, player wielding a tool.
**Objective:** Show the survival/combat element without appearing violent.
**What to show:** Torchlight glow, stylised brick creature (e.g., Cube Slime), player character in a ready stance.
**Notes:** Ensure the scene reads as playful/exciting, not scary. Avoid close-up of creature filling the frame.

---

## Capture Instructions

### Using Godot's headless screenshot tool

```bash
# Capture a specific scene to a PNG at 1320x2868 (iPhone 6.9" resolution)
godot --headless --render-thread-mode 0 \
  --resolution 1320x2868 \
  --screenshot screenshots/iphone-6.9-shot1.png \
  -- res://scenes/title_screen.tscn

# For landscape iPad at 2752x2064
godot --headless --render-thread-mode 0 \
  --resolution 2752x2064 \
  --screenshot screenshots/ipad13-shot2.png \
  -- res://scenes/main_scene.tscn
```

> Note: `--screenshot` is not a built-in Godot CLI flag. Use a custom `screenshot_capture.gd` autoload that calls `get_viewport().get_texture().get_image().save_png(path)` at a specific frame, or take screenshots manually via the running export.

### Manual capture workflow (recommended for v1)

1. Export a debug build for the target platform at the target resolution.
2. Run the build, navigate to the desired scene.
3. Use the platform's built-in screenshot (Cmd+Shift+4 on macOS, Power+Volume on iOS, etc.).
4. Crop to the exact required resolution if needed.
5. Review: no debug text visible, no real user data, aspect ratio matches requirement.

### Screenshot review checklist (per shot)

- [ ] Resolution matches requirement exactly (no upscaling artefacts)
- [ ] No debug overlays, FPS counters, or developer UI visible
- [ ] No real user data (email, real usernames) visible
- [ ] No third-party trademarks visible (no "Lego", no "Minecraft")
- [ ] Hotbar / UI elements are representative of the shipping build
- [ ] Aspect ratio is correct for the target device slot
- [ ] Shot is compelling and clearly illustrates the labelled feature

---

## File Naming Convention

```
screenshots/
  en/                          # locale
    iphone-6.9/
      01-title.png
      02-world-aerial.png
      03-brick-building.png
      04-friends-panel.png
      05-chat-overlay.png
      06-creature-night.png
    iphone-6.5/
      ... (same names)
    ipad-13/
      ... (same names)
    android-phone/
      ... (same names)
    android-feature-graphic.jpg
```

---

## Completion Status

| Device | Shots completed | Notes |
|--------|----------------|-------|
| iPhone 6.9" | 0 / 6 | Not yet captured |
| iPhone 6.5" | 0 / 6 | Not yet captured |
| iPad 13" | 0 / 6 | Not yet captured |
| Android Phone | 0 / 6 | Not yet captured |
| Android Feature Graphic | 0 / 1 | Not yet captured |

Update this table as screenshots are produced and approved.
