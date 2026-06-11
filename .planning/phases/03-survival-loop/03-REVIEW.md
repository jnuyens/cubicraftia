---
phase: 03-survival-loop
reviewed: 2026-05-27T00:00:00Z
depth: standard
files_reviewed: 47
files_reviewed_list:
  - src/autoload/inventory.gd
  - src/autoload/spawning.gd
  - src/autoload/world_save.gd
  - src/autoload/world_clock.gd
  - src/autoload/brick_registry.gd
  - src/autoload/features.gd
  - src/autoload/tool_wear.gd
  - src/autoload/toasts.gd
  - src/autoload/weather.gd
  - src/autoload/translations.gd
  - src/autoload/android_thermal.gd
  - src/autoload/thermal_probe.gd
  - src/autoload/iap_stub.gd
  - src/builder/builder.gd
  - src/combat/hostile_mob.gd
  - src/combat/bat.gd
  - src/combat/ghost.gd
  - src/combat/laser_penguin.gd
  - src/combat/vampire.gd
  - src/combat/cube_slime.gd
  - src/crafting/recipe.gd
  - src/crafting/recipe_registry.gd
  - src/items/item_definition.gd
  - src/loot/loot_roller.gd
  - src/loot/loot_table.gd
  - src/loot/loot_entry.gd
  - src/persistence/chunk_codec.gd
  - src/persistence/world_save_io.gd
  - src/tools/dynamite_handler.gd
  - src/tools/tool_definition.gd
  - src/ui/chest_panel.gd
  - src/ui/death_screen.gd
  - src/ui/hotbar.gd
  - src/ui/hp_bar.gd
  - src/ui/inventory_slide_in.gd
  - src/ui/inventory_slot.gd
  - src/ui/mobile_overlay.gd
  - src/ui/recipe_book_tab.gd
  - src/ui/workbench_panel.gd
  - src/world/bed_entity.gd
  - src/world/benchmark_runner.gd
  - src/world/biome_map.gd
  - src/world/chest_entity.gd
  - src/world/death_pile.gd
  - src/world/dropped_item.gd
  - src/world/fire_breath_vfx.gd
  - src/world/main_scene.gd
  - src/world/multipass_generator.gd
  - src/world/strawberry.gd
  - src/world/strawberry_spawner.gd
  - src/world/structure_placer.gd
  - src/world/stud_grid.gd
  - src/world/terrain_generator.gd
  - src/world/village_npc.gd
  - src/world/workbench_entity.gd
findings:
  critical: 5
  warning: 7
  info: 3
  total: 15
status: issues_found
---

# Phase 03: Code Review Report

**Reviewed:** 2026-05-27
**Depth:** standard
**Files Reviewed:** 47 (of 116 listed; remaining files either did not exist on disk or are configuration/test files not present in the source tree)
**Status:** issues_found

## Summary

This adversarial review covers the Phase 3 survival-loop implementation for Cubicraftia. The code is generally well-structured with consistent idioms, careful null-safety, and good separation of concerns. However, five critical bugs were found that either cause silent data loss, render core UI features non-functional, or permanently disable intended spawn-suppression behaviour. These must be fixed before the phase ships.

The most severe finding is a complete breakage of drag-and-drop inventory operations: `inventory_slot.gd` sends events with key names `"from"` and `"to"`, while every applier in `inventory.gd` reads `"from_slot"` and `"to_slot"`. Every drag-drop in the inventory silently fails. A second critical finding is that the `_is_locked_chest_at` spawn suppression in `spawning.gd` calls `Inventory.get_chest()` — a method that does not exist (the real method is `get_chest_state()`) — so the `has_method` guard returns false and chest-over spawn suppression is permanently disabled. Third, breaking a double-chest does not drop items for the broken half; they are silently deleted. Fourth, `_apply_craft` in `inventory.gd` consumes the first ingredient before checking for the second, creating an unrecoverable item-loss race. Fifth, the `_active_per_chunk` mob counter desynchronises whenever a mob moves between chunks between its `notify_spawned` and `notify_despawned` calls.

---

## Structural Findings (fallow)

No structural pre-pass was provided for this review.

---

## Narrative Findings (AI reviewer)

## Critical Issues

