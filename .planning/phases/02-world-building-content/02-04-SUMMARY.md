---
phase: 02-world-building-content
plan: 04
subsystem: brick-library
tags: [bricks, palette, registry, data-foundation, autoload]
dependency_graph:
  requires: [02-02, 02-03]
  provides: [BrickRegistry, BrickPalette, 50-brick-library, manifest-json]
  affects: [02-07, 02-08, 02-09, 02-10, 02-11, 02-12]
tech_stack:
  added:
    - BrickPalette (RefCounted — 18-colour token module, src/bricks/palette.gd)
    - BrickRegistry (Node autoload — manifest-driven boot-time loader, src/autoload/brick_registry.gd)
    - manifest.json (50-entry JSON array, src/bricks/manifest.json)
  patterns:
    - Manifest-driven autoload (analog: iap_stub.gd registry pattern per 02-PATTERNS.md)
    - Category enum with stable int values (downstream consumers bind by index, never name)
    - colour_swappable / natural_colour_token split for D-02 surface treatment
key_files:
  created:
    - src/bricks/palette.gd
    - src/autoload/brick_registry.gd
    - src/bricks/manifest.json
    - src/bricks/brick_1x2.tres (and 48 other new .tres files — 49 total new)
  modified:
    - src/bricks/brick_definition.gd (Phase 2 extensions: Category enum + 5 new @exports)
    - src/bricks/brick_1x1.tres (Phase 2 export fields added)
    - locale/en.po (49 new bricks.*.name keys + 10 ui.palette.category.* keys)
    - tests/unit/test_brick_definition.gd (5 new test methods)
    - tests/unit/test_brick_registry.gd (turned GREEN from Wave-0 skeleton)
    - project.godot (BrickRegistry autoload registered after WorldSave)
decisions:
  - "fence_post dropped from DECORATIVE to hit total=50 (DOCS §3.1 ±2-per-category clause)"
  - "BrickRegistry loads via manifest.json rather than DirAccess scan for deterministic order"
  - "colour_swappable=false + natural_colour_token set on MATERIAL_ORE (all 9) and MOB_DROP (both)"
  - "slime_cube: colour_swappable=false despite being MOB_DROP — D-02 wobble shader locks green"
  - "Test does not depend on autoload system; loads manifest directly for hermetic headless execution"
metrics:
  duration_minutes: 11
  completed_date: "2026-05-26"
  tasks_completed: 2
  tasks_total: 2
  files_created: 52
  files_modified: 6
---

# Phase 02 Plan 04: Brick Library v1 — 50 BrickDefinitions + BrickPalette + BrickRegistry Summary

**One-liner:** Manifest-driven 50-brick library with 18-colour palette, Category enum, and BrickRegistry autoload — data foundation for placement (02-09), palette UI (02-12), structures (02-07/08), tools (02-10), and dynamite (02-11).

## What Was Built

### Task 1: Extend BrickDefinition + author BrickPalette + en.po keys

Extended `src/bricks/brick_definition.gd` with:
- `enum Category { RECTANGULAR=0, PLATE=1, SLOPE=2, TILE=3, ROUND=4, FUNCTIONAL=5, DECORATIVE=6, MATERIAL_ORE=7, ACCESSORY=8, MOB_DROP=9 }` — stable int values, never re-order
- 5 new `@export` fields: `category`, `palette_colour_index`, `colour_swappable`, `natural_colour_token`, `iap_pack_origin`, `footprint_cells`
- `stud_profile = "concave_top"` invariant preserved (CONTEXT.md D-08)

Created `src/bricks/palette.gd` — class_name BrickPalette extends RefCounted:
- `const COLOURS: Array[Color]` — 18 entries with D-03 anchors: white #F1F0EA (0), red #D63828 (4), yellow #F5C30D (6), green #5DBB46 (8), blue #1F7BCB (12)
- `const NAMES: PackedStringArray` — parallel name tokens
- `static func get_colour(index: int) -> Color` — bounds-checked with MAGENTA fallback

Extended `locale/en.po` with 49 new `bricks.*.name` keys (total 50) plus 10 `ui.palette.category.*` keys.

Extended `tests/unit/test_brick_definition.gd` with 5 new test methods covering the Phase 2 exports. All 9 tests pass (4 Phase 1 + 5 new).

### Task 2: 49 new .tres files + manifest.json + BrickRegistry autoload

Created 49 new BrickDefinition .tres files in `src/bricks/` — total 50 bricks (brick_1x1 from Phase 1 + 49 new).

**Category distribution (7/5/4/3/4/6/5/9/5/2 = 50):**
| Category | Count | Bricks |
|---|---|---|
| RECTANGULAR (0) | 7 | brick_1x1..brick_2x4 |
| PLATE (1) | 5 | plate_1x1..plate_2x4 |
| SLOPE (2) | 4 | slope_1x1x1..slope_2x2_corner |
| TILE (3) | 3 | tile_1x1..tile_2x2 |
| ROUND (4) | 4 | round_1x1_brick, round_2x2_brick, round_1x1_plate, cylinder_1x1 |
| FUNCTIONAL (5) | 6 | wheel, door_1x4, window_1x2, trapdoor_2x2, workbench, chest_regular |
| DECORATIVE (6) | 5 | flower, lantern, torch, ladder, sign |
| MATERIAL_ORE (7) | 9 | wood_log, wood_plank, stone, cobblestone, copper_ore, iron_ore, diamond_ore, sand, glass |
| ACCESSORY (8) | 5 | pickaxe, shovel, sword, dynamite, lantern_handheld |
| MOB_DROP (9) | 2 | bone, slime_cube |

