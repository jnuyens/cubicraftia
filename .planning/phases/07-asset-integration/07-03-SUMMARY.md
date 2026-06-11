---
phase: 07-asset-integration
plan: "03"
subsystem: asset-replacement
tags: [asset-integration, png-replacement, vram-import, world-thumbnail]
dependency_graph:
  requires:
    - "07-01"
    - "07-02"
  provides:
    - title_bg_real_hero_art
    - title_bg_vram_import
    - world_thumb_placeholder_real_art
  affects:
    - assets/textures/icons/title_bg.png
    - assets/textures/icons/title_bg.png.import
    - assets/textures/ui/world_thumb_placeholder.png
    - src/ui/title_scene.gd
tech_stack:
  added: []
  patterns:
    - In-place PNG overwrite (same res:// path, preserve uid in .import)
    - compress/mode=3 (VRAM compressed) for large background texture
    - process/size_limit=2048 for mobile VRAM cap
    - Python Pillow for programmatic PNG generation
key_files:
  created:
    - assets/textures/ui/world_thumb_placeholder.png.license
  modified:
    - assets/textures/icons/title_bg.png
    - assets/textures/icons/title_bg.png.license
    - assets/textures/icons/title_bg.png.import (gitignored — on-disk only)
    - assets/textures/ui/world_thumb_placeholder.png
    - src/ui/title_scene.gd
decisions:
  - "Copy art-composed_world-cubicraftia-hero.png (2.6 MB) over title_bg.png in-place to preserve UID"
  - "Set compress/mode=3 + process/size_limit=2048 in title_bg.png.import for 4-6x mobile VRAM savings"
  - "Generate world_thumb_placeholder via Pillow: 320x180 navy #1B2C56 + brick-red border + white text"
  - "Remove dead title_bg_bricks.png fallback from title_scene.gd (Rule 1 auto-fix)"
metrics:
  duration_minutes: 8
  completed_date: "2026-06-01"
  tasks_completed: 2
  files_modified: 5
---

# Phase 07 Plan 03: Asset File Replacements G-04, G-05 + VRAM Import for Title BG Summary

Replace two remaining 68 B stub assets with real art (hero composition for title background; branded "No Preview" placeholder for world-select), and update the title background import preset for mobile VRAM efficiency.

## What Was Built

**Task 1 — title_bg.png: hero composition + VRAM import (G-05)**

Copied `art-composed_world-cubicraftia-hero.png` (2686×1048 px, 2.6 MB) over `assets/textures/icons/title_bg.png` in-place. Previous content was a 1.6 MB earlier crop; the hero composition contains the full viewport composition with foreground elements.

Edited `assets/textures/icons/title_bg.png.import` (gitignored, on-disk):
- `compress/mode`: 0 (Lossless) → 3 (VRAM Compressed) — 4–6x VRAM savings on mobile
- `process/size_limit`: 0 → 2048 — caps longest dimension during import for mobile
- `metadata.vram_texture`: false → true — reflects VRAM format
- All other params, `uid="uid://bqs5ltxjri1wb"`, `path=`, and `dest_files=` preserved verbatim

Deleted stale `.ctex` to force Godot reimport on next editor open.
Updated `.license` sidecar to reflect new provenance.

**Task 2 — world_thumb_placeholder.png: real branded "No Preview" (G-04)**

Generated a 320×180 RGBA PNG via Python Pillow:
- Navy background: `#1B2C56` (same shade as FTUE overlay)
- 3px brick-red border: `#C91111`
- Centered white "No Preview" text (Helvetica 28pt)
- Output: 3442 B (vs 68 B stub — 50× larger; well above 200 B audit threshold)

Copied to `assets/textures/ui/world_thumb_placeholder.png` in-place. Added `.license` sidecar (GPL-3.0-or-later). Did not touch `world_thumb_placeholder.png.import` — `compress/mode=0` (lossless) is correct for this UI texture.

## Verification Results

**Grep gates (all passed):**
- `title_bg.png` size: 2686381 B (> 200 B)
- `title_bg.png.import` contains `compress/mode=3` — confirmed
- `title_bg.png.import` contains `uid://bqs5ltxjri1wb` — unchanged
- `title_bg.png.import` contains `process/size_limit=2048` — confirmed
- `world_thumb_placeholder.png` size: 3442 B (> 200 B)
- `world_thumb_placeholder.png.import` contains `uid://2y2gnw11cw1w` — unchanged

**Audit test (`test_no_stub_textures_in_shipped_scenes`):**
- `title_bg.png` reference: GREEN (2.6 MB)
- `world_thumb_placeholder.png` reference: GREEN (3442 B)
- Remaining failures: 6 (icon_check×2, icon_error×2, day_panorama, key_bronze — pre-existing, out of Plan 07-03 scope; noted in Plan 07-02 SUMMARY as deferred)
- `avatar_presets/preset_1..8.png` references: still RED (fixed in 07-04)

Failure count reduced from 8 (pre-plan) to 6 (post-plan), consistent with plan scope.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Removed dead `title_bg_bricks.png` fallback from title_scene.gd**
- **Found during:** Task 1 verification (audit test run)
- **Issue:** `title_scene.gd:192` contained a dead fallback path `res://assets/textures/title_bg_bricks.png` (file never existed) in the background loading loop. `FileAccess.get_size()` returned `-1 B`, causing the audit to fail with one additional failure that the plan was supposed to fix.
- **Fix:** Removed the dead second entry from the fallback array. The array now has only the primary path `res://assets/textures/icons/title_bg.png` (which now has real content). Updated the comment to remove the historical-placeholder phrasing.
- **Files modified:** `src/ui/title_scene.gd`
- **Commit:** `b7f9b71`
- **Note:** This dead reference was acknowledged in Plan 07-02 SUMMARY as "out of scope" for that plan; it blocked Plan 07-03's audit gate so was auto-fixed here under Rule 1.

## Known Stubs

None. Both replaced assets have real content (>200 B). The `world_thumb_placeholder.png` is intentionally a simple branded graphic (not photo-realistic art) — this is by design per CONTEXT.md (Claude's Discretion: "The real 'no preview' default world graphic — compose from existing art or simple branded placeholder").

`avatar_presets/preset_1..8.png` are still stubs — those are fixed in Plan 07-04.

## Threat Flags

None. No new network endpoints, auth paths, file access patterns, or schema changes introduced. Asset integration only.

## Self-Check: PASSED

- `assets/textures/icons/title_bg.png` exists and is 2686381 B: FOUND
- `assets/textures/ui/world_thumb_placeholder.png` exists and is 3442 B: FOUND
- `assets/textures/ui/world_thumb_placeholder.png.license` created: FOUND
- Commit `3935748` (Task 1) in git log: FOUND
- Commit `44eac1f` (Task 2) in git log: FOUND
- Commit `b7f9b71` (deviation fix) in git log: FOUND
