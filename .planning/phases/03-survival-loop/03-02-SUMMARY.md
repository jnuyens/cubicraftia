---
phase: 03-survival-loop
plan: 02
subsystem: inventory + chest persistence
tags:
  - inventory
  - autoload
  - event-sourced
  - persistence
  - chest
  - recipes
dependency_graph:
  requires:
    - phase-03 plan-01 (v2 schema — inventories/chests/dropped_items/recipes_known tables)
    - phase-02 WorldSave autoload (get_world_meta/set_world_meta/mark_chunk_dirty/is_open)
    - phase-02 WorldClock autoload (day_boundary signal + elapsed_seconds)
    - phase-02 Features autoload (is_survival_mode)
    - phase-02 Toasts autoload (show)
    - phase-02 ToolWear autoload (worn_out signal)
  provides:
    - Inventory autoload (event-sourced 6×8 grid + chest + recipes-known state)
    - WorldSave.save_chest / load_chest / load_all_chests
    - All 9 event kinds dispatched through apply_event()
    - Survival-mode gate with _test_set_mode_override hook
  affects:
    - Plan 03-04 (ChestEntity emits UNLOCK via Inventory.apply_event)
    - Plan 03-05 (slide-in UI emits ADD/REMOVE/MOVE/SPLIT/SWAP)
    - Plan 03-06 (ChestEntity emits UNLOCK)
    - Plan 03-07 (Workbench emits CRAFT)
    - Plan 03-09 (DroppedItem.try_pickup emits ADD)
tech_stack:
  added: []
  patterns:
    - Event-sourced mutation: all writes go through apply_event() → validate → mutate → signal → mark dirty
    - Coalesced persistence: 30-s timer OR day_boundary OR detach_world → set_world_meta
    - Test mode override: _test_set_mode_override() mirrors ToolWear pattern
    - Shape-check on blob load: malformed blobs push_warning + start empty (T-03-02-INV-02)
key_files:
  created:
    - src/autoload/inventory.gd (450+ lines — event dispatcher + 10 applier functions)
  modified:
    - src/autoload/world_save.gd (added save_chest/load_chest/load_all_chests)
    - project.godot (Inventory registered after BrickRegistry)
    - tests/unit/test_inventory_grid.gd (pending → green)
    - tests/unit/test_recipe_book_reveal.gd (pending → green)
    - tests/unit/test_chest_unlock_validation.gd (pending → green)
    - tests/unit/test_chest_state.gd (3/4 pending → green; 1 remains pending for Plan 03-04)
    - tests/unit/test_double_chest.gd (pending → green)
    - tests/conftest_phase3.gd (Engine.has_singleton guard removed from populate_inventory)
decisions:
  - "Engine.has_singleton() does not work for GDScript autoloads registered via project.godot —
     test files updated to access Inventory directly (the autoload name is globally resolved at
     GDScript parse time). All Wave-0 stubs had Engine.has_singleton() guards that were correct
     for \"autoload not yet registered\" phase but incorrect once registered."
  - "double_chest_partner stored as str(Vector3i) to match test expectation (assert_eq with str(pos_b));
     _parse_coord_key updated to handle both str(Vector3i) '(x, y, z)' and _coord_key 'x_y_z' formats"
  - "SINGLE_TAKE added as a 10th event kind (not in original 9) because test_inventory_grid.gd
     test_single_take_decrements_by_1 requires it; it's a subset of REMOVE by 1 from a specific slot"
  - "apply_event CRAFT with no recipe registry wired: accepted gracefully — first-craft permanent
     unlock recorded, inventory_changed emitted; no consumption (registry not available yet)"
metrics:
  duration: 26 minutes
  completed: 2026-05-27
  tasks_completed: 1
  files_created: 1
  files_modified: 8
  total_files: 9
---

# Phase 3 Plan 02: Inventory Autoload — Event-Sourced Builder/Chest/Recipes State

**One-liner:** Event-sourced Inventory autoload implementing all 9 mutation kinds through apply_event(), with 30-s coalesced persistence to WorldSave, wrong-tier key rejection, toast-spam guard, and double-chest combine/break — turning 16 Wave-0 test stubs green.

## What Got Built

