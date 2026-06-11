---
phase: 03-survival-loop
plan: "09"
subsystem: consumables-dropped-items
tags:
  - phase-3
  - dropped-item
  - strawberry
  - cooked-food
  - tom-yum
  - fire-breath
dependency_graph:
  requires:
    - 03-02  # Inventory.apply_event ADD
    - 03-03  # WorldClock.elapsed_seconds + SECONDS_PER_DAY
    - 03-04  # Builder.eat_food + get_stable_builder_id
    - 03-05  # translation keys (ui.strawberry.pickup_prompt)
  provides:
    - DroppedItem.try_pickup + 2-day despawn + auto-pickup (extended dropped_item.gd)
    - 5 cooked-food ItemDefinitions (food_cooked_generic, food_tom_yum, food_roasted_fish, food_bread, food_pie)
    - 1 strawberry ItemDefinition (strawberry.tres, heal=6, super-heal)
    - Strawberry entity (strawberry.gd + strawberry.tscn) with per-chunk session metadata
    - FireBreathVfx particle effect (fire_breath_vfx.gd + fire_breath_vfx.tscn)
    - Builder.eat_food VFX dispatch (hard-coded "fire_breath" switch, T-03-09-DR-05)
    - ItemDefinition.vfx_on_use: String = "" field (all existing .tres default to "")
  affects:
    - src/world/dropped_item.gd (extended)
    - src/items/item_definition.gd (vfx_on_use field added)
    - src/builder/builder.gd (eat_food VFX dispatch + helper methods)
tech_stack:
  added:
    - GPUParticles3D flame puff (FireBreathVfx; 30 particles, 0.3 s one-shot)
    - StaticBody3D walk-up entity (Strawberry; walk-up + E-key instant pickup)
    - per-chunk WorldSave metadata (strawberries:<x>_<y>_<z> blob with last_picked_session_id)
    - lazy ResourceLoader item-definition cache in Builder (_loaded_item_defs Dictionary)
  patterns:
    - Game-clock despawn: WorldClock.elapsed_seconds − _spawn_tick > DESPAWN_AFTER_DAYS × SECONDS_PER_DAY
    - Pickup cooldown: _recently_rejected_until guards repeat Inventory.apply_event calls (Pitfall 8)
    - Auto-pickup proximity: _check_auto_pickup polls builder group at 1 m radius in _physics_process
    - VFX dispatch: hard-coded string switch in eat_food ("fire_breath" → _spawn_fire_breath_vfx; else no-op)
    - Session-ID lazy init: Strawberry reads WorldSave("session_id"); falls back to wall-clock str if absent
key_files:
  created:
    - src/world/strawberry.gd
    - src/world/strawberry.tscn
    - src/world/fire_breath_vfx.gd
    - src/world/fire_breath_vfx.tscn
    - src/bricks/food_cooked_generic.tres
    - src/bricks/food_tom_yum.tres
    - src/bricks/food_roasted_fish.tres
    - src/bricks/food_bread.tres
    - src/bricks/food_pie.tres
    - src/bricks/strawberry.tres
  modified:
    - src/world/dropped_item.gd
    - src/items/item_definition.gd
    - src/builder/builder.gd
decisions:
  - "consumable-heal-scale: food_cooked_generic=2, food_tom_yum=3, food_roasted_fish=2, food_bread=2, food_pie=4, strawberry=6 — preserves D-13 Tom Yum equivalence to standard cooked food; D-16 strawberry > all cooked food"
  - "vfx-dispatch-hard-coded: eat_food uses string == 'fire_breath' comparison (not dynamic loading) per T-03-09-DR-05 injection-safety"
  - "drop-item-clock-accessor: _get_clock_elapsed() helper reads WorldClock via /root/WorldClock node path for headless-test safety (no direct autoload reference in the helper)"
  - "strawberry-session-id-fallback: str(int(Time.get_unix_time_from_system())) as fallback token until Plan 03-11 writes session_id; benign race — first strawberry to write wins, rest read persisted value"
metrics:
  duration: "~45 min"
  completed: "2026-05-27T14:22:00Z"
  tasks_completed: 3
  files_created: 10
  files_modified: 3
