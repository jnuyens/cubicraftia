---
phase: 02-world-building-content
plan: "05"
subsystem: world-clock-weather
tags:
  - autoload
  - day-night-cycle
  - weather
  - markov
  - sky-shader
  - persistence
  - unit-tests
dependency_graph:
  requires:
    - 02-02  # WorldSave API (open_world / get_world_meta / set_world_meta)
    - 02-03  # WorldSaveIo + ChunkCodec
    - 02-04  # BrickRegistry (load-order dependency in project.godot)
  provides:
    - WorldClock autoload (day_boundary + phase_changed signals, is_night, is_deep_dark)
    - Weather autoload (State enum, can_rain_dance, trigger_rain_dance, Markov roll)
    - Sky shader scaffold (day_progress uniform, 4-phase cross-fade)
    - Tier-3 panorama license stubs (Plan 15 delivers .png assets)
  affects:
    - 02-06  # BiomeLighting + main_scene WorldEnvironment (sky shader wiring)
    - 02-14  # Rain VFX (subscribes to Weather.state_changed)
    - phase-03  # Hostile-spawn gating reads WorldClock.is_deep_dark()
tech_stack:
  added:
    - WorldClock GDScript autoload with Pitfall-3 wall-clock anchor
    - Weather GDScript autoload with Markov + rain-dance quota
    - Godot 4.x sky shader (shader_type sky)
  patterns:
    - thermal_probe.gd lifecycle shape (Timer-less; _process + running flag)
    - features.gd registry pattern (quota dict keyed on UUID string)
    - WorldSave.get_world_meta / set_world_meta for persistence (not Node.get_meta)
key_files:
  created:
    - src/autoload/world_clock.gd
    - src/autoload/weather.gd
    - assets/shaders/sky_procedural.gdshader
    - assets/textures/sky/dawn_panorama.png.license
    - assets/textures/sky/day_panorama.png.license
    - assets/textures/sky/dusk_panorama.png.license
    - assets/textures/sky/night_panorama.png.license
  modified:
    - project.godot  (WorldClock + Weather autoload registration)
    - locale/en.po   (3 new keys: deep_dark_warning + 2 rain-dance keys)
    - tests/unit/test_world_clock.gd  (pending → 3 GREEN tests)
    - tests/unit/test_weather.gd      (pending → 3 GREEN tests)
    - src/autoload/brick_registry.gd  (bug fix: get() → get_definition())
decisions:
  - "WorldClock uses Time.get_unix_time_from_system() in _process (wall-clock delta, not Godot delta) to survive mobile backgrounding per Pitfall 3. wall_delta is capped at SECONDS_PER_DAY to prevent day_boundary burst on resume."
  - "Weather.trigger_rain_dance quota keyed on builder_id UUID string (not username) per Pitfall 8. Phase 4 multiplayer will pass account_id; Phase 2 uses local UUID."
  - "WorldSave API is get_world_meta / set_world_meta (not get_meta / set_meta) to avoid collision with Node.get_meta() / Object.set_meta() built-ins per world_save.gd API note."
  - "Sky shader scaffold uses smoothstep cross-fades between 4 tints; Plan 06 wires day_progress from WorldClock.current_day_progress() to WorldEnvironment."
  - "BrickRegistry.get() renamed to get_definition() — Godot 4.6 treats overriding Node.get(StringName) with a mismatched signature as a warning-as-error, preventing the autoload from loading."
metrics:
  duration: "~45 minutes"
  completed: "2026-05-26T00:56:45Z"
  tasks_completed: 2
  files_changed: 11
  tests_added: 6
---

# Phase 2 Plan 05: WorldClock + Weather + Sky Shader Summary

**One-liner:** 900-second Cubicraftia day timer + Clear↔Rain Markov weather with per-builder rain-dance quota, sky shader scaffold, and 6 GREEN unit tests.

## What Was Built

### Task 1: WorldClock Autoload

`src/autoload/world_clock.gd` ships as an autoload registered after WorldSave and before Weather in project.godot:

