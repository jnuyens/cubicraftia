# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# test_brick_registry.gd — Unit tests for BrickRegistry autoload (50-brick manifest loading).
#
# Anchors:
#   DOCS.md §3.1 — 50 brick types across 10 categories; 18-colour palette for non-material bricks
#   CONTEXT.md D-02 — brick surface treatment per category (colour_swappable / natural_colour_token)
#   CONTEXT.md D-08 — stud_profile = "concave_top" invariant (T-04-01 threat mitigation)
#   02-RESEARCH.md §"Brick Library Schema"
#
# Category distribution contract (DOCS.md §3.1):
#   RECTANGULAR (0)=7, PLATE (1)=5, SLOPE (2)=4, TILE (3)=3, ROUND (4)=4,
#   FUNCTIONAL (5)=7, DECORATIVE (6)=5, MATERIAL_ORE (7)=9, ACCESSORY (8)=5, MOB_DROP (9)=3
#   Total = 50 (+ raw_meat & sashimi MOB_DROP from issue #17 + 16 art-furniture DECORATIVE
#               + builder_bed FUNCTIONAL — now manifest-loaded so the bed self-register no
#                 longer fires a register_pack warning on world load)
#
# fence_post intentionally dropped (per 02-04-PLAN.md DOCS §3.1 ±2-per-category clause).
#
# Turned GREEN by Plan 02-04 (BrickRegistry autoload implementation).

extends GutTest

# ─── Helpers ──────────────────────────────────────────────────────────────────

## Load all 50 BrickDefinitions directly from the manifest (no autoload dependency).
## This lets the test run without Godot's autoload system initialising BrickRegistry.
func _load_all_from_manifest() -> Array:
	var file := FileAccess.open("res://src/bricks/manifest.json", FileAccess.READ)
	if file == null:
		return []
	var text := file.get_as_text()
	file.close()
	var parsed = JSON.parse_string(text)
	if not parsed is Array:
		return []
	var result: Array = []
	for entry: Variant in (parsed as Array):
		if not entry is String:
			continue
		var def := load("res://src/bricks/" + (entry as String)) as BrickDefinition
		if def != null:
			result.append(def)
	return result

# ─── Test 1 ────────────────────────────────────────────────────────────────────

func test_all_50_load_and_validate() -> void:
	var defs: Array = _load_all_from_manifest()

	# Total count. Base 50 + 16 art-furniture decorative placeables (Meshy furniture set)
	# + raw_meat + sashimi (issue #17 wildlife drops) + builder_bed (now manifest-loaded) = 69.
	assert_eq(defs.size(), 69, "BrickRegistry must have exactly 69 BrickDefinitions")

	# Uniqueness and basic validity.
	var seen_ids: Dictionary = {}
	for def: Variant in defs:
		var bd := def as BrickDefinition
		assert_not_null(bd, "Every manifest entry must deserialise to a BrickDefinition")
		assert_true(bd.brick_id != "", "Every BrickDefinition must have a non-empty brick_id")
		assert_true(bd.display_name_key != "", "Every BrickDefinition must have a non-empty display_name_key")
		# D-08 invariant: stud_profile must be "concave_top" on every brick.
		assert_eq(bd.stud_profile, "concave_top",
			"T-04-01 invariant: stud_profile must be 'concave_top' for brick '%s'" % bd.brick_id)
		# No duplicate ids.
		assert_false(seen_ids.has(bd.brick_id),
			"brick_id '%s' must be unique across the brick set" % bd.brick_id)
		seen_ids[bd.brick_id] = true

	assert_eq(seen_ids.size(), 69, "All 69 brick_ids must be unique")

# ─── Test 2 ────────────────────────────────────────────────────────────────────

func test_get_by_category_returns_correct_set() -> void:
	var defs: Array = _load_all_from_manifest()
	assert_eq(defs.size(), 69, "Must have 69 definitions to verify category distribution")

	# Build per-category count map.
	var counts: Dictionary = {}
	for def: Variant in defs:
		var cat: int = (def as BrickDefinition).category
		counts[cat] = counts.get(cat, 0) + 1

	# Expected category distribution per DOCS.md §3.1.
	assert_eq(counts.get(BrickDefinition.Category.RECTANGULAR,  0), 7, "RECTANGULAR must have 7 bricks")
	assert_eq(counts.get(BrickDefinition.Category.PLATE,        0), 5, "PLATE must have 5 bricks")
	assert_eq(counts.get(BrickDefinition.Category.SLOPE,        0), 4, "SLOPE must have 4 bricks")
	assert_eq(counts.get(BrickDefinition.Category.TILE,         0), 3, "TILE must have 3 bricks")
	assert_eq(counts.get(BrickDefinition.Category.ROUND,        0), 4, "ROUND must have 4 bricks")
	assert_eq(counts.get(BrickDefinition.Category.FUNCTIONAL,   0), 7, "FUNCTIONAL must have 7 bricks (6 base + builder_bed)")
	assert_eq(counts.get(BrickDefinition.Category.DECORATIVE,   0), 21, "DECORATIVE must have 21 bricks (5 base + 16 art-furniture)")
	assert_eq(counts.get(BrickDefinition.Category.MATERIAL_ORE, 0), 9, "MATERIAL_ORE must have 9 bricks")
	assert_eq(counts.get(BrickDefinition.Category.ACCESSORY,    0), 5, "ACCESSORY must have 5 bricks")
	assert_eq(counts.get(BrickDefinition.Category.MOB_DROP,     0), 4, "MOB_DROP must have 4 bricks (bone, slime_cube, raw_meat, sashimi)")
