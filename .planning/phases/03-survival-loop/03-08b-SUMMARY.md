---
phase: 03-survival-loop
plan: 08b
subsystem: structure-integration
tags: [phase-3, structure-integration, chest-spawning, main-scene-integration, loot]

requires:
  - phase: 03-08a
    provides: "LootRoller.seed_for_chest + LootRoller.roll + 10 loot table .tres files"
  - phase: 03-06
    provides: "ChestEntity (chest_entity.tscn) + set_main_scene + initial_contents"
  - phase: 03-04
    provides: "main_scene.gd spawn_death_pile pattern + main_scene group precedent"

provides:
  - "StructurePlacer._stamp_chest_slot: two-step deterministic loot roll + ChestEntity spawn per template slot"
  - "StructurePlacer._load_structure_table / _load_chest_table / _world_to_chunk private helpers"
  - "BrickTemplate.structure_type @export field (merge-safe; empty default = no loot table)"
  - "main_scene.spawn_chest(tier, position, contents, locked) helper — integrates ChestEntity into world"
  - "add_to_group('main_scene') in main_scene._ready() for StructurePlacer group lookup"

affects:
  - 03-10 (creature death loot — separate from chest spawning; not affected by this plan)
  - 03-11 (starter chest uses spawn_chest helper; UAT verifies full lock/unlock loop)
  - Phase 4 (deterministic seed contract: world_seed + chunk_coord + table_id = same loot across failover)

tech-stack:
  added: []
  patterns:
    - "Two-step chest roll: structure_<type>.tres → chest tier → chest_<tier>.tres → contents"
    - "Deterministic seed: LootRoller.seed_for_chest(world_seed, chunk_coord, table_id) per slot"
    - "is_final flag on loot_chests entry → force tier=diamond + append key_diamond (dungeon boss room)"
    - "Locked status: locked = (tier != 'regular') per CONTEXT.md D-04"
    - "main_scene group: add_to_group('main_scene') + SceneTree.get_first_node_in_group lookup"
    - "Node3D duck-typing in spawn_chest (avoids class_name ChestEntity resolution ordering issue)"
    - "Object.get() 1-arg fix: 'field' in resource guard + direct @export property access"

key-files:
  created: []
  modified:
    - src/bricks/brick_template.gd
    - src/world/structure_placer.gd
    - src/world/main_scene.gd

key-decisions:
  - "structure-type-on-brick-template: BrickTemplate.structure_type @export var added in Plan 03-08b (Phase 2 templates have empty string default — graceful degradation: push_warning + return when empty). This is the smallest extension that lets StructurePlacer resolve the correct structure loot table without hardcoding type from TEMPLATE_DIRS reverse-lookup."
  - "loot-chests-field-not-chest-slots: BrickTemplate already has @export var loot_chests: Array (from Phase 2 02-07). Plan's chest_slots name was a planning alias. Implementation uses loot_chests with entries {chest_type, cell, is_final?}."
  - "is-final-optional-dict-key: is_final is an optional key on each loot_chests entry (chest_entry.get('is_final', false)). Phase 2 templates don't have this key — Dictionary.get() with default works correctly (vs Object.get() which only accepts 1 arg in GDScript 4)."
  - "node3d-duck-type-spawn-chest: spawn_chest casts to Node3D (not ChestEntity) to avoid class_name resolution ordering issue in main_scene.gd headless parse context — same pattern as VillageNpcScene + DroppedItem. Tier/locked/initial_contents set via Object.set() for @export var access."
  - "object-get-2arg-pre-existing-fix: Two pre-existing Object.get(field, default) calls in main_scene.spawn_village_npc were parse errors — auto-fixed as Rule 1 bugs (blocking script load). Replaced with 'field' in resource guard + direct property access. These caused main_scene.gd to fail --check-only before this plan's changes."

requirements-completed:
  - DOC-04
  - DOC-05

duration: 35min
completed: "2026-05-27"
---

# Phase 3 Plan 08b: Structure Chest-Slot Integration + main_scene.spawn_chest

**Wires Plan 03-08a's deterministic loot tables into the world generation pipeline: structure_placer rolls chest tiers + contents per template slot, main_scene.spawn_chest instantiates ChestEntity with pre-rolled loot at world positions.**

## Performance

- **Duration:** ~35 min
- **Completed:** 2026-05-27
- **Tasks:** 1
- **Files modified:** 3 (brick_template.gd, structure_placer.gd, main_scene.gd)

## Accomplishments

