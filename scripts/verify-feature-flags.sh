#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# verify-feature-flags.sh — DOC-09 invariant guard
#
# Every cubicraftia/features/* setting must ship as `false` in project.godot.
# If a §9 deferred-feature flag needs to flip true, the DOCS.md §9 table must
# be updated first. This script enforces the invariant in CI.
#
# Usage:
#   bash scripts/verify-feature-flags.sh
#   ./scripts/verify-feature-flags.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

FAIL=0

# Check project.godot for any feature flag set to true
if rg -n '^cubicraftia/features/[a-z_0-9]+\s*=\s*true' project.godot 2>/dev/null; then
    echo "FAIL: a §9 deferred-feature flag is set to true in project.godot." >&2
    echo "      Update DOCS.md §9 and get a review before flipping a feature flag." >&2
    FAIL=1
fi

# Also check override.cfg if it exists (T-02-02 threat mitigation)
if [[ -f "override.cfg" ]]; then
    if rg -n '^cubicraftia/features/[a-z_0-9]+\s*=\s*true' override.cfg 2>/dev/null; then
        echo "FAIL: a §9 deferred-feature flag is set to true in override.cfg." >&2
        FAIL=1
    fi
fi

if [[ "$FAIL" -eq 1 ]]; then
    exit 1
fi

echo "OK: all §9 deferred-feature flags ship off."
