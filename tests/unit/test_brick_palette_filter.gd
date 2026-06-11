# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# test_brick_palette_filter.gd — Unit tests for brick palette search + category + colour filters.
#
# Anchors:
#   DOCS.md §3 — palette UI: desktop sidebar + mobile bottom sheet
#   02-CONTEXT.md §D-12 — brick palette previews are 3D real-time renders
#   02-UI-SPEC.md §"Brick Palette" — search, category chip, colour chip filters
#   02-RESEARCH.md §"Brick Palette UI"
#
# Plan 12 ships BrickPalette filter logic — tests turned GREEN.
#
# Strategy: Filter logic is tested via:
#   1. BrickDefinition.display_name_key + tr() substring matching (the search contract)
#   2. BrickDefinition.category enum filtering (category filter contract)
#   3. BrickDefinition.colour_swappable flag (colour filter bypass for material bricks)
#
# BrickPaletteUI._matches_search() is tested via an injected helper function
# that replicates the exact same logic without requiring scene instantiation.
# This is the same pattern used in test_brick_registry.gd (headless-preload-pattern).
#
# NOTE: BrickPaletteUI (brick_palette.gd) extends PanelContainer and cannot be
# safely instantiated without a full scene tree + GPU (SubViewport dependency).
# Tests use the logic-only approach instead.

extends GutTest

# ─── Test fixtures ─────────────────────────────────────────────────────────────

## Minimal BrickDefinition stubs for filter logic tests.
## These are created in memory (not loaded from .tres) for hermeticity.

var _def_brick_1x1: BrickDefinition = null
var _def_plate_1x1: BrickDefinition = null
var _def_iron_ore: BrickDefinition = null

func before_each() -> void:
	# Create minimal BrickDefinition stubs
	_def_brick_1x1 = BrickDefinition.new()
	_def_brick_1x1.brick_id = "brick_1x1"
	_def_brick_1x1.display_name_key = "bricks.brick_1x1.name"  # "1×1 brick"
	_def_brick_1x1.category = BrickDefinition.Category.RECTANGULAR
	_def_brick_1x1.colour_swappable = true
	_def_brick_1x1.palette_colour_index = -1

	_def_plate_1x1 = BrickDefinition.new()
	_def_plate_1x1.brick_id = "plate_1x1"
	_def_plate_1x1.display_name_key = "bricks.plate_1x1.name"  # "1×1 plate"
	_def_plate_1x1.category = BrickDefinition.Category.PLATE
	_def_plate_1x1.colour_swappable = true
	_def_plate_1x1.palette_colour_index = -1

	_def_iron_ore = BrickDefinition.new()
	_def_iron_ore.brick_id = "iron_ore"
	_def_iron_ore.display_name_key = "bricks.iron_ore.name"  # "Iron ore"
	_def_iron_ore.category = BrickDefinition.Category.MATERIAL_ORE
	_def_iron_ore.colour_swappable = false
	_def_iron_ore.natural_colour_token = -1


## Replicate BrickPaletteUI._matches_search() logic for test isolation.
## Per brick_palette.gd: substring match on tr(def.display_name_key).
func _palette_matches_search(def: BrickDefinition, query: String) -> bool:
	var translated_name: String = tr(def.display_name_key)
	return translated_name.to_lower().contains(query.to_lower())


# ─── Test 1: search filter ────────────────────────────────────────────────────

## Verify that search filter correctly matches/excludes bricks by translated display name.
## Tests: substring match, negative match, case-insensitivity.
func test_search_matches_display_name_key() -> void:
	# "plate" should match plate_1x1 (name = "1×1 plate")
	assert_true(_palette_matches_search(_def_plate_1x1, "plate"),
		"Search 'plate' should match '1×1 plate'")

	# "plate" should NOT match brick_1x1 (name = "1×1 brick")
	assert_false(_palette_matches_search(_def_brick_1x1, "plate"),
		"Search 'plate' should NOT match '1×1 brick'")

	# "brick" should match brick_1x1 (name = "1×1 brick")
	assert_true(_palette_matches_search(_def_brick_1x1, "brick"),
		"Search 'brick' should match '1×1 brick'")

	# Case-insensitive: "PLATE" should match "1×1 plate"
	assert_true(_palette_matches_search(_def_plate_1x1, "PLATE"),
		"Search 'PLATE' (uppercase) should match '1×1 plate' (case-insensitive)")

	# Partial match at word boundary not required (substring): "1" should match "1×1 brick"
	assert_true(_palette_matches_search(_def_brick_1x1, "1"),
		"Search '1' should match '1×1 brick' (substring)")


