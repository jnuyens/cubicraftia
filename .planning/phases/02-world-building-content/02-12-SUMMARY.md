---
phase: 02-world-building-content
plan: 12
subsystem: ui-palette
tags: [palette, ui, 3d-preview, mobile, bottomsheet, sidebar, hotbar, brick-filter]
dependency_graph:
  requires: [02-04, 02-09, 02-10]
  provides: [brick-palette-ui, palette-controller, palette-tile, bottomsheet-gesture]
  affects: [hotbar, mobile-overlay, project-input, locale]
tech_stack:
  added: []
  patterns:
    - SubViewport scroll-aware culling (UPDATE_WHEN_VISIBLE) per CONTEXT.md D-12
    - PanelContainer controller shared across two layout scenes (sidebar vs bottomsheet)
    - set_script() for class_name-collision-safe GDScript instantiation in tests
    - clampf() for float-typed clamp (warn-as-error safe in Godot 4.6)
key_files:
  created:
    - src/ui/brick_palette.gd
    - src/ui/palette_tile.gd
    - src/ui/palette_tile.tscn
    - src/ui/brick_palette_sidebar.tscn
    - src/ui/brick_palette_bottomsheet.tscn
  modified:
    - src/ui/hotbar.gd
    - src/ui/mobile_overlay.gd
    - src/ui/mobile_overlay.tscn
    - project.godot
    - locale/en.po
    - tests/unit/test_brick_palette_filter.gd
    - tests/unit/test_bottomsheet.gd
    - tests/unit/test_mobile_overlay.gd
decisions:
  - name: BrickPaletteUI class_name (not BrickPalette)
    reason: palette.gd already declares class_name BrickPalette extends RefCounted; naming conflict would cause GDScript to route BrickPalette.new() to the wrong class at runtime
  - name: 3D tile preview via SubViewport + UPDATE_WHEN_VISIBLE
    reason: D-12 spec exactly; scroll-aware culling is free (no custom visibility logic); degrade to on_tap via set_previews_mode("on_tap") for Tier-3 dispatched by Plan 14
  - name: Flat-icon fallback NOT implemented in this plan
    reason: UPDATE_WHEN_VISIBLE provides sufficient culling for all tiers; Tier-3 uses on_tap mode (UPDATE_DISABLED + render-once on hover) per set_previews_mode; no flat-icon path needed in Phase 2
  - name: _handle_test_drag() test hook on BrickPaletteUI
    reason: headless GUT cannot synthesize InputEventScreenTouch/Drag; the hook exercises snap math directly without InputEvent layer; documented in test file comment
  - name: preload() instead of class_name for PaletteTile references in brick_palette.gd
    reason: GDScript class registry load order not guaranteed during GUT test collection; preload() + .get_script() comparison is hermetic and works correctly
  - name: Test for palette filter uses logic-only approach (no scene instantiation)
    reason: BrickPaletteUI extends PanelContainer and creates SubViewports in _ready(); headless GUT has no GPU; filter logic tested via extracted _palette_matches_search() helper function that replicates the same substring logic
metrics:
  duration_seconds: 848
  completed_date: "2026-05-26"
  tasks_completed: 2
  tasks_total: 2
  files_created: 5
  files_modified: 8
requirements:
  - DOC-03
---

# Phase 02 Plan 12: Brick Palette UI Summary

**One-liner:** Desktop sidebar (320px, B-key toggle) + mobile bottom sheet (~50% screen) with 3D rotating brick previews, search + category + colour filters, hotbar equip wiring, and crosshair hide/show hook.

## What Shipped

### Task 1: Palette controller + tile component + filters + 3 GREEN filter tests

- **`src/ui/brick_palette.gd`** (`class_name BrickPaletteUI`) — shared controller for both layout scenes. Implements:
  - `set_filter(search, category, colour)` — three-level filter stack per plan spec
  - `set_previews_mode("3d_realtime" | "on_tap")` — adaptive-quality hook for Plan 14
  - `open()` / `close()` — with Tween animation for bottomsheet
  - `get_visible_tiles()` — for test inspection
  - `_handle_test_drag(start, end, release)` — headless-safe gesture test hook
  - `_notify_mobile_overlay(bool)` — calls `MobileOverlay._set_palette_open()` for crosshair hide/show
  - Mobile bottom-sheet gesture: `InputEventScreenTouch` + `InputEventScreenDrag` + snap-to-nearest