---

# Phase 3 Plan 09: Consumables Surface (Dropped Items + Food + Strawberry + FireBreathVfx) Summary

**One-liner:** DroppedItem extended with 2-day game-clock despawn + Inventory pickup routing; 5 cooked-food + 1 strawberry ItemDefinitions; Tom Yum signature fire-breath VFX; Strawberry walk-up entity with per-chunk session metadata.

## What Was Built

### Task 1: DroppedItem Extensions (dropped_item.gd)

Three new constants and two new fields were added to the Phase 2 DroppedItem class:

| Constant | Value | Purpose |
|---|---|---|
| `DESPAWN_AFTER_DAYS` | 2.0 | 2 Cubicraftia-day lifetime threshold |
| `REJECT_COOLDOWN_S` | 2.0 | Inventory-full toast suppression window (Pitfall 8) |
| `AUTO_PICKUP_RADIUS_M` | 1.0 | Auto-pickup proximity radius (DOCS §4.1) |

Three new functions:
- `try_pickup(builder)` — routes through `Inventory.apply_event({kind: "ADD", ...})`; on overflow sets `_recently_rejected_until` cooldown (T-03-09-DR-02 mitigation)
- `_check_despawn()` — compares `WorldClock.elapsed_seconds - _spawn_tick` against `DESPAWN_AFTER_DAYS × SECONDS_PER_DAY` (game-clock semantics per Pitfall 2 + T-03-09-DR-01)
- `_check_auto_pickup()` — polls builder group at 1 m radius in settled _physics_process

The `_ready()` hook now records `_spawn_tick = WorldClock.elapsed_seconds` (accessed via `/root/WorldClock` node path for headless-test safety).

### Task 2: ItemDefinition .tres Files

**Heal-amount table** (chosen values + design rationale):

| Item | heal_amount | Rationale |
|---|---|---|
| `food_cooked_generic` | 2 | Modest "leftover stew" — baseline for found loot |
| `food_tom_yum` | 3 | Signature dish (D-13) — VFX is cosmetic, not a heal advantage |
| `food_roasted_fish` | 2 | Simple catch-and-roast; matches generic |
| `food_bread` | 2 | Classic staple from village chests |
| `food_pie` | 4 | "Labour of love" food — highest cooked-food heal per D-13 discretion |
| `strawberry` | 6 | Super-heal per D-16 — definitively exceeds all cooked food |

`vfx_on_use = ""` on all items except `food_tom_yum` which has `vfx_on_use = "fire_breath"`.

**ItemDefinition.vfx_on_use field** added to `src/items/item_definition.gd`:
```gdscript
@export var vfx_on_use: String = ""
```

### Task 3: Strawberry Entity + FireBreathVfx + Builder Dispatch

#### Strawberry._record_picked + _get_session_id

```gdscript
func _record_picked() -> void:
    var key: String = "strawberries:%d_%d_%d" % [_chunk_coord.x, _chunk_coord.y, _chunk_coord.z]
    var session_id: String = _get_session_id()
    var blob: PackedByteArray = var_to_bytes({
        "last_picked_session_id": session_id,
        "picked_at_tick": WorldClock.elapsed_seconds,
    })
    WorldSave.set_world_meta(key, blob)

func _get_session_id() -> String:
    var raw: Variant = WorldSave.get_world_meta("session_id")
    if raw == null:
        var sid: String = str(int(Time.get_unix_time_from_system()))
        WorldSave.set_world_meta("session_id", sid)
        return sid
    if raw is PackedByteArray:
        var decoded: Variant = bytes_to_var(raw as PackedByteArray)
        return str(decoded)
    return str(raw)
```

#### FireBreathVfx Particle Config (fire_breath_vfx.tscn ParticleProcessMaterial)

```
direction = Vector3(0, 0, -1)      # forward along -Z (Godot convention)
spread = 15.0                       # narrow cone
initial_velocity_min = 1.5
initial_velocity_max = 2.5
scale_min = 0.2, scale_max = 0.4   # ~10% of dynamite scale per CONTEXT D-13
lifetime_randomness = 0.3
color_ramp: #E68A1D (orange) → #D63828 (red) → alpha=0
amount = 30; lifetime = 0.3; one_shot = true; explosiveness = 0.4
```

