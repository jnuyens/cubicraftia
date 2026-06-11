---
phase: 03-survival-loop
plan: 06
subsystem: chest-system
tags:
  - phase-3
  - chest
  - key
  - lock
  - double-chest
  - placement
dependency_graph:
  requires:
    - 03-02  # Inventory autoload (register_chest, apply_event UNLOCK, get_chest_contents)
    - 03-05  # InventorySlideIn + open_chest_mode stub
  provides:
    - ChestEntity placed entity (walk-up interact, lock/unlock, double-chest pairing)
    - ChestPanel sub-controller (chest grid stacked above builder grid + key slot)
    - ItemDefinition Resource class for non-brick items
    - 5 chest .tres + 4 key .tres
    - Inventory.set_double_chest_partner + unregister_chest + unregister_chest_half
    - InventorySlideIn.open_chest_mode full body (replaces Plan 03-05 stub)
  affects:
    - 03-08a  # loot tables (drops keys + chest contents)
    - 03-08b  # loot integration calls main_scene.spawn_chest → ChestEntity
    - 03-09   # food + strawberry items follow ItemDefinition pattern from this plan
tech_stack:
  added: []
  patterns:
    - ItemDefinition new Resource class for non-brick items (keys, cooked_food, strawberry)
    - ChestEntity polled-input pattern (polls ui_inventory_toggle in _process when in range)
    - set_input_as_handled() to prevent Builder.gd inventory_toggle from firing on same frame
    - ChestPanel duck-typed Control instantiation via preload pattern
    - ResourceLoader fallback path for ItemDefinitions (bypass manifest.json for same-wave safety)
key_files:
  created:
    - src/items/item_definition.gd (ItemDefinition Resource class — 70 lines)
    - src/bricks/key_bronze.tres
    - src/bricks/key_silver.tres
    - src/bricks/key_gold.tres
    - src/bricks/key_diamond.tres
    - src/bricks/chest_bronze.tres
    - src/bricks/chest_silver.tres
    - src/bricks/chest_gold.tres
    - src/bricks/chest_diamond.tres
    - src/world/chest_entity.gd (ChestEntity — 260+ lines)
    - src/world/chest_entity.tscn (StaticBody3D + WalkupPrompt + LockPlate + AnimationPlayer)
    - src/ui/chest_panel.gd (ChestPanel — 230+ lines)
  modified:
    - src/autoload/inventory.gd (set_double_chest_partner + unregister_chest + unregister_chest_half)
    - src/ui/inventory_slide_in.gd (open_chest_mode full body + _return_to_inventory_mode teardown)
decisions:
  - "ItemDefinition separate from BrickDefinition: keys/cooked_food/strawberry are inventory-only
     items with no placed 3D mesh; chests are placed bricks using BrickDefinition. Claude's
     discretion per 03-CONTEXT.md canonical-refs L153."
  - "chest .tres files bypass manifest.json: Phase 3 chest/item discovery uses ResourceLoader
     fallback path to avoid same-wave file conflicts with Plan 03-09 (food + strawberry items)."
  - "ChestEntity polled-input (not signal-based): polls Input.is_action_just_pressed in _process
     when builder is in range; calls get_viewport().set_input_as_handled() to prevent Builder.gd
     from also toggling inventory on the same frame. Per 03-PATTERNS.md L920-927 prescription."
  - "Chest meshes are placeholder BoxMesh tinted per tier (Phase 3 v1); distinct silhouettes
     deferred to v1 polish. Per CONTEXT D-03 + RESEARCH Assumption A6 + brick-mesh-null-phase2."
  - "unregister_chest_half added in addition to unregister_chest: double-chest break needs a
     method that severs the pairing + splits contents before the broken half is removed."
  - "ChestPanel instantiated duck-typed as Control (not ChestPanel) to avoid class-name
     resolution ordering issues in inventory_slide_in.gd headless parse context."
metrics:
  duration: 12 minutes
  completed: 2026-05-27
  tasks_completed: 3
  files_created: 13
  files_modified: 2
  total_files: 15
---

# Phase 3 Plan 06: Chest Layer — ChestEntity, ChestPanel, ItemDefinition, Keys, Tiers

