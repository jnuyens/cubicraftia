---
status: deferred
phase: 02-world-building-content
plan: 15
source: [02-VALIDATION.md §"Manual-Only Verifications"]
started: 2026-05-26T00:00:00Z
updated: 2026-05-26T00:00:00Z
user_approval: "2026-05-26 (approved deferred — see Phase 2 carryover debt; hardware runs scheduled for standalone session)"
---

# Phase 2 — Human UAT Script

> 4 manual-only verifications that cannot be exercised by the automated test suite.
> Each row maps to a requirement from `02-VALIDATION.md §"Manual-Only Verifications"`.
> Results gate Plan 16 (DOCS sync). If any row is FAIL, a remediation plan (02-15.1 or
> hotfix branch) must ship before Plan 16 runs.
>
> Reference decisions: CONTEXT.md D-07 (benchmark fail → lower §7.2, not add Rust),
> D-12 (no Rust escalation), RESEARCH.md Pattern 5 (bulk-edit blast mitigation).

---

## Tests

### 1. Dynamite Frame-Time Gate on Tier-3 Reference Device

**Requirement:** DOC-03 (§7.2 budget)
**Why manual:** `godot_voxel` crashes headlessly; the §7.2 contract must be measured on
real silicon at real ambient temperature.

**Expected:**
- Peak main-thread process time in the blast window (t=8..t=9 s) is ≤ 33.3 ms
  (30 FPS cap, Tier-3 §7.2 contract).
- `user://benchmarks/02-dynamite.csv` is written and pullable via ADB.
- Benchmark runner logs: `Phase 2 macro: blast at t=8s; peak frame_time = N ms; threshold = 33.3 ms — PASS`

**How to run:**
1. Connect the Motorola One Macro (XT2016-1) via USB with USB Debugging enabled.
   Plug into mains power. Accept the RSA fingerprint prompt on the device.
2. Follow `docs/PHASE2_BENCHMARK.md` step-by-step.
3. Run: `bash scripts/run-benchmark.sh`
4. Wait for Phase 2 macro to complete (~2 min); the 30-min thermal loop then starts.
5. Pull the CSV: `adb pull /sdcard/Android/data/org.cubicraftia.app/files/benchmarks/02-dynamite.csv .planning/phases/02-world-building-content/motorola-phase2-dynamite.csv`
6. Inspect `time_ms` column. PASS = max value ≤ 33.3.

**Failure escalation (D-07 — NEVER Rust per D-12):**
- Option A: Force `ghost_preview_mode = "hidden"` on Tier-3 preset (remove one transparent draw).
- Option B: Reduce `dynamite_particle_count` to 15 in `settings_menu.gd::PRESET_DEFINITIONS`.
- If still FAIL: lower the §7.2 contract in `DOCS.md` §7.2 to the measured peak frame time.

result: deferred
peak_frame_ms: [not yet measured — hardware run pending]
csv_path: .planning/phases/02-world-building-content/motorola-phase2-dynamite.csv

---

### 2. Bottom-Sheet Swipe-Up Gesture on iOS + Android

**Requirement:** DOC-03 (§3.5 mobile UI — `02-UI-SPEC.md` §"Mobile Bottom Sheet")
**Why manual:** Touch-gesture handling cannot be exhaustively unit-tested across iOS/Android
quirks; the 0.22s ease-out Tween and 48dp drag-handle hit area must be validated on a
physical touch device.

**Expected:**
- Tapping the Build palette button opens the bottom sheet (sheet animates up, Tween 0.22s ease-out cubic).
- The sheet snaps to ~50% of viewport height (expanded state).
- Drag handle hit area is reachable (48dp tall, extended beyond the visible 16px handle).
- Tapping outside the sheet collapses it with the same 0.22s ease-out animation.
- Swiping the drag handle down collapses the sheet.
- The 3D world viewport remains responsive during sheet animation (no frame stall).

**How to run (swipe-up test steps):**
1. Install the dev APK on a physical Android device (or use the iOS dev build on a physical
   iPhone/iPad).
