---
status: deferred
phase: 03-survival-loop
plan: 11
source: [03-VALIDATION.md §"Manual-Only Verifications"]
started: 2026-05-27T00:00:00Z
updated: 2026-05-27T00:00:00Z
user_approval: "2026-05-27 (approved deferred — see Phase 3 carryover debt; hardware runs scheduled for standalone session)"
---

# Phase 3 — Human UAT Script

> 5 manual-only verifications that cannot be exercised by the automated GUT test suite.
> Each row maps to a requirement from `03-VALIDATION.md §"Manual-Only Verifications"`.
> Results gate Phase 4 (Multiplayer). If any row is FAIL, a remediation plan (03-11.1 or
> hotfix branch) must ship before Phase 4 runs.
>
> Reference decisions: CONTEXT.md D-10 (bed-bubble sacred 8 m sphere), D-12 (10× sleep lapse
> solo-only), D-13 (Tom Yum fire-breath VFX — no damage), D-15 (starter chest + bed at origin),
> D-16 (strawberry rare grassland super-heal). Phase 2 deferred-UAT precedent:
> STATE.md `phase-2-uat-deferred-2026-05-26`.

---

## Tests

### 1. Ghost Wall-Pass + Bed-Bubble Repel

**Requirement:** DOC-05 SC#4 (RESEARCH.md Pitfall 9)
**Why manual:** Requires visible voxel collision behaviour; physics-state assertions are
brittle vs visual confirmation. Ghost wall-pass and bubble repulsion require observing
the 3D scene — neither is reliably testable in headless GUT mode.

**Setup:**
- Open a fresh survival world.
- Teleport builder to a flat area via the Godot remote debugger.
- Place a builder-bed via the debug console (or the normal place interaction).

**Steps:**
1. Spawn a ghost via console at position ~20 m from bed: `Spawning.debug_spawn("ghost", Vector3(20,0,0))`
2. Wait for the ghost to detect the builder (ghost enter AGGRO state, moves toward builder).
3. Observe the ghost pass through any wall or brick obstacle between it and the builder.
4. Watch the ghost approach the 8 m bed-bubble boundary.
5. Observe the bubble repulsion: ghost reverses direction, shimmer particle ring emits on contact.

**Expected:**
- Ghost phases through bricks/terrain unimpeded (no collision deflection by solid voxels).
- Ghost cannot enter the 8 m sphere centred on the bed (Spawning.register_bed radius).
- On contact with the bubble boundary, ghost reverses its movement direction.
- A visible shimmer particle ring emits at the boundary contact point with a chime audio cue.

**Pass criteria:**
- 5 separate ghost-bed-bubble approach sequences all result in repulsion from the bubble.
- 0 ghost-inside-bubble incidents across all 5 approaches.
- Wall-pass visually confirmed (ghost passes through at least one brick/terrain face unimpeded).

**Tester sign-off:**
- Name: ___________
- Date: ___________

**Status:** deferred — hardware not available

---

### 2. Tom Yum Fire-Breath VFX

**Requirement:** DOC-05 D-13
**Why manual:** Cosmetic VFX (~0.3 s duration) is feel/timing, not deterministic state.
Verifying the flame puff, the absence of a light source, and the exact HP delta requires
live scene observation — headless GUT cannot render or time particle systems reliably.

**Setup:**
- Open survival world.
- Add 1× `food_tom_yum` to inventory via console: `Inventory.debug_add_item("food_tom_yum", 1)`

**Steps:**
1. Right-click (or long-press on mobile) the `food_tom_yum` slot in the inventory screen.
2. Watch the builder's mouth area (front of head mesh in CHASE cam, or forward direction in FPV).
3. Observe the HP bar in the HUD for 1-2 seconds after eating.
4. Open the Godot Remote Scene Tree inspector; search for `OmniLight3D` nodes added since eating.

