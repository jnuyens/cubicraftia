---
phase: 02-world-building-content
plan: 11
subsystem: dynamite-vfx + dropped-item-entity
tags:
  - dynamite
  - dropped-item
  - bulk-edit
  - performance
  - vfx
dependency_graph:
  requires:
    - 02-09   # StudGrid.cells_in_sphere + remove_bulk + dirty_chunks
    - 02-10   # dynamite.tres ToolDefinition + ToolWear.decrement_on_use
  provides:
    - dropped-item-entity   # DroppedItem class (Phase 3 inherits pickup)
    - dynamite-handler      # DynamiteHandler detonate() bulk-blast pipeline
    - spawn-dropped-item    # main_scene.spawn_dropped_item() API
  affects:
    - 02-13   # village NPCs do NOT touch these files (wave-8 serialisation)
    - 03-xx   # Phase 3 inherits DroppedItem.picked_up signal for inventory
tech_stack:
  added:
    - DroppedItem (RigidBody3D → MultiMeshInstance3D two-phase entity)
    - DynamiteHandler (Node3D with Timer + GPUParticles3D + Tween screen shake)
  patterns:
    - bulk-voxel-edit: VoxelTool.do_sphere (one call per detonate)
    - bulk-stud-remove: StudGrid.remove_bulk (one call per detonate)
    - settled-multimesh-pool: per-(def_id,colour) MultiMeshInstance3D
    - screen-shake: Camera3D h_offset/v_offset Tween ease-out cubic
key_files:
  created:
    - src/world/dropped_item.gd
    - src/world/dropped_item.tscn
    - src/tools/dynamite_handler.gd
    - src/tools/dynamite_handler.tscn
  modified:
    - src/world/main_scene.gd
    - src/builder/builder.gd
    - locale/en.po
    - project.godot
    - tests/integration/test_dynamite_blast.gd
decisions:
  - "TERRAIN_TO_BRICK_DROP const lives in DroppedItem (single source of truth); DynamiteHandler reads it — no duplication"
  - "SNOW_ID (3), ICE_ID (6), WATER_ID (7) all map to null (drop nothing) — per plan spec"
  - "Ore brick IDs use BrickRegistry names: copper_ore, iron_ore, diamond_ore (not *_brick suffix)"
  - "voxel/threads/main/time_budget_ms = 6 set in project.godot (TECH-3 mitigation)"
  - "30-cap on active RigidBody3D dropped items enforced in main_scene.spawn_dropped_item()"
  - "test_main_thread_time_within_budget remains PENDING (manual:tier3); Plan 15 runs it on hardware"
metrics:
  duration: "~8 minutes"
  completed_date: "2026-05-26"
  tasks_completed: 2
  tasks_total: 2
  files_created: 4
  files_modified: 5
---

# Phase 02 Plan 11: Dynamite + DroppedItem VFX Pipeline Summary

**One-liner:** Dynamite 5m bulk-edit blast with GPUParticles3D flash + screen shake + two-phase RigidBody3D/MultiMesh dropped-item entity proving the chunk-mesh batching architecture.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | DroppedItem entity + two-phase RigidBody3D/MultiMesh pool | 512716a | dropped_item.gd, dropped_item.tscn, main_scene.gd, locale/en.po |
| 2 | DynamiteHandler bulk-edit blast + screen shake + GREEN tests | e295837 | dynamite_handler.gd, dynamite_handler.tscn, builder.gd, project.godot, test_dynamite_blast.gd |

## What Was Built

### Task 1: DroppedItem entity

`src/world/dropped_item.gd` extends `RigidBody3D` with `class_name DroppedItem`. Implements the two-phase lifecycle from RESEARCH.md Pitfall 7:

1. **Physics-active phase** (~1.5s): RigidBody3D bounces with `apply_impulse(Vector3.UP * 3.0 + random XZ scatter)`. `gravity_scale = 1.5` for arcade-feel arc.
2. **Settled phase**: `_settle()` calls `main_scene.transition_to_settled_pool(self)` which adds an entry to a per-(def_id, colour) `MultiMeshInstance3D` and `queue_free()`s the physics node.

