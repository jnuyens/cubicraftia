# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# palette.gd — The 18-colour brick palette tokens (DOCS.md §3.1, UI-SPEC.md §Color).
#
# Source of truth for non-material brick colours. Material/ore bricks use their
# natural colour and bypass this table (palette_colour_index = -1 on BrickDefinition).
#
# Anchored to CONTEXT.md D-03 "saturated cheerful primaries" — four primaries locked:
#   white  = #F1F0EA   (index 0)
#   red    = #D63828   (index 4)
#   yellow = #F5C30D   (index 6)
#   green  = #5DBB46   (index 8)
#   blue   = #1F7BCB   (index 12)
#
# The remaining 14 colours are Claude's discretion within the same saturation band;
# they must be user-approved before the brick-library count is locked (CONTEXT.md D-06).
#
# Indices are STABLE — never re-order. BrickDefinition.natural_colour_token and
# per-instance StudGrid records reference these indices by integer.
#
# References:
#   DOCS.md §3.1 — 18-colour palette requirement
#   CONTEXT.md D-03 — palette saturation anchor
#   02-UI-SPEC.md §Color — "Content colours (18-brick-palette tokens — LOCKED)"
#   02-PATTERNS.md §"src/bricks/palette.gd" — class shape

class_name BrickPalette
extends RefCounted

# ─── Colour table (18 entries, indices stable) ────────────────────────────────

const COLOURS: Array[Color] = [
	Color(0.945, 0.941, 0.918, 1.0),   #  0 white        #F1F0EA  [D-03 anchor]
	Color(0.651, 0.651, 0.651, 1.0),   #  1 light grey   #A6A6A6
	Color(0.247, 0.247, 0.247, 1.0),   #  2 dark grey    #3F3F3F
	Color(0.067, 0.067, 0.067, 1.0),   #  3 black        #111111
	Color(0.839, 0.220, 0.157, 1.0),   #  4 red          #D63828  [D-03 anchor]
	Color(0.902, 0.541, 0.114, 1.0),   #  5 orange       #E68A1D
	Color(0.961, 0.765, 0.051, 1.0),   #  6 yellow       #F5C30D  [D-03 anchor]
	Color(0.776, 0.882, 0.102, 1.0),   #  7 lime         #C6E11A
	Color(0.365, 0.733, 0.275, 1.0),   #  8 green        #5DBB46  [D-03 anchor]
	Color(0.184, 0.447, 0.208, 1.0),   #  9 dark green   #2F7235
	Color(0.102, 0.769, 0.851, 1.0),   # 10 cyan         #1AC4D9
	Color(0.353, 0.839, 0.941, 1.0),   # 11 light blue   #5AD6F0
	Color(0.122, 0.482, 0.796, 1.0),   # 12 blue         #1F7BCB  [D-03 anchor]
	Color(0.478, 0.184, 0.682, 1.0),   # 13 purple       #7A2FAE
	Color(0.902, 0.345, 0.561, 1.0),   # 14 pink         #E6588F
	Color(0.478, 0.290, 0.137, 1.0),   # 15 brown        #7A4A23
	Color(0.843, 0.725, 0.478, 1.0),   # 16 tan          #D7B97A
	Color(0.890, 0.800, 0.482, 1.0),   # 17 sand-yellow  #E3CC7B
]

# ─── Name tokens (parallel to COLOURS; stable) ───────────────────────────────

const NAMES: PackedStringArray = [
	"white", "light_grey", "dark_grey", "black",
	"red", "orange", "yellow", "lime",
	"green", "dark_green", "cyan", "light_blue",
	"blue", "purple", "pink", "brown", "tan", "sand_yellow",
]

# ─── API ─────────────────────────────────────────────────────────────────────

## Return the Color for a palette index.
## Emits push_error and returns Color.MAGENTA for out-of-range indices.
static func get_colour(index: int) -> Color:
	if index < 0 or index >= COLOURS.size():
		push_error("BrickPalette.get_colour: invalid index %d (valid: 0..%d)" % [index, COLOURS.size() - 1])
		return Color.MAGENTA
	return COLOURS[index]