**Expected:**
- A flame puff particle effect emits from the builder's mouth direction for ~0.3 s (300 ms).
- HP increases by exactly 3 (matching `food_tom_yum.heal_amount`; confirmed in 03-09 item def).
- No `OmniLight3D` or `SpotLight3D` is created by `fire_breath_vfx.tscn` during or after the effect.
- No damage is applied to the builder or any entity near the builder.

**Pass criteria:**
- VFX duration is approximately 300 ms ± 50 ms (use stopwatch or frame-counter).
- HP delta = +3 (read from HP bar delta or debug console output).
- Remote scene tree shows no new `OmniLight3D` created by the VFX scene.

**Tester sign-off:**
- Name: ___________
- Date: ___________

**Status:** deferred — hardware not available

---

### 3. Inventory Persists Across Force-Quit

**Requirement:** DOC-04 SC#1 (save robustness — RESEARCH.md Pitfall 1)
**Why manual:** Cannot reliably force-quit Godot (kill -9) from inside headless GUT.
The persist-coalesce window (~30 s cadence) and the atomic-rename guarantee (Plan 02-03)
must be validated under a real OS kill.

**Setup:**
- Open survival world.
- Add varied items to inventory: mix of bricks, keys, food items, and at least 1 strawberry.
- Fill at least 20 inventory slots.

**Steps:**
1. Wait 5 s after filling inventory (ensure at least one autosave tick has passed; see `Inventory._persist_to_save` coalesce cadence).
2. Hard-kill the Godot process:
   - macOS/Linux: `kill -9 $(pgrep -f Godot)` in a terminal.
   - Windows: Task Manager → right-click Godot.exe → End Task.
3. Relaunch the Godot export or editor.
4. Reopen the same world.
5. Compare inventory contents to the pre-kill state (screenshot before kill recommended).
6. Repeat steps 1-5 a total of 5 times across different inventory states.

**Expected:**
- Inventory contents match the state from before the kill, minus any mutations within the last
  30 s of the persist coalesce window (items mutated in the last coalesce window may revert —
  this is acceptable and per-spec).
- No crash or error dialog on world reopen.
- No inventory slot corruption (mismatched stacks, negative counts, missing def_ids).

**Pass criteria:**
- ≥ 95% of pre-kill inventory state survives across all 5 kill-relaunch cycles.
- 0 corrupted or negative-count slots on any reopen.
- 0 "world data corrupted" or save-load error dialogs.

**Notes (fill in during test):**
- Platform tested: [fill in — e.g. "macOS 15.4", "Android 10"]
- Run 1 result (% surviving): [fill in]
- Run 2 result: [fill in]
- Run 3 result: [fill in]
- Run 4 result: [fill in]
- Run 5 result: [fill in]
- Any error dialogs on reopen: [fill in]

**Tester sign-off:**
- Name: ___________
- Date: ___________

**Status:** deferred — hardware not available

---

### 4. Tier-3 Motorola Perf @ 10 Hostiles + Death-Pile + Sleep Lapse

**Requirement:** DOC-05 §7.2 (ROADMAP Phase 3 spike-risk)
**Why manual:** Real-device frame timings — emulator readings skew significantly at
Tier-3 thermal constraints. The §7.2 Tier-3 frame budget must be measured on the
reference device (Motorola One Macro XT2016-1) at real ambient temperature.

**Setup:**
- Deploy the Phase 3 build to Motorola XT2016-1 (Plan 01-07 Tier-3 reference device).
- Connect via USB with USB Debugging enabled. Plug into mains power.
- Confirm `ThermalProbe.is_tier_3()` returns `true` on this device.

**Steps:**
1. Run the Phase 3 combat benchmark:
   `bash scripts/run-benchmark.sh combat_scene`
2. The bench scene (`tests/scenes/combat_bench.tscn`) loads automatically.
3. 10 hostile mobs spawn via `combat_bench.tscn`'s spawner array.
4. Builder receives lethal damage → death pile entity spawns at builder position.
5. Builder respawns at the starter bed (D-15).
6. Builder right-clicks the bed to enter the 10× sleep lapse (D-12).
7. Wait for the benchmark to complete (~5 min sustained run).
8. Pull the CSV output:
   `adb pull /sdcard/Android/data/org.cubicraftia.app/files/benchmarks/03-combat.csv .planning/phases/03-survival-loop/03-combat-benchmark.csv`
