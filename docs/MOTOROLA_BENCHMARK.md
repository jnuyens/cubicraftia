<!-- SPDX-FileCopyrightText: 2026 Cubicraftia contributors -->
<!-- SPDX-License-Identifier: GPL-3.0-or-later -->

# Motorola One Macro — 30-Minute Thermal Benchmark Runbook

**Version:** Phase 1 (Plan 07)
**Reference decisions:** CONTEXT.md D-02, D-03, D-05, D-06, D-07, D-12

---

## Purpose

This runbook documents how to execute and interpret the Phase 1 load-bearing
performance gate: a 30-minute sustained benchmark on the Motorola One Macro
(XT2016-1) — the Tier-3 Android reference device for Cubicraftia.

The benchmark answers: **Can GDScript + godot_voxel sustain the §7.2 Tier-3
frame target (30 FPS / 5-chunk render distance / shadows off) on a Helio P70 /
Mali-G72 MP3 device for 30 full minutes without thermal collapse?**

The result either:
- **Confirms** the §7.2 Tier-3 contract as-is (benchmark passes), or
- **Calibrates** it to what the hardware actually sustains (benchmark fails after
  settings tuning → LOWER §7.2 Tier-3 per D-07 — do NOT add Rust per D-12).

---

## Hardware Setup Checklist (One-Time per Device)

- [ ] **Enable Developer Options:** Settings → About phone → tap "Build number" 7 times.
- [ ] **Enable USB Debugging:** Settings → System → Developer options → USB debugging: ON.
- [ ] **Connect device to M4 MacBook Air** via USB-C or USB-A cable.
- [ ] **Accept RSA fingerprint prompt** on the device (appears on first connection).
- [ ] **Verify ADB connection:** Run `adb devices` on the MBA — the Motorola should appear as `<serial> device`.
- [ ] **Plug device into mains power.** Do NOT run on battery — power-saver throttling under low battery will pollute the thermal data.
- [ ] **Note the ambient room temperature in °C** — see the Run Log section below.

---

## Prerequisites (Software)

All software must be installed before running the benchmark. Run `bash scripts/install-deps.sh --check` to verify tool availability.

| Tool | Required Version | Install |
|------|-----------------|---------|
| Godot | 4.6.3 | `brew install --cask godot` |
| adb (Android Debug Bridge) | 1.0.41+ | bundled with Android SDK Platform Tools |
| Python 3 | 3.10+ | `brew install python3` |
| Android SDK + NDK | API 34 + NDK r25+ | Android Studio, or `barichello/godot-ci:4.6.3` Docker image |
| Godot Android export template | 4.6.3 | `godot --headless --install-android-build-template` (or already installed from Plan 03 CI setup) |

**Android Plugin Build (if not already done):**

The `CubicraftiaThermal.aar` must be compiled and placed at
`android/plugins/CubicraftiaThermal.aar` for the thermal probe to work.

```bash
# From the repo root
cd src/platform/android
gradle assembleRelease
cp build/outputs/aar/CubicraftiaThermal-release.aar \
   ../../../android/plugins/CubicraftiaThermal.aar
cd ../../..
```

If `gradle` is not installed: `brew install gradle` or use the Gradle wrapper
(`./gradlew` in `src/platform/android/` if you initialise a Gradle wrapper there).

If you prefer not to build the plugin, the benchmark still runs — the thermal
probe will fall back through `currentThermalStatus` or `sysfs_zone`, and the
CSV `thermal_probe_path` column will record which path was used.

---

## How to Run

```bash
cd /Users/jnuyens/src/LegoMinecraft
bash scripts/run-benchmark.sh
```

The script performs all steps automatically:

1. Verifies the Motorola is connected and recognised.
2. Exports a benchmark APK with `benchmark_scene.tscn` as the main scene.
3. Installs the APK on the device.
4. Launches the app.
5. Waits 31 minutes (30 min benchmark + 1 min buffer), printing progress every minute.
6. Pulls the CSV from the device.
7. Runs `scripts/analyse-benchmark.sh` and prints PASS or FAIL.

**Leave the device alone for the full 30 minutes.** Do not touch the screen, unlock,
or open notifications. The benchmark scene runs autonomously.

**Record the ambient temperature** (see Run Log section at the end of this file).

---

## Device Model Override

If you want to run the benchmark on a different Tier-3 device to compare:

```bash
BENCHMARK_DEVICE_MODEL_PATTERN="Pixel 4a" bash scripts/run-benchmark.sh
```

Results from non-Motorola devices are informative but do NOT update DOCS.md §7.2
Tier-3 row — that row is specifically calibrated to the Motorola XT2016-1.

