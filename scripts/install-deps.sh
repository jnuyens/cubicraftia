#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# install-deps.sh — idempotent dependency installer for Cubicraftia (Phase 1 + Phase 2)
#
# Usage:
#   bash scripts/install-deps.sh           # install all dependencies
#   bash scripts/install-deps.sh --check   # report tool presence without installing
#
# See docs/SETUP.md for full prerequisites and notes.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# ─── Pinned versions ──────────────────────────────────────────────────────────
GODOT_VERSION="4.6.3"
GODOT_VOXEL_COMMIT="4a9d311"
GUT_VERSION="v9.4.0"
GODOT_SQLITE_VERSION="v4.7"
# Pinned SHA-256 of demo.zip from 2shady4u/godot-sqlite v4.7 (pinned 2026-05-26, update if upstream re-tags)
# Verified via: gh release view v4.7 -R 2shady4u/godot-sqlite --json assets
GODOT_SQLITE_SHA256="26966044757cf86a223a8027f8bc88c49c289ab047dcf8138bb591d7632e580e"
GODOT_SQLITE_URL="https://github.com/2shady4u/godot-sqlite/releases/download/${GODOT_SQLITE_VERSION}/demo.zip"
WEBRTC_NATIVE_VERSION="1.1.0-stable"
WEBRTC_NATIVE_URL="https://github.com/godotengine/webrtc-native/releases/download/${WEBRTC_NATIVE_VERSION}/godot-extension-webrtc.zip"

CHECK_ONLY=false
if [[ "${1:-}" == "--check" ]]; then
  CHECK_ONLY=true
fi

# ─── Helpers ──────────────────────────────────────────────────────────────────

ok()   { echo "  [OK]  $*"; }
warn() { echo "  [!]   $*"; }
info() { echo "        $*"; }

check_tool() {
  local name="$1"
  local cmd="$2"
  local version_flag="${3:---version}"
  if command -v "$cmd" &>/dev/null; then
    local ver
    ver="$("$cmd" $version_flag 2>&1 | head -1)" || ver="(version unknown)"
    ok "$name: $ver"
    return 0
  else
    warn "$name: NOT FOUND  (install: $4)"
    return 1
  fi
}

# ─── Tool presence report ─────────────────────────────────────────────────────

echo ""
echo "=== Cubicraftia dependency check (Phase 1) ==="
echo ""

MISSING=0

check_tool "Godot $GODOT_VERSION" "godot" "--version" "brew install --cask godot" || MISSING=$((MISSING+1))
check_tool "ripgrep"              "rg"    "--version"  "brew install ripgrep" || MISSING=$((MISSING+1))
check_tool "gettext (xgettext)"   "xgettext" "--version" "brew install gettext" || MISSING=$((MISSING+1))
check_tool "jq"                   "jq"    "--version"  "brew install jq" || MISSING=$((MISSING+1))
check_tool "reuse"                "reuse" "--version"  "pipx install reuse" || MISSING=$((MISSING+1))
check_tool "pipx"                 "pipx"  "--version"  "brew install pipx" || MISSING=$((MISSING+1))

echo ""

# Check godot-sqlite addon (Phase 2)
if [[ -f "$REPO_ROOT/addons/godot-sqlite/gdsqlite.gdextension" ]]; then
  ok "godot-sqlite: installed in addons/godot-sqlite/ (version $GODOT_SQLITE_VERSION)"
else
  warn "godot-sqlite: NOT installed in addons/godot-sqlite/  (run without --check to install)"
  MISSING=$((MISSING+1))
fi

# Check webrtc-native addon (Phase 4)
if [[ -f "$REPO_ROOT/addons/webrtc-native/bin/libwebrtc_native.linux.template_release.x86_64.so" ]] || \
   [[ -f "$REPO_ROOT/addons/webrtc-native/bin/libwebrtc_native.windows.template_release.x86_64.dll" ]] || \
   [[ -d "$REPO_ROOT/addons/webrtc-native/bin/libwebrtc_native.macos.template_release.universal.framework" ]]; then
  ok "webrtc-native: installed in addons/webrtc-native/bin/ (version $WEBRTC_NATIVE_VERSION)"
