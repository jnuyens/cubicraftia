#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# run-benchmark.sh — One-command pipeline for the Motorola 30-min thermal benchmark.
#
# What this script does:
#   1. Verify adb sees exactly one Android device.
#   2. Verify the connected device is the Motorola One Macro (XT2016-1).
#   3. Export the benchmark Android APK with benchmark_scene.tscn as the main scene.
#   4. Install the APK on the device via adb.
#   5. Launch the app.
#   6. Wait 31 minutes (1800 s benchmark + 60 s setup/teardown buffer).
#   7. Pull the CSV from the device.
#   8. Run scripts/analyse-benchmark.sh on the pulled CSV.
#   9. Print PASS / FAIL result + escalation guidance per D-06 / D-07.
#
# Usage:
#   cd /path/to/LegoMinecraft
#   bash scripts/run-benchmark.sh
#
# Prerequisites (see docs/MOTOROLA_BENCHMARK.md §Prerequisites):
#   - Godot 4.6.3 installed and on PATH
#   - adb installed and on PATH
#   - Android SDK + NDK installed (for Godot Android export)
#   - Godot Android export template installed
#   - Motorola One Macro connected via USB with USB Debugging enabled
#   - Device plugged into mains power
#
# Device override (for testing on a different Tier-3 device):
#   Set BENCHMARK_DEVICE_MODEL_PATTERN env var to the expected product model string.
#   Example: BENCHMARK_DEVICE_MODEL_PATTERN="Pixel 4a" bash scripts/run-benchmark.sh
#
# Exit codes:
#   0 = benchmark ran and PASSED §7.2 Tier-3 contract
#   1 = benchmark ran but FAILED §7.2 Tier-3 contract (see escalation guidance)
#   2 = setup error (no device, wrong device, export failed, install failed, etc.)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# ─── Configuration ────────────────────────────────────────────────────────────

# The Motorola One Macro's Android property ro.product.model.
# Try both possible model strings (XT2016-1 shipped under slightly different
# marketing strings on different firmwares / carriers).
EXPECTED_MODEL_PATTERN="${BENCHMARK_DEVICE_MODEL_PATTERN:-moto g(8) power lite|moto g8 power lite|One Macro|XT2016}"

PACKAGE_NAME="org.cubicraftia.app"
ACTIVITY="com.godot.game.GodotApp"
APK_DIR="$REPO_ROOT/build/android"
APK_NAME="Cubicraftia-benchmark.apk"
APK_PATH="$APK_DIR/$APK_NAME"

PHASE_DIR="$REPO_ROOT/.planning/phases/01-foundation-mobile-spike"
TARGET_FPS=30
BENCHMARK_DURATION_S=1800
BUFFER_S=60
TOTAL_WAIT_S=$((BENCHMARK_DURATION_S + BUFFER_S))

TIMESTAMP=$(date +"%Y%m%d-%H%M%S")
CSV_DEVICE_GLOB="/sdcard/Android/data/${PACKAGE_NAME}/files/benchmark-*.csv"
CSV_LOCAL="$PHASE_DIR/motorola-benchmark-${TIMESTAMP}.csv"

# ─── Helpers ─────────────────────────────────────────────────────────────────

info()  { echo "[INFO]  $*"; }
warn()  { echo "[WARN]  $*" >&2; }
error() { echo "[ERROR] $*" >&2; exit 2; }

require_tool() {
    command -v "$1" &>/dev/null || error "$1 not found. Install it and re-run."
}

# ─── Step 0: Prerequisite tools ──────────────────────────────────────────────

info "Checking prerequisites..."
require_tool godot
require_tool adb
require_tool python3

# ─── Step 1: Verify ADB sees exactly one device ──────────────────────────────

info "Checking for connected Android device..."

DEVICE_COUNT=$(adb devices | grep -c "device$" || true)
if [[ "$DEVICE_COUNT" -eq 0 ]]; then
    error "No Android device found. Connect the Motorola One Macro via USB, enable USB Debugging, and accept the RSA prompt on the device."
fi
if [[ "$DEVICE_COUNT" -gt 1 ]]; then
    error "Multiple Android devices detected ($DEVICE_COUNT). Disconnect all but the Motorola One Macro."
fi
info "Device connected."

# ─── Step 2: Verify device is Motorola One Macro ─────────────────────────────

