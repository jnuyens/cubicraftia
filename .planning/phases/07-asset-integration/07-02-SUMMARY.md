---
phase: 07-asset-integration
plan: "02"
subsystem: ui-asset-wiring
tags: [asset-integration, code-fix, hp-bar, ftue, world-select]
dependency_graph:
  requires:
    - "07-01"
  provides:
    - hp_bar_heart_paths_correct
    - ftue_arrow_path_correct
    - ftue_storyboard_panel_wired
    - world_select_bg_path_correct
  affects:
    - src/ui/hp_bar.gd
    - src/ui/ftue_overlay.gd
    - src/ui/world_select_screen.gd
tech_stack:
  added: []
  patterns:
    - ResourceLoader.exists() guard + load() fallback (existing pattern, preserved)
    - _STEP_PANELS const array for panel-to-step mapping
key_files:
  created: []
  modified:
    - src/ui/hp_bar.gd
    - src/ui/ftue_overlay.gd
    - src/ui/world_select_screen.gd
decisions:
  - "Use _STEP_PANELS const array for storyboard panel-to-step mapping (clean, audit-visible)"
  - "StoryboardPanel TextureRect placed before narration_row so illustration renders above text"
  - "panel_05_crafts_a_tool.png selected for step 4 (tool progression matches completion theme)"
  - "title_bg.png wired to world_select for visual continuity with title_scene"
metrics:
  duration_minutes: 10
  completed_date: "2026-06-01"
  tasks_completed: 3
  files_modified: 3
---

# Phase 07 Plan 02: Code-side Path/Naming Gap Fixes (G-01, G-02, G-06, G-08) Summary

Fixed three GDScript files so existing real art assets are correctly referenced at runtime. All path constants pointed at wrong filenames or wrong directories; the committed art already existed at the correct paths. No assets were renamed.

## What Was Built

**Task 1 — hp_bar.gd heart icon paths (G-01)**

Updated `ICON_FULL`, `ICON_HALF`, and `ICON_EMPTY` constants to match the actual committed filenames (`health_heart_full.png` / `health_heart_half.png` / `health_heart_empty.png`). The previous constants referenced `heart_full.png`, `heart_half.png`, and `heart_empty.png` which do not exist. The `ResourceLoader.exists()` guard was silently suppressing the loads. Updated the file-header comment to match.

**Task 2 — ftue_overlay.gd arrow path + storyboard panel (G-02 + G-06)**

Three changes:
1. Fixed arrow texture path from `res://assets/icons/ftue_arrow.png` (wrong directory) to `res://assets/textures/icons/ftue_arrow.png` (both occurrences on line 233 — `ResourceLoader.exists()` check and `load()` call).
2. Added `_storyboard_panel: TextureRect` state variable alongside the other node-reference vars.
3. Added `_STEP_PANELS` const array mapping 4 panel PNGs to the 4 FTUE steps (panel_01 = arrival, panel_02 = mining, panel_04 = place plank, panel_05 = crafts tool), `StoryboardPanel` TextureRect node in `_setup_nodes()` (256×144, `EXPAND_FIT_WIDTH_PROPORTIONAL`), and panel-load logic at the top of `_activate_step()` with the standard `ResourceLoader.exists()` guard. Zero occurrences of "skip" preserved per DOCS §1.4 non-dismissable requirement.

**Task 3 — world_select_screen.gd dead background path (G-08)**

Replaced the dead path `res://assets/textures/title_bg_bricks.png` (never existed) with `res://assets/textures/icons/title_bg.png` (1.6 MB real art, same hero vista used by `title_scene.gd`). Added a comment explaining the visual-continuity intent. The `ResourceLoader.exists()` guard was preserved; no structural change.

## Verification Results

**Audit test (`test_no_stub_textures_in_shipped_scenes`):**
- hp_bar.gd heart path failures: GONE (health_heart_*.png resolve to ~60 KB each)
- ftue_overlay.gd arrow path failure: GONE (ftue_arrow.png = 3.2 KB real art)
- world_select_screen.gd title_bg_bricks failure: GONE

**Remaining audit failures (8, all intentional — outside this plan's scope):**
- `world_thumb_placeholder.png` (68 B stub) — fixed in 07-03
- `avatar_presets/preset_*.png` stubs — fixed in 07-04
- `title_scene.gd` historical `title_bg_bricks.png` in fallback chain — out of scope (noted below)
- `sign_in_panel.gd` icon_check/icon_error missing paths — out of scope
- `main_scene.gd` day_panorama.png — out of scope
- `item_definition.gd` key_bronze.png — out of scope

**Full GUT suite:** 256/280 passing, 8 failing — same count as pre-plan baseline. No regressions introduced.

**grep gates:**
- `grep -c "health_heart_full" src/ui/hp_bar.gd` → 2 (const + comment)
- `grep -o "assets/textures/icons/ftue_arrow" src/ui/ftue_overlay.gd | wc -l` → 2
- `grep -c "assets/textures/icons/title_bg.png" src/ui/world_select_screen.gd` → 1

## Deviations from Plan

None — plan executed exactly as written.

## Known Stubs

The following stub references remain in the codebase and are tracked for later plans:

| File | Path | Size | Plan |
|------|------|------|------|
| src/ui/world_select_screen.gd | assets/textures/ui/world_thumb_placeholder.png | 68 B | 07-03 |
| src/ui/avatar_creator.gd | assets/textures/ui/avatar_presets/preset_1-8.png | 68 B each | 07-04 |

## Deferred Items

- `src/ui/title_scene.gd:192` references `res://assets/textures/title_bg_bricks.png` as a "historical alternate path" in a fallback chain. This is a pre-existing dead entry outside this plan's scope. It gracefully no-ops (ResourceLoader.exists() returns false). Logged to deferred-items for 07-03 or later.

## Threat Surface Scan

No new network endpoints, auth paths, file access patterns, or schema changes. The three changes are all compile-time string constants in `res://` — no user-controlled input. Existing `ResourceLoader.exists()` guards preserved on all new paths.

## Self-Check: PASSED

- src/ui/hp_bar.gd exists and contains `health_heart_full`
- src/ui/ftue_overlay.gd exists and contains `assets/textures/icons/ftue_arrow`
- src/ui/world_select_screen.gd exists and contains `assets/textures/icons/title_bg.png`
- Commits d5b9bcc, 7b4a534, f292e65 exist in git log
- Full GUT suite: 256 passing, 8 failing — identical to pre-plan baseline (no regressions)
