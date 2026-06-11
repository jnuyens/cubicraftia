# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# test_recipes.gd — Unit tests for v1 recipe loading and shape matching.
#
# Anchors:
#   DOCS.md §4.5 — ~10 v1 recipes; shaped vs shapeless matching
#   03-PLAN.md 03-01 Task 2 — test_recipes.gd scaffold
#   03-CONTEXT.md D-07 — recipe ingredient ratios at Claude's discretion
#
# These tests reference recipe .tres resources shipping in Plan 03-07.
# They will FAIL until Plan 03-07 executes.

extends GutTest

const _RECIPE_PATHS: Array[String] = [
	"res://src/crafting/recipes/recipe_wooden_plank.tres",
	"res://src/crafting/recipes/recipe_stick.tres",
	"res://src/crafting/recipes/recipe_pickaxe_wood.tres",
	"res://src/crafting/recipes/recipe_shovel_wood.tres",
	"res://src/crafting/recipes/recipe_sword_wood.tres",
	"res://src/crafting/recipes/recipe_dynamite.tres",
	"res://src/crafting/recipes/recipe_lantern.tres",
	"res://src/crafting/recipes/recipe_torch.tres",
	"res://src/crafting/recipes/recipe_ladder.tres",
	"res://src/crafting/recipes/recipe_chest.tres",
]


# ─── Test 1: All 10 v1 recipes are loadable ───────────────────────────────────

func test_all_ten_v1_recipes_loadable() -> void:
	# Every recipe .tres file listed in DOCS §4.5 must be loadable as a Resource.
	for path: String in _RECIPE_PATHS:
		if not ResourceLoader.exists(path):
			pending("Recipe file '%s' does not exist yet — pending until Plan 03-07" % path)
			return
	for path: String in _RECIPE_PATHS:
		var recipe: Resource = load(path)
		assert_not_null(recipe, "Recipe resource should load from '%s'" % path)


# ─── Test 2: Recipe output def_ids resolve in BrickRegistry ───────────────────

func test_recipe_output_def_ids_resolve_in_brick_registry() -> void:
	# Every recipe.output_def_id must be registered in BrickRegistry OR be a
	# known non-brick item (key/food/tool).
	var non_brick_ids: Array[String] = [
		"key_bronze", "key_silver", "key_gold", "key_diamond",
		"food_cooked_generic", "food_tom_yum_seafood", "food_roasted_fish",
		"pickaxe_wooden", "pickaxe_stone", "pickaxe_iron", "pickaxe_diamond",
		"shovel_wooden", "shovel_stone", "shovel_iron", "shovel_diamond",
		"sword_wooden", "sword_stone", "sword_iron", "sword_diamond",
		"dynamite", "lantern", "torch", "ladder",
	]
	for path: String in _RECIPE_PATHS:
		if not ResourceLoader.exists(path):
			pending("Recipe files not yet available — pending until Plan 03-07")
			return
	for path: String in _RECIPE_PATHS:
		var recipe: Resource = load(path)
		if recipe == null:
			continue
		var output_id: String = str(recipe.get("output_def_id"))
		if output_id.is_empty():
			continue
		# Check BrickRegistry first, then non-brick allow-list.
		var resolved: bool = (
			BrickRegistry.get_definition(output_id) != null
			or non_brick_ids.has(output_id)
		)
		assert_true(resolved,
			"Recipe output_def_id '%s' (from '%s') must resolve in BrickRegistry or non-brick list" % [output_id, path])


# ─── Test 3: Shaped recipes are position-sensitive ────────────────────────────

func test_shaped_recipes_position_sensitive() -> void:
	# Shaped recipes (e.g. pickaxe) must NOT match if ingredients are in wrong positions.
	var pickaxe_path := "res://src/crafting/recipes/recipe_pickaxe_wood.tres"
	if not ResourceLoader.exists(pickaxe_path):
		pending("Pickaxe recipe not yet available — pending until Plan 03-07")
		return
	var recipe: Resource = load(pickaxe_path)
	assert_not_null(recipe, "Pickaxe recipe must load")
	# Access Inventory autoload directly (not via Engine.has_singleton —
	# GDScript autoloads registered in project.godot are not C++ singletons;
	# see STATE.md decision "inventory-engine-has-singleton").
	if not is_instance_valid(Inventory):
		pending("Inventory autoload not available — pending until Plan 03-02")
		return
	# A 3×3 grid with all ingredients in wrong positions should not match the pickaxe recipe.
	var wrong_grid: Array = []
	for _i: int in 9:
		wrong_grid.append({"def_id": "", "count": 0})
	# Put wood planks in corner instead of top row.
	wrong_grid[8] = {"def_id": "brick_plank_wooden", "count": 1}
	var match_result: Variant = Inventory.match_recipe(wrong_grid, false)
	assert_null(match_result,
		"Pickaxe recipe must not match when ingredients are in wrong positions (shaped)")


# ─── Test 4: Shapeless recipes are position-insensitive ───────────────────────

func test_shapeless_recipes_position_insensitive() -> void:
	# Shapeless recipes (e.g. planks from log) match regardless of slot position.
	var planks_path := "res://src/crafting/recipes/recipe_wooden_plank.tres"
	if not ResourceLoader.exists(planks_path):
		pending("Planks recipe not yet available — pending until Plan 03-07")
		return
	var recipe: Resource = load(planks_path)
	assert_not_null(recipe, "Planks recipe must load")
	# Access Inventory autoload directly (not via Engine.has_singleton —
	# GDScript autoloads registered in project.godot are not C++ singletons;
	# see STATE.md decision "inventory-engine-has-singleton").
	if not is_instance_valid(Inventory):
		pending("Inventory autoload not available — pending until Plan 03-02")
		return
	# Put a wood log in any slot of the 2×2 grid — should match planks recipe.
	for slot_idx: int in [0, 1, 2, 3]:
		var grid: Array = [
			{"def_id": "", "count": 0},
			{"def_id": "", "count": 0},
			{"def_id": "", "count": 0},
			{"def_id": "", "count": 0},
		]
		# def_id is "wood_log" — matches recipe_wooden_plank inputs, the wood_log.tres brick
		# id, and the mined-trunk grant (builder.gd voxel 10 → "wood_log"). The old
		# "brick_log_wood" was a test-only typo that never matched the real recipe.
		grid[slot_idx] = {"def_id": "wood_log", "count": 1}
		var match_result: Variant = Inventory.match_recipe(grid, true)
		assert_not_null(match_result,
			"Planks recipe must match with log in slot %d (shapeless)" % slot_idx)
