# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# test_inventory_grid.gd — Unit tests for Inventory grid shape and slot math.
#
# Anchors:
#   DOCS.md §4.1 — 6×8 inventory grid, 64/stack, hotbar = bottom 8 slots
#   03-PLAN.md 03-01 Task 2 — test_inventory_grid.gd scaffold
#   03-CONTEXT.md D-01 — inventory slide-in, hotbar at bottom row
#
# Plan 03-02 implements the Inventory autoload — tests are now active.
# Note: Engine.has_singleton() does not work for GDScript autoloads registered
# via project.godot; access the autoload directly by name instead.

extends GutTest

const Phase3Fixtures = preload("res://tests/conftest_phase3.gd")

var _world_id: String = ""
var _builder_id: String = "test_builder_grid_001"

func before_each() -> void:
	_world_id = Phase3Fixtures.open_temp_world("survival")
	# Reset builder state for each test.
	Inventory.detach_world()
	Inventory.attach_world()


func after_each() -> void:
	Phase3Fixtures.close_temp_world()
	Phase3Fixtures.cleanup_temp_world(_world_id)
	_world_id = ""


# ─── Test 1: 6×8 grid = 48 slots ──────────────────────────────────────────────

func test_grid_is_6x8_48_slots() -> void:
	# DOCS §4.1: inventory has 6 rows × 8 columns = 48 slots.
	var slots: Array = Inventory.get_slots(_builder_id)
	assert_eq(slots.size(), 48,
		"Inventory must have exactly 48 slots (6 rows × 8 columns per DOCS §4.1)")


# ─── Test 2: Stack max is 64 ──────────────────────────────────────────────────

func test_stack_max_is_64() -> void:
	# DOCS §4.1: maximum stack size per slot is 64.
	# Adding 100 of the same def_id should produce one stack of 64 and one of 36.
	Inventory.apply_event({"kind": "ADD", "builder_id": _builder_id, "def_id": "brick_1x1", "count": 100})
	var slots: Array = Inventory.get_slots(_builder_id)
	# Find all non-empty slots with brick_1x1.
	var brick_slots := slots.filter(func(s: Dictionary) -> bool:
		return s.get("def_id", "") == "brick_1x1" and s.get("count", 0) > 0)
	assert_true(brick_slots.size() >= 2, "100 items should fill at least 2 slots (64 + 36)")
	var max_stack: int = 0
	for s: Dictionary in brick_slots:
		max_stack = maxi(max_stack, s.get("count", 0))
	assert_eq(max_stack, 64, "No stack should exceed 64 per DOCS §4.1")


# ─── Test 3: Shift-split halves a stack ───────────────────────────────────────

func test_shift_split_halves() -> void:
	# DOCS §4.1: shift-split divides a stack in half (rounding down for the source, up for dest).
	# Stack of 10 → 5 + 5 (even split).
	# Place 10 items in slot 0.
	Inventory.apply_event({"kind": "ADD", "builder_id": _builder_id, "def_id": "brick_1x1", "count": 10, "slot": 0})
	# Shift-split slot 0 → slot 1.
	var ok: bool = Inventory.apply_event({
		"kind": "SPLIT",
		"builder_id": _builder_id,
		"from_slot": 0,
		"to_slot": 1,
	})
	assert_true(ok, "SPLIT event should succeed on a stack of 10")
	var slots: Array = Inventory.get_slots(_builder_id)
	var src: Dictionary = slots[0]
	var dst: Dictionary = slots[1]
	assert_eq(src.get("count", 0), 5, "Source slot should have 5 after shift-split of 10")
	assert_eq(dst.get("count", 0), 5, "Destination slot should have 5 after shift-split of 10")


# ─── Test 4: Single-take decrements by 1 ─────────────────────────────────────

func test_single_take_decrements_by_1() -> void:
	# DOCS §4.1: right-click on a stack takes exactly 1 item.
	Inventory.apply_event({"kind": "ADD", "builder_id": _builder_id, "def_id": "brick_1x1", "count": 10, "slot": 0})
	var ok: bool = Inventory.apply_event({
		"kind": "SINGLE_TAKE",
		"builder_id": _builder_id,
		"slot": 0,
	})
	assert_true(ok, "SINGLE_TAKE event should succeed on a stack of 10")
	var slots: Array = Inventory.get_slots(_builder_id)
	assert_eq(slots[0].get("count", 0), 9, "Stack should be 9 after single-take from 10")


# ─── Test 5: Hotbar is the bottom 8 slots ─────────────────────────────────────

func test_hotbar_is_bottom_8() -> void:
	# DOCS §4.1: hotbar = bottom row = row 5 (index 5 of 6 rows, 0-indexed) = slots 40-47.
	var hotbar_slots: Array = Inventory.get_hotbar_slots(_builder_id)
	assert_eq(hotbar_slots.size(), 8, "Hotbar must have 8 slots (bottom row of 6×8 grid)")
	# Hotbar slots should be indices 40-47 (row 5 × 8 columns = slots 40..47).
	for i: int in range(8):
		assert_eq(hotbar_slots[i], 40 + i,
			"Hotbar slot %d should be global slot index %d" % [i, 40 + i])
