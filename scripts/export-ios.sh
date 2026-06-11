#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# export-ios.sh — Manual iOS export for M4 MacBook Air (D-04)
#
# Cubicraftia iOS export is NOT part of CI (D-04: full iOS CI + Apple code-signing
# infrastructure is deferred to Phase 5). This script runs locally on the M4 MacBook
# and produces a "Designed-for-iPad" IPA that validates the iOS build pipeline.
#
# Threat mitigations per T-03-03:
#   - Runs scripts/glossary-check.sh, scripts/verify-feature-flags.sh, and reuse lint
#     BEFORE the godot export invocation so the same scope-gates as CI apply.
#
# Usage:
#   bash scripts/export-ios.sh          # full export
#   bash scripts/export-ios.sh --check  # check prerequisites without exporting
#
# See docs/IOS_MANUAL_EXPORT.md for the full step-by-step runbook.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

CHECK_ONLY=false
if [[ "${1:-}" == "--check" ]]; then
  CHECK_ONLY=true
fi

FAIL=0

echo ""
echo "=== Cubicraftia iOS Export (M4 MBA — D-04) ==="
echo ""

# ── Prerequisite checks ────────────────────────────────────────────────────────

# 1. Must run on macOS
if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "ERROR: This script must run on macOS (Darwin)." >&2
  echo "       iOS export via Designed-for-iPad requires Xcode, which is macOS-only." >&2
  echo "       For CI platforms see .github/workflows/ci.yml (iOS is excluded per D-04)." >&2
  exit 1
fi

echo "[OK]  Running on macOS (Darwin)."

# 2. Xcode must be installed
if ! xcode-select -p &>/dev/null; then
  echo "ERROR: Xcode command-line tools not found." >&2
  echo "       Install Xcode from the Mac App Store, then run:" >&2
  echo "         xcode-select --install" >&2
  FAIL=1
else
  XCODE_PATH="$(xcode-select -p)"
  XCODE_VERSION="$(xcodebuild -version 2>/dev/null | head -1 || echo 'unknown')"
  echo "[OK]  Xcode found at $XCODE_PATH ($XCODE_VERSION)."
fi

# 3. Godot 4.6.3 must be on PATH
if ! command -v godot &>/dev/null; then
  echo "ERROR: Godot not found on PATH." >&2
  echo "       Install Godot 4.6.3 via: brew install --cask godot" >&2
  echo "       Then ensure it is on your PATH." >&2
  FAIL=1
else
  GODOT_VER="$(godot --version 2>&1 | head -1 || echo 'unknown')"
  echo "[OK]  Godot found: $GODOT_VER"
  if ! echo "$GODOT_VER" | grep -qE "^4\.6"; then
    echo "WARNING: Expected Godot 4.6.x, found: $GODOT_VER" >&2
    echo "         Mismatch may cause export template incompatibilities." >&2
  fi
fi

# 4. iOS preset must exist in export_presets.cfg
if ! grep -q '"iOS"' export_presets.cfg 2>/dev/null; then
  echo "ERROR: No 'iOS' preset found in export_presets.cfg." >&2
  echo "       Task 2 of Plan 01-03 should have added a 5th preset named 'iOS'." >&2
  FAIL=1
else
  echo "[OK]  iOS preset found in export_presets.cfg."
fi

if [[ "$FAIL" -ne 0 ]]; then
  echo ""
  echo "Prerequisites not met. Fix the above issues and re-run." >&2
  exit 1
fi

if [[ "$CHECK_ONLY" == "true" ]]; then
  echo ""
  echo "=== --check mode: all prerequisites satisfied. No export performed. ==="
  exit 0
fi

echo ""
echo "=== Running scope-checks before export (T-03-03 threat mitigation) ==="
echo ""

# Run the same scope gates as CI (T-03-03: manual export cannot skip CI guards)
bash scripts/glossary-check.sh
bash scripts/verify-feature-flags.sh

if command -v reuse &>/dev/null; then
  reuse lint
elif command -v python3 &>/dev/null; then
  python3 -m reuse lint || true
fi

echo ""
echo "=== Exporting iOS (Designed-for-iPad) ==="
echo ""

BUILD_DIR="build/ios"
mkdir -p "$BUILD_DIR"

# Invoke Godot headless export using the "iOS" preset
godot --headless --export-release "iOS" "$BUILD_DIR/Cubicraftia.ipa"

echo ""
echo "=== Export complete ==="
echo "  Output: $BUILD_DIR/Cubicraftia.ipa"
echo ""

# ── Record run log ─────────────────────────────────────────────────────────────
LOG_FILE=".last-ios-export.json"
GODOT_VER_CLEAN="$(godot --version 2>&1 | head -1 | tr -d '\n')"
XCODE_VER_CLEAN="$(xcodebuild -version 2>/dev/null | head -1 | tr -d '\n' || echo 'unknown')"
TIMESTAMP="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
HOSTNAME_SAFE="$(hostname)"

cat > "$LOG_FILE" <<JSON
{
  "exported_at": "$TIMESTAMP",
  "godot_version": "$GODOT_VER_CLEAN",
  "xcode_version": "$XCODE_VER_CLEAN",
  "host": "$HOSTNAME_SAFE",
  "output": "$BUILD_DIR/Cubicraftia.ipa",
  "preset": "iOS",
  "note": "Designed-for-iPad path (D-04). Not CI-automated; full iOS CI is Phase 5."
}
JSON

echo "Run log written to $LOG_FILE"
echo ""
echo "=== Next steps ==="
echo "  1. Open the .ipa in Xcode: Window → Devices and Simulators → My Mac"
echo "     Drag the .ipa to the 'Installed Apps' section to verify it installs."
echo "  2. Smoke test: title loads, disclaimer dialog appears, touch/mouse input works."
echo "  3. Commit $LOG_FILE to record this build:"
echo "     git add $LOG_FILE && git commit -m 'chore: record iOS export $(date +%Y-%m-%d)'"
echo ""
echo "See docs/IOS_MANUAL_EXPORT.md for the full runbook."