else
  warn "webrtc-native: NOT installed in addons/webrtc-native/bin/  (run without --check to install)"
  MISSING=$((MISSING+1))
fi

# Check godot_voxel addon pin
if [[ -d "$REPO_ROOT/addons/godot_voxel/.git" ]] || [[ -f "$REPO_ROOT/addons/godot_voxel/SCsub" ]]; then
  ACTUAL_COMMIT=$(git -C "$REPO_ROOT/addons/godot_voxel" rev-parse --short HEAD 2>/dev/null || echo "unknown")
  if [[ "$ACTUAL_COMMIT" == "${GODOT_VOXEL_COMMIT:0:${#ACTUAL_COMMIT}}" ]]; then
    ok "godot_voxel: installed at commit $ACTUAL_COMMIT (pinned: $GODOT_VOXEL_COMMIT)"
  else
    warn "godot_voxel: installed at $ACTUAL_COMMIT, expected pin $GODOT_VOXEL_COMMIT"
    MISSING=$((MISSING+1))
  fi
else
  warn "godot_voxel: NOT cloned into addons/godot_voxel/  (run without --check to install)"
  MISSING=$((MISSING+1))
fi

# Check gut addon
if [[ -d "$REPO_ROOT/addons/gut" ]] && [[ -f "$REPO_ROOT/addons/gut/gut_cmdln.gd" ]]; then
  ok "Gut: installed in addons/gut/"
else
  warn "Gut: NOT installed in addons/gut/  (run without --check to install)"
  MISSING=$((MISSING+1))
fi

echo ""
echo "=== Summary ==="
if [[ "$MISSING" -eq 0 ]]; then
  echo "All dependencies present."
else
  echo "$MISSING item(s) missing or not pinned."
  if [[ "$CHECK_ONLY" == "true" ]]; then
    echo "(Run without --check to install missing dependencies.)"
  fi
fi
echo ""

if [[ "$CHECK_ONLY" == "true" ]]; then
  # In check mode, always exit 0 — we are only reporting, not requiring
  exit 0
fi

# ─── Installation (macOS only) ────────────────────────────────────────────────

if [[ "$(uname)" != "Darwin" ]]; then
  echo "ERROR: Auto-install is currently macOS-only. For Ubuntu/Linux, see docs/SETUP.md."
  exit 1
fi

echo "=== Installing dependencies (macOS via Homebrew) ==="
echo ""

# Install CLI tools via Homebrew
brew install ripgrep gettext jq

# Install reuse via pipx
if command -v pipx &>/dev/null; then
  pipx install reuse || pipx upgrade reuse
else
  echo "pipx not found — install with: brew install pipx && pipx ensurepath"
  exit 1
fi

# ─── Clone godot_voxel at pinned commit ───────────────────────────────────────

VOXEL_DIR="$REPO_ROOT/addons/godot_voxel"
if [[ -d "$VOXEL_DIR/.git" ]]; then
  echo "godot_voxel already cloned — skipping (will not overwrite an existing checkout)."
  echo "To update: cd addons/godot_voxel && git fetch && git checkout $GODOT_VOXEL_COMMIT"
else
  echo "Cloning Zylann/godot_voxel at $GODOT_VOXEL_COMMIT ..."
  # Remove the .gitkeep if present so git clone can create the directory
  if [[ -f "$VOXEL_DIR/.gitkeep" ]] && [[ "$(ls -A "$VOXEL_DIR")" == ".gitkeep" ]]; then
    rm "$VOXEL_DIR/.gitkeep"
    rmdir "$VOXEL_DIR"
  fi
  git clone https://github.com/Zylann/godot_voxel.git "$VOXEL_DIR"
  git -C "$VOXEL_DIR" checkout "$GODOT_VOXEL_COMMIT"
  echo "godot_voxel cloned at $(git -C "$VOXEL_DIR" rev-parse HEAD)"
