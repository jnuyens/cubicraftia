#!/usr/bin/env bash
# publish-update.sh (DIST-05): publish a new build for the notify-and-link auto-updater.
#
# Workflow to push a fix during testing:
#   1. commit your change
#   2. bash scripts/stamp-version.sh          # stamps version.txt to the new HEAD
#   3. godot --headless --path . --export-release "macOS" build/macOS/Cubicraftia.dmg
#   4. codesign --force --deep --sign - build/macOS/Cubicraftia.app   # ad-hoc (Apple Silicon)
#   5. ditto -c -k --keepParent build/macOS/Cubicraftia.app build/macOS/Cubicraftia.zip
#   6. bash deploy/publish-update.sh build/macOS/Cubicraftia.zip
#
# The running (older) build then sees "update available" on next launch and the
# Download button fetches this zip. version.txt MUST match the exported build (do not
# re-stamp between export and publish).
set -euo pipefail

ZIP="${1:?usage: publish-update.sh <path-to-Cubicraftia.zip>}"
[ -f "$ZIP" ] || { echo "not found: $ZIP" >&2; exit 1; }

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VER="$(cat "$REPO_ROOT/version.txt")"
HOST="${CUBI_HOST:-m1}"
DL="/var/www/cubicraftia/downloads/Cubicraftia.zip"
MAN="/var/www/cubicraftia/updates/latest.json"

echo "Publishing version: $VER"
echo "Uploading $(du -h "$ZIP" | cut -f1) to $HOST:$DL ..."
scp "$ZIP" "$HOST:$DL"

# Write the manifest atomically on the host (downloads/updates dirs are owned by the deploy user).
ssh "$HOST" "cat > $MAN <<EOF
{\"version\": \"$VER\", \"url\": \"https://cubicraftia.com/downloads/Cubicraftia.zip\", \"notes\": \"Cubicraftia test build\"}
EOF"

echo "Published. Older builds will now offer this update."
echo "Manifest: https://cubicraftia.com/updates/latest.json"
curl -s -m 10 https://cubicraftia.com/updates/latest.json && echo