### Task 1: Inventory Autoload + WorldSave Chest CRUD

#### Step 1 — `src/autoload/inventory.gd` (created, 450+ non-comment lines)

**Event dispatch table (all 9 kinds + SINGLE_TAKE bonus):**

| Kind | Applier | Signal Emitted | Dirty Mark |
|------|---------|---------------|------------|
| ADD | `_apply_add` | `inventory_changed` | `_dirty_builders[builder_id]` + timer restart |
| REMOVE | `_apply_remove` | `inventory_changed` | `_dirty_builders[builder_id]` + timer restart |
| MOVE | `_apply_move` | `inventory_changed` | `_dirty_builders[builder_id]` + timer restart |
| SPLIT | `_apply_split` | `inventory_changed` | `_dirty_builders[builder_id]` + timer restart |
| SWAP | `_apply_swap` | `inventory_changed` | `_dirty_builders[builder_id]` + timer restart |
| SINGLE_TAKE | `_apply_single_take` | `inventory_changed` | `_dirty_builders[builder_id]` + timer restart |
| CRAFT | `_apply_craft` | `inventory_changed` + `recipe_revealed` (first craft) | `_dirty_builders[builder_id]` + timer restart |
| UNLOCK | `_apply_unlock` | `chest_unlocked(chunk_coord)` | `WorldSave.mark_chunk_dirty(chest_coord)` |
| DEATH_DROP | `_apply_death_drop` | `death_pile_spawned(builder_id, pos, contents)` | `_dirty_builders[builder_id]` + timer restart |
| RECIPE_UNLOCK | `_apply_recipe_unlock` | `recipe_revealed(builder_id, recipe_id)` | `_dirty_builders[builder_id]` + timer restart |

**Persistence cadence diagram:**

```
Any mutation event
      │
      ▼
apply_event() → validate → mutate in-memory → emit signal → _mark_dirty_for_event()
                                                                    │
                                           _dirty_builders[id]=true + _persist_timer.start()
                                                                    │
                              ┌─────────────────────────────────────┤
                              │                                     │
                    WorldClock.day_boundary              _persist_timer timeout (30 s)
                    (belt-and-braces)                               │
                              │                                     │
                              └──────────────┬──────────────────────┘
                                             │
                                   _flush_persistence()
                                             │
                              WorldSave.set_world_meta(
                                "inventory:<builder_id>",
                                var_to_bytes({slots, recipes_known}))
                                             │
                                   _dirty_builders.clear()
```

Also: `detach_world()` calls `_flush_persistence()` synchronously (session end).

**Mode gate test override demonstration:**

The `_test_set_mode_override` hook mirrors `tool_wear.gd`. Tests in `test_chest_state.gd` and the DEATH_DROP path use it:

```gdscript
# Sandbox (default in test worlds):
# Inventory._test_set_mode_override("") → reads Features.is_survival_mode() → false
# _apply_death_drop returns true immediately (no-op, no items dropped)

# Survival:
# Inventory._test_set_mode_override("survival")
# _apply_death_drop drains all slots → emits death_pile_spawned(builder_id, pos, contents)
```

#### Step 2 — WorldSave chest CRUD methods

Three new public methods added to `src/autoload/world_save.gd`:

- `save_chest(chunk_coord, tier, locked, contents_blob, double_partner) -> bool` — INSERT OR REPLACE
- `load_chest(chunk_coord) -> Dictionary` — SELECT single row
- `load_all_chests() -> Array[Dictionary]` — SELECT all rows for `attach_world()` rehydration

All use `_db.call("query_with_bindings", sql, [params])` — never string concatenation (T-03-02-INV-05).

#### Step 3 — project.godot registration

`Inventory="*res://src/autoload/inventory.gd"` inserted after `BrickRegistry` line (load-order contract: BrickRegistry must be ready before Inventory validates brick def_ids).

## Pitfall Mitigation Evidence

### Pitfall 8 — Toast Spam Guard (`_can_show_full_tip`)

```gdscript
func _can_show_full_tip() -> bool:
    var elapsed: float = 0.0
    if Engine.has_singleton("WorldClock"):
        elapsed = Engine.get_singleton("WorldClock").elapsed_seconds
    else:
        elapsed = Time.get_ticks_msec() / 1000.0
    if elapsed - _last_full_tip_tick > FULL_TIP_COOLDOWN_S:
        _last_full_tip_tick = elapsed
        return true
    return false
```

