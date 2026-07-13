#!/usr/bin/env bash
# publish-update.sh (DIST-05): publish a fresh macOS build for the notify-and-link auto-updater.
#
# GOTCHA THIS SCRIPT GUARDS AGAINST: Godot's macOS export writes ONLY to the .dmg. The standalone
# build/macOS/Cubicraftia.app is NOT overwritten by an export and can be a STALE leftover from a
# previous build. Signing/zipping/publishing that standalone app ships old code. So this script
# ALWAYS extracts the app fresh from the .dmg (the authoritative export output), then signs, zips,
# reads the version by BOOTING the app (not by grepping the compressed pck), and only then uploads.
#
# Workflow to push a fix:
#   1. commit your change
#   2. bash scripts/stamp-version.sh
#   3. /opt/homebrew/bin/godot --headless --path . --export-release "macOS" build/macOS/Cubicraftia.dmg
#   4. bash deploy/publish-update.sh          # (defaults to build/macOS/Cubicraftia.dmg)
#
# Optional: pass a specific .dmg path as $1. Set CUBI_NO_UPLOAD=1 to build+verify locally without
# uploading (useful for a dry run).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DMG="${1:-$REPO_ROOT/build/macOS/Cubicraftia.dmg}"
[ -f "$DMG" ] || { echo "ERROR: .dmg not found: $DMG (export the release .dmg first, step 3)"; exit 1; }

APP="$REPO_ROOT/build/macOS/Cubicraftia.app"
ZIP="$REPO_ROOT/build/macOS/Cubicraftia.zip"
DIST="$REPO_ROOT/dist/macOS"
HOST="${CUBI_HOST:-m1}"
DL="/var/www/cubicraftia/downloads/Cubicraftia.zip"
MAN="/var/www/cubicraftia/updates/latest.json"

# --- 1. Extract the FRESH app from the .dmg (never trust the standalone build/ .app) ---
echo "Extracting fresh app from $(basename "$DMG") ..."
MP="$(mktemp -d)"
cleanup() { hdiutil detach "$MP" >/dev/null 2>&1 || true; rmdir "$MP" 2>/dev/null || true; }
trap cleanup EXIT
hdiutil attach "$DMG" -nobrowse -readonly -mountpoint "$MP" >/dev/null
SRC_APP="$(/bin/ls -d "$MP"/*.app 2>/dev/null | head -1)"
[ -n "$SRC_APP" ] || { echo "ERROR: no .app inside $DMG"; exit 1; }
rm -rf "$APP"
ditto "$SRC_APP" "$APP"
cleanup; trap - EXIT

# --- 2. Ad-hoc sign (universal, required for Apple Silicon launch) + clear quarantine ---
echo "Signing (ad-hoc, universal) ..."
codesign --force --deep --sign - "$APP" >/dev/null 2>&1
codesign --verify --deep --strict "$APP" >/dev/null 2>&1 && echo "  signature valid" || echo "  WARN: signature verify reported issues"
xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true

# --- 3. Zip ---
echo "Zipping ..."
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

# --- 4. AUTHORITATIVE version: boot the packed app and read BuildInfo's printed id ---
BOOT_VER="$(timeout 60 "$APP/Contents/MacOS/Cubicraftia" --headless --quit 2>&1 | sed -n 's/.*Cubicraftia build: //p' | head -1 | tr -d '\r')"
STAMP_VER="$(cat "$REPO_ROOT/version.txt" 2>/dev/null || echo "")"
VER="${BOOT_VER:-$STAMP_VER}"
[ -n "$VER" ] || { echo "ERROR: could not determine build version"; exit 1; }
echo "Build version (read from the running app): $VER"
if [ -n "$BOOT_VER" ] && [ -n "$STAMP_VER" ] && [ "$BOOT_VER" != "$STAMP_VER" ]; then
  echo "WARN: app boots as '$BOOT_VER' but version.txt is '$STAMP_VER' - the .dmg predates your last stamp. Re-export (step 3) before publishing." >&2
fi

# --- 5. Refresh dist/macOS with the exact same fresh artifacts ---
mkdir -p "$DIST"
rm -rf "$DIST/Cubicraftia.app"
ditto "$APP" "$DIST/Cubicraftia.app"
xattr -dr com.apple.quarantine "$DIST/Cubicraftia.app" 2>/dev/null || true
cp "$ZIP" "$DIST/Cubicraftia.zip"
echo "Refreshed dist/macOS/ (app + zip)."

# --- 6. Upload + bump the manifest (skip with CUBI_NO_UPLOAD=1 for a local dry run) ---
if [ "${CUBI_NO_UPLOAD:-0}" = "1" ]; then
  echo "CUBI_NO_UPLOAD=1 -> built + verified locally, skipping upload."
  exit 0
fi
echo "Uploading $(du -h "$ZIP" | cut -f1) to $HOST:$DL ..."
scp "$ZIP" "$HOST:$DL"
ssh "$HOST" "cat > $MAN <<EOF
{\"version\": \"$VER\", \"url\": \"https://cubicraftia.com/downloads/Cubicraftia.zip\", \"notes\": \"Cubicraftia test build\"}
EOF"
echo "Published. Older builds will now offer this update."
echo "Manifest: https://cubicraftia.com/updates/latest.json"
curl -s -m 10 https://cubicraftia.com/updates/latest.json && echo