Signals: `spawned(item_id)`, `settled(item_id)`, `picked_up(item_id)` (Phase 3 contract).

`const TERRAIN_TO_BRICK_DROP` is the locked mapping from terrain voxel IDs to BrickRegistry def_ids (single owner — DynamiteHandler reads this const).

`src/world/dropped_item.tscn`: RigidBody3D root + CollisionShape3D (SphereShape3D r=0.2) + MeshInstance3D (BoxMesh placeholder) + OmniLight3D (warm white #FFFAE6, light_energy=0.3, `light_cull_mask = 1` = CHANNEL_VISUAL_MASK per Pitfall 9 mitigation).

`src/world/main_scene.gd` extended with:
- `_settled_dropped_pools: Dictionary` (key = "def_id::colour", value = MultiMeshInstance3D)
- `get_settled_pool(def_id, colour_index)` — lazy MMI allocator
- `transition_to_settled_pool(item)` — physics → MultiMesh transition
- `spawn_dropped_item(def_id, colour_index, world_pos, active_physics)` — two-phase dispatch with 30-item cap

### Task 2: DynamiteHandler

`src/tools/dynamite_handler.gd` extends `Node3D` with `class_name DynamiteHandler`.

**Bulk-edit contract (TECH-1/2/3 mitigation):**
- `detonate()` calls `VoxelTool.do_sphere(centre, radius)` **exactly once** (grep-verified: `grep -v '^#' | grep -c 'do_sphere'` = 1)
- `detonate()` calls `StudGrid.remove_bulk(affected_cells)` **exactly once** (grep-verified: `grep -v '^#' | grep -c 'remove_bulk'` = 1)
- `project.godot`: `voxel/threads/main/time_budget_ms = 6` spreads Vulkan mesh-buffer swaps across frames

**Sequence:**
1. `light_fuse(world_pos, radius)`: starts `Timer (wait_time=3.0)` + `FuseSparks` particles + "Fuse lit — step back!" toast
2. On `Timer.timeout` → `detonate(global_position, 5.0)`:
   a. `FlashParticles.emitting = true` (orange/yellow burst)
   b. Screen shake: `Camera3D.h_offset` / `v_offset` Tween, 0.3s, max 0.08 amplitude, ease-out cubic
   c. ONE `VoxelTool.do_sphere(centre, radius)` — removes terrain voxels
   d. ONE `StudGrid.remove_bulk(affected_cells)` — removes all brick cells in sphere
   e. `main_scene.spawn_dropped_item()` for each removed cell (terrain via `TERRAIN_TO_BRICK_DROP` + bricks directly)
   f. `blast_completed.emit(centre, removed_count)`

`src/builder/builder.gd` extended with `_active_tool_is_dynamite` flag, `set_active_tool_dynamite()` setter, and `_try_place_dynamite()` which instantiates DynamiteHandler and calls `light_fuse()`.

**Tests:** `test_dynamite_blast.gd`
- `test_5m_radius_correctness`: GREEN headlessly — places 50 bricks in a 10×5 grid, verifies `cells_in_sphere` returns exactly the cells within Euclidean distance 5.0, verifies `remove_bulk` removes all of them, verifies `removed_bulk` signal emitted via GUT `watch_signals`, verifies dirty-chunk coalescing (≤4 distinct chunks).
- `test_main_thread_time_within_budget`: PENDING (manual:tier3) — Plan 15 runs on Motorola One Macro reference device.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] GDScript lambda closure does not update outer scope**
- **Found during:** Task 2 — test_5m_radius_correctness failing
- **Issue:** `_stud_grid.removed_bulk.connect(func(cells) -> void: signal_received = true)` — the GDScript 4 lambda captures `signal_received` by value; the outer variable was never updated.
- **Fix:** Replaced lambda with GUT's built-in `watch_signals(_stud_grid)` + `assert_signal_emitted()` + `get_signal_parameters()`.
- **Files modified:** tests/integration/test_dynamite_blast.gd
- **Commit:** e295837