- `StructurePlacer._stamp_chest_slot` added: two-step deterministic loot roll (structure table → tier → chest table → contents) + main_scene.spawn_chest dispatch
- `BrickTemplate.structure_type` @export field added (empty default = no loot, graceful degradation)
- `main_scene.spawn_chest(tier, position, contents, locked)` helper instantiates ChestEntity duck-typed as Node3D
- `add_to_group("main_scene")` in `main_scene._ready()` as first action — ensures StructurePlacer can locate main_scene via group lookup before any structure stamps fire
- Dungeon final-room override: `chest_entry.get("is_final", false)` forces tier=diamond + appends `{def_id: "key_diamond", count: 1}` to rolled contents
- Locked status: `locked = (tier != "regular")` enforced at spawn_chest call site (D-04)
- Auto-fixed 2 pre-existing Object.get() parse errors in main_scene.spawn_village_npc (blocked --check-only before this plan)
- `godot --check-only --quit` exits 0; all 136 pre-passing tests still pass; 3 pre-existing failures unchanged; glossary check OK

## _stamp_chest_slot Body

```gdscript
func _stamp_chest_slot(template: Resource, chest_entry: Dictionary,
                       world_anchor: Vector3i) -> void:
    var local_cell: Vector3i = chest_entry.get("cell", Vector3i.ZERO) as Vector3i
    var world_pos: Vector3 = Vector3(world_anchor) + Vector3(local_cell)
    var chunk_coord: Vector3i = _world_to_chunk(world_pos)

    var structure_type: String = ""
    if template != null and "structure_type" in template:
        structure_type = str(template.structure_type)
    if structure_type.is_empty():
        push_warning("StructurePlacer._stamp_chest_slot: template has no structure_type — cannot roll loot.")
        return

    # Step 1 — Roll chest tier from structure loot table
    var structure_table: Resource = _load_structure_table(structure_type)
    var tier: String = ""
    if structure_table != null:
        var struct_table_id: String = structure_type
        if "table_id" in structure_table:
            struct_table_id = str(structure_table.table_id)
        var tier_seed: int = LootRollerScript.seed_for_chest(_world_seed, chunk_coord, struct_table_id)
        var tier_rng := RandomNumberGenerator.new()
        tier_rng.seed = tier_seed
        var tier_rolls: Array = LootRollerScript.roll(structure_table, tier_rng)
        if not tier_rolls.is_empty():
            tier = str(tier_rolls[0].get("def_id", "")).replace("chest_", "")
    if tier.is_empty():
        tier = chest_entry.get("chest_type", "regular")

    # Step 2 — Dungeon final-room override (is_final flag)
    var is_final: bool = chest_entry.get("is_final", false)
    if is_final:
        tier = "diamond"

    # Step 3 — Roll chest contents
    var contents: Array = []
    var contents_table: Resource = _load_chest_table(tier)
    if contents_table != null:
        var chest_table_id: String = "chest_" + tier
        if "table_id" in contents_table:
            chest_table_id = str(contents_table.table_id)
        var contents_seed: int = LootRollerScript.seed_for_chest(_world_seed, chunk_coord, chest_table_id)
        var contents_rng := RandomNumberGenerator.new()
        contents_rng.seed = contents_seed
        contents = LootRollerScript.roll(contents_table, contents_rng)

    # Step 4 — Dungeon final room: guaranteed diamond key
    if is_final:
        contents.append({"def_id": "key_diamond", "count": 1})

    # Step 5 — Spawn via main_scene
    var main_scene: Node = null
    var tree: SceneTree = Engine.get_main_loop() as SceneTree
    if tree != null:
        main_scene = tree.get_first_node_in_group("main_scene")

    if main_scene == null or not main_scene.has_method("spawn_chest"):
        push_warning("StructurePlacer._stamp_chest_slot: main_scene not found or lacks spawn_chest — chest at %s dropped." % str(world_pos))
        return

    var locked: bool = (tier != "regular")
    main_scene.spawn_chest(tier, world_pos, contents, locked)
```

## Dungeon Final-Room Override Evidence

```gdscript
# Step 2 — Dungeon final-room override (T-03-08b-INT-02 + D-04)
var is_final: bool = chest_entry.get("is_final", false)
if is_final:
    tier = "diamond"

# ...after rolling contents from chest_diamond.tres...

# Step 4 — Append guaranteed diamond key for dungeon final rooms (D-04).
if is_final:
    contents.append({"def_id": "key_diamond", "count": 1})
```

The `is_final` key is optional on each `loot_chests` entry in BrickTemplate. Phase 2 templates don't have it — `chest_entry.get("is_final", false)` correctly returns false for them. Dungeon boss-room templates should set `"is_final": true` on the final-room chest_slot when they are authored in Phase 2 template art passes.

## Per-Tier Key Sourcing Validation (D-04)

| Structure | Table | Tier Roll | Key Sourced From |
|-----------|-------|-----------|-----------------|
| mineshaft | structure_mineshaft.tres | 70% regular, 30% bronze | chest_bronze.tres → key_bronze |
| savannah_village | structure_savannah_village.tres | 80% regular, 20% bronze | chest_bronze.tres → key_bronze |
| jungle_temple | structure_jungle_temple.tres | 100% silver | chest_silver.tres → key_silver |
| underwater_temple | structure_underwater_temple.tres | 100% gold | chest_gold.tres → key_gold |
| dungeon (mid-room) | structure_dungeon.tres | 70% gold, 30% diamond | chest_gold/diamond.tres |
| dungeon (final-room) | is_final=true override | forced diamond | chest_diamond.tres + key_diamond appended |

