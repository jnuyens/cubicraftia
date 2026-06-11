---
phase: 02-world-building-content
plan: "09"
subsystem: placement-system
tags:
  - stud-grid
  - placement
  - ghost-preview
  - crosshair
  - no-gravity
  - multi-cell
dependency_graph:
  requires:
    - 02-04  # BrickRegistry — get_definition(id)
    - 02-06  # BiomeMap + extended terrain
    - 02-08.5  # camera-mode-agnostic crosshair APIs
  provides:
    - multi-cell-placement   # StudGrid.place_multi (all-or-nothing)
    - ghost-preview          # GhostPreview MeshInstance3D + set_mode
    - crosshair-ui           # crosshair.tscn + crosshair.gd
    - builder-yaw-rotation   # _derive_rotation_from_builder_yaw (0..3 steps)
    - side-face-placement    # Phase 1 top-face restriction lifted
    - no-gravity-test        # test_no_gravity GREEN
  affects:
    - 02-11  # WorldSave uses dirty_chunks + removed_bulk
    - 02-12  # Palette UI wires Hotbar.active_def_id to _try_place
    - 02-14  # Adaptive-quality plan uses GhostPreview.set_mode("outline_only")
tech_stack:
  added:
    - "GhostPreview (MeshInstance3D subclass, GDScript)"
    - "Crosshair (Control + _draw, GDScript)"
    - "DDA raycast across StudGrid (integer step, GDScript)"
  patterns:
    - "all-or-nothing multi-cell insert (RESEARCH Pattern 4 / Pitfall 4)"
    - "same BrickInstance reference in all footprint cells"
    - "builder-yaw → 90° snap (rotation step 0..3)"
    - "XZ-only footprint rotation (Y invariant)"
    - "adaptive-quality mode switch hook (set_mode full/outline_only)"
key_files:
  created:
    - src/ui/ghost_preview.gd
    - src/ui/crosshair.tscn
    - src/ui/crosshair.gd
  modified:
    - src/world/stud_grid.gd
    - src/builder/builder.gd
    - src/autoload/world_save.gd
    - src/ui/mobile_overlay.gd
    - src/ui/mobile_overlay.tscn
    - src/world/main_scene.tscn
    - locale/en.po
    - tests/unit/test_stud_grid.gd
    - tests/unit/test_placement_rotation.gd
    - tests/integration/test_place_break.gd
    - tests/integration/test_no_gravity.gd
decisions:
  - "Ghost preview uses StandardMaterial3D (not ShaderMaterial) for v1; shader upgrade deferred to Plan 14"
  - "ghost_preview.gd reads BRICK_1X1 from builder as mesh fallback until Plan 12 wires Hotbar.active_def_id"
  - "DDA raycast is O(max_dist) per frame — acceptable for d<=10m at mobile fps"
  - "remove() erases all cells of a multi-cell brick via same-instance-reference scan (O(n) in brick count)"
  - "world_save._on_stud_placed signature extended to match new placed(anchor, def, colour, rotation)"
metrics:
  duration_min: 25
  completed_date: "2026-05-26T02:04:59Z"
  tasks_completed: 2
  files_touched: 11
requirements:
  - DOC-03
---

# Phase 2 Plan 09: Advanced Placement — Multi-Cell, Ghost Preview, Crosshair Summary

**One-liner:** Multi-cell footprint placement with all-or-nothing atomicity, builder-yaw rotation (0..3 × 90°), side + brick-on-brick face support, transparent ghost preview (white/red 0.35α), and 12×12 crosshair reticle per DOC-03 §3.2 contract.

## Tasks Completed

| Task | Name | Commit | Key Files |
|------|------|--------|-----------|
| 1 | StudGrid multi-cell + builder yaw rotation + tests | b03615b | stud_grid.gd, builder.gd, world_save.gd, 4 test files |
| 2 | Ghost preview + crosshair + mobile overlay | 7433ea2 | ghost_preview.gd, crosshair.tscn/.gd, mobile_overlay.gd/.tscn, main_scene.tscn, en.po |

## What Was Built

### Task 1: StudGrid + Builder extension

**StudGrid.place_multi** (all-or-nothing, RESEARCH Pitfall 4 mitigation):
- Pre-checks every footprint cell before inserting any
- Stores the **same BrickInstance reference** in every footprint cell (T-09-01 mitigated)
- Marks all affected 16m chunks dirty (`_dirty_chunks`) for WorldSave (Plan 11)
- `rotation` clamped to 0..3 (T-09-02 mitigated)

**StudGrid.remove** extended to erase all cells of a multi-cell brick (finds all cells sharing the same BrickInstance reference).

**StudGrid additions:** `remove_bulk`, `cells_in_sphere`, `get_dirty_chunks`, `clear_dirty_chunks`, `signal removed_bulk`.

**Phase 1 `place(anchor, def)` preserved** as a 1-cell wrapper around `place_multi`.