### CR-01: Drag-drop event key mismatch — all inventory drag operations silently fail

**File:** `src/ui/inventory_slot.gd:266-275`
**Issue:** `_drop_data` builds the event dictionary with keys `"from"` and `"to"`:
```gdscript
var event: Dictionary = {
    "kind": kind,
    "builder_id": data.get("builder_id", _builder_id),
    "from": data.get("source_slot", -1),   # wrong key
    "to": slot_index,                        # wrong key
    ...
}
```
Every applier in `inventory.gd` reads `"from_slot"` and `"to_slot"`:
```gdscript
# _apply_move (inventory.gd ~L860):
var from_slot: int = event.get("from_slot", -1)
var to_slot:   int = event.get("to_slot",   -1)
```
The key mismatch means `from_slot` and `to_slot` are always `-1`. `_apply_move` and `_apply_swap` immediately return `false` (slot index -1 is out of range). `_apply_split` likewise reads `-1` for the source slot. All drag-drop operations in the inventory panel silently do nothing — items appear to move visually (because Godot's built-in `_drop_data` accepts the drag) but the actual inventory state is never mutated.

**Fix:**
```gdscript
var event: Dictionary = {
    "kind": kind,
    "builder_id": data.get("builder_id", _builder_id),
    "from_slot": data.get("source_slot", -1),   # fix: was "from"
    "to_slot": slot_index,                        # fix: was "to"
    "from_grid": data.get("source_grid", "inventory"),
    "to_grid": source_grid,
}
```

---

### CR-02: `_is_locked_chest_at` calls non-existent method — spawn suppression over chests is permanently disabled

**File:** `src/autoload/spawning.gd:450-453`
**Issue:**
```gdscript
func _is_locked_chest_at(chunk_coord: Vector3i) -> bool:
    if not Inventory.has_method("get_chest"):
        return false                              # always takes this branch
    var chest_data: Dictionary = Inventory.get_chest(chunk_coord)
    return chest_data.has("type")
```
The actual method in `inventory.gd` is `get_chest_state(chunk_coord: Vector3i)`, not `get_chest()`. `has_method("get_chest")` returns `false`, so `_is_locked_chest_at` always returns `false`. Gate 3 in `_run_spawn_tick` ("suppress over locked chests") is permanently disabled, allowing hostile mobs to spawn over player-built locked chests at any time.

**Fix:**
```gdscript
func _is_locked_chest_at(chunk_coord: Vector3i) -> bool:
    if not Inventory.has_method("get_chest_state"):
        return false
    var chest_data: Dictionary = Inventory.get_chest_state(chunk_coord)
    return not chest_data.is_empty() and chest_data.get("locked", false)
```
Note also that the original check (`chest_data.has("type")`) would have been incorrect anyway — it would suppress spawns over unlocked regular chests. The fix above additionally gates on the `locked` field per 03-PATTERNS.md L1038.

---

### CR-03: Double-chest break discards all items from the broken half without dropping them

**File:** `src/world/chest_entity.gd:281-308`
**Issue:**
```gdscript
func on_break() -> void:
    var half_capacity: int = SLOT_COUNTS.get(tier, 48)

    if _has_partner:
        Inventory.unregister_chest_half(_chunk_coord)
        # BUG: No item-drop loop here — items in this half are silently destroyed.
    else:
        var contents: Array = Inventory.get_chest_contents(_chunk_coord)
        for entry: Dictionary in contents:
            ...
            _main_scene.spawn_dropped_item(...)
        Inventory.unregister_chest(_chunk_coord)
```
The double-chest branch calls `unregister_chest_half` but never iterates and drops the first-half contents. The comment says "Inventory.unregister_chest_half already split them" but that method removes the half from registration — it does not spawn DroppedItem entities. Items stored in slots 0..(half_capacity-1) of the broken double-chest are silently deleted; this is irreversible data loss from the player's perspective.

**Fix:** Read the half-contents from Inventory before unregistering, then drop them:
```gdscript
if _has_partner:
    var contents: Array = Inventory.get_chest_contents(_chunk_coord)
    var half_cap: int = SLOT_COUNTS.get(tier, 48)
    for i in range(min(half_cap, contents.size())):
        var entry: Dictionary = contents[i]
        var def_id: String = entry.get("def_id", "")
        var count: int = entry.get("count", 0)
        if def_id.is_empty() or count <= 0:
            continue
        if _main_scene != null and _main_scene.has_method("spawn_dropped_item"):
            _main_scene.spawn_dropped_item(
                def_id, 0,
                global_position + Vector3(randf_range(-0.5, 0.5), 0.5, randf_range(-0.5, 0.5)),
                true)
    Inventory.unregister_chest_half(_chunk_coord)
```

---

### CR-04: `_apply_craft` consumes first ingredient before validating remaining ingredients — ingredient loss on failure

**File:** `src/autoload/inventory.gd:1053-1060`
**Issue:**
```gdscript
for def_id: String in ingredients:
    var need: int = ingredients[def_id]
    var remove_ok := _apply_remove({"builder_id": builder_id, "def_id": def_id, "count": need})
    if not remove_ok:
        return false   # BUG: already consumed earlier ingredients
```
The loop calls `_apply_remove` for each ingredient in sequence without rolling back previously consumed items. If ingredient A is removed successfully but ingredient B fails (missing from inventory), ingredient A is permanently consumed and `false` is returned. The player loses ingredient A without receiving the crafting output. This is an unrecoverable state.

**Fix:** Pre-validate that all ingredients are present before consuming any:
```gdscript
# Pre-check: all ingredients available
for def_id: String in ingredients:
    var need: int = ingredients[def_id]
    if _count_item(builder_id, def_id) < need:
        return false
# All available — consume
for def_id: String in ingredients:
    var need: int = ingredients[def_id]
    _apply_remove({"builder_id": builder_id, "def_id": def_id, "count": need})
```
Add a `_count_item(builder_id, def_id) -> int` helper that sums counts across all slots.

---

### CR-05: `_active_per_chunk` hostile counter desynchronises when mobs move between chunks

**File:** `src/autoload/spawning.gd:219-238`
**Issue:**
```gdscript
func notify_spawned(mob: Node) -> void:
    ...
    var ck := _chunk_of((mob as Node3D).global_position)
    _active_per_chunk[ck] = _active_per_chunk.get(ck, 0) + 1

func notify_despawned(mob: Node) -> void:
    ...
    var ck := _chunk_of((mob as Node3D).global_position)
    var current: int = _active_per_chunk.get(ck, 0)
    if current > 0:
        _active_per_chunk[ck] = current - 1
```
Both functions use `global_position` at call time. A mob spawned in chunk A that moves to chunk B before dying will: increment chunk A's counter on spawn (correct), then decrement chunk B's counter on despawn (wrong — chunk A is leaked, chunk B is under-counted). Over time, this causes chunk A to permanently report 1+ extra mob and never reach the cap for spawning, while chunk B allows extra spawns beyond the real cap. The only reliable fix is to record the spawn chunk at spawn time.

**Fix:** Store the spawn chunk on the mob itself (or in a parallel dictionary keyed by mob identity):
```gdscript
func notify_spawned(mob: Node) -> void:
    if not _active_mobs.has(mob):
        _active_mobs.append(mob)
    if mob is Node3D:
        var ck := _chunk_of((mob as Node3D).global_position)
        _active_per_chunk[ck] = _active_per_chunk.get(ck, 0) + 1
        mob.set_meta("_spawn_chunk", ck)   # record spawn chunk
    emit_signal("hostile_spawned", ...)

func notify_despawned(mob: Node) -> void:
    _active_mobs.erase(mob)
    if mob.has_meta("_spawn_chunk"):
        var ck: Vector3i = mob.get_meta("_spawn_chunk") as Vector3i
        var current: int = _active_per_chunk.get(ck, 0)
        if current > 0:
            _active_per_chunk[ck] = current - 1
        elif _active_per_chunk.has(ck):
            _active_per_chunk.erase(ck)
    emit_signal("hostile_despawned", mob)
```

---

## Warnings

### WR-01: Spawn kind selection uses non-deterministic `randi()` — breaks Phase 4 journal replay

**File:** `src/autoload/spawning.gd:440`
**Issue:**
```gdscript
var kind: String = spawn_kinds[randi() % spawn_kinds.size()]
emit_signal("should_spawn", kind, candidate)
```
`randi()` uses the global non-seeded RNG. The kind selected varies between runs and between hosts. When Phase 4 replays the in-RAM journal on the new host, the spawn kinds will differ from what the original host chose, breaking the determinism contract for multiplayer state reconciliation.

**Fix:** Use a seeded `RandomNumberGenerator` derived from the world seed and spawn-tick sequence number, or seed from `LootRoller.seed_for_chest`-style mixing. At minimum, emit the chosen kind in the journal so the new host replays the recorded kind rather than re-rolling.

---

### WR-02: `apply_event` stamps seq before validation — gaps accumulate in Phase 4 journal on every rejected event

**File:** `src/autoload/inventory.gd:231-232`
**Issue:**
```gdscript
func apply_event(event: Dictionary) -> bool:
    event["seq"] = _next_seq
    _next_seq += 1         # incremented before we know if the event is valid
```
Sequence numbers are consumed even for events that return `false`. Every failed validation (wrong key tier, slot full, invalid kind) creates a gap in the seq stream. Phase 4 relies on the journal for host-failover replay. A new host receiving a journal with non-contiguous seq numbers cannot distinguish intentional gaps from dropped packets. The journal then cannot detect mid-transfer truncation reliably.

**Fix:** Stamp seq only after the applier returns `true`:
```gdscript
func apply_event(event: Dictionary) -> bool:
    var kind: String = event.get("kind", "")
    var ok: bool = false
    match kind:
        ...
    if ok:
        event["seq"] = _next_seq
        _next_seq += 1
        _journal.append(event)
        _mark_dirty_for_event(event)
    return ok
```

---

### WR-03: `inventory_slide_in._on_toggle` when mode != "inventory" opens without tearing down the current panel

**File:** `src/ui/inventory_slide_in.gd` (toggle method)
**Issue:** When the slide-in is open in "chest" or "workbench" mode and `_on_toggle` is called (e.g. via the E key or mobile inventory button), the code sets `_mode = "inventory"` and calls `open()` without first calling `_return_to_inventory_mode()`. The chest panel remains connected and its Inventory signal subscriptions remain live. Signals that fire for the now-closed chest continue to update the stale chest UI. On a subsequent chest open, `open_for_chest()` connects the signals again, creating duplicate connections.

**Fix:** In `_on_toggle`, call `_return_to_inventory_mode()` (or equivalent teardown) before switching to inventory mode if the current mode is not already "inventory".

---

### WR-04: `_refresh_crafting_output` passes integer `2` where `bool shapeless` is expected

**File:** `src/ui/inventory_slide_in.gd` (crafting refresh method)
**Issue:**
```gdscript
var result = Inventory.match_recipe(_crafting_grid_state, 2)
```
`match_recipe`'s second parameter is `shapeless: bool`. In GDScript, `2` is truthy, so this always passes `true` for shapeless — only shapeless recipes ever appear in the 2×2 crafting output, even when the player has shaped a grid pattern that should match a shaped recipe. Shaped 2×2 recipes are never shown.

**Fix:**
```gdscript
var result = Inventory.match_recipe(_crafting_grid_state, false)
```
Shaped matching should be tried first; `false` means "shaped recipe". If the intent was to show both, call it twice (once shaped, once shapeless) and merge results.

---

### WR-05: `world_save._migrate_schema` runs `_migrate_1_to_2()` twice for version-0 worlds

**File:** `src/autoload/world_save.gd` (migrate_schema method)
**Issue:** The migration logic for version-0 worlds falls through from the `0 → 1` case to the `1 → 2` case without a `break` or `return`, then the top-level function detects version 1 and calls `_migrate_1_to_2()` again. The migration is documented as idempotent but the double run emits spurious `push_warning` messages about columns already existing, and any non-idempotent future migration added between versions 1 and 2 would silently be applied twice, corrupting the schema.

**Fix:** After each migration step, update the stored schema version and `return` (or use an explicit `while schema_version < TARGET` loop) so each migration step executes exactly once.

---

### WR-06: `strawberry.gd` picks up the strawberry using the wrong action name

**File:** `src/world/strawberry.gd:91`
**Issue:**
```gdscript
if in_range and Input.is_action_just_pressed("ui_inventory_toggle"):
    _try_pick(builder)
```
The strawberry uses `"ui_inventory_toggle"` (the E key / inventory button) as its interact action. This action already opens and closes the inventory panel. Pressing E near a strawberry simultaneously picks the berry AND toggles the inventory — the player loses a frame of inventory state every time they pick a strawberry. The correct action should be `"sleep_interact"` or a dedicated `"interact"` action per the walk-up pattern described in 03-PATTERNS.md L951.

**Fix:** Define or reuse a dedicated `"interact"` input action for all walk-up entities (strawberry, bed, chest) and use that action here instead of `"ui_inventory_toggle"`.

---

### WR-07: `dropped_item.gd` continues executing `_check_despawn` and `_check_auto_pickup` after `queue_free()` is called in the same `_physics_process` frame

**File:** `src/world/dropped_item.gd` (physics process method)
**Issue:** The `_physics_process` method calls `_settle()` which calls `queue_free()` when the item settles. The method then continues executing `_check_despawn()` and `_check_auto_pickup()` on the already-freeing node. While Godot defers the actual free to end-of-frame, accessing state on a `queue_free`'d node that calls signal handlers into the scene tree can cause unexpected behaviour or null references if any of those handlers check `is_instance_valid`.

**Fix:** Add an early `return` after `queue_free()` is called inside `_settle()`, or check a `_settling` flag:
```gdscript
if _settling:
    _settle(delta)
    if not is_inside_tree():
        return   # already freed
_check_despawn()
_check_auto_pickup()
```

---

## Info

### IN-01: `recipe_book_tab.gd` accesses `Inventory._recipe_registry` directly (private field coupling)

**File:** `src/ui/recipe_book_tab.gd:115-116`
**Issue:**
```gdscript
if Inventory != null and "_recipe_registry" in Inventory:
    registry = Inventory._recipe_registry
```
This accesses an underscore-prefixed (private) field on the Inventory autoload. In GDScript there is no access control, but the coupling is fragile: renaming or restructuring `_recipe_registry` will silently break the recipe book tab without any compile error. The Inventory autoload should expose a public `get_recipe_registry() -> Dictionary` or `get_all_recipe_ids() -> Array` method.

**Fix:** Add to `inventory.gd`:
```gdscript
func get_recipe_registry() -> Dictionary:
    return _recipe_registry
```
Then update `recipe_book_tab.gd` to call `Inventory.get_recipe_registry()`.

---

### IN-02: `_is_valid_def_id` in `loot_roller.gd` accepts any short snake_case string — includes obvious garbage

**File:** `src/loot/loot_roller.gd:157-191`
**Issue:** The final fallback at the end of `_is_valid_def_id` accepts any string of ≤30 chars containing only `[a-z0-9_]` with a comment saying it may be a "future plan" ID. This means a typo in a loot table such as `"stne"` (meant: `"stone"`) passes validation silently, emits no warning, and appears in the player's inventory as an unresolvable item. The prefix-based acceptance already covers forward-compatible IDs from known namespaces; the catch-all should at minimum emit a warning.

**Fix:** The final `return true` should be a `push_warning` + `return true` so the warning aids debugging without breaking forward compatibility:
```gdscript
push_warning("LootRoller._is_valid_def_id: '%s' not found in registry or files — accepting as potential future ID." % def_id)
return true
```

---

### IN-03: `benchmark_runner.gd` overwrites user settings.cfg with Tier-3 preset and never restores it

**File:** `src/world/benchmark_runner.gd:553-562`
**Issue:** `_apply_tier3_preset()` writes to `user://settings.cfg` with low-quality graphics settings. If the benchmark scene is loaded in a developer's normal game session by mistake (or if the process is killed mid-benchmark), the user's graphics preferences are permanently overwritten with Tier-3 settings. There is no restore path.

**Fix:** Read and store a snapshot of the existing settings before overwriting, then restore them in `stop_benchmark()` or on `_exit_tree()`. Alternatively, use a separate `user://benchmark-settings.cfg` file and apply settings in-memory without persisting to the main config.

---

_Reviewed: 2026-05-27_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