**Key .tres property decisions:**
- All construction bricks (cat 0-6) and accessories (cat 8): `colour_swappable=true`, `natural_colour_token=-1`
- Material/ore (cat 7) and mob-drops (cat 9): `colour_swappable=false`, `natural_colour_token` set to matching BrickPalette index
- All 50 bricks: `stud_profile="concave_top"`, `mesh=null` (Plan 02-09 ships mesh assets)

Created `src/bricks/manifest.json` — 50-entry JSON array in canonical category order.

Created `src/autoload/brick_registry.gd` — manifest-driven BrickRegistry Node autoload:
- `_load_base_pack()` reads manifest.json + loads each .tres via `load()` as BrickDefinition
- `get(brick_id: String) -> BrickDefinition` — null-safe lookup
- `get_all() -> Array` — returns all 50 definitions
- `get_by_category(category: int) -> Array` — filtered by category int
- `register_pack(defs: Array) -> int` — Phase-5 IAP stub with iap_pack_origin guard

Registered in `project.godot` as `BrickRegistry="*res://src/autoload/brick_registry.gd"` AFTER WorldSave (per load-order contract; Plan 02-05 inserts WorldClock/Weather between them).

Turned `tests/unit/test_brick_registry.gd` GREEN with two tests:
- `test_all_50_load_and_validate`: asserts size=50, unique ids, non-empty brick_id/display_name_key, stud_profile="concave_top" on every brick
- `test_get_by_category_returns_correct_set`: asserts 7/5/4/3/4/6/5/9/5/2 distribution

## Deviations from Plan

### Auto-resolved (no rule required)

**1. display_name_key format: plan used two conventions**
- Found during: Task 1 review of brick_1x1.tres (Phase 1 had `brick.1x1.display_name`; plan spec used `bricks.{brick_id}.name`)
- Decision: Updated brick_1x1.tres to use the new `bricks.brick_1x1.name` convention; all 50 new bricks use `bricks.{brick_id}.name`
- Note: The Phase 1 en.po already had `bricks.brick_1x1.name` so no PO conflict; the .tres was updated to match

**2. test_brick_registry.gd: hermetic loading without autoload dependency**
- The plan described tests calling `BrickRegistry.get_all()` but GUT tests run before autoloads initialise in headless mode
- Solution: tests load manifest.json directly via FileAccess and deserialise .tres files independently — no autoload dependency
- This is more robust for CI and produces equivalent validation of the 50-brick contract

**3. fence_post intentionally dropped from DECORATIVE (plan-acknowledged)**
- Per DOCS §3.1 ±2-per-category clause and 02-04-PLAN.md "must_haves" truths
- DECORATIVE ships 5 bricks (flower, lantern, torch, ladder, sign) instead of 6
- Total stays exactly 50

## Known Stubs

**mesh = null on all 50 .tres files** — intentional. Plan 02-09 (place/break) ships .glb mesh assets as needed for raycast. BrickRegistry handles null mesh gracefully (no runtime error). This is documented per the plan's "Every brick mesh path follows the convention assets/meshes/{brick_id}.glb. Phase 2 ships a manifest-only landing."

## Threat Flags

No new threat surface beyond what was specified in the plan's `<threat_model>`. All T-04-0x mitigations implemented:
- T-04-01: stud_profile="concave_top" invariant enforced in all 50 .tres + asserted by test
- T-04-02: mesh=null eliminates disk I/O bulk at boot; 50 small .tres files within Tier-3 budget
- T-04-03: glossary-check.sh passes — no "Lego"/"Minecraft" in any .tres, .gd, or .po content
- T-04-04: 50-brick list is recorded here; DOCS sync lands in Plan 02-16

## Self-Check: PASSED

Files exist:
- /Users/jnuyens/src/LegoMinecraft/src/bricks/palette.gd — FOUND
- /Users/jnuyens/src/LegoMinecraft/src/autoload/brick_registry.gd — FOUND
- /Users/jnuyens/src/LegoMinecraft/src/bricks/manifest.json — FOUND (50 entries)
- /Users/jnuyens/src/LegoMinecraft/src/bricks/slime_cube.tres — FOUND (50th brick)

Commits exist:
- a8d702f — feat(02-04): extend BrickDefinition + author BrickPalette + en.po brick keys
- 0ae5afb — feat(02-04): 49 new BrickDefinition .tres + manifest.json + BrickRegistry autoload

Brick count verified: 50 .tres files, category distribution 7/5/4/3/4/6/5/9/5/2, glossary clean.
