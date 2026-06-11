---
phase: 02-world-building-content
plan: "08"
subsystem: world-generation
tags: [mineshafts, multipass, voxel, procedural, brick-template]
dependency_graph:
  requires: [02-01, 02-02, 02-04, 02-06, 02-07]
  provides: [mineshaft-generator, mineshaft-templates]
  affects: [src/world/multipass_generator.gd, src/world/terrain.tscn, assets/templates/mineshafts/]
tech_stack:
  added: [VoxelGeneratorMultipassCB]
  patterns: [multipass-two-pass, depth-gated-structure-placement, knuth-multiplicative-hash]
key_files:
  created:
    - src/world/multipass_generator.gd
    - assets/templates/mineshafts/corridor_straight.tres
    - assets/templates/mineshafts/corridor_t_junction.tres
    - assets/templates/mineshafts/corridor_cross.tres
    - assets/templates/mineshafts/corridor_dead_end.tres
    - assets/templates/mineshafts/corridor_room.tres
    - tests/unit/test_mineshaft_generator.gd
  modified:
    - src/world/terrain.tscn
    - src/world/main_scene.tscn
decisions:
  - "VoxelToolMultipassGenerator.set_voxel() takes (pos: Vector3i, v: int) not (v, x, y, z) — fixed from API docs"
  - "VoxelToolMultipassGenerator uses get_main_area_min/max for column bounds, not get_origin/get_size"
  - "terrain.tscn modified (not main_scene.tscn) because VoxelTerrain node lives in terrain.tscn; main_scene.tscn comment updated"
  - "StudGrid brick placements deferred to Phase 4 — push_warning trace documents intent; call_deferred guards main thread (T-08-01)"
  - "pass_count uses property assignment; set_pass_extent_blocks(1,2) call after"
  - "Mineshaft tests use Object type hints instead of MineshaftGenerator to avoid class_name resolution issues in headless GUT"
metrics:
  duration_minutes: 35
  completed: "2026-05-26"
  tasks_completed: 2
  files_created: 7
  files_modified: 2
  tests_added: 12
  tests_passing: 12
---

# Phase 2 Plan 08: Mineshaft Generator Summary

**One-liner:** VoxelGeneratorMultipassCB two-pass mineshaft system — pass 0 base terrain + pass 1 depth-gated corridor carving from a 5-piece BrickTemplate library.

## What Was Built

### Task 1: 5 Mineshaft BrickTemplate .tres Files

Five corridor/junction pieces authored as `BrickTemplate` Resources in `assets/templates/mineshafts/`:

| Piece | Size | Connections | Loot |
|-------|------|-------------|------|
| `corridor_straight.tres` | 3×4×8m | 2 ends | none |
| `corridor_t_junction.tres` | 12×4×12m | 3 exits | none |
| `corridor_cross.tres` | 12×4×12m | 4 exits | none |
| `corridor_dead_end.tres` | 3×4×8m | 1 entrance | regular chest (DOCS §4.4) |
| `corridor_room.tres` | 6×4×6m | open | bronze chest (DOCS §4.4) |

All pieces:
- Use `terrain_overrides` for stone floor/ceiling and air interior carving (RESEARCH Pitfall 1 compliance — corridor geometry is TERRAIN voxels, not stud-grid bricks)
- Use `bricks` entries for decorations: support beams (`brick_2x4` brown), ladders, lanterns
- `allowed_biomes = []` — depth-gated by multipass_generator, not biome-gated
- SPDX headers present on all .tres files

### Task 2: VoxelGeneratorMultipassCB + Terrain Pipeline Wiring

`src/world/multipass_generator.gd` extends `VoxelGeneratorMultipassCB` with:

**Pass 0 (extent 0) — base terrain:**
- Replicates terrain_generator.gd height-map + biome logic using `VoxelToolMultipassGenerator.get_main_area_min/max()` and `set_voxel(Vector3i, int)`
- Six-biome classification via BiomeMap; ocean water fill; stone subsurface

**Pass 1 (extent 2) — mineshaft corridor carving:**
- Depth gate: `area_min.y >= MINESHAFT_DEPTH_GATE (-8)` returns early (surface terrain unaffected)
- 35% spawn chance per deep column (CONTEXT.md D-08: "common while digging deeper stone layers")
- Deterministic hash (`_hash_chunk`) uses same Knuth multiplicative mix as `structure_placer._hash` (T-08-03 — peers compute identical placement)
- Picks 1 of 5 pieces + 0..3 quarter-turn rotation from hash
- Stamps `terrain_overrides` via `voxel_tool.set_voxel()` within editable area bounds
- StudGrid brick placements deferred to main thread via `call_deferred("_queue_stud_bricks", ...)` (T-08-01 — worker thread isolation)

**Terrain wiring:**
- `terrain.tscn`: `generator` sub_resource type changed from `VoxelGeneratorScript` to `VoxelGeneratorMultipassCB`, script pointed to `multipass_generator.gd`
- `main_scene.tscn`: comment updated documenting the multipass wiring

