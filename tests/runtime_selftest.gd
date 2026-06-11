extends Node

# Runtime selftest — boots the project normally so Inventory + WorldSave
# autoloads exist as globals, then exercises the crafting + chest routing
# fixes and prints pass/fail to stdout. Quits when done.

func _ready() -> void:
	print("\n========= CRAFTING SELFTEST =========\n")
	var pass_count: int = 0
	var fail_count: int = 0

	# Open a temp world so WorldSave.is_open() is true (needed for chest tests).
	if WorldSave.has_method("open_world"):
		WorldSave.open_world("selftest_world", 1234, "survival")

	# ─── Test 1: stick recipe is shapeless ────────────────────────────────
	var stick: Resource = load("res://src/crafting/recipes/recipe_stick.tres")
	if stick.get("shaped") == false:
		print("Test 1 PASS  stick recipe is shapeless (shaped=false)")
		pass_count += 1
	else:
		print("Test 1 FAIL  stick recipe is still shaped=true")
		fail_count += 1

	# ─── Test 2: 8 planks lumped in slot 0 → stick recipe matches ─────────
	var grid_lump: Array = [
		{"def_id": "wood_plank", "count": 8},
		{"def_id": "", "count": 0},
		{"def_id": "", "count": 0},
		{"def_id": "", "count": 0},
	]
	var recipe: Resource = Inventory.match_recipe(grid_lump, true)
	if recipe != null and recipe.get("output_def_id") == "stick" and recipe.get("output_count") == 4:
		print("Test 2 PASS  8-plank lump → stick × 4")
		pass_count += 1
	else:
		print("Test 2 FAIL  8-plank lump did not match: %s" % str(recipe))
		fail_count += 1

	# ─── Test 3: 1+1 planks distributed → also matches ────────────────────
	var grid_split: Array = [
		{"def_id": "wood_plank", "count": 1},
		{"def_id": "", "count": 0},
		{"def_id": "wood_plank", "count": 1},
		{"def_id": "", "count": 0},
	]
	var recipe_split: Resource = Inventory.match_recipe(grid_split, true)
	if recipe_split != null:
		print("Test 3 PASS  1+1 distributed → stick × 4")
		pass_count += 1
	else:
		print("Test 3 FAIL  distributed planks did not match")
		fail_count += 1

	# ─── Test 4: only 1 plank → no match ──────────────────────────────────
	var grid_short: Array = [
		{"def_id": "wood_plank", "count": 1},
		{"def_id": "", "count": 0},
		{"def_id": "", "count": 0},
		{"def_id": "", "count": 0},
	]
	var recipe_short: Resource = Inventory.match_recipe(grid_short, true)
	if recipe_short == null:
		print("Test 4 PASS  1 plank correctly does not match")
		pass_count += 1
	else:
		print("Test 4 FAIL  1 plank false-positive matched")
		fail_count += 1

	# ─── Test 5: SINGLE_TAKE inventory → crafting ─────────────────────────
	var bid: String = "selftest_builder"
	Inventory._ensure_inventory(bid)
	var inv_arr: Array = Inventory._inventories[bid]
	inv_arr[0]["def_id"] = "wood_plank"
	inv_arr[0]["count"] = 8
	var ok: bool = Inventory.apply_event({
		"kind": "SINGLE_TAKE",
		"builder_id": bid,
		"from": 0,
		"from_grid": "inventory",
		"single_take": true,
	})
	var crafting: Array = Inventory.get_crafting_grid("crafting_2x2")
	var t5_pass: bool = ok and inv_arr[0]["count"] == 7 and crafting[0]["def_id"] == "wood_plank" and crafting[0]["count"] == 1
	if t5_pass:
		print("Test 5 PASS  SINGLE_TAKE inv→craft: inv 8→7, craft 0→1")
		pass_count += 1
	else:
		print("Test 5 FAIL  ok=%s inv[0]=%s craft[0]=%s" % [ok, inv_arr[0], crafting[0]])
		fail_count += 1

	# ─── Test 6: SINGLE_TAKE again → merges in crafting[0] ────────────────
	Inventory.apply_event({
		"kind": "SINGLE_TAKE",
		"builder_id": bid,
		"from": 0,
		"from_grid": "inventory",
		"single_take": true,
	})
	var crafting2: Array = Inventory.get_crafting_grid("crafting_2x2")
	var t6_pass: bool = inv_arr[0]["count"] == 6 and crafting2[0]["count"] == 2
	if t6_pass:
		print("Test 6 PASS  SINGLE_TAKE merges: inv 7→6, craft 1→2")
		pass_count += 1
	else:
		print("Test 6 FAIL  inv[0]=%s craft[0]=%s" % [inv_arr[0], crafting2[0]])
		fail_count += 1

	# ─── Test 6b: live crafting buffer matches stick recipe ───────────────
	var live_recipe: Resource = Inventory.match_recipe(crafting2, true)
	if live_recipe != null and live_recipe.get("output_def_id") == "stick":
		print("Test 6b PASS live buffer (2 planks) → stick × 4 preview")
		pass_count += 1
	else:
		print("Test 6b FAIL live buffer didn't match")
		fail_count += 1

	# ─── Test 7: cross-grid MOVE chest → inventory ────────────────────────
	var chunk: Vector3i = Vector3i(0, 0, 0)
	Inventory.register_chest(chunk, "regular", false, [
		{"def_id": "pickaxe", "count": 1},
		{"def_id": "wood_plank", "count": 8},
	], true)
	inv_arr[10] = {"def_id": "", "count": 0}
	var move_ok: bool = Inventory.apply_event({
		"kind": "MOVE",
		"builder_id": bid,
		"from_slot": 0,
		"to_slot": 10,
		"from_grid": "chest",
		"to_grid": "inventory",
		"from_chest_id": "0_0_0",
	})
	if move_ok and inv_arr[10]["def_id"] == "pickaxe":
		print("Test 7 PASS  drag chest[0] pickaxe → inv[10]")
		pass_count += 1
	else:
		print("Test 7 FAIL  ok=%s inv[10]=%s" % [move_ok, inv_arr[10]])
		fail_count += 1

	# ─── Test 8: chest_id format with 'chest_' prefix also works ──────────
	inv_arr[11] = {"def_id": "", "count": 0}
	var move_ok2: bool = Inventory.apply_event({
		"kind": "MOVE",
		"builder_id": bid,
		"from_slot": 1,
		"to_slot": 11,
		"from_grid": "chest",
		"to_grid": "inventory",
		"from_chest_id": "chest_0_0_0",  # prefixed form
	})
	if move_ok2 and inv_arr[11]["def_id"] == "wood_plank":
		print("Test 8 PASS  'chest_x_y_z' prefix form also resolves")
		pass_count += 1
	else:
		print("Test 8 FAIL  ok=%s inv[11]=%s" % [move_ok2, inv_arr[11]])
		fail_count += 1

	print("")
	print("========= %d/%d passed, %d failed =========" % [pass_count, pass_count + fail_count, fail_count])
	print("")
	get_tree().quit(fail_count)
