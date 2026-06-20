#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# stamp-version.sh — write a per-build identifier to res://version.txt (repo root).
#
# The file holds ONE line: the short commit hash (with a "+" suffix if the working
# tree is dirty) followed by the short date, e.g.
#
#     a1b2c3d 2026-06-20
#     a1b2c3d+ 2026-06-20   (working tree has uncommitted changes)
#
# version.txt is a build artifact (git-ignored). Re-run this before every playtest
# or export so the in-game BuildInfo label/console line matches the running build:
#
#     bash scripts/stamp-version.sh
#
# Idempotent: re-running for the same commit + tree state produces identical output.
# No dependencies beyond git and date.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OUT_FILE="$REPO_ROOT/version.txt"

# Short commit hash (fallback "unknown" if not in a git repo / no commits yet).
SHORT_HASH="$(git -C "$REPO_ROOT" rev-parse --short HEAD 2>/dev/null || echo "unknown")"

# Append "+" when the working tree has uncommitted changes (tracked files).
if [ -n "$(git -C "$REPO_ROOT" status --porcelain 2>/dev/null)" ]; then
	SHORT_HASH="${SHORT_HASH}+"
fi

SHORT_DATE="$(date +%F)"

printf '%s %s\n' "$SHORT_HASH" "$SHORT_DATE" > "$OUT_FILE"

echo "stamp-version: wrote $OUT_FILE -> $SHORT_HASH $SHORT_DATE"