---

## CSV Format

The benchmark runner (`src/world/benchmark_runner.gd`) writes a CSV via
`ThermalProbe.start()`. The CSV is pulled from the device by the script and
saved to `.planning/phases/01-foundation-mobile-spike/motorola-benchmark-<timestamp>.csv`.

### Sample CSV Header

```csv
timestamp,fps,thermal_headroom,thermal_status,thermal_probe_path
```

### Column Descriptions

| Column | Type | Description |
|--------|------|-------------|
| `timestamp` | float (seconds) | Elapsed time since benchmark start |
| `fps` | float | Average FPS over the 10-second sample window |
| `thermal_headroom` | float or NaN | getThermalHeadroom(0) value [0.0–1.0]. NaN if probe path is not getThermalHeadroom |
| `thermal_status` | int | currentThermalStatus value [0–6]. -1 if probe path is not currentThermalStatus |
| `thermal_probe_path` | string | Which thermal layer was used: `getThermalHeadroom`, `currentThermalStatus`, `sysfs_zone`, or `unavailable` |

### Sample CSV Rows (illustration only — not real data)

```
timestamp,fps,thermal_headroom,thermal_status,thermal_probe_path
10.000,47.32,NaN,1,currentThermalStatus
20.001,46.89,NaN,1,currentThermalStatus
30.002,45.11,NaN,2,currentThermalStatus
...
1790.103,28.77,NaN,3,currentThermalStatus
1800.010,27.43,NaN,3,currentThermalStatus
```

### Thermal Probe Path Notes

The Motorola One Macro shipped with Android 9 (API 28) and received an OTA to
Android 10 (API 29). `getThermalHeadroom` requires API 30 (Android 11), so the
Motorola will almost certainly fall through to `currentThermalStatus` (API 29+)
or `sysfs_zone` as the thermal probe path. The CSV header records which path was
actually used so you can confirm the measurement method.

### Thermal Status Values (THERMAL_STATUS_* enum)

| Value | Constant | Meaning |
|-------|----------|---------|
| 0 | THERMAL_STATUS_NONE | No throttling |
| 1 | THERMAL_STATUS_LIGHT | Light throttling |
| 2 | THERMAL_STATUS_MODERATE | Moderate throttling |
| 3 | THERMAL_STATUS_SEVERE | Severe throttling |
| 4 | THERMAL_STATUS_CRITICAL | Critical — frame rates likely impacted |
| 5 | THERMAL_STATUS_EMERGENCY | Emergency |
| 6 | THERMAL_STATUS_SHUTDOWN | Imminent shutdown |

---

## Pass / Fail Criteria

`scripts/analyse-benchmark.sh` computes: **min FPS over the worst 30-second
sliding window in the last 10 minutes of the run.**

This is the correct metric per RESEARCH.md Pitfall 9 — thermal collapse is a
sustained effect that appears in the late phase of a run, not in the cold first
few minutes.

**"Thermal collapse"** (CONTEXT.md D-02): sustained drop below the §7.2 target
frame rate for >30 seconds.

| Result | Condition | §7.2 Tier-3 Contract (as of Phase 1 start) |
|--------|-----------|---------------------------------------------|
| PASS | worst-window min-FPS >= 30 | 30 FPS / 5 chunks / shadows off — confirmed |
| FAIL | worst-window min-FPS < 30 | Requires escalation (see below) |

---

## Escalation Paths

### If PASS

1. Rename the CSV:
   ```bash
   mv .planning/phases/01-foundation-mobile-spike/motorola-benchmark-<timestamp>.csv \
      .planning/phases/01-foundation-mobile-spike/motorola-benchmark.csv
   ```
2. Update `.planning/DOCS.md` §7.1 Android Tier-3 row to pin `"Motorola One Macro (XT2016-1) and equivalent or better"` (D-05: provisional → confirmed).
3. Update `.planning/DOCS.md` §7.2 Tier-3 row to mark the contract confirmed with the measured result.
4. Add a run-log entry to this file's **Run Log** section.
5. Commit:
   ```bash
   git add .planning/phases/01-foundation-mobile-spike/motorola-benchmark.csv \
           .planning/DOCS.md \
           docs/MOTOROLA_BENCHMARK.md
   git commit -m "feat(01-07): confirmed Tier-3 §7.2 contract — benchmark CSV committed"
   ```

### If FAIL — Settings Tuning Round (D-06)

Per CONTEXT.md D-06, try **one round of settings tuning** before escalating.

