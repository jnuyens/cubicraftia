# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# test_recipe_book_reveal.gd — Unit tests for progressive recipe book reveal.
#
# Anchors:
#   03-CONTEXT.md D-05 — recipe reveals when all ingredients in inventory OR first-crafted
#   03-PLAN.md 03-01 Task 2 — test_recipe_book_reveal.gd scaffold
#   DOCS.md §4.5 — recipe book reveals progressively
#
# Plan 03-02 implements the Inventory autoload — tests are now active.
# Note: Engine.has_singleton() does not work for GDScript autoloads registered
# via project.godot; access the autoload directly by name instead.

extends GutTest

const Phase3Fixtures = preload("res://tests/conftest_phase3.gd")

var _world_id: String = ""
var _builder_id: String = "test_builder_recipes_001"

func before_each() -> void:
	_world_id = Phase3Fixtures.open_temp_world("survival")
	Inventory.detach_world()
	Inventory.attach_world()


func after_each() -> void:
	Phase3Fixtures.close_temp_world()
	Phase3Fixtures.cleanup_temp_world(_world_id)
	_world_id = ""


# ─── Test 1: Recipe revealed when all ingredients in inventory ────────────────

func test_recipe_revealed_when_all_ingredients_in_inventory() -> void:
	# D-05: A recipe is permanently unlocked once crafted (CRAFT event).
	# Until Plan 03-07a wires the recipe registry, ingredient-presence reveal is not active.
	# Test that a CRAFT event reveals the recipe.
	var revealed_before: Array = Inventory.get_revealed_recipes(_builder_id)
	assert_false(revealed_before.has("recipe_wooden_plank"),
		"Planks recipe should not be revealed before any craft")
	# Simulate crafting the planks recipe (RECIPE_UNLOCK for first craft).
	Inventory.apply_event({
		"kind": "RECIPE_UNLOCK",
		"builder_id": _builder_id,
		"recipe_id": "recipe_wooden_plank",
	})
	var revealed_after: Array = Inventory.get_revealed_recipes(_builder_id)
	assert_true(revealed_after.has("recipe_wooden_plank"),
		"Planks recipe should be revealed after RECIPE_UNLOCK event (first-craft per D-05)")


# ─── Test 2: Recipe unlocked on first craft persists ─────────────────────────

func test_recipe_unlocked_on_first_craft_persists() -> void:
	# D-05: crafting a recipe once permanently unlocks it; removing ingredients doesn't hide it.
	Phase3Fixtures.populate_inventory(_builder_id, [
		{"def_id": "wood_plank", "count": 3},
		{"def_id": "stick", "count": 2},
	])
	# Real craft flow: fill the 3×3 grid from inventory, then take the output. A bare
	# CRAFT with no grid no longer reveals (free crafting was a bug — see test_craft_consume).
	var filled: bool = Inventory.apply_event({
		"kind": "CRAFT_AUTOFILL", "builder_id": _builder_id,
		"recipe_id": "recipe_pickaxe_wood", "target_grid": "crafting_3x3",
	})
	assert_true(filled, "autofill should succeed with 3 planks + 2 sticks in inventory")
	Inventory.apply_event({
		"kind": "CRAFT", "builder_id": _builder_id,
		"recipe_id": "recipe_pickaxe_wood", "grid_size": 3,
	})
	# Now remove all inventory items to simulate an empty inventory.
	for slot_idx: int in range(48):
		Inventory.apply_event({
			"kind": "REMOVE",
			"builder_id": _builder_id,
			"slot": slot_idx,
			"count": 99,
		})
	# Pickaxe recipe should still be revealed (first-craft unlock is permanent per D-05).
	var revealed: Array = Inventory.get_revealed_recipes(_builder_id)
	assert_true(revealed.has("recipe_pickaxe_wood"),
		"Pickaxe recipe must remain revealed after emptying inventory (first-craft permanent unlock per D-05)")


# ─── Test 3: Revealed state persists across save+close+reopen ────────────────

func test_revealed_state_persists_across_save_close_reopen() -> void:
	# recipes_known blob must survive close+reopen (in-memory state persists
	# across WorldSave.close_world/open_world without full detach_world/attach_world).
	# Craft planks to unlock the planks recipe (real flow: log → fill grid → craft).
	Inventory.apply_event({"kind": "ADD", "builder_id": _builder_id, "def_id": "wood_log", "count": 1})
	Inventory.apply_event({
		"kind": "CRAFT_AUTOFILL", "builder_id": _builder_id,
		"recipe_id": "recipe_wooden_plank", "target_grid": "crafting_2x2",
	})
	Inventory.apply_event({
		"kind": "CRAFT", "builder_id": _builder_id,
		"recipe_id": "recipe_wooden_plank", "grid_size": 2,
	})
	var revealed_before: Array = Inventory.get_revealed_recipes(_builder_id)
	assert_true(revealed_before.has("recipe_wooden_plank"),
		"Planks recipe should be revealed after crafting")
	# Flush to disk and reopen.
	Inventory._flush_persistence()
	var wid := _world_id
	Phase3Fixtures.close_temp_world()
	var ok := WorldSave.open_world(wid, 42, "survival")
	assert_true(ok, "World should reopen successfully")
	Inventory.attach_world()
	# The planks recipe should still be in the revealed set.
	var revealed_after: Array = Inventory.get_revealed_recipes(_builder_id)
	assert_true(revealed_after.has("recipe_wooden_plank"),
		"Planks recipe must remain revealed after close+reopen (recipes_known blob persisted per D-05)")
