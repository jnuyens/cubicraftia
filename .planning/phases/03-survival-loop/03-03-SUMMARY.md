---
phase: 03-survival-loop
plan: "03"
subsystem: survival-spawning
tags:
  - phase-3
  - survival
  - autoload
  - spawning
  - hostile-mob-base
  - sleep-multiplier
dependency_graph:
  requires:
    - 03-01 (WorldSave schema v2 migration)
    - 03-02 (Inventory autoload — load-order dependency for Spawning)
  provides:
    - Spawning autoload (bed-bubble index, spawn gates, chunk cap)
    - HostileMob base class (Plan 03-10 extends with 5 concrete creatures)
    - WorldClock sleep multiplier API (Plan 03-04 wires from Builder.sleep_interact)
  affects:
    - 03-04 (Builder sleep_interact calls WorldClock.start_sleep_lapse)
    - 03-10 (5 creature subclasses extend HostileMob; connect should_spawn signal)
    - 03-11 (BedEntity._ready calls Spawning.register_bed on scene entry)
tech_stack:
  added:
    - src/combat/ directory (new hostile-creature subsystem)
    - GDScript autoload Spawning (chunk-keyed bed index, 1 Hz spawn-tick throttle)
  patterns:
    - WorldClock wall-delta multiplier (same Pitfall-3-safe pattern; multiplier is applied before the SECONDS_PER_DAY cap)
    - Chunk-keyed Dictionary index for O(beds-in-chunk) bubble lookups (per RESEARCH Pitfall 5)
    - Direct autoload name access in tests (not Engine.has_singleton — per STATE.md inventory-engine-has-singleton)
key_files:
  created:
    - src/combat/hostile_mob.gd (286 lines, base class for 5 creatures)
    - src/autoload/spawning.gd (458 lines, bed index + spawn gates + bookkeeping)
  modified:
    - src/autoload/world_clock.gd (sleep multiplier extension + 3 new methods + 1 signal)
    - project.godot (Spawning autoload registered after Inventory)
    - tests/unit/test_spawning_rules.gd (pending→passing; Engine.has_singleton→direct access)
    - tests/unit/test_sleep_lapse.gd (pending→passing; fixed signal names + direct access)
decisions:
  - "spawning-direct-autoload-test-access: Test files updated to use Spawning.* directly (not Engine.has_singleton) — consistent with inventory-engine-has-singleton decision"
  - "cancel-sleep-lapse-reason-param: cancel_sleep_lapse() takes reason String param (not parameterless) so WorldClock can emit contextual reason to Builder listeners"
  - "hostile-mob-_ready-spawning-notify: HostileMob._ready uses get_tree().root.get_node_or_null('/root/Spawning') pattern (not Engine.has_singleton) — same pattern established for GDScript autoloads"
  - "try-spawn-tick-public: try_spawn_tick() public wrapper added to Spawning (calls _run_spawn_tick) so tests can trigger explicit ticks without relying on _process accumulator"
  - "toast-requested-signal-name: cancel_sleep_lapse_with_reason uses Toasts.show() which emits toast_requested (not toast_shown); test updated to match actual Toasts API"
metrics:
  duration: "~30 minutes"
  completed: "2026-05-27"
  tasks_completed: 1
  files_modified: 6
---

# Phase 03 Plan 03: Spawning Autoload + HostileMob Base Class + WorldClock Sleep Multiplier Summary

**One-liner:** Chunk-keyed bed-bubble spawn-gate autoload, HostileMob CharacterBody3D base class with 6-state dispatcher, and 10× WorldClock sleep-lapse multiplier wired to Toasts.

## What Was Built

### 1. Spawning Autoload (`src/autoload/spawning.gd`)

Registered after Inventory in project.godot (load-order contract: Inventory initialises before Spawning, enabling Spawning to consult `Inventory.get_chest(chunk)` for locked-chest spawn suppression).

#### API Table

| Function | Purpose | Caller |
|---|---|---|
| `register_bed(world_pos)` | Add a bed to the chunk-keyed bubble index | BedEntity._ready (Plan 03-11) |
| `unregister_bed(world_pos)` | Remove a bed from the bubble index | BedEntity._exit_tree (Plan 03-11) |
| `is_inside_any_bed_bubble(world_pos)` | O(beds-in-chunk) bubble check | _run_spawn_tick, ghost.gd bubble-repel (Plan 03-10) |
| `hostiles_inside_bed_bubble(bed_pos)` | Count active hostiles inside 8 m of bed | Builder.sleep_interact (Plan 03-04, Pitfall 9 poll) |
| `is_eligible_spawn_position(pos, ambient_light)` | Bed-bubble + light-gate combined check | _run_spawn_tick, test_spawning_rules |
| `can_spawn_in_chunk(chunk_coord)` | Per-chunk cap check (default 10) | _run_spawn_tick |
| `try_spawn_tick()` | Public entry point for one spawn tick | Tests + any system wanting explicit control |
| `notify_spawned(mob)` | Register mob when it enters tree | HostileMob._ready() |
| `notify_despawned(mob)` | Deregister mob when it leaves tree | HostileMob._exit_tree() |
| `clear_hostiles_in_chunk_range(centre, radius)` | Queue-free hostiles in chunk cube | Tier-3 sleep fallback (Plan 03-04) |
| `set_hostile_mob_cap_override(cap)` | Adaptive-quality cap override | main_scene adaptive-quality (Plan 03-10) |
| `register_active_sleep_bubble(bed_pos)` | Mark a bed bubble as active during sleep | Builder.sleep_interact (Plan 03-04) |
| `_on_hostile_entered_bed_bubble(bed_pos, mob_id)` | Cancels WorldClock sleep lapse | Ghost.gd bubble-repel (Plan 03-10), tests |
| `_test_set_mode_override(mode)` | Test hook for survival/sandbox override | test_spawning_rules |