All 4 key tiers sourced correctly per D-04.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Pre-existing Object.get() 2-arg parse errors in main_scene.spawn_village_npc**
- **Found during:** Task 1 (godot --check-only --quit)
- **Issue:** Two calls `template.get("npc_spawns", [])` and `npc_template.get("npc_spawns", [])` used `Object.get()` with a default argument, which is not valid in GDScript 4. This caused `main_scene.gd` to fail --check-only before any of this plan's changes.
- **Fix:** Replaced with `template.npc_spawns if "npc_spawns" in template else []` pattern — direct @export property access with in-operator guard. Same pattern used for `structure_type` and `loot_chests` in structure_placer.
- **Files modified:** `src/world/main_scene.gd`
- **Commit:** 2650a79 (same task commit)

**2. [Rule 1 - Bug] Plan referenced chest_slots but BrickTemplate has loot_chests**
- **Found during:** Task 1 (reading Phase 2 BrickTemplate source)
- **Issue:** PLAN.md and plan context consistently referenced `chest_slots: Array[Dictionary]` with `{position, is_final}` schema. BrickTemplate from Phase 2 (02-07) already has `@export var loot_chests: Array` with `{chest_type, cell}` schema.
- **Fix:** Used `loot_chests` field; `is_final` is treated as optional key on each entry (Dictionary.get with default works correctly).
- **Files modified:** `src/world/structure_placer.gd`
- **Commit:** 2650a79

**3. [Rule 2 - Missing] BrickTemplate.structure_type field not present in Phase 2**
- **Found during:** Task 1 (reading BrickTemplate source — no structure_type field)
- **Issue:** `_stamp_chest_slot` needs to know which loot table to load (structure_mineshaft.tres, structure_jungle_temple.tres, etc.). BrickTemplate had no field for this.
- **Fix:** Added `@export var structure_type: String = ""` to BrickTemplate (minimal, merge-safe, empty default). Graceful degradation: `push_warning + return` when empty.
- **Files modified:** `src/bricks/brick_template.gd`
- **Commit:** 2650a79

Total deviations: 3 auto-fixed (2 Rule 1 bugs, 1 Rule 2 missing). No scope creep.

## Open Carries to Plan 03-11

- Starter chest spawning (D-15) — NOT in this plan. Plan 03-11 calls `main_scene.spawn_chest("regular", spawn_pos, [], false)` once on first survival world open.
- UAT loop: "approach chest → press E → key slot pulses → drop key → chest unlocks → contents revealed" — Plan 03-11 human verification.
- Phase 2 template authors: set `structure_type = "mineshaft"` (etc.) on each .tres template, and optionally `is_final = true` on the dungeon boss-room loot_chests entry.

## 03-VALIDATION.md Updates

- `test_loot_roll.gd` → 2/3 PASS + 1 Risky (unchanged from Plan 03-08a — no test file modifications in this plan).
- Full suite: 136 passing, 3 failing (all pre-existing), 13 risky — no regressions.

## Task Commits

1. **Task 1: structure_placer chest-slot integration + BrickTemplate.structure_type + main_scene.spawn_chest + pre-existing bug fixes** — `2650a79` (feat)

## Self-Check: PASSED

- [x] `src/bricks/brick_template.gd` — FOUND, contains `@export var structure_type: String`
- [x] `src/world/structure_placer.gd` — FOUND, contains `func _stamp_chest_slot`
- [x] `src/world/main_scene.gd` — FOUND, contains `func spawn_chest` + `add_to_group("main_scene")`
- [x] `grep -c "func spawn_chest" src/world/main_scene.gd` → 1 ✓
- [x] `grep -c "func _stamp_chest_slot" src/world/structure_placer.gd` → 1 ✓
- [x] `grep -c "LootRollerScript.seed_for_chest\|LootRollerScript.roll" src/world/structure_placer.gd` → 4 ✓
- [x] `grep -c 'add_to_group("main_scene")' src/world/main_scene.gd` → 1 ✓
- [x] `godot --check-only --quit` exits 0 ✓
- [x] `test_loot_roll.gd` 2/3 PASS + 1 Risky (unchanged) ✓
- [x] Full suite: 136 PASS, 3 FAIL (pre-existing), 13 Risky ✓
- [x] `bash scripts/glossary-check.sh` → OK ✓
- [x] Commit 2650a79 — FOUND ✓

## Threat Flags

None. No new network endpoints or auth paths introduced. ChestEntity spawning is local-only; trust boundary is StructurePlacer → main_scene (same process, same host). Threat register T-03-08b-INT-01 through T-03-08b-SC mitigated per PLAN.md threat_model section.
