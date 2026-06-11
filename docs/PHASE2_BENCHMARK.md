<!-- SPDX-FileCopyrightText: 2026 Cubicraftia contributors -->
<!-- SPDX-License-Identifier: GPL-3.0-or-later -->

# Phase 2 Dynamite-Blast Benchmark Runbook

**Version:** Phase 2 (Plan 02-15)
**Extends:** `docs/MOTOROLA_BENCHMARK.md` (Phase 1 runbook)
**Reference decisions:** CONTEXT.md D-07, D-12, RESEARCH.md Pitfall 2, Pattern 5

---

## Purpose

This runbook documents how to execute and interpret the Phase 2 load-bearing
performance gate: the dynamite-blast worst-case frame-time acceptance test on the
Tier-3 reference device (Motorola One Macro XT2016-1).

The benchmark answers: **Can GDScript + godot_voxel handle a worst-case 5 m dynamite
blast (100 placed bricks + ~524 terrain voxels at a 4-chunk-intersection spot) without
main-thread-stalling the §7.2 Tier-3 frame budget?**

The Phase 2 macro runs **before** the existing 30-minute thermal loop. The combined run
takes approximately 32 minutes (2 min Phase 2 macro buffer + 30 min thermal loop).

**§7.2 Tier-3 frame budget:** 33.3 ms per frame (30 FPS cap, shadows off, 5-chunk
render distance).