Edit `src/world/benchmark_runner.gd`:
- Option A: Reduce `TIER3_RENDER_DISTANCE` from 80 (5 chunks) to 64 (4 chunks).
- Option B: Change `TIER3_PARTICLE_DENSITY` to `"off"` (disables all particles).
- Do NOT combine multiple changes in one round — isolate to one setting at a time.

Re-run: `bash scripts/run-benchmark.sh`

### If STILL FAIL — Lower §7.2 Contract (D-07)

Per CONTEXT.md D-07: the correct response is to **lower the §7.2 Tier-3 contract
in DOCS.md** to what the hardware actually sustains. Do NOT add Rust — this is
explicitly prohibited by D-12.

1. Identify the actual sustained minimum FPS from the benchmark CSV
   (e.g. `scripts/analyse-benchmark.sh motorola-benchmark-<timestamp>.csv`).
2. Update `.planning/DOCS.md` §7.2 Tier-3 row to the measured contract
   (e.g. `25 FPS / 4-chunk render distance / shadows off`).
3. Add a note to §7.2 explaining the Phase 1 calibration result.
4. Commit the lowered contract, the benchmark CSV, and this runbook with a run log entry.

**Do NOT add Rust GDExtension to compensate for thermal failure (D-12).** The
response to thermal failure is to calibrate the performance target to what the
hardware sustains, not to increase implementation complexity.

---

## Troubleshooting

### adb not seeing the device

1. Check USB cable (data cable, not charge-only).
2. On the device: Settings → Developer options → USB debugging: ON.
3. Re-plug the USB cable and accept the RSA fingerprint prompt on the device.
4. Run `adb kill-server && adb start-server && adb devices`.

### Wrong device model detected

The script uses `adb shell getprop ro.product.model` to identify the device.
If your firmware version uses a different string, set the override:
```bash
BENCHMARK_DEVICE_MODEL_PATTERN="<your-model-string>" bash scripts/run-benchmark.sh
```

### godot_voxel ABI crash on Android (RESEARCH.md Pitfall 4)

**Symptom:** App crashes on launch with "cannot load library libgodot_voxel.so".
**Cause:** The godot_voxel GDExtension may not include the `arm64-v8a` ABI
binary that the Motorola One Macro requires.

**Fix:**
1. Check `addons/godot_voxel/` for `.so` files targeting `arm64-v8a`:
   ```bash
   find addons/godot_voxel/ -name "*.so" | grep arm64
   ```
2. If missing, build godot_voxel from source against Godot 4.6.3:
   ```bash
   # See addons/godot_voxel/BUILD.md or docs/SETUP.md for build steps.
   # Short version (requires Android NDK):
   cd addons/godot_voxel
   scons platform=android arch=arm64v8 godot_version=4.6 generate_bindings=yes
   ```
3. After building, copy the resulting `.so` to the correct addon path and re-export.

### Godot export fails — no Android template

```bash
godot --headless --install-android-build-template
```
Then re-run `bash scripts/run-benchmark.sh`.

### CSV not found after the run

Check Android logcat during the run for crash messages:
```bash
adb logcat -d | grep -i "godot\|benchmark\|crash"
```
Common causes: OOM (out of memory) on the device; godot_voxel ABI mismatch;
ThermalProbe failing to open user:// on certain Android versions.

### Thermal readings all NaN or all -1

The Motorola One Macro (Android 10, API 29) does not support `getThermalHeadroom`
(API 30+). Expected behaviour: `thermal_probe_path` column should show
`currentThermalStatus` or `sysfs_zone`, and `thermal_headroom` will be `NaN`.
This is normal — see Thermal Probe Path Notes above.

---

## What to Commit After the Run

After a successful (or calibrated-fail) benchmark run, commit:

```
.planning/phases/01-foundation-mobile-spike/motorola-benchmark.csv   ← the canonical CSV
.planning/DOCS.md                                                      ← §7.1 + §7.2 updated
docs/MOTOROLA_BENCHMARK.md                                            ← run log entry added
```

**The CSV is the immutable Phase 1 evidence anchor.** Future commits that revise
§7.2 must reference a new benchmark CSV per the §7 lock.

---

## Run Log

*Update this section after each benchmark run.*

<!-- Run log format:
| Date | Ambient °C | Device | API level | Thermal probe path | Worst 30s min-FPS | Result |
-->

| Date | Ambient °C | Device | API | Probe path | Worst 30s min-FPS | Result |
|------|-----------|--------|-----|-----------|-------------------|--------|
| (pending — run not yet executed) | — | Motorola XT2016-1 | — | — | — | — |
