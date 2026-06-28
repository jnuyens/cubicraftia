<!--
SPDX-FileCopyrightText: 2026 Cubicraftia contributors
SPDX-License-Identifier: GPL-3.0-or-later
-->

# Changelog

All notable changes to Cubicraftia are recorded here.

## v1.1 — 2026-06-28

### Avatar / builder
- Reworked the avatar creator (wordmark header, leaf-flanked title, three distinct
  named builders with portraits, pixel font, brighter backdrop, click-drag turntable,
  and customisers for skin tone, hair colour, hairstyle, outfit and accessory).
- The customised builder now appears **in-world** using the textured, rigged skin GLB
  (the smooth "original builder" look) with real Walking/Running/Jump animations.

### World / spawn
- New **spawn showcase**: a hand-built village around the spawn point — lighthouse,
  windmill, stone castle, market stall, cottages, flags, a hot-air balloon, a floating
  island, animals, a campfire, a voxel water lake and shipwreck boats.
- A large **stepped sand pyramid** built from terrain voxels, anchored to the nearest
  desert (or a stamped sand patch), beside the village.
- **Fixed** a spawn-blocking bug where the pyramid and lake crowded the spawn point —
  the player now lands on an open, walkable green with the village as a backdrop.

### Terrain
- New **MOUNTAIN biome**: tall terrain with occasional sheer **vertical cliffs**
  (terraced heights), smoothly blended at biome edges.
- **Snow caps** with a natural wavy snow line and a patchy transition band (bare rock
  pokes through near the line, fuller snow toward the peaks).
- **Clouds flow around mountain peaks** — they part toward the lower flank and lift to
  skim over tall summits, then relax back to their lane.

### Crafting
- Completed the recipe set from the crafting sheet: added the full **axe** tier
  (wood/stone/iron/diamond/gold), the **stone/iron/gold sword** tiers, **fishing rod**,
  **hammer**, **compass**, **map**, and a new **diamond chestplate** item + recipe.
  All localised in English and Dutch.

### Tooling / housekeeping
- Added `render_world` (boots the in-world scene and screenshots spawn) for headless
  visual verification.
- Fixed CI lint issues (a hardcoded glyph in a scene; forbidden glossary terms in
  comments).

## v1.0

- Initial Cubicraftia milestone.