9. Inspect the `time_ms` column. Verify average frame time is ≤ the §7.2 Tier-3 contract.

**Expected:**
- Average main-thread frame time stays under the §7.2 Tier-3 budget throughout all phases
  of the benchmark (10-hostile combat + death-pile spawn + sleep lapse + post-lapse combat).
- CSV file `03-combat-benchmark.csv` is written and pullable via ADB.
- Adaptive hostile cap (Plan 03-11 Tier-3 override) engages: `hostile_mob_active_cap` drops to 6
  when `ThermalProbe.is_tier_3()` is true. Verify via log: `[Spawning] adaptive cap = 6`.
- Thermal throttle warning (if triggered) is logged with timestamp and frame count.

**Pass criteria:**
- Average frame time ≤ §7.2 Tier-3 number (see `DOCS.md §7.2` — provisional per
  STATE.md `phase-1-perf-floor`; pin the number once this run completes).
- CSV committed to `.planning/phases/03-survival-loop/03-combat-benchmark.csv`.
- Thermal throttle MAY trigger — the test captures WHEN it triggers, not WHETHER.
  If throttle exceeds X% of frames: lower §7.2 contract (per D-07 escalation path),
  do NOT add Rust (D-12 prohibition).

**Failure escalation (D-07 — NEVER Rust per D-12):**
- Option A: Force `hostile_mob_active_cap = 4` on Tier-3 (already wired in Plan 03-11).
- Option B: Reduce death-pile compound mesh count at Tier-3 (Plan 03-04 `death-pile-box-mesh-placeholder`).
- If still FAIL: lower the §7.2 Tier-3 contract in `DOCS.md §7.2` to the measured peak frame time.

**Tester sign-off:**
- Name: ___________
- Date: ___________

**Status:** deferred — hardware not available

---

### 5. 10× Sleep Lapse Feel

**Requirement:** DOC-05 D-12
**Why manual:** Visual feel (~5-6 s sweep of stars/dawn colour transition) is a
judgement call, not a deterministic number. The CHASE camera must remain unchanged
through the lapse. Tier-3 fallback path (instant fade-to-black → "Sleeping…" card →
sunrise fade-in) requires confirming `ThermalProbe.is_tier_3()` triggers the branch.

**Setup:**
- Open survival world at night (or wait for WorldClock to reach NIGHT phase).
- Place a builder-bed if not already present.
- Confirm no hostile mobs are inside the 8 m bed-bubble (otherwise sleep is cancelled).

**Steps:**
1. Walk builder within 2 m of the bed (walk-up prompt appears: "Press E to sleep").
2. Press E (or the mobile sleep-interact action) to start the 10× sleep lapse.
3. Observe the sky: stars, moon, dawn colour transition, sunrise.
4. Observe the CHASE camera: third-person SpringArm3D must remain at its normal distance.
5. Listen for ambient sound shift: night crickets fading, dawn birds starting.
6. Watch HP bar: should restore to max HP on wake.
7. Note the real-world elapsed time from lapse-start to dawn wake-up.

**Tier-3 fallback verification:**
- On the Motorola XT2016-1 (or any device where `ThermalProbe.is_tier_3()` returns true):
  the lapse should skip the sky animation and show instead:
  (a) instant fade-to-black, (b) "Sleeping…" screen card, (c) sunrise fade-in.
  Verify this branch by running the above steps on the Motorola (same benchmark session as Row 4).

**Expected:**
- World clock and sky simulation accelerate ~10× for ~5-6 real seconds.
- Stars sweep overhead; moon sets toward the horizon; dawn breaks with a visible colour
  gradient (night blue → dawn orange → morning yellow-white).