info "Verifying device model..."
DEVICE_MODEL=$(adb shell getprop ro.product.model 2>/dev/null | tr -d '\r\n' || echo "unknown")
info "  ro.product.model = '${DEVICE_MODEL}'"

if ! echo "$DEVICE_MODEL" | grep -Eiq "$EXPECTED_MODEL_PATTERN"; then
    warn "Device model '${DEVICE_MODEL}' does not match expected pattern: ${EXPECTED_MODEL_PATTERN}"
    warn "This benchmark is calibrated for the Motorola One Macro (XT2016-1) — the Phase 1 Tier-3 reference device."
    warn "To override, set BENCHMARK_DEVICE_MODEL_PATTERN=<your-model> and re-run."
    warn "Proceeding anyway — note that results will NOT update DOCS.md §7.2 Tier-3 unless the device is the XT2016-1."
fi

# Log Android API level for the thermal probe path record.
API_LEVEL=$(adb shell getprop ro.build.version.sdk 2>/dev/null | tr -d '\r\n' || echo "unknown")
info "  API level: ${API_LEVEL}"

# ─── Step 3: Export the benchmark APK ────────────────────────────────────────

info "Exporting benchmark APK (main_scene override: benchmark_scene.tscn)..."

mkdir -p "$APK_DIR"

# The benchmark uses a custom project.godot override to set the main scene to
# benchmark_scene.tscn. We generate a temporary override.cfg in the repo root
# that Godot picks up automatically (it merges with project.godot at runtime).
OVERRIDE_CFG="$REPO_ROOT/override.cfg"
cat > "$OVERRIDE_CFG" <<'OVERRIDE_EOF'
[application]
run/main_scene="res://src/world/benchmark_scene.tscn"
OVERRIDE_EOF

info "  override.cfg written (main_scene -> benchmark_scene.tscn)"
info "  Running: godot --headless --export-release Android $APK_PATH"

# Run the export. Errors from Godot go to stderr; we let set -e handle failures.
godot --headless --export-release "Android" "$APK_PATH" \
    2>&1 | grep -v "^$" | while IFS= read -r line; do
        echo "[godot] $line"
    done

# Clean up the override.cfg immediately after export.
rm -f "$OVERRIDE_CFG"
info "  override.cfg removed."

if [[ ! -f "$APK_PATH" ]]; then
    error "APK not found at $APK_PATH after export. Check Godot export logs above."
fi
info "  APK exported: $APK_PATH ($(du -sh "$APK_PATH" | cut -f1))"

# ─── Step 4: Install the APK ──────────────────────────────────────────────────

info "Installing APK on device..."
adb install -r "$APK_PATH" 2>&1 | while IFS= read -r line; do
    echo "[adb]   $line"
done
info "  APK installed."

# ─── Step 5: Launch the benchmark activity ────────────────────────────────────

info "Launching benchmark activity..."
adb shell am start -n "${PACKAGE_NAME}/${ACTIVITY}" \
    --activity-brought-to-front 2>&1 | while IFS= read -r line; do
    echo "[adb]   $line"
done
info "  App launched."
info ""
info "  ====================================================================="
info "  Benchmark running. DO NOT touch the device for 30 minutes."
info "  Keep the device on mains power."
info "  ====================================================================="
info ""

# ─── Step 6: Wait for the benchmark to complete ───────────────────────────────

ELAPSED_S=0
while [[ "$ELAPSED_S" -lt "$TOTAL_WAIT_S" ]]; do
    REMAINING=$((TOTAL_WAIT_S - ELAPSED_S))
    ELAPSED_MIN=$((ELAPSED_S / 60))
    REMAINING_MIN=$((REMAINING / 60))
    printf "\r[INFO]  Elapsed: %2d min  |  Remaining: %2d min  " "$ELAPSED_MIN" "$REMAINING_MIN"
    sleep 60
    ELAPSED_S=$((ELAPSED_S + 60))
done
echo ""
info "  Wait complete. Pulling CSV from device..."

# ─── Step 7: Pull the CSV ─────────────────────────────────────────────────────

mkdir -p "$PHASE_DIR"

# The benchmark runner writes to Godot's user:// which on Android maps to
# /sdcard/Android/data/<package>/files/ (or the app's internal storage in some cases).
# We try sdcard external storage first, then internal app files via run-as.
PULLED=false