**One-liner:** 5 chest tiers with correct slot counts, 4 key items (ItemDefinition Resource class), ChestEntity walk-up interact + lock/unlock + double-chest pairing, and ChestPanel sub-controller stacking chest grid above builder grid in the inventory slide-in.

## Chest Tier → Slot Count → Required Key

| Tier | Slot Count | Required Key | Grid Columns | Notes |
|------|-----------|--------------|--------------|-------|
| regular | 48 | (none — always unlocked) | 8 | Standard wooden chest |
| bronze | 48 | key_bronze | 8 | Banded metal, found in caves/lower-tier loot |
| silver | 54 | key_silver | 9 | Double-lid, found in jungle temples |
| gold | 60 | key_gold | 10 | Ornate, found in underwater temples + dungeons |
| diamond | 72 | key_diamond | 12 | Jewel-shaped, boss room reward |

Double-chest doubles both slot count and column count (e.g. double regular = 96 slots, 16 columns).

## Double-Chest Partner Detection Flow

```
ChestEntity._ready()
    │
    ├─ Inventory.register_chest(chunk_coord, tier, locked, contents)
    │
    └─ _check_for_double_chest_partner()
           │
           ├─ for offset in [±X, ±Z]:
           │     neighbour_state = Inventory.get_chest_state(chunk + offset)
           │     if neighbour_state.type == tier AND no existing partner:
           │         Inventory.set_double_chest_partner(my_chunk, neighbour_chunk) → true
           │         _double_chest_partner_chunk = neighbour_chunk
           │         _has_partner = true
           │         BREAK (first match wins — T-03-06-CH-02 cascade guard)
           │
           └─ If _has_partner: slide-in receives partner_chunk in open_chest_mode()
                ChestPanel doubles the grid columns and total slot count
```

## Inventory Extension Signatures

```gdscript
# Set partner link between two same-tier adjacent chests.
func set_double_chest_partner(chunk_a: Vector3i, chunk_b: Vector3i) -> bool

# Unregister a standalone chest; if paired, severs partner link first.
func unregister_chest(chunk_coord: Vector3i) -> void

# Break one half of a double-chest: splits contents proportionally,
# drops broken half's items (caller spawns DroppedItems), severs pairing,
# partner half becomes standalone with its share of items.
func unregister_chest_half(chunk_coord: Vector3i) -> void
```

## Chest Mesh Authoring Trade-off

Per CONTEXT D-03 ("5 distinct silhouettes") + RESEARCH Assumption A6 ("rough-art stand-ins ship in Phase 3"):

- **Phase 3 v1 (this plan):** All 5 chest .tres files reference `mesh = null` (placeholder). ChestEntity uses a BoxMesh tinted via `StandardMaterial3D.albedo_color` in the .tscn. The BrickDefinition `natural_colour_token` encodes the intended tier colour (brown/orange/silver/gold/light-blue).
- **Deferred:** Distinct `.glb` silhouette assets per D-03 (regular=wooden box, bronze=banded chunky, silver=double-lid, gold=ornate, diamond=faceted jewel) will replace the null mesh in a v1 polish pass.
- **Rationale:** Authoring 5 distinct `.glb` files is an art-pass task outside the code deliverables for Phase 3. The slot counts, key matching, lock/unlock UX, and double-chest logic all work correctly with the placeholder mesh.

## ItemDefinition Convention

Keys, cooked food, and strawberries use `ItemDefinition` (NOT `BrickDefinition`) because they are inventory-only items with no placed 3D mesh representation. Their `.tres` files live in `src/bricks/` alongside brick definitions for proximity, and are discovered via `ResourceLoader.load("res://src/bricks/<id>.tres")` fallback (bypassing `manifest.json` to avoid same-wave file conflicts with Plan 03-09).

Plan 03-09 (food + strawberry) follows the same pattern: new `.tres` files in `src/bricks/` using `ItemDefinition` as the script class.

## Open Carries

- **Plan 03-08a** (loot tables): defines which loot tables drop which key tiers and chest contents. The `initial_contents` @export on ChestEntity accepts the loot-rolled contents from Plan 03-08b.
- **Plan 03-08b** (loot integration): calls `main_scene.spawn_chest()` which instantiates ChestEntity, sets `tier`, `locked`, and `initial_contents` from the loot table roll.
- **Plan 03-09** (food + strawberry): follow the ItemDefinition pattern established here. `.tres` files in `src/bricks/`, same `ResourceLoader` fallback path.
- **Plan 03-11** (UAT): verify the full "approach chest → press E → key slot pulses → drop key → chest unlocks → contents revealed" loop manually, plus triple-chest configuration check.