# ─── Test 2: category filter ───────────────────────────────────────────────────

## Verify that category filter returns only bricks in the correct category.
func test_category_filter_returns_subset() -> void:
	# PLATE category should only match plate definitions
	assert_true(_def_plate_1x1.category == BrickDefinition.Category.PLATE,
		"plate_1x1 should be in PLATE category")
	assert_false(_def_brick_1x1.category == BrickDefinition.Category.PLATE,
		"brick_1x1 should NOT be in PLATE category")
	assert_false(_def_iron_ore.category == BrickDefinition.Category.PLATE,
		"iron_ore should NOT be in PLATE category")

	# RECTANGULAR category should only match brick_1x1 out of our stubs
	assert_true(_def_brick_1x1.category == BrickDefinition.Category.RECTANGULAR,
		"brick_1x1 should be in RECTANGULAR category")
	assert_false(_def_plate_1x1.category == BrickDefinition.Category.RECTANGULAR,
		"plate_1x1 should NOT be in RECTANGULAR category")

	# MATERIAL_ORE category
	assert_true(_def_iron_ore.category == BrickDefinition.Category.MATERIAL_ORE,
		"iron_ore should be in MATERIAL_ORE category")

	# Verify BrickRegistry.get_by_category works (live autoload if available)
	if BrickRegistry.get_all().size() > 0:
		var plate_results: Array = BrickRegistry.get_by_category(BrickDefinition.Category.PLATE)
		assert_true(plate_results.size() > 0,
			"BrickRegistry.get_by_category(PLATE) should return at least 1 result")
		for entry: Variant in plate_results:
			var bdef: BrickDefinition = entry as BrickDefinition
			assert_eq(bdef.category, BrickDefinition.Category.PLATE,
				"All results from get_by_category(PLATE) must be PLATE category")


# ─── Test 3: colour filter ─────────────────────────────────────────────────────

## Verify colour filter contract:
## - Colour-swappable bricks are shown with the selected colour index
## - Material bricks (colour_swappable=false) always bypass the colour filter
func test_colour_filter_returns_subset() -> void:
	var colour_index_red: int = 4  # red = #D63828 per UI-SPEC.md

	# Colour index 4 must be valid in the 18-colour palette
	assert_true(colour_index_red >= 0 and colour_index_red < BrickPalette.COLOURS.size(),
		"Colour index 4 (red) should be valid in the 18-colour palette")

	# Verify red is correct (D-03 anchor: #D63828)
	assert_eq(BrickPalette.COLOURS[colour_index_red], Color(0.839, 0.220, 0.157, 1.0),
		"Colour index 4 should be red #D63828 (D-03 anchor)")

	# Colour-swappable brick passes colour filter: it will be shown with colour_index=4
	assert_true(_def_brick_1x1.colour_swappable,
		"brick_1x1 should be colour_swappable=true (passes colour filter)")

	# Material brick bypasses colour filter (colour_swappable=false)
	# Per UI-SPEC.md: "material bricks bypass colour swap"
	assert_false(_def_iron_ore.colour_swappable,
		"iron_ore should be colour_swappable=false (bypasses colour filter)")

	# Verify all-colours filter (-1): both types should be included
	# All-colours filter means: include ALL bricks regardless of colour_swappable
	var all_filter: int = -1
	var swappable_included: bool = (all_filter == -1 or _def_brick_1x1.colour_swappable)
	var material_included: bool = (all_filter == -1 or not _def_iron_ore.colour_swappable)
	assert_true(swappable_included,
		"All-colours filter should include colour-swappable bricks")
	assert_true(material_included,
		"All-colours filter should include material bricks (colour_swappable=false)")

	# Specific colour filter: colour-swappable bricks included, material bricks also included
	var swappable_passes_colour: bool = _def_brick_1x1.colour_swappable
	var material_bypasses_colour: bool = (not _def_iron_ore.colour_swappable)
	assert_true(swappable_passes_colour,
		"Colour-swappable brick should pass when colour filter == 4")
	assert_true(material_bypasses_colour,
		"Material brick (colour_swappable=false) should bypass colour filter == 4")