2. Launch the app and create or open a sandbox world.
3. On mobile: tap the Build palette button (bottom-right of the hotbar row).
4. Verify the bottom sheet slides up smoothly to the 50% snap point.
5. Tap outside the sheet — it should collapse smoothly.
6. Swipe up from the drag handle — sheet should expand again.
7. Swipe down on the drag handle — sheet should collapse.
8. Repeat on both iOS and Android if both devices are available.

**Notes (fill in during test):**
- Device tested (Android): [fill in — e.g. "Motorola One Macro XT2016-1, Android 10"]
- Device tested (iOS): [fill in — e.g. "iPhone 12, iOS 17.4"]
- Any visual glitches: [fill in]

result: deferred

---

### 3. Save Reload Across an OS-Level Kill (Force-Quit During Save)

**Requirement:** DOC-03 (CRIT-3 atomicity — Plan 02-03 WorldSaveIo atomic-rename + .bak fallback)
**Why manual:** Mocking `dispose_during_save` is partial; full-system OS kill behaviour
during the atomic-rename window (~200 ms) requires a real OS.

**Expected (atomic guarantee):**
- After a force-quit during any point in the save sequence, relaunching the app and opening
  the same world must yield EITHER the pre-save state OR the post-save state — never a torn
  state (e.g. 27 out of 50 bricks present).
- The `.atomic-marker` + `.bak.1` fallback chain (Plan 02-03) ensures that if the
  canonical file is corrupted, the backup is loaded cleanly.
- No error dialog or crash on relaunch.

**How to run:**
1. Open a fresh sandbox world.
2. Place exactly 50 bricks (any configuration — note the count or take a screenshot).
3. Trigger an auto-save checkpoint: wait for a day-boundary event (WorldClock emits
   `day_boundary` every 900 s / 15 min), OR use the debug shortcut if available
   (check `src/autoload/world_save.gd` for a `debug_checkpoint()` method or use the
   Godot remote debugger console: `WorldSave.checkpoint()`).
4. During the save operation (the window is approximately 200 ms after the checkpoint
   is triggered — practice the timing once with a test world before the real run),
   force-quit the app via the OS task manager:
   - Android: Recent Apps → swipe the app away.
   - iOS: App Switcher → swipe the app card up.
   - macOS: Force Quit Applications (Cmd+Option+Esc) → select Cubicraftia → Force Quit.
   - Windows: Task Manager → End Task.
5. Relaunch the app and open the same world.
6. Count the bricks present. Acceptable: 0 (pre-save) or 50 (post-save). Failure: any
   intermediate count.
7. Repeat this sequence at least 5 times to sample across the rename window.

**Notes (fill in during test):**
- Platform tested: [fill in — e.g. "Android 10", "macOS 15.4"]
- Run 1 result (0 or 50 bricks?): [fill in]
- Run 2 result: [fill in]
- Run 3 result: [fill in]
- Run 4 result: [fill in]
- Run 5 result: [fill in]
- Any error dialogs on relaunch: [fill in]

result: deferred

---

### 4. Cross-Platform Export Smoke Test

**Requirement:** DOC-03 (cross-platform invariant)
**Why manual:** Export-template differences across macOS/Windows/Linux/iOS/Android can
only be caught by running each target binary on matching hardware or a VM.
The CI matrix (`.github/workflows/build.yml`) covers macOS/Windows/Linux/Android;
iOS requires `scripts/export-ios.sh` on a Mac (Phase 1 D-04 carry-forward — iOS in CI
is deferred to Phase 5).

**Expected:**
- Each platform binary launches without crash.
- The title/splash screen appears (or the world loads directly if there is no title screen yet).
- The 5-step happy path completes without error on each platform:
  1. Launch the app.
  2. Create a new world (or open an existing one).
  3. Place 5 bricks.
  4. Save (auto-save or via debug trigger).
  5. Quit and relaunch — verify the 5 bricks are present.

