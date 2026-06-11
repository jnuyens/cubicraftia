#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# glossary-check.sh — CI grep enforcing DOC-10 terminology hygiene
#
# Fails (exit 1) if any forbidden term appears outside the allowlist.
# Passes (exit 0) if clean.
#
# Forbidden terms with their locked replacements (DOCS.md §10):
#   "Lego" / "LEGO" / homoglyph Lеgo (Cyrillic е)  →  "brick" / (no replacement needed)
#   "minifig" / "minifigure"                         →  "builder"
#   "Minecraft"                                       →  (no replacement; must not appear)
#
# Usage:
#   bash scripts/glossary-check.sh
#   ./scripts/glossary-check.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

ALLOWLIST_FILE="scripts/glossary-allowlist.txt"

# Standard forbidden pattern (word-boundary, case variants):
FORBIDDEN_PATTERN='\b([Ll]ego|LEGO|[Mm]inifig(ure)?s?|[Mm]inecraft)\b'

# Cyrillic-е homoglyph defense: "Lеgo" where е is U+0435 (Cyrillic small letter ie)
# rg supports --pcre2 for this Unicode codepoint check.
HOMOGLYPH_PATTERN='L\x{0435}go'

FAIL=0

# ─── Standard pattern — search from repo root with globs ─────────────────────
# Pass '.' as the search root so --glob flags activate for all subdirectories.
# Restrict to player-facing surfaces only.
if rg -n \
       --regexp "$FORBIDDEN_PATTERN" \
       --glob 'src/**/*.gd' \
       --glob 'src/**/*.tscn' \
       --glob 'src/**/*.tres' \
       --glob 'locale/**/*.po' \
       --glob 'locale/**/*.pot' \
       --glob 'docs/**/*.md' \
       --glob 'README.md' \
       --glob 'project.godot' \
       . \
       2>/dev/null \
   | grep -v -F -f "$ALLOWLIST_FILE" \
   | grep -q .; then
    echo "FAIL: forbidden terminology found outside the allowlist." >&2
    rg -n \
           --regexp "$FORBIDDEN_PATTERN" \
           --glob 'src/**/*.gd' \
           --glob 'src/**/*.tscn' \
           --glob 'src/**/*.tres' \
           --glob 'locale/**/*.po' \
           --glob 'locale/**/*.pot' \
           --glob 'docs/**/*.md' \
           --glob 'README.md' \
           --glob 'project.godot' \
           . \
           2>/dev/null \
       | grep -v -F -f "$ALLOWLIST_FILE" >&2 || true
    FAIL=1
fi

# ─── Cyrillic homoglyph check ─────────────────────────────────────────────────
if rg --pcre2 -n \
       --regexp "$HOMOGLYPH_PATTERN" \
       --glob 'src/**/*.gd' \
       --glob 'src/**/*.tscn' \
       --glob 'src/**/*.tres' \
       --glob 'locale/**/*.po' \
       --glob 'locale/**/*.pot' \
       --glob 'docs/**/*.md' \
       --glob 'README.md' \
       --glob 'project.godot' \
       . \
       2>/dev/null \
   | grep -v -F -f "$ALLOWLIST_FILE" \
   | grep -q .; then
    echo "FAIL: Cyrillic-е homoglyph of 'Lego' found." >&2
    FAIL=1
fi

if [[ "$FAIL" -eq 1 ]]; then
    exit 1
fi

echo "OK: no forbidden terminology in player-facing surfaces."