The result either:
- **Confirms** the §7.2 Tier-3 blast contract (peak frame time ≤ 33.3 ms = PASS), or
- **Triggers D-07 escalation:** lower the §7.2 contract OR back out a visual feature via
  adaptive-quality (Plan 14's preset table). Per CONTEXT.md D-12, **never add Rust** as
  the response to a frame-budget failure.

---

## What the Phase 2 Macro Does

The benchmark scene (`src/world/benchmark_scene.tscn`) now contains a `Phase2DynamiteMacro`
Node3D child. When the scene starts, `BenchmarkRunner._ready()` calls
`start_phase_2_macro()` instead of `start_benchmark()` directly.

**Macro sequence (deterministic, seed-locked):**

| Sim time | Event |
|----------|-------|
| t = 0 s  | 100 bricks (`brick_2x4`, colour red) placed in a 10×10 grid at world (0, 5, 0) using `BrickRegistry.get("brick_2x4")` |
| t = 5 s  | Dynamite fuse lit at world (8, 5, 8) — the worst-case 4-chunk-intersection spot |
| t = 8 s  | BLAST — `DynamiteHandler.detonate(Vector3(8,5,8), 5.0)` fires the bulk `VoxelTool.do_sphere` + `StudGrid.remove_bulk()` |
| t = 8–9 s | Per-frame process time sampled via `Performance.get_monitor(Performance.TIME_PROCESS)` |
| t = 9 s  | CSV written → 30-min thermal loop starts automatically |

**CSV output:** `user://benchmarks/02-dynamite.csv`

**CSV columns:**

| Column | Description |
|--------|-------------|
| `frame` | Frame index (0-based) within the 1-second capture window |
| `time_ms` | Main-thread process time for that frame in milliseconds |
| `active_dropped_items` | Number of active `DroppedItem` `RigidBody3D` entities at blast time |
| `affected_voxels` | Approximate count of voxel cells cleared by the blast (worst-case estimate: 524) |

---

## Prerequisites

All Phase 1 prerequisites apply (see `docs/MOTOROLA_BENCHMARK.md` §Prerequisites).
No additional tools are required for the Phase 2 macro — it runs automatically as the
first part of the benchmark scene.

| Tool | Required Version | Install |
|------|-----------------|---------|
| Godot | 4.6.3 | `brew install --cask godot` |
| adb (Android Debug Bridge) | 1.0.41+ | bundled with Android SDK Platform Tools |
| Python 3 | 3.10+ | `brew install python3` |
| Android SDK + NDK | API 34 + NDK r25+ | Android Studio, or `barichello/godot-ci:4.6.3` Docker image |
| Godot Android export template | 4.6.3 | `godot --headless --install-android-build-template` |

---

## Hardware Setup

Follow the Phase 1 hardware setup checklist in `docs/MOTOROLA_BENCHMARK.md`
§"Hardware Setup Checklist" verbatim. No Phase 2-specific hardware steps are needed.

Key reminders:
- Enable USB Debugging on the device.
- Plug the device into mains power (battery-saver throttling will pollute results).
- Connect via USB-C or USB-A data cable.
- Accept the RSA fingerprint prompt on the device.

---

## How to Run

```bash
cd /path/to/LegoMinecraft
bash scripts/run-benchmark.sh
```

The existing `run-benchmark.sh` script already exports `benchmark_scene.tscn` as the
main scene via the `override.cfg` pattern. Because `BenchmarkRunner._ready()` now calls
`start_phase_2_macro()` instead of `start_benchmark()` directly, the Phase 2 macro runs
**automatically as the first stage** of every benchmark run.

**Total wait time:** ~32 minutes (2-minute Phase 2 macro + buffer + 30-minute thermal loop).

The script waits 31 minutes by default (`BENCHMARK_DURATION_S=1800 + BUFFER_S=60`).
For a Phase 2-only run (skip the 30-min loop), set `BENCHMARK_DURATION_S=120` locally:

```bash
BENCHMARK_DURATION_S=120 bash scripts/run-benchmark.sh
```

This pulls only the Phase 2 dynamite CSV without waiting for the thermal loop — useful
for rapid iteration if you are tuning adaptive-quality presets.

**Leave the device alone for the entire run duration.** The benchmark scene runs
autonomously. Do not touch the screen, unlock, or open notifications.

---

## Pulling the Phase 2 CSV

After the run, the `run-benchmark.sh` script pulls the Phase 1 thermal CSV automatically.
To additionally pull the Phase 2 dynamite CSV:

```bash
# Pull the Phase 2 CSV from the device
adb pull \
  /sdcard/Android/data/org.cubicraftia.app/files/benchmarks/02-dynamite.csv \
  .planning/phases/02-world-building-content/motorola-phase2-dynamite.csv

# Fallback via run-as (if the above fails):
adb shell run-as org.cubicraftia.app cat files/benchmarks/02-dynamite.csv \
  > .planning/phases/02-world-building-content/motorola-phase2-dynamite.csv
```

---

## Pass / Fail Criteria

Open `.planning/phases/02-world-building-content/motorola-phase2-dynamite.csv` and
inspect the `time_ms` column.

**PASS condition:** The maximum `time_ms` value in the blast window (frames 0–N in the
CSV) is **≤ 33.3 ms**.

The benchmark runner logs a one-line summary to Android logcat:

```
[Phase2Macro] Phase 2 macro: blast at t=8s; peak frame_time = N.NN ms; threshold (Tier-3 §7.2 budget) = 33.3 ms (30 FPS cap) — PASS/FAIL
```

To read it directly:

```bash
adb logcat -d | grep "Phase2Macro"
```

| Result | Condition | Action |
|--------|-----------|--------|
| PASS | peak `time_ms` ≤ 33.3 ms | Record PASS in `02-HUMAN-UAT.md` row 1. Commit CSV to `.planning/phases/02-world-building-content/motorola-phase2-dynamite.csv`. |
| FAIL | peak `time_ms` > 33.3 ms | Apply D-07 escalation (see below). **Never add Rust — D-12.** |

---

## Escalation Paths

### If PASS

1. Pull the CSV to `.planning/phases/02-world-building-content/motorola-phase2-dynamite.csv`.
2. Record PASS + measured peak frame time in `02-HUMAN-UAT.md` row 1.
3. Commit:
   ```bash
   git add .planning/phases/02-world-building-content/motorola-phase2-dynamite.csv \
           .planning/phases/02-world-building-content/02-HUMAN-UAT.md
   git commit -m "feat(02-15): Phase 2 dynamite benchmark PASS — peak_frame_ms=N.NN committed"
   ```

### If FAIL — Settings Tuning Round (D-06 carry-forward)

Try one round of adaptive-quality tuning before escalating to D-07:

- **Option A (Plan 14 preset):** Force `ghost_preview_mode = "hidden"` on Tier-3 preset
  (removes one transparent draw per frame, reducing main-thread GPU upload pressure).
- **Option B:** Reduce `dynamite_particle_count` to 15 in the Tier-3 adaptive-quality
  preset table (`src/ui/settings_menu.gd::PRESET_DEFINITIONS`).
- **Do NOT combine** multiple changes in one round — isolate to one setting at a time.

Re-run: `bash scripts/run-benchmark.sh`

### If STILL FAIL — Lower §7.2 Contract (D-07)

Per CONTEXT.md D-07: the correct response is to **lower the §7.2 Tier-3 contract**
to what the hardware actually sustains. Do NOT add Rust (D-12 prohibition).

1. Identify the measured sustained peak frame time from the CSV.
2. Update `.planning/DOCS.md` §7.2 Tier-3 row to the measured contract.
3. Add a note explaining the Phase 2 dynamite calibration result.
4. Commit the lowered contract and the benchmark CSV.

---

## Troubleshooting

### Phase 2 CSV not found at `user://benchmarks/02-dynamite.csv`

Check logcat for Phase 2 macro errors:

```bash
adb logcat -d | grep -i "Phase2Macro\|benchmark\|godot\|crash"
```

Common causes:
- `DirAccess.make_dir_recursive_absolute` failed (storage permission on Android 10).
- The macro completed but the CSV write failed (check `FileAccess.get_open_error()`).

### Macro logs `FAIL — per D-07 + CONTEXT.md D-12 (no Rust)`

This is expected output when peak frame time exceeds 33.3 ms. It is **not a crash**.
Apply the D-07 escalation path above.

### All Phase 2 frame times are 0.0 ms

`Performance.get_monitor(Performance.TIME_PROCESS)` returns 0.0 if called from a
non-running scene (e.g. headless export). This benchmark must run on-device, not headless.

### DynamiteHandler or StudGrid not available

The macro gracefully falls back to `StudGrid.remove_bulk()` if `DynamiteHandler` is
not available as an autoload in the benchmark context. Frame-time data is still captured.
Check that `DynamiteHandler` is listed in `project.godot` autoloads.

### Phase 1 troubleshooting

For ADB, godot_voxel ABI, and thermal-probe issues, see `docs/MOTOROLA_BENCHMARK.md`
§Troubleshooting.

---

## What to Commit After the Run

```
.planning/phases/02-world-building-content/motorola-phase2-dynamite.csv   ← Phase 2 blast CSV
.planning/phases/02-world-building-content/02-HUMAN-UAT.md                ← UAT row 1 filled in
```

The Phase 1 thermal CSV (`motorola-benchmark.csv`) is committed separately per the Phase 1
runbook.

---

## Run Log

*Update this section after each Phase 2 benchmark run.*

<!-- Run log format:
| Date | Ambient °C | Device | API | Peak frame_ms | Threshold_ms | Result |
-->

| Date | Ambient °C | Device | API | Peak frame_ms | Threshold_ms | Result |
|------|-----------|--------|-----|---------------|-------------|--------|
| (pending — run not yet executed) | — | Motorola XT2016-1 | — | — | 33.3 | — |