**Builder extensions:**
- Phase 1 top-face-only restriction **lifted** — now uses `hit.previous_position` uniformly for top/side/bottom faces
- `_derive_rotation_from_builder_yaw()` → snaps builder Y-rotation to 90° steps (0..3)
- `_rotated_footprint(footprint, rotation)` → permutes XZ only; Y invariant
- `_raycast_stud_grid(origin, direction, max_dist)` → integer DDA traversal across sparse grid
- `predict_placement_target()` → shared raycast logic consumed by both `_try_place` and `ghost_preview.gd`
- `add_to_group("builder")` → `get_first_node_in_group("builder")` in ghost_preview works

**Crosshair APIs unchanged:** `get_crosshair_position()` / `get_crosshair_direction()` from Plan 08.5 are the only ray source — no direct camera access.

**Tests GREEN:**
- `test_placement_rotation`: `test_yaw_to_rotation_step` + `test_rotation_permutes_xz_only`
- `test_stud_grid`: 8 extended tests (place_multi_2x4, collision_rejected, chunk_boundary, remove_bulk, cells_in_sphere, dirty_chunks, same_instance_in_all_cells, remove_multi_cell_erases_all)
- `test_no_gravity`: `test_removing_support_leaves_brick_floating` + `test_features_brick_gravity_is_false`
- `test_place_break`: 3 new tests (side_face_accepted_phase2, brick_on_brick, multi_cell_2x4)

### Task 2: Ghost Preview + Crosshair

**GhostPreview** (`src/ui/ghost_preview.gd`, extends MeshInstance3D):
- `_process`: calls `builder.predict_placement_target()` each frame; positions ghost at target cell centre
- `show_valid()` → white 0.35α; `show_invalid()` → red (#D63828) 0.35α per UI-SPEC
- `set_mode("full"|"outline_only")` → Plan 14 Tier-3 adaptive-quality hook is a real non-no-op switch
- `cast_shadow = false`; unshaded StandardMaterial3D with TRANSPARENCY_ALPHA

**Crosshair** (`src/ui/crosshair.tscn` + `crosshair.gd`):
- `_draw()` paints 12×12 + cross; 1px navy drop-shadow first, then #F1F0EA primary arms
- `set_invalid_state(bool)` → red tint for invalid placement; `queue_redraw()`
- Anchored to screen centre via `anchors_preset = 8` (CENTER)

**main_scene.tscn extended:**
- `GhostPreview` node (MeshInstance3D) as sibling of BrickRenderer in 3D scene
- `Crosshair` instance in UI CanvasLayer

**mobile_overlay.gd + .tscn extended:**
- Crosshair hidden when palette bottom sheet expands (`_set_palette_open(true)`)
- `_crosshair` cached from parent CanvasLayer in `_ready()`

**locale/en.po additions:**
- `ui.builder.cant_place_there` = "Can't place there."
- `ui.builder.no_tool` = "Select a brick or tool from the hotbar."

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] world_save.gd placed-signal handler signature mismatch**
- **Found during:** Task 1 — after extending `StudGrid.placed` signal to include `colour_index` and `rotation`
- **Issue:** `world_save.gd::_on_stud_placed(anchor_cell, definition)` would fail to connect to the updated `placed(anchor_cell, definition, colour_index, rotation)` signal
- **Fix:** Updated `_on_stud_placed` signature to `(anchor_cell, definition, colour_index, rotation)` — the new parameters are ignored (underscored) since WorldSave only needs the anchor for dirty-chunk marking
- **Files modified:** `src/autoload/world_save.gd`
- **Commit:** b03615b

## Known Stubs

| Stub | File | Line | Reason |
|------|------|------|--------|
| Ghost uses BRICK_1X1 mesh always | `src/ui/ghost_preview.gd` | ~120 | Plan 12 (Palette UI) wires `Hotbar.active_def_id`; until then the ghost always previews a 1x1 brick regardless of selected type |

This stub does not prevent the plan's goal (ghost preview works, valid/invalid state works, set_mode works). It will be resolved when Plan 12 ships.

## No-Gravity Invariant

Per DOCS.md §3.2 + §9 and RESEARCH.md Contradiction 1: no falling-block algorithm was added. `StudGrid.remove()` simply erases cells; upper bricks remain floating. `test_no_gravity::test_removing_support_leaves_brick_floating` asserts this. `Features.brick_gravity` remains `false` (CI: `verify-feature-flags.sh`).

## Camera-Mode-Agnostic Placement

Both `_try_place` and `predict_placement_target` (used by ghost_preview) call `get_crosshair_position()` / `get_crosshair_direction()` exclusively — the Plan 08.5 locked APIs. Placement and ghost preview work identically in FPV and CHASE modes.

## Threat Surface Scan

No new network endpoints, auth paths, or file access patterns introduced. New trust boundary (builder input → StudGrid) was already in the plan's `<threat_model>`. T-09-01 (Pitfall 4 all-or-nothing) and T-09-02 (rotation clamping) are both mitigated in the implementation.

## Self-Check: PASSED

- All files exist at the expected paths (verified above)
- Both commits present in git log: b03615b (Task 1), 7433ea2 (Task 2)
- Glossary check passed: no forbidden terminology
- No CLAUDE.md directives violated