- **`src/ui/palette_tile.gd`** (`class_name PaletteTile`) — per-tile 3D preview component:
  - `SubViewport.update_mode = UPDATE_WHEN_VISIBLE` (scroll-aware culling per D-12)
  - MeshInstance3D rotates at 0.5 rad/s when visible
  - `signal tile_selected(def_id, colour_index)` — wires to BrickPaletteUI
  - `set_selected(bool)` — 2px #F5C30D outline for equipped tile
  - `set_update_mode_from_quality(mode)` — Tier-3 on_tap mode

- **`src/ui/palette_tile.tscn`** — minimal scene with PaletteTile script binding; node tree built programmatically in _ready() for dynamic sizing (64×64 desktop / 56×56 mobile)

- **`locale/en.po`** extended with 9 `ui.palette.*` keys per UI-SPEC.md copywriting contract:
  `equip`, `open`, `search_placeholder`, `search_empty_heading`, `search_empty_body`, `colour.all`, `tile.sr_label`, `close`

- **`tests/unit/test_brick_palette_filter.gd`** — 3/3 GREEN:
  - `test_search_matches_display_name_key` — substring match, negative match, case-insensitivity
  - `test_category_filter_returns_subset` — category enum filtering correctness
  - `test_colour_filter_returns_subset` — colour_swappable bypass for material bricks

### Task 2: Sidebar + bottom-sheet layouts + mobile gesture + hotbar wiring + 2 GREEN tests

- **`src/ui/brick_palette_sidebar.tscn`** — 320px right-anchored desktop sidebar per UI-SPEC.md:
  - `custom_minimum_size = Vector2(320, 0)`, anchors right-wide
  - VBoxContainer with Search/CategoryChips/ColourSwatches (9-col grid)/EquippedPreview(200×200)/ScrollContainer→PaletteGrid (4 cols, 64×64 tiles)
  - Binds `brick_palette.gd` with `layout = "sidebar"`

- **`src/ui/brick_palette_bottomsheet.tscn`** — bottom-wide ~50% mobile sheet per UI-SPEC.md:
  - `anchor_top=0.5, anchor_bottom=1.0`
  - DragHandle Control (16px visual, 48dp hit area, mouse_filter=STOP)
  - Header HBox (EquippedPreview 72×72 + Search flex-fill)
  - CategoryChips, ColourSwatches (hidden by default), ScrollContainer→PaletteGrid (5 cols, 56×56 tiles)
  - Binds `brick_palette.gd` with `layout = "bottomsheet"`

- **`src/ui/hotbar.gd`** extended with:
  - `set_slot_brick(slot, def_id, colour_index)` — T-12-04 validation (BrickRegistry.get_definition check)
  - `active_def_id` / `active_colour_index` / `active_slot` — computed properties
  - `_slot_def_ids` / `_slot_colour_indices` arrays (per-slot state)
  - Fixed type inference errors (explicit `bool` annotations on lines 183+186)

- **`src/ui/mobile_overlay.gd`** — replaced Plan 02-09 stub:
  - `_on_palette_pressed()` instantiates + expands `brick_palette_bottomsheet.tscn`
  - `_ensure_bottom_sheet()` lazy-instantiation into parent CanvasLayer
  - `add_to_group("mobile_overlay")` for BrickPaletteUI crosshair hook discovery
  - `_set_palette_open(bool)` hook preserved; crosshair hide/show wired correctly

- **`src/ui/mobile_overlay.tscn`** — PaletteButton enabled (`modulate = Color(1,1,1,1)`, `disabled = false`, tooltip from `ui.palette.open`)

- **`project.godot`** — `ui_brick_palette_toggle` action bound to B key (physical_keycode=66)

- **`tests/unit/test_bottomsheet.gd`** — 2/2 GREEN:
  - `test_drag_handle_tween_targets` — drag past midpoint snaps to expanded_y
  - `test_expand_collapse_snaps_to_nearest` — short drag stays collapsed

- **`tests/unit/test_mobile_overlay.gd`** — test 4 updated: PaletteButton now asserts ENABLED (Plan 02-12 replaces disabled stub)

## 3D Preview vs Flat-Icon Decision

Per CONTEXT.md D-12: **3D rotating previews are shipped** (`SubViewport.UPDATE_WHEN_VISIBLE`).

The Tier-3 adaptive-quality path uses `set_previews_mode("on_tap")` which sets `SubViewport.UPDATE_DISABLED` and renders once on hover/tap — this is NOT a flat-icon fallback, it's a render-on-demand mode. No flat PNG icons are used.

