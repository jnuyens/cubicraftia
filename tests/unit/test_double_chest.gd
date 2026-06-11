# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# test_double_chest.gd — Unit tests for double-chest combine and split-on-break.
#
# Anchors:
#   DOCS.md §4.4 — double chests: same-tier adjacent chests combine; break splits proportionally
#   03-PLAN.md 03-01 Task 2 — test_double_chest.gd scaffold
#   03-CONTEXT.md D-02 — double chest combines as single composite container
#
# Plan 03-02 implements the Inventory autoload — tests are now active.

extends GutTest

const Phase3Fixtures = preload("res://tests/conftest_phase3.gd")

var _world_id: String = ""
var _builder_id: String = "test_builder_double_001"

func before_each() -> void:
	_world_id = Phase3Fixtures.open_temp_world("survival")
	Inventory.detach_world()
	Inventory.attach_world()


func after_each() -> void:
	Phase3Fixtures.close_temp_world()
	Phase3Fixtures.cleanup_temp_world(_world_id)
	_world_id = ""


# ─── Test 1: Two adjacent same-tier chests combine into double ────────────────

func test_two_adjacent_same_tier_combine_to_double() -> void:
	# DOCS §4.4: placing two regular chests side-by-side → they become a double chest.
	# double_chest_partner of pos_a == pos_b; combined slot count == 96 (2 × 48).
	var pos_a := Vector3i(0, 0, 0)
	var pos_b := Vector3i(1, 0, 0)  # Adjacent on X axis.
	# Register two regular chests.
	Inventory.register_chest(pos_a, "regular")
	Inventory.register_chest(pos_b, "regular")
	# Placing second chest adjacent should trigger double-chest combine.
	Inventory.try_combine_double_chest(pos_a, pos_b)
	var state_a: Dictionary = Inventory.get_chest_state(pos_a)
	assert_eq(state_a.get("double_chest_partner", ""), str(pos_b),
		"Chest at pos_a should have pos_b as double_chest_partner after combining")
	var combined_slots: int = Inventory.get_double_chest_slot_count(pos_a)
	assert_eq(combined_slots, 96,
		"Double regular chest should have 96 slots (2 × 48 per DOCS §4.4)")


# ─── Test 2: Breaking double chest splits contents proportionally ─────────────

func test_break_double_splits_contents_proportionally() -> void:
	# DOCS §4.4: breaking one half of a double chest splits contents proportionally.
	# 90 items in 96-slot double → break one half → each single has some items, total = 90.
	var pos_a := Vector3i(2, 0, 0)
	var pos_b := Vector3i(3, 0, 0)
	Inventory.register_chest(pos_a, "regular")
	Inventory.register_chest(pos_b, "regular")
	Inventory.try_combine_double_chest(pos_a, pos_b)
	# Add 90 items to the double chest.
	for _i: int in range(90):
		Inventory.apply_event({
			"kind": "ADD",
			"chest_coord": pos_a,
			"def_id": "brick_1x1",
			"count": 1,
		})
	# Break one half → split should distribute items to each single chest.
	Inventory.break_double_chest(pos_a)
	var total_a: int = 0
	var total_b: int = 0
	var slots_a: Array = Inventory.get_chest_contents(pos_a)
	var slots_b: Array = Inventory.get_chest_contents(pos_b)
	for s: Dictionary in slots_a:
		total_a += s.get("count", 0)
	for s: Dictionary in slots_b:
		total_b += s.get("count", 0)
	assert_eq(total_a + total_b, 90, "Total items must be preserved after split (90)")
	assert_true(total_a > 0 and total_b > 0,
		"Each half must receive a proportional share of the 90 items")


# ─── Test 3: Double chest only combines same-tier ─────────────────────────────

func test_double_chest_only_combines_same_tier() -> void:
	# DOCS §4.4: only same-tier adjacent chests can combine into a double chest.
	# Regular adjacent to bronze must NOT combine.
	var pos_a := Vector3i(4, 0, 0)
	var pos_b := Vector3i(5, 0, 0)
	Inventory.register_chest(pos_a, "regular")
	Inventory.register_chest(pos_b, "bronze")
	# Attempt to combine regular with bronze — should return false.
	var combined: bool = Inventory.try_combine_double_chest(pos_a, pos_b)
	assert_false(combined,
		"Regular and bronze chests must NOT combine into a double chest (different tiers)")
	var state_a: Dictionary = Inventory.get_chest_state(pos_a)
	assert_true(state_a.get("double_chest_partner", "").is_empty(),
		"Regular chest should have no partner after failed combine with different tier")