fi

# ─── Clone Gut at pinned tag ──────────────────────────────────────────────────

GUT_DIR="$REPO_ROOT/addons/gut"
if [[ -f "$GUT_DIR/gut_cmdln.gd" ]]; then
  echo "Gut already installed — skipping."
else
  echo "Cloning bitwes/Gut at $GUT_VERSION ..."
  TMPDIR_GUT=$(mktemp -d)
  git clone --branch "$GUT_VERSION" --depth 1 https://github.com/bitwes/Gut.git "$TMPDIR_GUT/gut"
  # Copy only the addons/gut portion
  if [[ -d "$TMPDIR_GUT/gut/addons/gut" ]]; then
    # Remove .gitkeep stub to place real addon
    rm -f "$GUT_DIR/.gitkeep"
    cp -r "$TMPDIR_GUT/gut/addons/gut/." "$GUT_DIR/"
  else
    cp -r "$TMPDIR_GUT/gut/." "$GUT_DIR/"
  fi
  rm -rf "$TMPDIR_GUT"
  echo "Gut installed at $GUT_DIR"
fi

# ─── Install godot-sqlite v4.7 (Phase 2) ─────────────────────────────────────
# Source: https://github.com/2shady4u/godot-sqlite (MIT licence)
# Installs the full addon from demo.zip which contains the gdextension manifest +
# all platform binaries under addons/godot-sqlite/bin/.

SQLITE_DIR="$REPO_ROOT/addons/godot-sqlite"
if [[ -f "$SQLITE_DIR/gdsqlite.gdextension" ]]; then
  echo "godot-sqlite already installed at $SQLITE_DIR — skipping (idempotent)."
else
  echo "Installing 2shady4u/godot-sqlite $GODOT_SQLITE_VERSION ..."
  TMPDIR_SQLITE=$(mktemp -d)

  # Download demo.zip (contains the full addon under demo/addons/godot-sqlite/)
  if ! curl -fL --max-time 120 -o "$TMPDIR_SQLITE/demo.zip" "$GODOT_SQLITE_URL"; then
    echo "ERROR: Failed to download godot-sqlite from $GODOT_SQLITE_URL" >&2
    rm -rf "$TMPDIR_SQLITE"
    exit 1
  fi

  # Verify SHA-256 checksum (supply-chain protection, T-02-SC)
  ACTUAL_SHA=$(sha256sum "$TMPDIR_SQLITE/demo.zip" 2>/dev/null | awk '{print $1}' \
    || shasum -a 256 "$TMPDIR_SQLITE/demo.zip" | awk '{print $1}')
  if [[ "$ACTUAL_SHA" != "$GODOT_SQLITE_SHA256" ]]; then
    echo "ERROR: SHA-256 mismatch for godot-sqlite demo.zip!" >&2
    echo "  Expected: $GODOT_SQLITE_SHA256" >&2
    echo "  Got:      $ACTUAL_SHA" >&2
    echo "  If upstream re-tagged, update GODOT_SQLITE_SHA256 in scripts/install-deps.sh." >&2
    rm -rf "$TMPDIR_SQLITE"
    exit 1
  fi
  echo "godot-sqlite checksum verified OK."

  # Unzip the demo.zip — addon lives under demo/addons/godot-sqlite/
  if ! unzip -q "$TMPDIR_SQLITE/demo.zip" "demo/addons/godot-sqlite/*" -d "$TMPDIR_SQLITE/"; then
    echo "ERROR: Failed to unzip godot-sqlite demo.zip" >&2
    rm -rf "$TMPDIR_SQLITE"
    exit 1
  fi

  # Copy addon files into addons/godot-sqlite/ (preserving directory structure).
  # Remove .gitkeep stub first so directories merge cleanly, then restore it.
  rm -f "$SQLITE_DIR/.gitkeep"
  cp -r "$TMPDIR_SQLITE/demo/addons/godot-sqlite/." "$SQLITE_DIR/"
  # Restore .gitkeep so the directory stays tracked in git even after gitignore rules
  # exclude the binary contents (the .gitkeep itself is never ignored).
  touch "$SQLITE_DIR/.gitkeep"

  rm -rf "$TMPDIR_SQLITE"
  echo "godot-sqlite installed at $SQLITE_DIR"

  # Verify expected binary files for key platforms
  for expected_lib in \
    "bin/libgdsqlite.macos.template_release.framework" \
    "bin/libgdsqlite.windows.template_release.x86_64.dll" \
    "bin/libgdsqlite.linux.template_release.x86_64.so" \
    "bin/libgdsqlite.android.template_release.arm64.so"; do
    if [[ ! -e "$SQLITE_DIR/$expected_lib" ]]; then
      echo "WARNING: Expected binary not found: addons/godot-sqlite/$expected_lib"
    fi
  done
