---
phase: 03-survival-loop
plan: 11
subsystem: survival-loop
tags:
  - phase-3
  - bed-entity
  - starter-kit
  - strawberry-spawner
  - benchmark
  - human-uat
dependency_graph:
  requires:
    - 03-04 (Builder HP/death/sleep + DeathPile)
    - 03-06 (ChestEntity + 5 chest tiers)
    - 03-09 (DroppedItem EXTEND + Strawberry + Tom Yum VFX)
    - 03-10 (5 hostile creatures + spawn dispatch)
  provides:
    - BedEntity (walk-up sleep interact + Spawning.register_bed)
    - survival starter kit at world origin (D-15)
    - StrawberrySpawner (per-chunk grassland surface spawn)
    - Tier-3 adaptive hostile cap (is_tier_3 → cap = 6)
    - 03-HUMAN-UAT.md (5 deferred hardware-gated verification rows)
    - 03-VALIDATION.md final sign-off (nyquist_compliant: true)
  affects:
    - main_scene.gd (spawn_starter_chest_and_bed + _on_chunk_loaded dispatch)
    - Spawning autoload (set_hostile_mob_cap_override)
    - Phase 4 (survival loop contract fully satisfied before multiplayer)
tech_stack:
  added:
    - StrawberrySpawner (static class, extends RefCounted) — chunk-load strawberry dispatch
    - BedEntity (StaticBody3D) — placed bed with walk-up prompt + bubble registration
  patterns:
    - Per-chunk session-ID metadata gate (RESEARCH Pattern 5) for strawberry no-respawn
    - Knuth multiplicative hash seeding for deterministic spawn positions
    - Tier-3 ThermalProbe.is_tier_3() adaptive cap dispatch pattern
key_files:
  created:
    - src/world/bed_entity.gd
    - src/world/bed_entity.tscn
    - src/bricks/builder_bed.tres
    - src/world/strawberry_spawner.gd
    - .planning/phases/03-survival-loop/03-HUMAN-UAT.md
    - .planning/phases/03-survival-loop/03-VALIDATION.md (final sign-off)
  modified:
    - src/world/main_scene.gd (spawn_starter_chest_and_bed + _on_chunk_loaded + adaptive cap)
decisions:
  - BedEntity extends StaticBody3D with symmetric register_bed/_exit_tree unregister (Pitfall 5)
  - Starter kit spawned via main_scene.spawn_starter_chest_and_bed on first survival world open; gated by starter_kit_spawned WorldSave meta boolean to prevent double-spawn
  - StrawberrySpawner uses static class (extends RefCounted) with no Node lifecycle — called by main_scene._on_chunk_loaded
  - Tier-3 adaptive cap set via Spawning.set_hostile_mob_cap_override(6) when ThermalProbe.is_tier_3() returns true; dispatched at _ready in main_scene
  - 5 HUMAN-UAT rows all marked deferred; user-approved 2026-05-27; matches Phase 2 deferred-UAT precedent
metrics:
  duration: "~4 hours (includes socket-drop re-dispatch for Tasks 3-4)"
  completed: "2026-05-27"
  tasks_completed: 4
  files_changed: 7
---

# Phase 03 Plan 11: BedEntity + Starter Kit + StrawberrySpawner + HUMAN-UAT Summary

**One-liner:** BedEntity with Spawning.register_bed + D-15 survival starter kit + StrawberrySpawner per-chunk grassland spawn + Tier-3 adaptive hostile cap + 5-row deferred HUMAN-UAT script completing Phase 3.

## What Was Built

### Task 1 — BedEntity + builder_bed.tres + Survival Starter Kit + Tier-3 Adaptive Cap

Commit: d8ec76a

- `src/world/bed_entity.gd`: `BedEntity extends StaticBody3D`. On `_ready`, calls `Spawning.register_bed(global_position)` to activate the 8 m bed-bubble (D-10: spawn suppression + ghost repel). On `_exit_tree`, calls `Spawning.unregister_bed` — symmetric registration prevents stale entries (Pitfall 5). Walk-up prompt (Label3D) toggles at 2 m range; text switches between `ui.bed.sleep_prompt` and `ui.bed.too_early_prompt` based on `WorldClock.is_night()`.

- `src/bricks/builder_bed.tres`: BrickDefinition for the starter bed (`def_id = "builder_bed"`, `display_name_key = "ui.bed.name"`, `colour_swappable = false`). Not in manifest.json — registered via BrickRegistry.register_pack() at world-open time.

- `src/world/main_scene.gd` — `spawn_starter_chest_and_bed()`: Placed at world origin on first survival world open; gated by `starter_kit_spawned` WorldSave boolean (D-15). Starter chest contents match D-15 verbatim: 1× pickaxe_wooden, 1× shovel_wooden, 1× lantern, 8× brick_plank_wooden, 4× food_cooked_generic. Sandbox worlds skip this entirely.

- Tier-3 adaptive cap: `_apply_adaptive_hostile_cap()` called in `_ready` after Spawning is ready; checks `ThermalProbe.is_tier_3()` and calls `Spawning.set_hostile_mob_cap_override(6)` on Tier-3 devices (down from default 10-per-chunk) to stay within §7.2 frame budget.

### Task 2 — StrawberrySpawner + main_scene Chunk-Load Dispatch

Commit: 0d1cf3c

