# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# recipe_registry.gd — Loads all Recipe .tres files from src/crafting/recipes/ and
# registers crafting-only items (e.g. stick) with BrickRegistry.
#
# Called by Inventory autoload at _ready() via the preloaded script constant.
#
# Design:
#   - DirAccess scan: adding a new recipe is drop-in (no hard-coded list).
#   - Stick (and any future crafting-only items) are registered via
#     BrickRegistry.register_pack() so recipe outputs resolve in BrickRegistry.
#     This does NOT modify manifest.json, preserving the 50-brick contract.
#   - Duck typing used throughout to avoid Recipe class_name scope issues at
#     parse time (headless-preload-pattern — STATE.md decision 02-07).
#
# DOCS.md §4.5 — ~10 v1 recipes (11 with workbench-craft planner extension).
# 03-CONTEXT.md D-07 — recipe ingredient ratios at Claude's discretion.
# 03-07a-PLAN.md Task 1 — RecipeRegistry.load_all(), match_recipe_in_grid().

class_name RecipeRegistry
extends RefCounted

# Preload-based reference to the BrickDefinition Resource subclass — avoids
# class_name registry race during boot (see brick_registry.gd for rationale).
const BrickDefinition = preload("res://src/bricks/brick_definition.gd")

## Path to the directory containing recipe .tres files.
const RECIPE_DIR: String = "res://src/crafting/recipes/"

## Crafting-only items to register in BrickRegistry at boot (not in manifest.json).
const CRAFTING_ITEM_PATHS: Array[String] = [
	"res://src/bricks/stick.tres",
	# Materials + outputs for the art-crafting recipe cards (generated). Registered so the
	# new recipes' ingredients/outputs resolve in BrickRegistry.
	"res://src/bricks/gold_ingot.tres",
	"res://src/bricks/coal.tres",
	"res://src/bricks/leather.tres",
	"res://src/bricks/string.tres",
	"res://src/bricks/wheat.tres",
	"res://src/bricks/sugar_cane.tres",
	"res://src/bricks/obsidian.tres",
	"res://src/bricks/furnace.tres",
	"res://src/bricks/bucket.tres",
	"res://src/bricks/sugar.tres",
	"res://src/bricks/bread.tres",
	"res://src/bricks/campfire.tres",
	"res://src/bricks/coal_block.tres",
	"res://src/bricks/bow.tres",
	"res://src/bricks/flint_and_steel.tres",
	"res://src/bricks/chestplate_iron.tres",
	"res://src/bricks/chestplate_leather.tres",
	"res://src/bricks/helmet_diamond.tres",
	"res://src/bricks/helmet_gold.tres",
	"res://src/bricks/nether_portal.tres",
	# Tool items from the art-tools models (axe/hammer/fishing_rod/compass/map).
	"res://src/bricks/axe.tres",
	"res://src/bricks/hammer.tres",
	"res://src/bricks/fishing_rod.tres",
	"res://src/bricks/compass.tres",
	"res://src/bricks/map.tres",
]


# ─── Public API ───────────────────────────────────────────────────────────────

## Scan RECIPE_DIR for .tres files, load each as a Recipe resource, and return a
## {recipe_id: Resource} dictionary. Also registers crafting-only items with BrickRegistry.
##
## @param directory  Directory to scan (default: RECIPE_DIR).
## @return           {recipe_id: Resource} dictionary of successfully loaded recipes.
static func load_all(directory: String = RECIPE_DIR) -> Dictionary:
	# Register crafting-only items first so recipe output lookups resolve.
	register_crafting_items()

	var recipes: Dictionary = {}
	var dir: DirAccess = DirAccess.open(directory)
	if dir == null:
		push_error("RecipeRegistry.load_all: could not open directory '%s' (err %d)" % [
			directory, DirAccess.get_open_error()])
		return recipes

	dir.list_dir_begin()
	var fname: String = dir.get_next()
	while fname != "":
		if fname.ends_with(".tres"):
			var path: String = directory + fname
			var resource: Resource = ResourceLoader.load(path)
			if resource != null and resource.get("recipe_id") != null:
				# Duck-typed Recipe check: must have recipe_id (Recipe-specific field).
				var recipe_id: String = str(resource.get("recipe_id"))
				if recipe_id.is_empty():
					push_warning("RecipeRegistry.load_all: recipe at '%s' has empty recipe_id — skipped." % path)
				else:
					recipes[recipe_id] = resource
			elif resource != null:
				push_warning("RecipeRegistry.load_all: '%s' has no recipe_id — skipped." % path)
		fname = dir.get_next()
	dir.list_dir_end()

	return recipes


