# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# test_craft_consume.gd — Regression tests for the CRAFT event consuming the crafting
# grid buffer and producing output. Guards the wood_log → wood_plank inline-2×2 craft
# that was silently broken (CRAFT read a nonexistent `ingredients` Dict, ignored the
# grid, produced nothing useful, and left the grid stuck).
#
# Flow under test (matches the inline 2×2 UX):
#   ADD wood_log → CRAFT_AUTOFILL (consumes from inventory, fills grid) →
#   CRAFT (consumes grid, adds output to inventory).

extends GutTest

var _world_id: String = ""
const _BUILDER: String = "test_builder_craft_001"


func before_each() -> void:
	_world_id = Phase3Fixtures.open_temp_world("survival")
	Inventory.detach_world()
	Inventory.attach_world()


func after_each() -> void:
	Phase3Fixtures.close_temp_world()
	Phase3Fixtures.cleanup_temp_world(_world_id)
	_world_id = ""


func _count(def_id: String) -> int:
	var total: int = 0
	for s: Dictionary in Inventory.get_slots(_BUILDER):
		if s.get("def_id", "") == def_id:
			total += int(s.get("count", 0))
	return total


# ── wood_log → 4 wood_plank via autofill + craft ──────────────────────────────

func test_plank_craft_consumes_grid_and_produces_output() -> void:
	Inventory.apply_event({"kind": "ADD", "builder_id": _BUILDER, "def_id": "wood_log", "count": 1})
	assert_eq(_count("wood_log"), 1, "precondition: 1 wood_log in inventory")

	# Recipe-book "Fill grid" path: consumes the log from inventory into the 2×2 buffer.
	var filled: bool = Inventory.apply_event({
		"kind": "CRAFT_AUTOFILL", "builder_id": _BUILDER,
		"recipe_id": "recipe_wooden_plank", "target_grid": "crafting_2x2",
	})
	assert_true(filled, "CRAFT_AUTOFILL should succeed with a log in inventory")
	assert_eq(_count("wood_log"), 0, "autofill removes the log from the main inventory")

	var grid_log: int = 0
	for cell: Dictionary in Inventory.get_crafting_grid("crafting_2x2"):
		if cell.get("def_id", "") == "wood_log":
			grid_log += int(cell.get("count", 0))
	assert_eq(grid_log, 1, "the log now sits in the 2×2 grid buffer")

	# Take the output: CRAFT consumes the grid and adds 4 planks.
	var crafted: bool = Inventory.apply_event({
		"kind": "CRAFT", "builder_id": _BUILDER,
		"recipe_id": "recipe_wooden_plank", "grid_size": 2,
	})
	assert_true(crafted, "CRAFT should succeed when the grid matches the recipe")
	assert_eq(_count("wood_plank"), 4, "craft yields 4 wood_plank (output_count)")

	var remaining_log: int = 0
	for cell: Dictionary in Inventory.get_crafting_grid("crafting_2x2"):
		if cell.get("def_id", "") == "wood_log":
			remaining_log += int(cell.get("count", 0))
	assert_eq(remaining_log, 0, "the grid buffer is drained after crafting")


# ── No free crafting: empty grid must not produce output ──────────────────────

func test_craft_with_empty_grid_fails() -> void:
	var crafted: bool = Inventory.apply_event({
		"kind": "CRAFT", "builder_id": _BUILDER,
		"recipe_id": "recipe_wooden_plank", "grid_size": 2,
	})
	assert_false(crafted, "CRAFT must fail when the grid has no ingredients")
	assert_eq(_count("wood_plank"), 0, "no planks produced from an empty grid")