if adb shell ls "$CSV_DEVICE_GLOB" &>/dev/null 2>&1; then
    # External sdcard path — directly pullable.
    adb pull "$CSV_DEVICE_GLOB" "$PHASE_DIR/" 2>&1 | while IFS= read -r line; do
        echo "[adb]   $line"
    done
    # Rename the most recently pulled file to the canonical local name.
    LATEST_CSV=$(ls -t "$PHASE_DIR"/benchmark-*.csv 2>/dev/null | head -1 || true)
    if [[ -n "$LATEST_CSV" ]]; then
        mv "$LATEST_CSV" "$CSV_LOCAL"
        PULLED=true
        info "  CSV pulled: $CSV_LOCAL"
    fi
fi

if [[ "$PULLED" != "true" ]]; then
    # Fallback: try run-as (debug-signed APK in debug mode allows run-as).
    info "  Trying run-as fallback for CSV pull..."
    REMOTE_FILES=$(adb shell run-as "$PACKAGE_NAME" ls files/ 2>/dev/null | tr -d '\r' | grep "benchmark-" || true)
    if [[ -n "$REMOTE_FILES" ]]; then
        LATEST_REMOTE=$(echo "$REMOTE_FILES" | sort | tail -1)
        adb shell run-as "$PACKAGE_NAME" cat "files/$LATEST_REMOTE" > "$CSV_LOCAL"
        info "  CSV pulled via run-as: $CSV_LOCAL"
        PULLED=true
    fi
fi

if [[ "$PULLED" != "true" ]]; then
    error "Could not pull benchmark CSV from device. Check that the benchmark ran for the full 30 minutes and that the app has storage permission. See docs/MOTOROLA_BENCHMARK.md §Troubleshooting."
fi

# ─── Step 8: Analyse the CSV ─────────────────────────────────────────────────

info ""
info "  ====================================================================="
info "  Analysing benchmark results..."
info "  CSV: $CSV_LOCAL"
info "  Target FPS: $TARGET_FPS"
info "  ====================================================================="
info ""

ANALYSE_EXIT=0
bash "$SCRIPT_DIR/analyse-benchmark.sh" "$CSV_LOCAL" --target-fps "$TARGET_FPS" || ANALYSE_EXIT=$?

# ─── Step 9: Print result + escalation guidance ───────────────────────────────

echo ""
if [[ "$ANALYSE_EXIT" -eq 0 ]]; then
    info "  ===== BENCHMARK PASSED ====="
    info "  The Motorola One Macro sustains >= ${TARGET_FPS} FPS over the worst 30s"
    info "  window of the last 10 minutes. §7.2 Tier-3 contract confirmed."
    info ""
    info "  Next steps (per docs/MOTOROLA_BENCHMARK.md §If PASS):"
    info "    1. Rename the CSV to .planning/phases/01-foundation-mobile-spike/motorola-benchmark.csv"
    info "    2. Update DOCS.md §7.1 to pin Motorola One Macro as Tier-3 (confirmed)."
    info "    3. Update DOCS.md §7.2 Tier-3 row to mark contract confirmed."
    info "    4. Add a run-log entry to docs/MOTOROLA_BENCHMARK.md."
    info "    5. git add + commit the CSV and DOCS.md changes."
    exit 0
else
    warn "  ===== BENCHMARK FAILED ====="
    warn "  The Motorola One Macro did NOT sustain >= ${TARGET_FPS} FPS over the"
    warn "  worst 30s window of the last 10 minutes. §7.2 Tier-3 contract NOT met."
    warn ""
    warn "  Escalation per CONTEXT.md D-06 / D-07:"
    warn "    1. First: try ONE settings-tuning round (per D-06):"
    warn "       a. Edit src/world/benchmark_runner.gd:"
    warn "          - Reduce render_distance from 5 to 4 (TIER3_RENDER_DISTANCE = 64)"
    warn "          - OR set particle_density to 'off' entirely"
    warn "       b. Re-run: bash scripts/run-benchmark.sh"
    warn "    2. If STILL FAIL after tuning (per D-07):"
    warn "       a. The correct response is to LOWER the §7.2 Tier-3 contract in DOCS.md."
    warn "       b. Update .planning/DOCS.md §7.2 Tier-3 row to the measured minimum."
    warn "       c. Do NOT add Rust — this is explicitly prohibited by D-12."
    warn "    See docs/MOTOROLA_BENCHMARK.md §Escalation for full details."
    exit 1
fi
