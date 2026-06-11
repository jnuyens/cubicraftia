#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# extract-pot.sh — extract translation keys from GDScript source into locale/messages.pot
#
# Scans all .gd files under src/ for tr() and Translations.t() calls and extracts
# msgid strings into locale/messages.pot using xgettext.
#
# The POT-Creation-Date header is stripped to ensure idempotent output (two
# consecutive runs produce byte-identical output, per Pitfall 5 / Test 4).
#
# Usage:
#   bash scripts/extract-pot.sh
#   ./scripts/extract-pot.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

POT_FILE="locale/messages.pot"

# Collect all GDScript sources
GD_FILES=$(find src -name '*.gd' 2>/dev/null | sort)
TSCN_FILES=$(find src -name '*.tscn' 2>/dev/null | sort)

# Build the file list for xgettext
# xgettext can parse Python-style files for tr() / t() keywords
# --language=Python handles GDScript tr("key") calls adequately

POT_TMP=$(mktemp /tmp/cubicraftia-messages.XXXXXXXX.pot)

# Run xgettext
# shellcheck disable=SC2086
if [[ -n "$GD_FILES" || -n "$TSCN_FILES" ]]; then
    xgettext \
        --language=Python \
        --keyword=tr \
        --keyword=t:1 \
        --keyword=Translations.t:1 \
        --from-code=UTF-8 \
        --package-name=Cubicraftia \
        --package-version=0.1.0 \
        --copyright-holder="Cubicraftia contributors" \
        --no-location \
        --output="$POT_TMP" \
        $GD_FILES $TSCN_FILES 2>/dev/null || true
else
    # No source files yet — emit an empty but valid POT header
    cat > "$POT_TMP" <<'EMPTY_POT'
# SOME DESCRIPTIVE TITLE.
# Copyright (C) YEAR Cubicraftia contributors
# This file is distributed under the same license as the Cubicraftia package.
# FIRST AUTHOR <EMAIL@ADDRESS>, YEAR.
#
msgid ""
msgstr ""
"Project-Id-Version: Cubicraftia 0.1.0\n"
"Report-Msgid-Bugs-To: \n"
"MIME-Version: 1.0\n"
"Content-Type: text/plain; charset=UTF-8\n"
"Content-Transfer-Encoding: 8bit\n"
EMPTY_POT
fi

# Strip the POT-Creation-Date line to make output deterministic
# macOS sed: -i '' ; GNU sed: -i (detect automatically)
if sed --version 2>&1 | grep -q GNU; then
    sed -i '/^"POT-Creation-Date/d' "$POT_TMP"
else
    sed -i '' '/^"POT-Creation-Date/d' "$POT_TMP"
fi

# Move to final destination
mv "$POT_TMP" "$POT_FILE"

echo "OK: locale/messages.pot updated ($(wc -l < "$POT_FILE") lines)."
