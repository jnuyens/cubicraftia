---
phase: 03-survival-loop
fixed_at: 2026-05-27T19:02:12Z
review_path: .planning/phases/03-survival-loop/03-REVIEW.md
iteration: 1
findings_in_scope: 12
fixed: 12
skipped: 0
status: all_fixed
---

# Phase 03: Code Review Fix Report

**Fixed at:** 2026-05-27T19:02:12Z
**Source review:** .planning/phases/03-survival-loop/03-REVIEW.md
**Iteration:** 1

**Summary:**
- Findings in scope: 12 (5 critical + 7 warning; 3 info findings excluded per fix_scope)
- Fixed: 12
- Skipped: 0

## Fixed Issues

### CR-01: Drag-drop event key mismatch — all inventory drag operations silently fail

**Files modified:** `src/ui/inventory_slot.gd`
**Commit:** 8d9328b
**Applied fix:** Changed `"from"` to `"from_slot"` and `"to"` to `"to_slot"` in the `_drop_data` event dictionary (lines 269-270). The keys now match what `_apply_move`, `_apply_swap`, and `_apply_split` read in `inventory.gd`.

---

### CR-02: `_is_locked_chest_at` calls non-existent method — spawn suppression over chests is permanently disabled

**Files modified:** `src/autoload/spawning.gd`
**Commit:** 2141044
**Applied fix:** Changed `has_method("get_chest")` to `has_method("get_chest_state")` and `Inventory.get_chest(chunk_coord)` to `Inventory.get_chest_state(chunk_coord)`. Also corrected the return condition from `chest_data.has("type")` (which would suppress over any chest including unlocked ones) to `not chest_data.is_empty() and chest_data.get("locked", false)` per 03-PATTERNS.md L1038.

---

### CR-03: Double-chest break discards all items from the broken half without dropping them

**Files modified:** `src/world/chest_entity.gd`
**Commit:** d2608ba
**Applied fix:** In the `_has_partner` branch of `on_break()`, added a loop that reads the first-half contents via `Inventory.get_chest_contents(_chunk_coord)` and spawns `DroppedItem` entities for each non-empty slot before calling `unregister_chest_half`. Used the existing `half_capacity` variable (already computed at function top) with `mini()` to iterate only the correct half.

---

### CR-04: `_apply_craft` consumes first ingredient before validating remaining ingredients — ingredient loss on failure

**Files modified:** `src/autoload/inventory.gd`
**Commit:** 4373fff
**Applied fix:** Added a pre-validation loop before the consume loop in `_apply_craft`. The pre-check iterates all ingredients and calls `_count_in_inventory(builder_id, def_id)` (already exists at line 1422) to verify availability. Only if all ingredients pass does the consume loop run. The consume loop no longer checks `remove_ok` since availability was pre-validated.

---

### CR-05: `_active_per_chunk` hostile counter desynchronises when mobs move between chunks

**Files modified:** `src/autoload/spawning.gd`
**Commit:** b2d1dc6
**Applied fix:** In `notify_spawned`, after computing the spawn chunk `ck`, stores it on the mob node as `mob.set_meta("_spawn_chunk", ck)`. In `notify_despawned`, reads `mob.get_meta("_spawn_chunk")` when present and uses that stored chunk key for the decrement instead of the mob's current position. A fallback using current position is retained for mobs that lack the meta (pre-fix spawns). Requires human verification of the logic — commit flagged accordingly.

**Note:** Requires human verification (logic fix — runtime behavior confirms correctness but unit test is recommended).

---

### WR-01: Spawn kind selection uses non-deterministic `randi()` — breaks Phase 4 journal replay

**Files modified:** `src/autoload/spawning.gd`
**Commit:** 64858b1
**Applied fix:** Added `_kind_rng: RandomNumberGenerator` and `_spawn_tick_seq: int` member variables. Added `seed_from_world(world_seed: int)` public method so the RNG can be seeded when a world is opened. Changed `randi() % spawn_kinds.size()` to `_kind_rng.randi() % spawn_kinds.size()` and increments `_spawn_tick_seq` after each spawn. The RNG defaults to unseeded (seed=0) until `seed_from_world` is called; Phase 4 should wire `seed_from_world` to the world open event.

---

### WR-02: `apply_event` stamps seq before validation — gaps accumulate in Phase 4 journal on every rejected event

**Files modified:** `src/autoload/inventory.gd`
**Commit:** 9922762
**Applied fix:** Moved `event["seq"] = _next_seq` and `_next_seq += 1` from before the match dispatch to inside the `if ok:` block after the applier returns. Seq is now stamped only for events that succeed, so the journal stream is contiguous and host-failover replay can detect truncation by a missing seq.

---

### WR-03: `inventory_slide_in._on_toggle` when mode != "inventory" opens without tearing down the current panel

**Files modified:** `src/ui/inventory_slide_in.gd`
**Commit:** 92aae6d
**Applied fix:** In the `else` branch of `_on_toggle`, added a guard: `if _mode != "inventory": _return_to_inventory_mode()` before calling `open()`. This tears down any live chest/workbench panel (disconnecting signal subscriptions) before the inventory panel is opened.

---

### WR-04: `_refresh_crafting_output` passes integer `2` where `bool shapeless` is expected

**Files modified:** `src/ui/inventory_slide_in.gd`
**Commit:** 87fdea8
**Applied fix:** Changed `Inventory.match_recipe(_crafting_grid_state, 2)` to `Inventory.match_recipe(_crafting_grid_state, false)`. Shaped matching (`false`) is now tried, allowing shaped 2×2 recipes to appear in the crafting output slot.

---

### WR-05: `world_save._migrate_schema` runs `_migrate_1_to_2()` twice for version-0 worlds

**Files modified:** `src/autoload/world_save.gd`
**Commit:** 8580ede
**Applied fix:** Added an explicit `0:` case in the `match current_version` block that does `ok = true` (no-op — v0 has the same base schema as v1). This advances `current_version` to 1 on the first iteration; the next iteration then runs `_migrate_1_to_2()` exactly once. Also updated the `_:` fallback to jump `current_version` to `SCHEMA_VERSION - 1` after applying v2 tables, preventing infinite loops for completely unknown versions.

---

### WR-06: `strawberry.gd` picks up the strawberry using the wrong action name

**Files modified:** `src/world/strawberry.gd`
**Commit:** 997f183
**Applied fix:** Changed `Input.is_action_just_pressed("ui_inventory_toggle")` to `Input.is_action_just_pressed("sleep_interact")`. This matches the walk-up interact pattern used by `bed_entity.gd` and avoids the inventory panel toggling every time a player picks a strawberry.

---

### WR-07: `dropped_item.gd` continues executing after `queue_free()` in the same `_physics_process` frame

**Files modified:** `src/world/dropped_item.gd`
**Commit:** ef0a205
**Applied fix:** Added `if not is_inside_tree(): return` immediately after the `_settle()` call in `_physics_process`. When `_settle()` calls `queue_free()` (the fallback when no main_scene pool exists), the `is_inside_tree()` check returns false and the frame short-circuits before `_check_despawn()` and `_check_auto_pickup()` run on the pending-free node.

---

_Fixed: 2026-05-27T19:02:12Z_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 1_