Called in `_apply_add` on overflow. `FULL_TIP_COOLDOWN_S = 2.0`. Only the first overflow per 2-second window shows "ui.inventory.full". DroppedItem (Plan 03-09) routes through `Inventory.apply_event(ADD)` so also benefits from this cooldown.

### Pitfall 7 — Reveal Cache Invalidation (`_invalidate_reveal_cache`)

```gdscript
func _invalidate_reveal_cache(builder_id: String, _def_id_changed: String) -> void:
    _revealed_recipes_cache.erase(builder_id)
```

Until Plan 03-07a wires the recipe registry, invalidation is unconditional (erases cache on any slot change). Once Plan 03-07a sets a registry, the `_def_id_changed` parameter will be used to check ingredient membership before deciding to invalidate. Acceptable for ≤10 recipes in Phase 3.

## Test Results

| File | Tests | Result |
|------|-------|--------|
| `tests/unit/test_inventory_grid.gd` | 5/5 | ✅ PASS |
| `tests/unit/test_recipe_book_reveal.gd` | 3/3 | ✅ PASS |
| `tests/unit/test_chest_unlock_validation.gd` | 2/2 | ✅ PASS |
| `tests/unit/test_chest_state.gd` | 3/4 + 1 pending | ✅ PASS (1 pending: ChestEntity Plan 03-04) |
| `tests/unit/test_double_chest.gd` | 3/3 | ✅ PASS |

**Full suite after Plan 03-02:**

- Scripts: 48 (unchanged)
- Tests: 189 (unchanged total)
- Passing: 150 (up from 134 — +16 turned green)
- Failing: 2 (same 2 pre-existing failures — removed_bulk signal + starter kit)
- Pending: 37 (down from 53 — 16 turned green)

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Engine.has_singleton() not applicable to GDScript autoloads**

- **Found during:** Task 1 first test run
- **Issue:** `Engine.has_singleton("Inventory")` returns false for GDScript autoloads registered via project.godot — this is by design in Godot 4. The Wave-0 test stubs used this as a "pending" guard, assuming it would return true when the autoload was registered. In fact `Engine.has_singleton()` only returns true for C++ engine singletons. The autoload IS accessible by direct name reference.
- **Fix:** All 5 test files updated to remove `Engine.has_singleton("Inventory")` guard and `Engine.get_singleton("Inventory")` calls, replacing with direct `Inventory.*` access. Added `Inventory.detach_world()` + `Inventory.attach_world()` calls in `before_each` for clean state isolation between tests. Same fix applied to `conftest_phase3.gd.populate_inventory`.
- **Files modified:** all 5 test files + conftest_phase3.gd
- **Commit:** 8ea3236

**2. [Rule 1 - Bug] break_double_chest split logic bug — str(Vector3i) vs coord_key format**

- **Found during:** Task 1 test_double_chest failure — `test_break_double_splits_contents_proportionally`
- **Issue 1:** `_parse_coord_key()` expected `"x_y_z"` format but `str(Vector3i)` produces `"(x, y, z)"`. The double_chest_partner was stored as `str(pos_b)` (because the test asserts `state_a.get("double_chest_partner") == str(pos_b)`), so round-tripping through `_parse_coord_key` returned `Vector3i.ZERO` and the partner half was never found.
- **Issue 2:** The `break_double_chest` fill loop had a `break` statement that exited after one inner `for` iteration regardless of whether `placed_a` reached `half_a_target`, resulting in only the first item being processed.
- **Fix:** `_parse_coord_key` extended to handle both `"(x, y, z)"` (str(Vector3i)) and `"x_y_z"` (_coord_key) formats. Split loop rewritten without nested `break` confusion.
- **Files modified:** src/autoload/inventory.gd
- **Commit:** 8ea3236

**3. [Rule 2 - Missing functionality] SINGLE_TAKE event kind added**