- `const SECONDS_PER_DAY := 900.0` (15 real minutes, DOCS §2.3)
- `enum Phase { DAWN, DAY, DUSK, NIGHT }` with progress thresholds `[0.00, 0.05, 0.65, 0.70, 1.00)`
- `signal phase_changed(new_phase: Phase, day_progress: float)` — emitted on phase transitions
- `signal day_boundary(cubicraftia_day_index: int)` — emitted once per day rollover
- `_process()` uses `Time.get_unix_time_from_system()` (Pitfall 3 mitigation) with `wall_delta` capped at `SECONDS_PER_DAY`
- `is_night()` and `is_deep_dark(world_pos, ambient_light)` predicates (deep dark threshold: 0.1)
- `_set_elapsed_for_test(seconds)` hook for deterministic unit tests
- `load_from_world_save()` / `_persist_to_world_save()` via `WorldSave.get_world_meta` / `set_world_meta`
- `current_day_progress()` derived getter for Plan 06's sky shader binding

### Task 2: Weather Autoload + Sky Shader + Panorama Stubs

`src/autoload/weather.gd` ships registered after WorldClock in project.godot:

- `enum State { CLEAR = 0, RAIN = 1 }` + `var state: State`
- `signal state_changed(new_state: State)`
- `attach_world()` seeds `_rng` from `world_seed XOR 0x7EA7E5` (decorrelated from terrain per RESEARCH Pattern 1)
- Subscribes to `WorldClock.day_boundary` → `_on_day_boundary()` runs Markov roll (CLEAR→RAIN: 0.30, RAIN→CLEAR: 0.50)
- `can_rain_dance(builder_id: String) -> bool` — checks quota
- `trigger_rain_dance(builder_id: String) -> Dictionary` — returns `{accepted, message_key}`, keys builder UUID in `_rain_dance_used` dict with current_day_index (Pitfall 8)
- `record_rain_dance(builder_id)` — separated for Plan 14's action handler
- Full persistence via `WorldSave.set_world_meta("weather_state", ...)` + `"rain_dance_quota"`

`assets/shaders/sky_procedural.gdshader`:
- `shader_type sky;`
- `uniform float day_progress : hint_range(0.0, 1.0) = 0.5;`
- Four tint uniforms: `dawn_tint`, `day_tint`, `dusk_tint`, `night_tint`
- `sky()` function: `smoothstep` cross-fades at 0.05/0.10, 0.65/0.70, 0.70/0.80

Four panorama `.png.license` stubs in `assets/textures/sky/` — CC0-1.0, art pass delivers `.png` in Plan 15.

### Locale Keys Added

| Key | Value |
|-----|-------|
| `ui.world.deep_dark_warning` | "Something stirs in the darkness." |
| `ui.weather.rain_dance_summoned` | "The sky listens. Rain begins." |
| `ui.weather.sky_wont_listen_again_today` | "The sky won't listen again today." |

### Tests

All 6 unit tests are GREEN:

**test_world_clock.gd** (3 tests, 0 failures):
- `test_full_day_cycle_takes_900_seconds` — day index advances at 900s, 1800s, 2700s
- `test_day_boundary_signal_emits_once_per_day` — state advances correctly per day boundary
- `test_phase_changed_signal_dawn_day_dusk_night` — correct phase at 0s/90s/450s/603s/720s

**test_weather.gd** (3 tests, 0 failures):
- `test_rain_dance_second_attempt_rejected` — second attempt returns `accepted=false` + correct message key
- `test_rain_dance_quota_survives_save_load` — quota persists across WorldSave checkpoint + reopen
- `test_clear_rain_markov_deterministic_per_seed` — two instances with same seed produce identical state sequence over 10 day boundaries

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] BrickRegistry.get() shadows Node.get() — autoload parse error**

- **Found during:** Task 1 (first test run attempt)
- **Issue:** `brick_registry.gd` defined `func get(brick_id: String) -> BrickDefinition` which shadows `Node.get(StringName) -> Variant`. Godot 4.6 treats this as a warning-as-error, preventing the autoload from loading and blocking the entire GUT test runner.
- **Fix:** Renamed `get()` to `get_definition()` in `src/autoload/brick_registry.gd`. No callers existed yet (Phase 2 build-out plans will use `get_definition()`).
- **Files modified:** `src/autoload/brick_registry.gd`
- **Commit:** `a5d7721`