## 03-VALIDATION.md Updates

| Test | Before 03-06 | After 03-06 |
|------|------------|------------|
| test_chest_state.gd (4 tests) | 3 PASS + 1 pending (ChestEntity) | 3 PASS + 1 pending (ClassDB.class_exists returns false in headless — known Godot 4 limitation for GDScript class_names not loaded by any scene) |
| test_chest_unlock_validation.gd (2 tests) | 2/2 PASS | 2/2 PASS (unchanged) |
| test_double_chest.gd (3 tests) | 3/3 PASS | 3/3 PASS (unchanged) |

Note: `test_chest_state.gd` test 2 (`test_four_key_types_exist`) checks `ClassDB.class_exists("ChestEntity")` which returns false in headless GUT mode for GDScript class_names not referenced by any loaded scene. This is the same constraint as `Engine.has_singleton()` found in Plan 03-02. The test gracefully `pending()`s in this case and is not a failure. Manual/UAT verification (Plan 03-11) will confirm the ChestEntity class is accessible in-game.

## Known Stubs

| Stub | File | Reason |
|------|------|--------|
| `mesh = null` in chest .tres | 5 chest .tres files | Art-pass deferred; placeholder BoxMesh in .tscn (Phase 3 v1 per RESEARCH Assumption A6) |
| `on_break()` double-chest path | chest_entity.gd | Calls `Inventory.unregister_chest_half()` which handles splitting; DroppedItem spawning from the broken half's contents depends on Plan 03-08b `spawn_dropped_item` being available in main_scene |
| `icon_path` in key .tres | 4 key .tres files | Icon assets (.png) not yet authored; InventorySlot will show no texture until Phase 3 polish |

## Threat Flags

None. No new network endpoints or auth paths introduced. Chest CRUD uses the existing WorldSave.save_chest parameterised queries. Input consumption via `set_input_as_handled()` is local-only (T-03-06-CH-04 accepts multi-builder open race as Phase 4 concern).

## Self-Check: PASSED

Files exist:
- src/items/item_definition.gd — FOUND
- src/bricks/key_bronze.tres — FOUND
- src/bricks/key_silver.tres — FOUND
- src/bricks/key_gold.tres — FOUND
- src/bricks/key_diamond.tres — FOUND
- src/bricks/chest_bronze.tres — FOUND
- src/bricks/chest_silver.tres — FOUND
- src/bricks/chest_gold.tres — FOUND
- src/bricks/chest_diamond.tres — FOUND
- src/world/chest_entity.gd — FOUND
- src/world/chest_entity.tscn — FOUND
- src/ui/chest_panel.gd — FOUND

Commits exist:
- 008a079 feat(03-06): ItemDefinition Resource + 4 key .tres + 4 chest .tres files — FOUND
- c60f063 feat(03-06): ChestEntity placed entity + Inventory double-chest/unregister methods — FOUND
- d92eb5e feat(03-06): ChestPanel sub-controller + InventorySlideIn chest mode body — FOUND

Key assertions:
- `grep -c "class_name ItemDefinition" src/items/item_definition.gd` → 1 ✓
- `ls src/bricks/key_*.tres | wc -l` → 4 ✓
- `ls src/bricks/chest_*.tres | wc -l` → 5 ✓
- `grep -l 'stud_profile = "concave_top"' src/bricks/chest_*.tres | wc -l` → 5 ✓ (D-08 invariant)
- `grep -c "class_name ChestEntity" src/world/chest_entity.gd` → 1 ✓
- `grep -c "class_name ChestPanel" src/ui/chest_panel.gd` → 1 ✓
- `grep -c "^func set_double_chest_partner\|^func unregister_chest" src/autoload/inventory.gd` → 3 ✓
- `grep -c "^func open_chest_mode" src/ui/inventory_slide_in.gd` → 1 ✓ (body filled, not stub)
- test suite: 134 passing, 3 failing (all pre-existing), 0 new failures ✓
- `bash scripts/glossary-check.sh` → OK ✓
