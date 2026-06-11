#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# analyse-benchmark.sh — Tier-3 perf gate for the Motorola benchmark CSV
#
# Reads a CSV with columns: timestamp,fps,thermal_headroom,thermal_status
# (header row required). Computes the MIN FPS over the worst 30-second sliding
# window in the LAST 10 MINUTES of the run (Pitfall 9 / D-02 contract).
#
# Exit 0 = pass (worst-window min-FPS >= target).
# Exit 1 = fail (worst-window min-FPS < target), with diagnostics on stderr.
#
# Usage:
#   bash scripts/analyse-benchmark.sh <csv-file> [--target-fps N]
#   ./scripts/analyse-benchmark.sh motorola-benchmark.csv --target-fps 30

set -euo pipefail

CSV_FILE=""
TARGET_FPS=30

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --target-fps)
            TARGET_FPS="$2"
            shift 2
            ;;
        --target-fps=*)
            TARGET_FPS="${1#--target-fps=}"
            shift
            ;;
        -*)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
        *)
            CSV_FILE="$1"
            shift
            ;;
    esac
done

if [[ -z "$CSV_FILE" ]]; then
    echo "Usage: $0 <csv-file> [--target-fps N]" >&2
    exit 1
fi

if [[ ! -f "$CSV_FILE" ]]; then
    echo "ERROR: CSV file not found: $CSV_FILE" >&2
    exit 1
fi

# Use Python3 for the sliding-window analysis (POSIX awk doesn't handle floats
# reliably and isn't available on all CI images)
python3 - "$CSV_FILE" "$TARGET_FPS" <<'EOF'
import sys
import csv
import math

csv_file = sys.argv[1]
target_fps = float(sys.argv[2])

rows = []
with open(csv_file, newline='') as f:
    reader = csv.DictReader(f)
    for row in reader:
        try:
            ts = float(row['timestamp'])
            fps = float(row['fps'])
            rows.append((ts, fps))
        except (ValueError, KeyError):
            continue  # skip malformed rows

if not rows:
    print("ERROR: no valid data rows found in CSV.", file=sys.stderr)
    sys.exit(1)

# Determine the last 10 minutes of data
last_ts = rows[-1][0]
first_ts = rows[0][0]
window_start_ts = last_ts - 600.0  # last 10 minutes (600 seconds)

# Filter to last-10-minute rows
last10 = [(ts, fps) for ts, fps in rows if ts >= window_start_ts]

if not last10:
    # If total duration < 10 min, analyse the whole run
    last10 = rows
    print(f"WARNING: run duration is less than 10 minutes ({last_ts - first_ts:.0f}s). "
          f"Analysing entire run.", file=sys.stderr)

# Sliding window: worst (minimum) average FPS over any 30-second window
WINDOW_SECONDS = 30.0
worst_min_fps = math.inf
worst_window_start = None

for i, (ts_i, _) in enumerate(last10):
    # Collect all rows within the 30-second window starting at ts_i
    window_fps = [fps for ts, fps in last10 if ts_i <= ts <= ts_i + WINDOW_SECONDS]
    if not window_fps:
        continue
    window_min = min(window_fps)
    if window_min < worst_min_fps:
        worst_min_fps = window_min
        worst_window_start = ts_i

if worst_min_fps == math.inf:
    print("ERROR: could not compute sliding window (no data).", file=sys.stderr)
    sys.exit(1)

total_duration = last_ts - first_ts
print(f"Benchmark analysis:")
print(f"  Total duration: {total_duration:.0f}s")
print(f"  Rows in last 10 min: {len(last10)}")
print(f"  Worst 30s window starts at: t={worst_window_start:.1f}s")
print(f"  Min FPS in worst window: {worst_min_fps:.2f}")
print(f"  Target FPS: {target_fps}")

if worst_min_fps >= target_fps:
    print(f"PASS: worst-window min-FPS ({worst_min_fps:.2f}) >= target ({target_fps})")
    sys.exit(0)
else:
    print(f"FAIL: worst-window min-FPS ({worst_min_fps:.2f}) < target ({target_fps}) — "
          f"§7.2 Tier-3 contract not met.", file=sys.stderr)
    sys.exit(1)
EOF