**How to run:**

macOS / Windows / Linux (CI):
1. Trigger the CI matrix via GitHub Actions (`.github/workflows/build.yml`) or run locally:
   `godot --headless --export-release "macOS" build/macos/Cubicraftia.dmg`
2. Launch the exported binary on the matching platform.
3. Run the 5-step happy path.

Android:
1. The standard `bash scripts/run-benchmark.sh` exports and installs the benchmark APK.
   For the smoke test, export the release APK instead:
   `godot --headless --export-release "Android" build/android/Cubicraftia-release.apk`
2. Install: `adb install build/android/Cubicraftia-release.apk`
3. Launch and run the 5-step happy path.

iOS (manual — CI deferred to Phase 5):
1. On a Mac with Xcode installed: `bash scripts/export-ios.sh`
2. Install the IPA on a physical device via Xcode Organizer or `ios-deploy`.
3. Launch and run the 5-step happy path.

**Results per platform (fill in):**

| Platform | Binary Launches | Happy Path (5 steps) | Notes |
|----------|----------------|----------------------|-------|
| macOS | [pending] | [pending] | |
| Windows | [pending] | [pending] | |
| Linux | [pending] | [pending] | |
| Android | [pending] | [pending] | |
| iOS | [pending] | [pending] | iOS CI deferred to Phase 5; run `scripts/export-ios.sh` manually |

result: deferred

---

## Summary

total: 4
passed: 0
issues: 0
pending: 0
deferred: 4
skipped: 0
blocked: 0

## Escalation

If any row is FAIL:
- Row 1 (dynamite frame-time): apply D-07 — lower §7.2 contract or back out a visual feature via
  Plan 14's adaptive-quality presets. **Never add Rust (D-12 prohibition).**
- Row 2 (bottom-sheet gesture): file a hotfix targeting `src/ui/brick_palette_bottomsheet.tscn`
  and `src/ui/brick_palette.gd`. Plan 16 cannot ship until the gesture is validated.
- Row 3 (save force-quit): file a hotfix targeting `src/persistence/world_save_io.gd`.
  The atomic-rename + `.bak.1` fallback (Plan 02-03) must be confirmed correct per platform.
- Row 4 (cross-platform export): file a platform-specific hotfix. Identify which export
  template, GDExtension ABI, or Android plugin is causing the failure.

Reply "approved" after all 4 rows are PASS (or DEFERRED with an explicit note and user choice).
Reply with the failing row number + failure detail if any row is FAIL.

## Known Debt

All 4 rows are marked `deferred` with explicit user approval (2026-05-26). The benchmark
infrastructure and UAT script ship fully functional; physical hardware verification is
carried forward as Phase 2 known debt, mirroring Phase 1's Task 3 Motorola benchmark
deferral pattern.

| Row | Deferral context | Prerequisite |
|-----|-----------------|--------------|
| 1 — Dynamite frame-time | Needs Motorola One Macro (XT2016-1) hardware run; `02-dynamite.csv` must be pulled via ADB and committed to `.planning/phases/02-world-building-content/motorola-phase2-dynamite.csv`. | Android SDK + USB Debugging + connected device |
| 2 — Bottom-sheet swipe-up | Needs physical touch device (iOS or Android) with dev build installed; swipe-up gesture must be validated on real screen hardware. | APK / IPA dev build installed on device |
| 3 — Save force-quit cycle | Needs 5-repetition save-force-quit-relaunch cycle on any platform; timing window (~200 ms rename window) requires manual coordination. | Any platform with debug build |
| 4 — Cross-platform export smoke | Needs CI matrix run for macOS / Windows / Linux / Android (`.github/workflows/build.yml`) plus manual iOS run via `scripts/export-ios.sh` on a Mac. | CI credentials + Godot export templates for all targets |

To discharge this debt: run each row per the procedure above and update `result:` from
`deferred` to `pass` (or `fail` + escalation) and set `updated:` to the run date.

## Gaps