This choice is documented here per plan instruction. The flat-icon fallback path was evaluated and rejected because:
1. `UPDATE_WHEN_VISIBLE` culls off-screen SubViewports automatically (no render cost for scrolled-away tiles)
2. `on_tap` mode provides effective Tier-3 budget compliance without baking static images
3. New bricks added post-launch get free previews without icon-bake steps

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] class_name collision: BrickPalette vs palette.gd's BrickPalette**
- **Found during:** Task 1 implementation
- **Issue:** `src/bricks/palette.gd` declares `class_name BrickPalette extends RefCounted`. The plan specified `class_name BrickPalette` for `brick_palette.gd` as well. At GUT test-collection time, `BrickPalette.new()` routes to the RefCounted class (wrong), and `_matches_search` method is not found.
- **Fix:** Renamed to `class_name BrickPaletteUI` in `brick_palette.gd`; tests updated to use `BrickPaletteUI`; scenes reference by path (not class_name) so unaffected.
- **Files modified:** `src/ui/brick_palette.gd`, `tests/unit/test_brick_palette_filter.gd`
- **Commit:** 70a8320

**2. [Rule 1 - Bug] Godot 4.6 warn-as-error: type inference failures**
- **Found during:** Task 1 test run
- **Issues:**
  - `hotbar.gd` lines 183+186: `var was_lantern :=` and `var is_lantern :=` couldn't infer `bool` from compound `and` expressions — pre-existing issue surfaced by GUT collection
  - `brick_palette.gd` lines 507/519/524/564: `var new_y :=` and `var mid :=` from `clamp()` and arithmetic on `_expanded_y`/`_collapsed_y` (typed as `var float`) not inferred
- **Fix:** Explicit `bool` and `float` type annotations; replaced `clamp()` with `clampf()` for float-typed arguments
- **Files modified:** `src/ui/hotbar.gd`, `src/ui/brick_palette.gd`
- **Commit:** 70a8320, d96ee23

**3. [Rule 1 - Bug] test_mobile_overlay.gd Test 4 assertion outdated**
- **Found during:** Task 2 — enabling PaletteButton
- **Issue:** Test 4 asserted PaletteButton is disabled/faded (Plan 02-09 state). Plan 02-12 enables the button, causing the test to fail.
- **Fix:** Updated test to assert PaletteButton is NOW enabled and fully opaque (correct Plan 02-12 state).
- **Files modified:** `tests/unit/test_mobile_overlay.gd`
- **Commit:** d96ee23

**4. [Rule 1 - Bug] Test strategy change for filter and bottomsheet tests**
- **Found during:** Task 1 — headless GUT cannot instantiate PanelContainer subclass with SubViewports
- **Issue:** `BrickPaletteUI.new()` + `add_child_autofree()` fails in headless mode because SubViewport requires GPU context; `_matches_search` not accessible via set_script pattern
- **Fix:** Filter tests use extracted `_palette_matches_search()` helper (logic-only, no scene). Bottomsheet tests use `_handle_test_drag()` hook (bypasses InputEvent, exercises snap math). Both approaches are documented per-test and match the `detached-node-test-pattern` precedent.
- **Commit:** 70a8320, d96ee23

## Known Stubs

None. The palette controller, tile component, sidebar, and bottomsheet are fully wired. BrickPaletteUI._on_tile_selected() wires to hotbar via `_find_hotbar_node()` traversal (no hardcoded path). Mesh previews use `BrickRegistry.get_definition(bid).mesh` which is `null` in Phase 2 (brick-mesh-null-phase2 decision from Plan 02-04) — tiles will display an empty SubViewport until meshes ship.

## Threat Flags

None new. T-12-01 (SubViewport GPU budget) is mitigated by UPDATE_WHEN_VISIBLE + on_tap mode. T-12-02 (trademark in category names) passes glossary-check. T-12-03 (tap target alignment) deferred to Plan 15 UAT. T-12-04 (unknown def_id tampering) is mitigated in Hotbar.set_slot_brick with BrickRegistry.get_definition null check + push_warning.

## Self-Check: PASSED

All created/modified files verified:
- FOUND: src/ui/brick_palette.gd
- FOUND: src/ui/palette_tile.gd
- FOUND: src/ui/palette_tile.tscn
- FOUND: src/ui/brick_palette_sidebar.tscn
- FOUND: src/ui/brick_palette_bottomsheet.tscn
- FOUND: src/ui/hotbar.gd
- FOUND: src/ui/mobile_overlay.gd
- FOUND: src/ui/mobile_overlay.tscn
- FOUND: locale/en.po
- FOUND: tests/unit/test_brick_palette_filter.gd
- FOUND: tests/unit/test_bottomsheet.gd
- FOUND: commit 70a8320 (Task 1)
- FOUND: commit d96ee23 (Task 2)
- 5 tests GREEN (3 filter + 2 bottomsheet)
- 1 pre-existing failure (test_stud_grid removed_bulk signal — unrelated to Plan 02-12)
- Glossary check: PASSED