#### Signals

| Signal | When | Consumer |
|---|---|---|
| `hostile_spawned(mob, position)` | mob enters scene tree | future: multiplayer replication (Phase 4) |
| `hostile_despawned(mob)` | mob leaves scene tree | future: multiplayer replication (Phase 4) |
| `bed_registered(world_pos)` | bed added to index | future: minimap (Phase 6) |
| `bed_unregistered(world_pos)` | bed removed from index | future: minimap (Phase 6) |
| `should_spawn(kind, position)` | spawn gates all passed | Plan 03-10 → main_scene.spawn_hostile_mob |

### 2. HostileMob Base Class (`src/combat/hostile_mob.gd`)

```
HostileMob (CharacterBody3D)      ← THIS PLAN
├── LaserPenguin                  ← Plan 03-10
├── Ghost                         ← Plan 03-10
├── Vampire                       ← Plan 03-10
├── Bat                           ← Plan 03-10
└── CubeSlime                     ← Plan 03-10
```

**DOES NOT extend VillageNpc** — per CONTEXT D-09 + Architectural Responsibility Map. Inherits the SHAPE (CharacterBody3D, state timer, physics process dispatch, gravity branch), not the IDENTITY.

State machine dispatch (6 virtuals, all empty by default — subclasses override only what they use):
```gdscript
enum State { IDLE, SEEK, ATTACK, FLEE, TRANSFORM, DEAD }

func _physics_process(delta: float) -> void:
    _state_timer += delta
    _path_query_cooldown -= delta
    if not is_on_floor():
        velocity.y += get_gravity().y * delta
    else:
        velocity.y = 0.0
    match state:
        State.IDLE:      _process_idle(delta)
        State.SEEK:      _process_seek(delta)
        State.ATTACK:    _process_attack(delta)
        State.FLEE:      _process_flee(delta)
        State.TRANSFORM: _process_transform(delta)
        State.DEAD:      _process_dead(delta)
    move_and_slide()
```

### 3. WorldClock Sleep Multiplier Extension

**Modified `_process` (relevant excerpt):**
```gdscript
var now: float = Time.get_unix_time_from_system()
# _sleep_multiplier: 1.0 normally; 10.0 during a sleep lapse
var wall_delta: float = (now - _last_wall_unix) * _sleep_multiplier
_last_wall_unix = now
if wall_delta > SECONDS_PER_DAY:
    wall_delta = SECONDS_PER_DAY   # Pitfall 3 cap still intact
elapsed_seconds += wall_delta
# … existing phase/day_boundary logic …
# Wake-target check appended at end:
if _sleep_target_progress >= 0.0:
    var progress: float = current_day_progress()
    if progress <= _sleep_target_progress + 0.01 and progress >= 0.0:
        cancel_sleep_lapse("woke_at_dawn")
```

New signals and methods:
- `signal sleep_lapse_ended(reason: String)` — Plan 03-04 Builder listens to restore HP + close UI
- `func start_sleep_lapse(multiplier: float = 10.0, target_phase: Phase = Phase.DAWN) -> void`
- `func cancel_sleep_lapse(reason: String = "cancelled_by_caller") -> void`
- `func cancel_sleep_lapse_with_reason(reason: String) -> void` — shows toast + cancels

## Pitfall 5 Mitigation Evidence

`register_bed()` uses a bounding-box scan over chunk coordinates to index each bed under EVERY chunk its 8 m bubble intersects (rather than a flat list of all beds):

```gdscript
func register_bed(world_pos: Vector3) -> void:
    _all_beds.append(world_pos)
    var min_chunk := Vector3i(
        floori((world_pos.x - BED_BUBBLE_RADIUS_M) / CHUNK_SIZE_M),
        floori((world_pos.y - BED_BUBBLE_RADIUS_M) / CHUNK_SIZE_M),
        floori((world_pos.z - BED_BUBBLE_RADIUS_M) / CHUNK_SIZE_M)
    )
    var max_chunk := Vector3i(
        floori((world_pos.x + BED_BUBBLE_RADIUS_M) / CHUNK_SIZE_M),
        floori((world_pos.y + BED_BUBBLE_RADIUS_M) / CHUNK_SIZE_M),
        floori((world_pos.z + BED_BUBBLE_RADIUS_M) / CHUNK_SIZE_M)
    )
    for cx in range(min_chunk.x, max_chunk.x + 1):
        for cy in range(min_chunk.y, max_chunk.y + 1):
            for cz in range(min_chunk.z, max_chunk.z + 1):
                var ck := Vector3i(cx, cy, cz)
                if not _beds_by_chunk.has(ck):
                    _beds_by_chunk[ck] = []
                (_beds_by_chunk[ck] as Array).append(world_pos)
    emit_signal("bed_registered", world_pos)
```

