---
phase: 02-world-building-content
plan: "07"
subsystem: world-structures
tags: [structures, brick-template, procedural-generation, deterministic-placement, biomes]
dependency_graph:
  requires: [02-01, 02-04, 02-06]
  provides: [BrickTemplate, StructurePlacer, structure-templates]
  affects: [src/world/main_scene.gd, locale/en.po, tests/integration/test_structure_placement.gd]
tech_stack:
  added: []
  patterns:
    - Deterministic blueprint hash pattern (seed XOR cell coordinates → spawn decision)
    - Knuth multiplicative mixing for spatial hash stability
    - Resource-script-class .tres format for reloadable brick templates
key_files:
  created:
    - src/bricks/brick_template.gd
    - src/world/structure_placer.gd
    - assets/templates/villages/desert_village_a.tres
    - assets/templates/villages/desert_village_b.tres
    - assets/templates/villages/desert_village_c.tres
    - assets/templates/villages/snow_village_a.tres
    - assets/templates/villages/snow_village_b.tres
    - assets/templates/villages/snow_village_c.tres
    - assets/templates/villages/savannah_village_a.tres
    - assets/templates/villages/savannah_village_b.tres
    - assets/templates/villages/savannah_village_c.tres
    - assets/templates/temples/jungle_temple_a.tres
    - assets/templates/temples/jungle_temple_b.tres
    - assets/templates/temples/jungle_temple_c.tres
    - assets/templates/temples/underwater_temple_a.tres
    - assets/templates/temples/underwater_temple_b.tres
    - assets/templates/temples/underwater_temple_c.tres
    - assets/templates/shipwrecks/shipwreck_surface_a.tres
    - assets/templates/shipwrecks/shipwreck_surface_b.tres
    - assets/templates/shipwrecks/shipwreck_submerged_a.tres
    - assets/templates/shipwrecks/shipwreck_submerged_b.tres
    - assets/templates/dungeons/dungeon_a.tres
    - assets/templates/dungeons/dungeon_b.tres
    - assets/templates/dungeons/dungeon_c.tres
  modified:
    - locale/en.po
    - src/world/main_scene.gd
    - tests/integration/test_structure_placement.gd
decisions:
  - "Blueprint cell sizes: 128m village/shipwreck, 192m temple, 256m dungeon — matches CONTEXT.md D-08 rarity tiers"
  - "Dungeon Y anchor fixed at -32 (deep underground), no biome restriction (allowed_biomes empty)"
  - "Knuth multiplicative mixing (h * 2654435761) ^ value for hash — avalanche properties prevent correlated spawns"
  - "BiomeMap/BrickTemplate typed as RefCounted/Resource in headless-compatible code paths — class_name types cannot be resolved without explicit preload() in headless test mode"
  - "Spawn chances: village=0.60, temple=0.40, shipwreck=0.75, dungeon=0.50"
metrics:
  duration: "~4 hours (across session boundary)"
  completed_date: "2026-05-26"
  tasks_completed: 2
  files_created: 24
  files_modified: 3
---

# Phase 02 Plan 07: Structure Templates and Deterministic Placer Summary

Deterministic blueprint placer with 22 hand-authored BrickTemplate .tres files covering villages (desert/snow/savannah), temples (jungle/underwater), shipwrecks (surface/submerged), and dungeons — seeded hash ensures identical structure placement across all peers.

## Tasks Completed

| # | Task | Commit | Key Files |
|---|------|--------|-----------|
| 1 | BrickTemplate resource + 22 structure templates | 686d30b | src/bricks/brick_template.gd, assets/templates/**/*.tres (22 files) |
| 2 | StructurePlacer + GREEN tests + locale + main_scene wiring | 40e5716 | src/world/structure_placer.gd, locale/en.po, src/world/main_scene.gd, tests/integration/test_structure_placement.gd |

## Verification

- Full test suite: 84 passing, 14 pending (pre-existing), 0 failing
- `test_village_positions_deterministic_per_seed`: PASS — two placers with seed=42 produce identical spawn decisions across 100 blueprint cells × 4 structure types
- `test_no_overlapping_structures`: PASS — idempotency verified, duplicate-cell check clean, village spawn count within 10-100 / 100 range
- Glossary check: PASS — no "Lego"/"Minecraft"/"minifig" in any created/modified file

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] AABB format in .tres files used constructor form invalid for Godot's text scene parser**
- **Found during:** Task 1 verification / Task 2 test run (village count was 0)
- **Issue:** All 22 .tres files initially wrote `bbox = AABB(Vector3(0, 0, 0), Vector3(22, 5, 8))` — Godot's text resource parser requires 6 bare floats: `AABB(0, 0, 0, 22, 5, 8)`. The parser emitted "Expected float in constructor" and fell back to silently skipping template loads, causing village spawn count of 0 in tests.
- **Fix:** Applied perl regex across all 22 files to rewrite to the 6-float form.
- **Files modified:** All 22 assets/templates/**/*.tres
- **Commit:** 40e5716

**2. [Rule 3 - Blocking] GDScript class_name types not resolvable in headless test mode without preload()**
- **Found during:** Task 2 test run
- **Issue:** `StructurePlacer`, `BrickTemplate`, `BiomeMap` referenced by class_name in type annotations caused "Identifier not found" in headless GUT runner. GDScript in headless mode requires explicit `const X := preload("res://path.gd")` for type resolution.
- **Fix:** Added preload constants to structure_placer.gd, test_structure_placement.gd, and main_scene.gd. Changed typed parameters to use built-in base types (`Resource`, `RefCounted`) where custom class references would fail. Used `var biome: int = int(_biome_map.biome_at(...))` instead of `BiomeMap.Biome` enum type.
- **Files modified:** src/world/structure_placer.gd, tests/integration/test_structure_placement.gd, src/world/main_scene.gd
- **Commit:** 40e5716

**3. [Rule 1 - Bug] Blueprint cell size discrepancy between plan text and must_haves**
- **Found during:** Task 2 implementation
- **Issue:** Plan `must_haves` stated temple cell size as 128m but the objective text specified 192m. Dungeon stated 256m in must_haves but 128m in the objective. Resolved in favor of must_haves text (192m temples, 256m dungeons) as it aligned with CONTEXT.md D-08 rarity tiers.
- **Fix:** Implemented BLUEPRINT_CELL_M = {village: 128, temple: 192, shipwreck: 128, dungeon: 256}
- **Commit:** 40e5716

## Known Stubs

None. All 22 templates contain concrete brick placements, loot chests (chest_type + cell), and NPC spawn skin_variant slots. Patrol paths are empty `PackedVector3Array()` — this is intentional per plan (Plan 02-13 fills patrol paths). Loot table contents are empty per plan (Phase 3 fills loot tables; Phase 2 records chest_type + cell only).

## Threat Flags

None. StructurePlacer reads only from preloaded .tres resources (no file-system access at runtime), uses deterministic seeded RNG (no external input), and stamps bricks through BrickRegistry's validated API. Null-check guard on `get_definition(def_id)` (T-07-01 mitigation) prevents crash on unknown brick IDs.

## Self-Check: PASSED

Files verified to exist:
- FOUND: src/bricks/brick_template.gd
- FOUND: src/world/structure_placer.gd
- FOUND: assets/templates/villages/desert_village_a.tres
- FOUND: assets/templates/dungeons/dungeon_c.tres
- FOUND: locale/en.po
- FOUND: src/world/main_scene.gd
- FOUND: tests/integration/test_structure_placement.gd

Commits verified to exist:
- FOUND: 686d30b (Task 1)
- FOUND: 40e5716 (Task 2)
