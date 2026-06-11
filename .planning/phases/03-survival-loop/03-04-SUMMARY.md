---
phase: 03-survival-loop
plan: "04"
subsystem: survival-hud-death-respawn
tags:
  - phase-3
  - survival
  - hp
  - damage
  - death
  - respawn
  - sleep
  - ui
dependency_graph:
  requires:
    - 03-02  # Inventory autoload (DEATH_DROP event, apply_event, death_pile_spawned signal)
    - 03-03  # Spawning autoload (hostiles_inside_bed_bubble), WorldClock (sleep lapse, sleep_lapse_ended)
  provides:
    - Builder HP/damage/death/respawn/sleep state machine
    - HpBar HBoxContainer (10 hearts, survival-mode gated)
    - DeathScreen ColorRect (3-second fade overlay, respawn_ready signal)
    - DeathPile StaticBody3D (single composite entity, walk-through pickup, 2-day despawn)
    - main_scene.gd death_pile_spawned wiring
  affects:
    - src/world/main_scene.tscn (HpBar + DeathScreen + DamageVignette added to UI layer)
    - src/builder/builder.gd (extended with ~350 lines of survival state machine)
tech_stack:
  added:
    - HBoxContainer heart icons with TextureRect/ColorRect fallback (HpBar)
    - ColorRect full-screen tween with Tween.EASE_IN, TRANS_QUART (DeathScreen)
    - StaticBody3D + Area3D walk-through pickup + MultiMeshInstance3D (DeathPile)
    - OmniLight3D glow on DeathPile (GLOW_COLOR #F5C30D, energy 0.6, range 2 m)
    - SpringArm3D camera h_offset shake on damage
    - Input.vibrate_handheld(50) haptic feedback on damage (mobile)
  patterns:
    - Survival mode gate: Features.is_survival_mode() at top of take_damage / eat_food
    - Double-death prevention: _is_dead flag set immediately, cleared only by respawn_at
    - Sleep input disambiguation: sleep_interact processed before ui_inventory_toggle + set_input_as_handled
    - Game-clock despawn timer: WorldClock.elapsed_seconds (not wall-clock) for 2-day pile lifetime
    - Tier-3 adaptive quality: ThermalProbe.is_tier_3() reduces DeathPile glow energy 0.6 → 0.3
    - Void-fall surface raycast: collision_mask=1 (terrain only), searches downward from Y=256
key_files:
  created:
    - src/ui/hp_bar.gd
    - src/ui/hp_bar.tscn
    - src/ui/death_screen.gd
    - src/ui/death_screen.tscn
    - src/world/death_pile.gd
    - src/world/death_pile.tscn
  modified:
    - src/builder/builder.gd
    - src/world/main_scene.gd
    - src/world/main_scene.tscn
    - project.godot
    - tests/integration/test_death_respawn.gd
decisions:
  - "death-pile-box-mesh-placeholder: DeathPile CompositeMesh uses BoxMesh placeholder (not brick_1x1.glb) because no .glb assets exist yet; Plan 02-09 ships placement raycasts but not standalone glb assets; placeholder is a visual stand-in only"
  - "void-fall-pre-compute-position: Builder._compute_death_pile_position runs before DEATH_DROP event dispatch so the event position IS the final surface-corrected pile position; Inventory does not need to know about void-fall logic"
  - "death-screen-color-rect: DeathScreen extends ColorRect (not CanvasLayer) so it lives in the UI tree and can be positioned with anchor presets; color.a used for the fade (not modulate.a)"
  - "show-death-screen-alias: show_death_screen() is a public alias for start_fade(false, Callable()) to support GUT test assertions without needing builder context"
metrics:
  duration_minutes: 90
  completed_date: "2026-05-27"
  tasks_completed: 4
  files_created: 6
  files_modified: 5
---

# Phase 03 Plan 04: Survival HUD + Damage + Death + Respawn Summary

**One-liner:** Full survival state machine — 10-heart HP bar, 3-second death overlay, single-entity DeathPile with walk-through pickup, void-fall surface correction, and bed-sleep WorldClock lapse integration.

## Tasks Completed

| # | Task | Commit | Files |
|---|------|--------|-------|
| 1 | Builder HP/damage/death/respawn/sleep state machine + input actions | `aabbd87` | `src/builder/builder.gd`, `project.godot` |
| 2 | HP bar UI + Death overlay scene | `e2f11b0` | `src/ui/hp_bar.gd`, `src/ui/hp_bar.tscn`, `src/ui/death_screen.gd`, `src/ui/death_screen.tscn` |
| 3 | DeathPile entity + main_scene HUD wiring + spawn_death_pile helper | `16db0fa` | `src/world/death_pile.gd`, `src/world/death_pile.tscn`, `src/world/main_scene.gd`, `src/world/main_scene.tscn` |
| 4 | Fix test_death_respawn.gd — direct autoload access + local DeathPile wiring | `d73f006` | `tests/integration/test_death_respawn.gd` |

## Test Results

All 6 tests in `tests/integration/test_death_respawn.gd` pass:

- `test_hp_zero_triggers_death_drop` — PASS
- `test_death_pile_is_single_composite_entity` — PASS
- `test_respawn_at_last_slept_bed` — PASS
- `test_respawn_at_world_spawn_if_never_slept` — PASS
- `test_void_fall_drops_at_surface_coordinates` — PASS
- `test_3s_fade_overlay_runs_before_respawn` — PASS

Overall suite: 33 passing, 4 pending (pre-existing pending tests in test_pickup_integration.gd and test_dynamite_blast.gd — unrelated to this plan).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Engine.has_singleton returns false for GDScript autoloads**
- **Found during:** Task 4 (test run — all 6 tests went pending)
- **Issue:** Original test stubs used `Engine.has_singleton("Inventory")` as a guard before accessing the autoload. GDScript autoloads registered via project.godot are not C++ engine singletons; `has_singleton()` returns false for them (per `inventory-engine-has-singleton` decision, STATE.md). This caused tests 1, 2, and 5 to fall through to pending.
- **Fix:** Removed all `Engine.has_singleton("Inventory")` guards. Used `Inventory.*` directly (same as the 03-02/03-03 test pattern).
- **Files modified:** `tests/integration/test_death_respawn.gd`
- **Commit:** `d73f006`

**2. [Rule 2 - Missing functionality] Tests 2 and 5 needed local DeathPile wiring**
- **Found during:** Task 4
- **Issue:** `Inventory.death_pile_spawned` is only wired to `main_scene._on_death_pile_spawned` when main_scene is running. In headless GUT tests, main_scene is not present, so no DeathPile was ever spawned and `get_nodes_in_group("death_pile")` returned empty.
- **Fix:** Added a local lambda signal handler using `CONNECT_ONE_SHOT` in tests 2 and 5. The handler instantiates the DeathPile scene and calls `add_child_autofree(pile)` — mirroring what main_scene does in production.
- **Files modified:** `tests/integration/test_death_respawn.gd`
- **Commit:** `d73f006`

**3. [Rule 1 - Bug] Test 6 used wrong base type and wrong alpha property**
- **Found during:** Task 4
- **Issue:** Original test 6 created `CanvasLayer.new()` and set the death_screen.gd script on it. `DeathScreen` extends `ColorRect`, not `CanvasLayer`. The test also checked `death_screen.modulate.a` but `DeathScreen` controls `color.a` (the ColorRect's fill color), not the inherited `modulate` property.
- **Fix:** Changed test 6 to load and instantiate `death_screen.tscn` directly as `ColorRect`, and changed the assertion to `death_screen.color.a <= 0.1`.
- **Files modified:** `tests/integration/test_death_respawn.gd`
- **Commit:** `d73f006`

**4. [Rule 2 - Missing functionality] DeathPile uses BoxMesh placeholder instead of brick_1x1.glb**
- **Found during:** Task 3
- **Issue:** The plan referenced the composite mesh heap using brick .glb assets. No .glb files exist in `src/bricks/` (mesh=null on all .tres files per `brick-mesh-null-phase2` decision).
- **Fix:** Used `BoxMesh` as a placeholder mesh in the MultiMesh sub-resource. The functional behaviour (single composite entity, walk-through pickup, glow, despawn) is unaffected. Documented as `death-pile-box-mesh-placeholder` decision.
- **Files modified:** `src/world/death_pile.tscn`
- **Commit:** `16db0fa`

## Decisions Made

- **death-pile-box-mesh-placeholder:** CompositeMesh uses BoxMesh placeholder; no .glb assets exist yet (brick-mesh-null-phase2). Plan 14 / Phase 2 asset work will swap to actual brick mesh.
- **void-fall-pre-compute-position:** Builder._compute_death_pile_position runs before DEATH_DROP dispatch; the event position IS the final surface-corrected position. Inventory.apply_event(DEATH_DROP) is position-agnostic.
- **death-screen-color-rect:** DeathScreen extends ColorRect; color.a drives the fade (not modulate.a). Positioned via anchor presets in the UI CanvasLayer.
- **show-death-screen-alias:** show_death_screen() is a GUT-friendly public alias for start_fade(false, Callable()) to allow test 6 to verify fade behaviour without builder context.

## Known Stubs

None — all plan goals are functionally achieved. The BoxMesh placeholder in DeathPile.tscn is cosmetic only; the entity logic (pickup, despawn, glow, group membership) is fully wired.

## Threat Flags

None — no new network endpoints, auth paths, or trust-boundary schema changes introduced.

## Self-Check: PASSED

- `src/builder/builder.gd` — FOUND
- `src/ui/hp_bar.gd` — FOUND
- `src/ui/hp_bar.tscn` — FOUND
- `src/ui/death_screen.gd` — FOUND
- `src/ui/death_screen.tscn` — FOUND
- `src/world/death_pile.gd` — FOUND
- `src/world/death_pile.tscn` — FOUND
- `src/world/main_scene.gd` — FOUND
- Commits `aabbd87`, `e2f11b0`, `16db0fa`, `d73f006` — FOUND in git log
- 6/6 test_death_respawn tests passing — VERIFIED