`is_inside_any_bed_bubble()` only reads the 1-3 chunks containing `world_pos` — O(beds-in-chunk), not O(all-beds).

## Pitfall 9 Mitigation Evidence

`Spawning._on_hostile_entered_bed_bubble()` is the hook Plan 03-10's ghost.gd calls when the ghost enters a bubble boundary. It immediately calls `WorldClock.cancel_sleep_lapse("cancelled_unsafe")`.

Plan 03-04 (Builder.sleep_interact) is responsible for the per-tick poll:
```gdscript
# Plan 03-04 will add this to Builder._physics_process during a lapse:
if Spawning.hostiles_inside_bed_bubble(_active_sleep_bed_pos) > 0:
    WorldClock.cancel_sleep_lapse("cancelled_unsafe")
```
This plan provides `hostiles_inside_bed_bubble()` and the wiring stub; Plan 03-04 completes the connection.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Engine.has_singleton() returns false for GDScript autoloads**
- **Found during:** Test verification
- **Issue:** test_spawning_rules.gd and test_sleep_lapse.gd both used `Engine.has_singleton("Spawning")` which always returns false per the established `inventory-engine-has-singleton` decision in STATE.md. Tests would remain permanently pending even after implementation.
- **Fix:** Updated both test files to use direct autoload access (`Spawning.*`, `Toasts.*`) and `has_method()` guards — consistent with the established codebase pattern.
- **Files modified:** tests/unit/test_spawning_rules.gd, tests/unit/test_sleep_lapse.gd
- **Commit:** 14c0016

**2. [Rule 2 - Missing critical] Wrong Toasts signal name in test_sleep_lapse.gd test 4**
- **Found during:** Test execution
- **Issue:** Original test used `Toasts.has_signal("toast_shown")` and asserted `toast_shown` signal. The actual Toasts autoload emits `toast_requested` (not `toast_shown`). Test would remain pending indefinitely.
- **Fix:** Updated test to use `toast_requested` + added `cancel_sleep_lapse_with_reason()` to WorldClock that calls `Toasts.show("ui.sleep.cancelled_unsafe", "warning")`.
- **Files modified:** tests/unit/test_sleep_lapse.gd, src/autoload/world_clock.gd
- **Commit:** 14c0016

**3. [Rule 2 - Missing] try_spawn_tick() public entry point missing**
- **Found during:** Test verification
- **Issue:** test_spawning_rules.gd test 1 calls `Spawning.try_spawn_tick()` directly but the plan's action only specified `_run_spawn_tick()` as a private method.
- **Fix:** Added public `try_spawn_tick()` wrapper that applies the sandbox gate and delegates to `_run_spawn_tick()`.
- **Files modified:** src/autoload/spawning.gd
- **Commit:** 14c0016

## Validation Table Updates

| Test File | Before | After |
|---|---|---|
| tests/unit/test_spawning_rules.gd | 4 pending | 4 passing |
| tests/unit/test_sleep_lapse.gd | 4 pending | 4 passing |

Overall suite: 125 → 131 passing; 25 → 19 pending; 2 failing (pre-existing, unrelated).

## Self-Check: PASSED

Files confirmed to exist:
- /Users/jnuyens/src/LegoMinecraft/src/combat/hostile_mob.gd: FOUND
- /Users/jnuyens/src/LegoMinecraft/src/autoload/spawning.gd: FOUND
- /Users/jnuyens/src/LegoMinecraft/src/autoload/world_clock.gd: FOUND (modified)
- /Users/jnuyens/src/LegoMinecraft/project.godot: FOUND (modified)

Commit confirmed: 14c0016 (feat(03-03): Spawning autoload, HostileMob base class, WorldClock sleep multiplier)

Done-criteria verified:
- class_name HostileMob: 1 match
- extends VillageNpc (must be 0): 0 matches
- enum State: 1 match
- _process_<state> virtuals: 6 (idle, seek, attack, flee, transform, dead)
- func is_inside_any_bed_bubble: 1 match
- register_bed + unregister_bed + hostiles_inside_bed_bubble + clear_hostiles_in_chunk_range: 4 matches
- BED_BUBBLE_RADIUS_M: float = 8.0: 1 match
- func start_sleep_lapse + cancel_sleep_lapse: 3 matches (includes cancel_sleep_lapse_with_reason)
- (now - _last_wall_unix) * _sleep_multiplier: 1 match
- signal sleep_lapse_ended: 1 match
- Spawning="*res://src/autoload/spawning.gd" in project.godot: 1 match
- test_spawning_rules.gd: 4/4 passing
- test_sleep_lapse.gd: 4/4 passing