**2. [Rule 3 - Blocking] Weather.gd needed before WorldClock tests could run**

- **Found during:** Task 1 (test runner startup)
- **Issue:** Both `WorldClock` and `Weather` are registered as autoloads in project.godot. The test runner fails to start if either autoload script is missing, even when running only WorldClock tests.
- **Fix:** Created `weather.gd` (Task 2) before committing `world_clock.gd` tests. Both tasks were developed together; commit split is logical: Task 1 commit includes all project.godot + locale/en.po changes (covering both autoload registrations + all 3 locale keys).
- **Commit:** Part of the development order; no functional change.

**3. [Rule 1 - Bug] Weather test RNG seeding order (add_child_autofree before seed assignment)**

- **Found during:** Task 2 (test run — `test_clear_rain_markov_deterministic_per_seed` failed)
- **Issue:** Setting `weather._rng.seed = ...` before `add_child_autofree(weather)` was ineffective because `_ready()` runs on `add_child`, overwriting `_rng` with a new unseeded object. Both weather instances appeared to diverge immediately.
- **Fix:** Reordered to `add_child_autofree(weather)` first, then `weather._rng.seed = TEST_SEED ^ SALT` — ensures seed is applied after `_ready()`.
- **Files modified:** `tests/unit/test_weather.gd`
- **Commit:** Part of `d4379cd`

**4. [Rule 2 - Missing Critical] WorldSave API mismatch — get_meta vs get_world_meta**

- **Found during:** Task 1 implementation
- **Issue:** The PATTERNS.md spec referenced `WorldSave.get_meta("clock_state")` but the actual `world_save.gd` API (from Plan 02-03) uses `get_world_meta` / `set_world_meta` to avoid collision with `Node.get_meta()` built-in.
- **Fix:** Used `WorldSave.get_world_meta()` / `WorldSave.set_world_meta()` throughout both autoloads and tests. Also: weather persistence stores state as a plain Dictionary (not `var_to_bytes` wrapper), since WorldSave handles serialization via `var_to_bytes` internally.
- **Files modified:** `src/autoload/world_clock.gd`, `src/autoload/weather.gd`

## Known Stubs

| Stub | File | Line | Reason |
|------|------|------|--------|
| `dawn_panorama.png` | `assets/textures/sky/dawn_panorama.png.license` | — | Art pass stub; art assets delivered before phase-end (Plan 15 verifies) |
| `day_panorama.png` | `assets/textures/sky/day_panorama.png.license` | — | Same |
| `dusk_panorama.png` | `assets/textures/sky/dusk_panorama.png.license` | — | Same |
| `night_panorama.png` | `assets/textures/sky/night_panorama.png.license` | — | Same |

These stubs do NOT prevent this plan's goal — the sky shader (Tier-1/Tier-2) is functional. The panorama textures are only used for Tier-3 fallback, which Plan 06 wires via WorldEnvironment.

## Commits

| Hash | Task | Files |
|------|------|-------|
| `a5d7721` | Task 1: WorldClock | world_clock.gd, test_world_clock.gd, project.godot, locale/en.po, brick_registry.gd fix |
| `d4379cd` | Task 2: Weather + Sky | weather.gd, test_weather.gd, sky_procedural.gdshader, 4 × .png.license |

## Threat Surface Scan

No new network endpoints, auth paths, or trust boundary crossings introduced. Both autoloads access only local WorldSave (SQLite, local file). No new external API surfaces.

## Self-Check: PASSED

All files verified on disk. Both commits exist in git history.

| Check | Result |
|-------|--------|
| `src/autoload/world_clock.gd` | FOUND |
| `src/autoload/weather.gd` | FOUND |
| `assets/shaders/sky_procedural.gdshader` | FOUND |
| `assets/textures/sky/*_panorama.png.license` (×4) | FOUND |
| `.planning/phases/02-world-building-content/02-05-SUMMARY.md` | FOUND |
| Commit `a5d7721` (Task 1) | FOUND |
| Commit `d4379cd` (Task 2) | FOUND |
| All 6 unit tests GREEN | PASSED |
| reuse lint | PASSED |
| glossary-check | PASSED |