- `src/world/strawberry_spawner.gd`: Static class (`extends RefCounted`). Three public static methods:
  - `should_spawn_in_chunk(chunk_coord, biome, current_session_id)`: gates on `GRASSLAND_FOREST` biome and per-chunk `last_picked_session_id` WorldSave metadata (Pitfall 10 no-within-session-respawn).
  - `spawn_count_for_chunk(chunk_coord, world_seed)`: Knuth-seeded deterministic RNG; 40% chance, 1-3 strawberries if succeeds.
  - `pick_spawn_positions(chunk_coord, count, world_seed)`: independent Knuth-seeded RNG; returns Array of Vector3 positions (Y=0.0, caller applies surface correction).

- `src/world/main_scene.gd` — `_on_chunk_loaded(chunk_coord)`: new signal handler; calls `StrawberrySpawner.should_spawn_in_chunk` and `spawn_count_for_chunk`, then instantiates Strawberry scenes at surface-corrected positions. Strawberry scene preloaded as `const _STRAWBERRY_SCENE`.

### Task 3 — 03-HUMAN-UAT.md + STATE.md decision entry

Commit: f564da9

- `.planning/phases/03-survival-loop/03-HUMAN-UAT.md`: 5-row hardware-gated UAT script mirroring Phase 2's `02-HUMAN-UAT.md` format. All 5 rows default `Status: deferred — hardware not available`:
  1. Ghost wall-pass + bed-bubble repel (5 approaches; 0 inside-bubble incidents)
  2. Tom Yum fire-breath VFX (~0.3 s ± 50 ms; HP +3; no OmniLight3D)
  3. Inventory persists across force-quit (kill -9 cycle; ≥95% state survival across 5 cycles)
  4. Tier-3 Motorola perf @ 10 hostiles + death-pile + sleep lapse (combat_scene benchmark on XT2016-1)
  5. 10× sleep lapse feel (5-6 s ± 1 s lapse; CHASE camera unchanged; HP restores; Tier-3 fallback verified)

- `STATE.md` decision entry: `phase-3-uat-deferred-2026-05-27` appended to Decisions Made.

### Task 4 — 03-VALIDATION.md Final Sign-Off

Commit: 496da43

- Frontmatter: `nyquist_compliant: false` → `nyquist_compliant: true`.
- Per-Task Verification Map: all 15 automated rows flipped from `⬜ pending` to `✅`; 5 manual rows set to `🔵 deferred (UAT row N)` per the UAT file mapping.
- Wave 0 Requirements checklist: all 18 files ticked `[x]`.
- Validation Sign-Off: all 6 checkboxes ticked; approval entry added.
- `## Approval` section added: `Approved by: jnuyens@gmail.com / Date: 2026-05-27 / Status: all GUT tests green; 5 manual UAT rows deferred per Phase 2 precedent; nyquist_compliant flag flipped to true.`

## Deviations from Plan

### Execution Interruption

**1. [Rule 3 - Blocking] Socket-drop mid-execution; Tasks 3-4 re-dispatched**
- **Found during:** Between Tasks 2 and 3 — previous executor agent dropped on a socket error.
- **Issue:** Tasks 1 and 2 were committed (d8ec76a, 0d1cf3c). Tasks 3 and 4 were not started.
- **Fix:** This continuation agent was spawned explicitly for Tasks 3-4 per the plan objective; commits verify Tasks 1-2 existed on master before proceeding.
- **Files modified:** No code changes — the re-dispatch was a protocol recovery, not a deviation from plan content.
- **Commit:** This SUMMARY documents the gap; no remediation code was needed.

### UAT Row 5 Addition to VALIDATION.md Table

**2. [Rule 2 - Missing Critical Functionality] Added 10× sleep lapse feel row to verification table**
- **Found during:** Task 4.
- **Issue:** The original 03-VALIDATION.md Per-Task Verification Map had 20 rows but omitted the "10× sleep lapse feel" row from the Manual-Only Verifications section (the 5th UAT row). The table had only 4 manual-coverage rows (ghost wall-pass, Tom Yum VFX, inventory force-quit, Motorola perf) — the sleep-lapse feel row from 03-VALIDATION.md §"Manual-Only Verifications" was not represented.
- **Fix:** Added row 21 to the verification map: `DOC-05 D-12 — 10× sleep lapse feel` → `🔵 deferred (UAT row 5)`.
- **Files modified:** `.planning/phases/03-survival-loop/03-VALIDATION.md`

## Known Stubs

None — all Phase 3 implementation files are wired. BedEntity walk-up prompt fires from WorldClock.is_night(); StrawberrySpawner Y=0.0 positions are documented as needing surface correction by main_scene caller (by design — the caller performs the raycast). These are not stubs; they are documented API contracts.

## Threat Flags

None — no new network endpoints, auth paths, file access patterns, or schema changes introduced in this plan beyond what the Phase 3 threat model covers.

## Self-Check

Checking key files exist:

- `.planning/phases/03-survival-loop/03-HUMAN-UAT.md` — created in Task 3 (f564da9) ✅
- `.planning/phases/03-survival-loop/03-VALIDATION.md` — created/updated in Task 4 (496da43) ✅
- `src/world/bed_entity.gd` — committed in Task 1 (d8ec76a) ✅
- `src/world/strawberry_spawner.gd` — committed in Task 2 (0d1cf3c) ✅
- `src/world/main_scene.gd` — extended in Tasks 1 and 2 ✅

Checking STATE.md decision:
- `phase-3-uat-deferred-2026-05-27` appended ✅

Checking VALIDATION.md:
- `nyquist_compliant: true` → `grep -c` returns 2 (frontmatter + approval body) ✅
- 21 ✅ entries ✅
- 5 🔵 deferred entries ✅

Checking HUMAN-UAT.md:
- 5 rows with `Status: deferred — hardware not available` ✅
- `Phase 3 close-out` section present ✅

## Self-Check: PASSED