**Tests:**
- `tests/unit/test_mineshaft_generator.gd`: 12 new GREEN tests
  - Pieces load (5 × BrickTemplate)
  - Depth gate constant (-8), blocks/allows by Y coordinate
  - Hash determinism + coord sensitivity
  - Spawn chance ~35% over 1000 samples
  - rotate_cell identity + quarter-turn rotation
  - Dead-end has regular chest; room has bronze chest
  - All pieces have empty allowed_biomes

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] VoxelToolMultipassGenerator API mismatch**
- **Found during:** Task 2 implementation, confirmed by Godot headless editor parse errors
- **Issue:** Plan action specified `voxel_tool.set_voxel(value, x, y, z)` but the actual `VoxelTool.set_voxel()` API takes `(pos: Vector3i, v: int)` (confirmed from `doc/classes/VoxelTool.xml`)
- **Fix:** Updated all `set_voxel` calls to use `Vector3i(x, y, z)` form; replaced `get_origin()/get_size()` with `get_main_area_min()/get_main_area_max()` per `VoxelToolMultipassGenerator.xml`
- **Files modified:** `src/world/multipass_generator.gd`
- **Commit:** ec1993f

**2. [Rule 2 - Architectural Adjustment] terrain.tscn instead of main_scene.tscn**
- **Found during:** Task 2 — VoxelTerrain node lives in `terrain.tscn`, not `main_scene.tscn`
- **Issue:** Plan's `files_modified` listed `main_scene.tscn` for the VoxelTerrain generator swap, but the `[node name="Terrain" type="VoxelTerrain"]` is defined in `terrain.tscn` (instanced into main_scene)
- **Fix:** Modified `terrain.tscn` for the actual generator swap; updated `main_scene.tscn` comment only
- **Files modified:** `src/world/terrain.tscn` (generator swap), `src/world/main_scene.tscn` (comment only)
- **Commit:** ec1993f

**3. [Rule 2 - Missing] Test type hints use Object to avoid headless class_name resolution**
- **Found during:** Task 2 testing — `MineshaftGenerator` type hints in test file caused parse errors in headless GUT because `VoxelGeneratorMultipassCB` C++ class requires the GDExtension to be fully registered before class_name resolution
- **Fix:** Test file uses `Object` return type for `_make_generator()` instead of `MineshaftGenerator`; `MineshaftGeneratorScript = preload(...)` for constants access
- **Files modified:** `tests/unit/test_mineshaft_generator.gd`
- **Commit:** ec1993f

## Known Stubs

**StudGrid brick placements deferred to Phase 4:**
- `_queue_stud_bricks()` in `multipass_generator.gd` emits `push_warning` instead of calling `StudGrid.place()`. The intent is recorded but the actual stud-grid bricks (support beams, ladders, lanterns) are not placed until Phase 4 wires the mineshaft manager.
- This is intentional per the plan's architecture — the multipass worker thread cannot safely call into the Node tree (T-08-01). Phase 4's MineshaftManager autoload will consume the queued events.
- File: `src/world/multipass_generator.gd`, method `_queue_stud_bricks()`
- Future plan: 04-xx MineshaftManager

## Threat Surface Scan

No new network endpoints, auth paths, file access patterns, or schema changes introduced. All generation runs deterministically server/client-side from world seed.

## Threat Mitigations Applied

| Threat ID | Mitigation Applied |
|-----------|-------------------|
| T-08-01 | `call_deferred("_queue_stud_bricks", ...)` — StudGrid mutations always on main thread |
| T-08-02 | `MINESHAFT_SPAWN_CHANCE = 0.35` — tunable constant; T-08-02 accepted per plan threat register |
| T-08-03 | Same Knuth hash as `structure_placer._hash` — both peers compute identical piece/rotation |

## Pre-existing Test Failure (Out of Scope)

`tests/unit/test_stud_grid.gd::test_remove_bulk_removes_multiple` — 1 pre-existing failure from Plan 02-09 (commit `b03615b`). Not caused by Plan 02-08. Plan 02-08 introduced 0 new test failures and 12 new passing tests.

## DOC-02 Contract Completion

Plans 02-07 (villages, temples, shipwrecks, dungeons) + 02-08 (mineshafts) together complete the DOC-02 generated-structures contract. All 5 structure types from DOCS §2 now have implementations:
- Villages, temples, shipwrecks, dungeons: blueprint pattern (Plan 02-07)
- Mineshafts: multipass corridor-carving pattern (Plan 02-08)

## Self-Check

### Files Exist
- [x] `src/world/multipass_generator.gd` — FOUND
- [x] `assets/templates/mineshafts/corridor_straight.tres` — FOUND
- [x] `assets/templates/mineshafts/corridor_t_junction.tres` — FOUND
- [x] `assets/templates/mineshafts/corridor_cross.tres` — FOUND
- [x] `assets/templates/mineshafts/corridor_dead_end.tres` — FOUND
- [x] `assets/templates/mineshafts/corridor_room.tres` — FOUND
- [x] `tests/unit/test_mineshaft_generator.gd` — FOUND
- [x] `src/world/terrain.tscn` — modified (generator swapped)
- [x] `src/world/main_scene.tscn` — modified (comment updated)

### Commits Exist
- [x] `ef8aa11` — feat(02-08): 5 mineshaft BrickTemplate .tres pieces
- [x] `ec1993f` — feat(02-08): VoxelGeneratorMultipassCB mineshaft generator + terrain pipeline

### Template Count
Verified: exactly 5 .tres files in `assets/templates/mineshafts/` (pass: `ls *.tres | wc -l` = 5)

### Multipass Experimental Warning
`VoxelGeneratorMultipassCB` is marked `is_experimental="true"` in the godot_voxel XML docs (addon commit 4a9d311). This is expected and acceptable per 02-MULTIPASS-NOTE.md. The API is confirmed stable enough for production use in Cubicraftia v1.

## Self-Check: PASSED