No Area3D, no CollisionShape3D, no damage handler (T-03-09-DR-04 cosmetic-only invariant).

#### Builder._spawn_fire_breath_vfx

```gdscript
func _spawn_fire_breath_vfx() -> void:
    var vfx_scene: PackedScene = load("res://src/world/fire_breath_vfx.tscn")
    if vfx_scene == null:
        push_warning("Builder._spawn_fire_breath_vfx: fire_breath_vfx.tscn not found.")
        return
    var vfx: Node3D = vfx_scene.instantiate() as Node3D
    if vfx == null:
        return
    var camera: Camera3D = get_active_camera()
    add_child(vfx)
    var forward: Vector3 = -camera.global_transform.basis.z.normalized()
    vfx.global_position = camera.global_position + forward * 0.5
    var look_target: Vector3 = vfx.global_position + forward
    if look_target.distance_to(vfx.global_position) > 0.001:
        vfx.look_at(look_target, Vector3.UP)
```

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing Field] ItemDefinition.vfx_on_use not added by Plan 03-06**
- **Found during:** Task 2 (reading item_definition.gd — `vfx_on_use` was absent)
- **Issue:** Plan 03-06 PLAN.md noted it should add `vfx_on_use` but the shipped item_definition.gd (03-06-SUMMARY.md confirms) did not include it; Plan 03-09 was responsible for adding it if missing
- **Fix:** Added `@export var vfx_on_use: String = ""` to item_definition.gd with threat-model comment referencing T-03-09-DR-05
- **Files modified:** `src/items/item_definition.gd`
- **Commit:** d2b48aa

**2. [Rule 2 - Missing Critical Functionality] WorldClock access in dropped_item.gd via node path**
- **Found during:** Task 1 (dropped_item.gd extends RigidBody3D, not Node — direct `WorldClock.*` autoload access is reliable but _ready fires before scene is fully ready in some test contexts)
- **Fix:** Used `/root/WorldClock` node path via `_get_clock_elapsed()` helper for `_ready()` spawn-tick recording; kept direct `WorldClock.SECONDS_PER_DAY` reference in `_check_despawn()` (called only after settle, when scene is fully ready)
- **Files modified:** `src/world/dropped_item.gd`
- **Commit:** 6c7a3e1

## Open Carries to Plan 03-11

Plan 03-11 (main_scene survival init) must:
1. Write `WorldSave.set_world_meta("session_id", <uuid>)` at world-open BEFORE any Strawberry._ready() fires. The Strawberry lazy-init fallback remains as defensive code.
2. Call `spawn_strawberry(chunk_coord, position)` for grassland-biome chunks on world load, checking `WorldSave.get_world_meta("strawberries:<x>_<y>_<z>")` → `last_picked_session_id` against current session_id to gate respawn (RESEARCH Pattern 5 + Pitfall 10).

## 03-VALIDATION.md Updates

- `test_despawn_timer.gd` — Tests 1, 2, 3 now pass (WorldClock._set_elapsed_for_test hook + SECONDS_PER_DAY confirmed available; despawn logic uses game-clock not wall-clock)
- `test_pickup_integration.gd` — Tests 1, 2, 3 pass (try_pickup routed through Inventory.apply_event; Pitfall 8 reject cooldown implemented; toast spam prevented)

## Threat Flags

None — no new trust-boundary surfaces beyond what the plan's threat_model anticipated.

## Self-Check: PASSED

All 11 files verified present. All 3 task commits verified in git log:
- 6c7a3e1: feat(03-09): extend DroppedItem with try_pickup + 2-day despawn + auto-pickup
- d2b48aa: feat(03-09): 5 cooked-food + 1 strawberry ItemDefinitions + vfx_on_use field
- 9031dd8: feat(03-09): Strawberry entity + FireBreathVfx + Builder.eat_food vfx dispatch