**2. [Rule 1 - Bug] Grep count inflated by inline tab-indented comments**
- **Found during:** Task 2 verification — `grep -v '^#' | grep -c 'do_sphere'` returned 4
- **Issue:** Tab-indented comment lines inside functions (e.g. `\t# do_sphere batches`) are NOT stripped by `grep -v '^#'` because they start with `\t#` not `#`. The plan's verification command was sensitive to this.
- **Fix:** Removed inline comments mentioning `do_sphere` / `remove_bulk` from function bodies; kept documentation only in the file header (lines starting with `#`).
- **Files modified:** src/tools/dynamite_handler.gd
- **Commit:** e295837

**3. [Rule 2 - Missing validation] Ore brick IDs adjusted to match BrickRegistry manifest**
- **Found during:** Task 1 implementation — verifying BrickRegistry .tres files
- **Issue:** Plan spec listed `copper_ore_brick`, `iron_ore_brick`, `diamond_ore_brick` as def_ids; actual brick_id values in `src/bricks/*.tres` are `copper_ore`, `iron_ore`, `diamond_ore`.
- **Fix:** `TERRAIN_TO_BRICK_DROP` const uses the actual manifest names. Also noted that cobblestone/ores are not terrain voxels in terrain_generator.gd; extended the mapping to cover ICE_ID, WATER_ID, JUNGLE_GRASS_ID, SAVANNAH_GRASS_ID with sensible defaults.
- **Files modified:** src/world/dropped_item.gd
- **Commit:** 512716a

## Known Stubs

**DynamiteStick mesh** — `dynamite_handler.tscn` uses a placeholder `CylinderMesh` (small red cylinder). Art pass deferred to a future plan (Phase 2 art polish wave). The placeholder does not prevent the blast mechanics from working.

**DroppedItem mesh** — `dropped_item.tscn` uses a placeholder `BoxMesh` (0.5×0.5×0.5). Runtime `spawn_dropped_item()` does not yet replace this with the brick's actual mesh (BrickRegistry.get_definition(def_id).mesh). This is intentional Phase 2 scope: Phase 3 wires the inventory + pickup system and can update the mesh at that time. Items appear as plain cubes in Phase 2.

## Threat Surface Scan

No new network endpoints, auth paths, or schema changes introduced. All new surfaces are local simulation only:

| Flag | File | Description |
|------|------|-------------|
| threat_flag: T-11-01 mitigated | src/tools/dynamite_handler.gd | Single do_sphere replaces per-cell set_voxel (verified by grep) |
| threat_flag: T-11-02 mitigated | src/world/main_scene.gd | 30-cap on active RigidBody3D items enforced |
| threat_flag: T-11-03 mitigated | project.godot | time_budget_ms = 6 limits main-thread mesh-swap time |
| threat_flag: T-11-04 accepted | src/world/main_scene.gd | Unknown def_id falls back with push_warning (no crash) |

## Performance Contract Status

- TECH-1: Single `do_sphere` call — enforced and grep-verified
- TECH-2: Single `remove_bulk` call — enforced and grep-verified; `removed_bulk` signal coalesces dirty_chunks
- TECH-3: `voxel/threads/main/time_budget_ms = 6` in project.godot — mesh swaps spread across frames
- Tier-3 frame-time assertion: PENDING (manual:tier3) — Plan 15 runs the Motorola One Macro benchmark

## Self-Check: PASSED

Files exist:
- src/world/dropped_item.gd: FOUND
- src/world/dropped_item.tscn: FOUND
- src/tools/dynamite_handler.gd: FOUND
- src/tools/dynamite_handler.tscn: FOUND

Commits exist:
- 512716a (feat(02-11): DroppedItem): FOUND
- e295837 (feat(02-11): DynamiteHandler): FOUND

Tests:
- test_5m_radius_correctness: PASSED (1/1 headless)
- test_main_thread_time_within_budget: PENDING (manual:tier3)