- **Found during:** Reading test_inventory_grid.gd test 4 (`test_single_take_decrements_by_1`)
- **Issue:** The plan specified 9 event kinds (ADD/REMOVE/MOVE/SPLIT/SWAP/CRAFT/UNLOCK/DEATH_DROP/RECIPE_UNLOCK). The test scaffold for Wave-0 added `SINGLE_TAKE` as a separate event kind (right-click to take exactly 1 from a stack). Without it the test would fail.
- **Fix:** `_apply_single_take` added as a private applier dispatched from `apply_event`. Semantically it is `REMOVE` with count=1 from a specific slot, but it is distinct per the test expectation.
- **Files modified:** src/autoload/inventory.gd
- **Commit:** 8ea3236

## 03-VALIDATION.md Wave-0 Test Status Updates

| File | Before 03-02 | After 03-02 |
|------|-------------|-------------|
| `tests/unit/test_inventory_grid.gd` | ⏳ Pending | ✅ 5/5 PASS |
| `tests/unit/test_recipe_book_reveal.gd` | ⏳ Pending | ✅ 3/3 PASS |
| `tests/unit/test_chest_unlock_validation.gd` | ⏳ Pending | ✅ 2/2 PASS |
| `tests/unit/test_chest_state.gd` | ⏳ Pending | ✅ 3/4 PASS + 1 pending (Plan 03-04) |
| `tests/unit/test_double_chest.gd` | ⏳ Pending | ✅ 3/3 PASS |

## Known Stubs

The following methods are stubbed until Plan 03-07a wires the recipe registry:

- `_builder_has_all_ingredients()` — always returns false (ingredient-presence reveal inactive; permanently-unlocked recipes still work via `_recipes_known`)
- `_grid_matches_recipe()` — always returns false (crafting grid match inactive; CRAFT events accepted by recipe_id only)
- `match_recipe()` — returns null (no registry wired)

These stubs prevent false-positive recipe reveals before the registry is available. The `get_revealed_recipes()` function correctly returns permanently-known recipes in all tests. Tests using CRAFT without a registry (test_recipe_book_reveal.gd) work because CRAFT auto-records first-craft unlock even without ingredient validation.

## Threat Flags

None. Plan 03-02 introduces no new network endpoints, auth paths, or schema changes beyond the WorldSave chest CRUD methods (which extend the existing chests table from Plan 03-01). All chest CRUD uses parameterised queries (T-03-02-INV-05 mitigated).

## Self-Check: PASSED

**Files exist:**
- `src/autoload/inventory.gd` — FOUND (450+ lines)
- `src/autoload/world_save.gd` — FOUND (extended with 3 chest CRUD methods)
- `project.godot` — FOUND (Inventory autoload registered)

**Commits exist:**
- `8ea3236` feat(03-02): implement Inventory autoload — event-sourced 6×8 grid + WorldSave chest CRUD — FOUND

**Key assertions:**
- `grep -c 'Inventory="*res://src/autoload/inventory.gd"' project.godot` → 1 ✓
- `grep -c '^func apply_event' src/autoload/inventory.gd` → 1 ✓
- `grep -cE '^func _apply_(add|remove|...)' src/autoload/inventory.gd` → 10 (≥9) ✓
- `grep -c '^signal ' src/autoload/inventory.gd` → 4 ✓
- `grep -c 'STACK_MAX: int = 64' src/autoload/inventory.gd` → 1 ✓
- `grep -c 'SLOT_COUNT: int = 48' src/autoload/inventory.gd` → 1 ✓
- `grep -c '_test_set_mode_override|_test_mode_override' src/autoload/inventory.gd` → 6 (≥2) ✓
- `grep -c 'save_chest|load_chest|load_all_chests' src/autoload/world_save.gd` → 3 ✓
- `grep -v '^#' src/autoload/inventory.gd | grep -c 'query_with_bindings|set_world_meta'` → 2 (≥1) ✓
- test_inventory_grid.gd: 5/5 PASS ✓
- test_recipe_book_reveal.gd: 3/3 PASS ✓
- test_chest_unlock_validation.gd: 2/2 PASS ✓
- test_chest_state.gd: 3/4 PASS + 1 pending (expected) ✓
- test_double_chest.gd: 3/3 PASS ✓
- `bash scripts/glossary-check.sh` → OK ✓
- No inventory.gd errors in `godot --headless --check-only --quit` ✓