- CHASE camera stays in its normal third-person follow position (no camera mode change).
- Ambient sounds shift from night (cricket/wind) to dawn (birds/morning breeze).
- HP bar restores to max HP on wake (D-12 rest mechanic).
- Tier-3 fallback: fade-to-black + "Sleeping…" card + sunrise fade, NOT the sky sweep.

**Pass criteria:**
- Lapse duration: 5-6 s ± 1 s real time (stopwatch from E-press to sunrise wake).
- Camera mode unchanged (CHASE cam still active, no FPV switch).
- HP delta = +(max_hp - current_hp) on wake (full restore).
- Tier-3 fallback verified via `ThermalProbe.is_tier_3()` returning true on Motorola;
  "Sleeping…" card visible; no 5-6 s sky sweep on that device.

**Tester sign-off:**
- Name: ___________
- Date: ___________

**Status:** deferred — hardware not available

---

## Summary

total: 5
passed: 0
issues: 0
pending: 0
deferred: 5
skipped: 0
blocked: 0

## Escalation

If any row is FAIL:
- Row 1 (ghost wall-pass + bubble repel): file hotfix targeting `src/combat/ghost.gd` and
  `src/autoload/spawning.gd` bed-bubble repulsion logic.
- Row 2 (Tom Yum VFX): file hotfix targeting `src/world/fire_breath_vfx.tscn` and
  `src/items/food_tom_yum.tres`. Verify `vfx_on_use = "fire_breath"` dispatch in `inventory.gd`.
- Row 3 (inventory force-quit): file hotfix targeting `src/autoload/world_save.gd` atomic-rename
  + `src/autoload/inventory.gd` `_persist_to_save` coalesce cadence. Per Plan 02-03 backup chain.
- Row 4 (Tier-3 combat perf): apply D-07 escalation path — lower §7.2 contract or reduce
  hostile cap or death-pile complexity. **Never add Rust (D-12 prohibition).**
- Row 5 (sleep lapse feel): file hotfix targeting `src/autoload/world_clock.gd`
  sleep-lapse timing and `src/world/main_scene.gd` sky-shader uniform drive.

Reply "approved" after all 5 rows are PASS (or DEFERRED with an explicit note and user choice).
Reply with the failing row number + failure detail if any row is FAIL.

## Known Debt

All 5 rows are marked `deferred` with explicit user approval (2026-05-27). The UAT script ships
fully functional; physical hardware verification is carried forward as Phase 3 known debt,
mirroring Phase 1's Task 3 Motorola benchmark deferral and Phase 2's 4-row deferred UAT.

| Row | Deferral context | Prerequisite |
|-----|-----------------|--------------|
| 1 — Ghost wall-pass + bubble repel | Needs a running Godot build with a survival world + console access; ghost AI aggro must be testable in isolation | Debug build + console commands |
| 2 — Tom Yum VFX | Needs a running Godot build with food inventory + Remote Scene Tree inspector | Debug build |
| 3 — Inventory force-quit | Needs 5-repetition kill-relaunch cycle on any platform; requires terminal access for `kill -9` | Any platform with debug build + terminal |
| 4 — Tier-3 combat perf | Needs Motorola One Macro (XT2016-1) with USB Debugging; `scripts/run-benchmark.sh combat_scene` + ADB pull | Android SDK + USB Debugging + connected device on mains power |
| 5 — 10× sleep lapse feel | Needs running build with survival world at night + stopwatch timing; Tier-3 path needs Motorola hardware | Debug build (any platform for feel; Motorola for Tier-3 fallback) |

To discharge this debt: run each row per the procedure above, update `result:` from
`deferred` to `pass` (or `fail` + escalation) and set `updated:` to the run date.

## Gaps

---

## Phase 3 close-out

User approves Plan 03-11 close-out with all 5 HUMAN-UAT rows in `deferred` state.
Hardware-gated verifications carry forward as Phase 3 known debt alongside Phase 1's
`motorola-benchmark` and Phase 2's 4-row deferred UAT.

Signed: ___________
Date: 2026-05-27