## Match a crafting grid against all recipes in the registry.
##
## @param grid      Array of slot dicts {def_id: String, count: int}, one per cell.
## @param shapeless true = check only shapeless recipes (position-independent);
##                  false = check only shaped recipes (position must match).
## @param registry  {recipe_id: Resource} dictionary from load_all().
## @return          First matching Recipe resource, or null if none match.
static func match_recipe_in_grid(grid: Array, shapeless: bool, registry: Dictionary) -> Resource:
	for recipe_id: String in registry:
		var recipe: Resource = registry[recipe_id]
		if recipe == null:
			continue
		# shaped=true means it's a shaped recipe (not shapeless).
		var recipe_shaped: bool = bool(recipe.get("shaped"))
		if recipe_shaped == shapeless:
			continue  # shaped=true: skip when shapeless=true; shaped=false: skip when shapeless=false
		if shapeless:
			if shapeless_match(grid, recipe):
				return recipe
		else:
			if shaped_match(grid, recipe):
				return recipe
	return null


## Register crafting-only items (e.g. stick) into BrickRegistry.
## These items are not in manifest.json (50-brick contract intact) but must resolve
## in BrickRegistry for recipe output validation (T-03-07a-CR-05).
static func register_crafting_items() -> void:
	# Access BrickRegistry autoload. Guard for test environments where it may not exist.
	var scene_tree: SceneTree = Engine.get_main_loop() as SceneTree
	if scene_tree == null:
		return

	var brick_registry: Node = scene_tree.root.get_node_or_null("/root/BrickRegistry")
	if brick_registry == null:
		return

	for path: String in CRAFTING_ITEM_PATHS:
		# Check if already registered (idempotent — survive multiple load_all() calls).
		var item_id: String = path.get_file().get_basename()  # e.g. "stick"
		if brick_registry.get_definition(item_id) != null:
			continue  # Already registered.
		var def: Resource = ResourceLoader.load(path)
		if def != null and def is BrickDefinition:
			brick_registry.register_pack([def])


## Check whether a shaped recipe matches the exact grid positions.
## Duck-typed: recipe is a Resource with {inputs, shaped, grid_size} fields.
## All inputs must have grid[slot].def_id == input.def_id AND count >= input.count.
static func shaped_match(grid: Array, recipe: Resource) -> bool:
	var inputs: Variant = recipe.get("inputs")
	if inputs == null or not inputs is Array or (inputs as Array).is_empty():
		return false
	var inp_arr: Array = inputs as Array
	# Verify grid covers all required slot indices with the right item + count.
	for inp: Dictionary in inp_arr:
		var slot: int = inp.get("slot", -1)
		if slot < 0 or slot >= grid.size():
			return false
		var cell: Dictionary = grid[slot]
		if cell.get("def_id", "") != inp.get("def_id", ""):
			return false
		if cell.get("count", 0) < inp.get("count", 1):
			return false
	# EXACT match: every OTHER grid cell must be empty. Without this, a grid filled for a
	# larger recipe (e.g. pickaxe: 5 cells) also satisfied a subset recipe (shovel: 3 cells)
	# and the first subset in registry order won — so tools crafted the wrong item / "failed".
	var required_slots: Dictionary = {}
	for inp: Dictionary in inp_arr:
		required_slots[int(inp.get("slot", -1))] = true
	for i: int in range(grid.size()):
		if required_slots.has(i):
			continue
		if not str((grid[i] as Dictionary).get("def_id", "")).is_empty():
			return false  # extra ingredient outside the recipe pattern → not this recipe
	return true


## Check whether a shapeless recipe matches the grid (ingredient presence, any slot).
## Duck-typed: recipe is a Resource with {inputs} field.
static func shapeless_match(grid: Array, recipe: Resource) -> bool:
	var inputs: Variant = recipe.get("inputs")
	if inputs == null or not inputs is Array or (inputs as Array).is_empty():
		return false
	var inp_arr: Array = inputs as Array

	# Count all def_ids in the grid.
	var grid_counts: Dictionary = {}
	for cell: Dictionary in grid:
		var did: String = cell.get("def_id", "")
		if not did.is_empty():
			grid_counts[did] = grid_counts.get(did, 0) + cell.get("count", 0)

	# Aggregate required counts per def_id.
	var required: Dictionary = {}
	for inp: Dictionary in inp_arr:
		var did: String = inp.get("def_id", "")
		required[did] = required.get(did, 0) + inp.get("count", 1)

	# All required ingredients must be present in sufficient quantity.
	for did: String in required:
		if grid_counts.get(did, 0) < required[did]:
			return false
	return true