fi

# ─── Install webrtc-native GDExtension 1.1.0-stable (Phase 4) ────────────────
# Source: https://github.com/godotengine/webrtc-native (MPL-2.0 / libdatachannel)
# Installs platform binaries under addons/webrtc-native/bin/.
# The .gdextension manifest is already committed to git (addons/webrtc-native/).

WEBRTC_DIR="$REPO_ROOT/addons/webrtc-native"
WEBRTC_BIN_DIR="$WEBRTC_DIR/bin"
# Check if at least one platform binary is present
if [[ -f "$WEBRTC_BIN_DIR/libwebrtc_native.linux.template_release.x86_64.so" ]] || \
   [[ -f "$WEBRTC_BIN_DIR/libwebrtc_native.windows.template_release.x86_64.dll" ]] || \
   [[ -d "$WEBRTC_BIN_DIR/libwebrtc_native.macos.template_release.universal.framework" ]]; then
  echo "webrtc-native already installed at $WEBRTC_BIN_DIR — skipping (idempotent)."
else
  echo "Installing godotengine/webrtc-native $WEBRTC_NATIVE_VERSION ..."
  TMPDIR_WEBRTC=$(mktemp -d)

  if ! curl -fL --max-time 300 -o "$TMPDIR_WEBRTC/webrtc.zip" "$WEBRTC_NATIVE_URL"; then
    echo "ERROR: Failed to download webrtc-native from $WEBRTC_NATIVE_URL" >&2
    rm -rf "$TMPDIR_WEBRTC"
    exit 1
  fi

  # Extract only the lib/ directory (platform binaries) from webrtc/ prefix
  mkdir -p "$WEBRTC_BIN_DIR"
  if ! unzip -q "$TMPDIR_WEBRTC/webrtc.zip" "webrtc/lib/*" -d "$TMPDIR_WEBRTC/"; then
    echo "ERROR: Failed to unzip webrtc-native zip" >&2
    rm -rf "$TMPDIR_WEBRTC"
    exit 1
  fi

  # Copy extracted binaries from webrtc/lib/ into addons/webrtc-native/bin/
  cp -r "$TMPDIR_WEBRTC/webrtc/lib/." "$WEBRTC_BIN_DIR/"

  rm -rf "$TMPDIR_WEBRTC"
  echo "webrtc-native binaries installed at $WEBRTC_BIN_DIR"
fi

# ─── Verification ─────────────────────────────────────────────────────────────

echo ""
echo "=== Post-install verification ==="
echo ""

godot --version 2>&1 | grep -E "^4\.6\." || echo "WARNING: godot version mismatch"
git -C "$REPO_ROOT/addons/godot_voxel" rev-parse HEAD 2>/dev/null || echo "WARNING: godot_voxel commit unknown"
rg --version | head -1
reuse --version

echo ""
echo "Installation complete. See docs/SETUP.md for next steps."
