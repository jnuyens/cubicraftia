# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# test_stud_grid.gd — Unit tests for StudGrid sparse stud-grid data structure.
#
# Tests (Phase 1 — preserved):
#   1. test_empty_grid            — fresh grid has size==0, query returns null
#   2. test_place_increments_size — place makes size==1, query returns correct BrickInstance
#   3. test_remove_returns_to_empty — place then remove returns to size==0
#   4. test_double_place_returns_false — placing twice at same anchor returns false
#   5. test_remove_missing_returns_false — removing from empty cell returns false
#
# Tests (Phase 2 — Plan 02-09 extensions):
#   6. test_place_multi_2x4_succeeds          — 8-cell footprint all placed
#   7. test_place_multi_collision_rejected     — one cell occupied; entire place rejected
#   8. test_chunk_boundary_footprint          — footprint straddles two chunks; both dirty
#   9. test_remove_bulk_removes_multiple       — remove_bulk erases multiple cells
#  10. test_cells_in_sphere_returns_nearby    — cells_in_sphere correct
#  11. test_dirty_chunks_tracked_and_cleared  — dirty chunks populated then cleared
#  12. test_place_multi_same_instance_in_all_cells — same BrickInstance ref in every cell
#  13. test_remove_multi_cell_erases_all_cells — removing one cell of multi-cell removes all

extends GutTest

const BRICK_1X1_PATH := "res://src/bricks/brick_1x1.tres"

var _grid: StudGrid = null
var _brick_def: BrickDefinition = null

func before_each() -> void:
	_grid = StudGrid.new()
	add_child_autofree(_grid)
	# Load the 1x1 brick definition for tests that need a BrickDefinition.
	_brick_def = load(BRICK_1X1_PATH) as BrickDefinition
	assert_not_null(_brick_def, "brick_1x1.tres should load")

# ─── Test 1 ────────────────────────────────────────────────────────────────────

func test_empty_grid() -> void:
	assert_eq(_grid.size(), 0, "fresh grid should have size 0")
	assert_null(_grid.query(Vector3i(0, 0, 0)),
		"fresh grid query should return null")

# ─── Test 2 ────────────────────────────────────────────────────────────────────

func test_place_increments_size() -> void:
	var anchor := Vector3i(0, 5, 0)
	var ok := _grid.place(anchor, _brick_def)
	assert_true(ok, "place should return true on an empty cell")
	assert_eq(_grid.size(), 1, "size should be 1 after one place")
	var instance = _grid.query(anchor)
	assert_not_null(instance, "query should return a BrickInstance after place")
	assert_eq(instance.definition, _brick_def,
		"BrickInstance.definition should match the placed BrickDefinition")

# ─── Test 3 ────────────────────────────────────────────────────────────────────

func test_remove_returns_to_empty() -> void:
	var anchor := Vector3i(0, 5, 0)
	_grid.place(anchor, _brick_def)
	var removed := _grid.remove(anchor)
	assert_true(removed, "remove should return true when a brick was present")
	assert_eq(_grid.size(), 0, "size should be 0 after remove")
	assert_null(_grid.query(anchor), "query should return null after remove")

# ─── Test 4 ────────────────────────────────────────────────────────────────────

func test_double_place_returns_false() -> void:
	var anchor := Vector3i(3, 2, 1)
	var first := _grid.place(anchor, _brick_def)
	var second := _grid.place(anchor, _brick_def)
	assert_true(first, "first place should succeed")
	assert_false(second, "second place at same anchor should return false (Phase 1 no-stack)")
	assert_eq(_grid.size(), 1, "size should remain 1 after double place")

# ─── Test 5 ────────────────────────────────────────────────────────────────────

func test_remove_missing_returns_false() -> void:
	var empty_anchor := Vector3i(99, 99, 99)
	var removed := _grid.remove(empty_anchor)
	assert_false(removed, "remove on empty cell should return false without error")
	assert_eq(_grid.size(), 0, "size should stay 0")

# ─── Test 6: place_multi 2×4 footprint ─────────────────────────────────────────

func test_place_multi_2x4_succeeds() -> void:
	# A 2×4 brick in xz occupies 8 cells: x in [0,1], z in [0,3].
	var footprint: Array[Vector3i] = []
	for x in range(2):
		for z in range(4):
			footprint.append(Vector3i(x, 0, z))

	var anchor := Vector3i(0, 5, 0)
	var ok := _grid.place_multi(anchor, footprint, _brick_def, 0, 0)
	assert_true(ok, "place_multi of 2×4 footprint should succeed on empty grid")
	assert_eq(_grid.size(), 8, "grid should have 8 entries after 2×4 placement")

	# Every footprint cell should be occupied.
	for x in range(2):
		for z in range(4):
			var cell := anchor + Vector3i(x, 0, z)
			assert_not_null(_grid.query(cell),
				"cell (%d,%d,%d) should be occupied after place_multi" % [cell.x, cell.y, cell.z])

# ─── Test 7: place_multi collision rejection ──────────────────────────────────

func test_place_multi_collision_rejected() -> void:
	# Place a 1×1 brick at (1, 5, 0) — one cell of the footprint.
	_grid.place(Vector3i(1, 5, 0), _brick_def)

	# Try to place a 2×4 whose footprint includes (1, 0, 0) → anchor+(1,0,0).
	var footprint: Array[Vector3i] = []
	for x in range(2):
		for z in range(4):
			footprint.append(Vector3i(x, 0, z))

	var anchor := Vector3i(0, 5, 0)
	var ok := _grid.place_multi(anchor, footprint, _brick_def, 0, 0)
	assert_false(ok, "place_multi should be rejected when one footprint cell is occupied")
	# The original single brick at (1,5,0) should still be there.
	assert_not_null(_grid.query(Vector3i(1, 5, 0)), "original brick should remain after failed place_multi")
	# No new cells should have been added — still only 1 entry.
	assert_eq(_grid.size(), 1, "size should remain 1 after rejected place_multi")

# ─── Test 8: chunk boundary footprint ─────────────────────────────────────────

func test_chunk_boundary_footprint() -> void:
	# Place a 2-cell brick straddling the chunk boundary at x=16.
	# Cell (15, 0, 0) → chunk (0, 0, 0). Cell (16, 0, 0) → chunk (1, 0, 0).
	var anchor := Vector3i(15, 0, 0)
	var footprint: Array[Vector3i] = [Vector3i(0, 0, 0), Vector3i(1, 0, 0)]
	_grid.place_multi(anchor, footprint, _brick_def, -1, 0)

	var dirty := _grid.get_dirty_chunks()
	# Both chunk (0,0,0) and chunk (1,0,0) must be marked dirty.
	assert_true(dirty.has(Vector3i(0, 0, 0)),
		"chunk (0,0,0) should be dirty after straddling placement")
	assert_true(dirty.has(Vector3i(1, 0, 0)),
		"chunk (1,0,0) should be dirty after straddling placement")
	assert_eq(dirty.size(), 2, "exactly 2 chunks should be dirty")

# ─── Test 9: remove_bulk ──────────────────────────────────────────────────────

func test_remove_bulk_removes_multiple() -> void:
	var a1 := Vector3i(0, 5, 0)
	var a2 := Vector3i(1, 5, 0)
	var a3 := Vector3i(2, 5, 0)
	_grid.place(a1, _brick_def)
	_grid.place(a2, _brick_def)
	_grid.place(a3, _brick_def)
	assert_eq(_grid.size(), 3, "should have 3 bricks before bulk remove")

	# Use GUT's signal watcher rather than a captured local bool: GDScript lambdas capture
	# locals BY VALUE, so `signal_received = true` inside the handler wrote to the lambda's
	# own copy and never propagated out — the assert failed even though remove_bulk DID emit.
	watch_signals(_grid)

	_grid.remove_bulk([a1, a3])
	assert_eq(_grid.size(), 1, "should have 1 brick after removing 2 via remove_bulk")
	assert_null(_grid.query(a1), "a1 should be gone after remove_bulk")
	assert_not_null(_grid.query(a2), "a2 should still be present")
	assert_null(_grid.query(a3), "a3 should be gone after remove_bulk")
	assert_signal_emitted(_grid, "removed_bulk", "removed_bulk signal should have been emitted")

# ─── Test 10: cells_in_sphere ─────────────────────────────────────────────────

func test_cells_in_sphere_returns_nearby() -> void:
	# Place bricks at (0,0,0), (1,0,0), (5,0,0).
	_grid.place(Vector3i(0, 0, 0), _brick_def)
	_grid.place(Vector3i(1, 0, 0), _brick_def)
	_grid.place(Vector3i(5, 0, 0), _brick_def)

	# Sphere at centre (0.5, 0.5, 0.5), radius 2 — should capture (0,0,0) and (1,0,0).
	var centre := Vector3(0.5, 0.5, 0.5)
	var in_sphere: Array = _grid.cells_in_sphere(centre, 2.0)

	assert_true(in_sphere.has(Vector3i(0, 0, 0)),
		"cell (0,0,0) should be within radius 2 from centre (0.5,0.5,0.5)")
	assert_true(in_sphere.has(Vector3i(1, 0, 0)),
		"cell (1,0,0) should be within radius 2 from centre (0.5,0.5,0.5)")
	assert_false(in_sphere.has(Vector3i(5, 0, 0)),
		"cell (5,0,0) should NOT be within radius 2 from centre (0.5,0.5,0.5)")
	assert_eq(in_sphere.size(), 2, "exactly 2 cells should be within sphere")

# ─── Test 11: dirty chunks tracked and cleared ────────────────────────────────

func test_dirty_chunks_tracked_and_cleared() -> void:
	_grid.place(Vector3i(0, 0, 0), _brick_def)
	var dirty := _grid.get_dirty_chunks()
	assert_false(dirty.is_empty(), "dirty_chunks should be non-empty after place")

	_grid.clear_dirty_chunks()
	dirty = _grid.get_dirty_chunks()
	assert_true(dirty.is_empty(), "dirty_chunks should be empty after clear_dirty_chunks")

# ─── Test 12: same BrickInstance reference in all cells ───────────────────────

func test_place_multi_same_instance_in_all_cells() -> void:
	var footprint: Array[Vector3i] = [
		Vector3i(0, 0, 0), Vector3i(1, 0, 0), Vector3i(0, 0, 1), Vector3i(1, 0, 1)
	]
	var anchor := Vector3i(0, 5, 0)
	_grid.place_multi(anchor, footprint, _brick_def, 5, 2)

	# All cells must return the exact same BrickInstance object.
	var inst_00 = _grid.query(anchor + Vector3i(0, 0, 0))
	var inst_10 = _grid.query(anchor + Vector3i(1, 0, 0))
	var inst_01 = _grid.query(anchor + Vector3i(0, 0, 1))
	var inst_11 = _grid.query(anchor + Vector3i(1, 0, 1))

	assert_not_null(inst_00, "cell (0,0,0) must be occupied")
	assert_eq(inst_00, inst_10, "cells (0,0,0) and (1,0,0) must share same BrickInstance")
	assert_eq(inst_00, inst_01, "cells (0,0,0) and (0,0,1) must share same BrickInstance")
	assert_eq(inst_00, inst_11, "cells (0,0,0) and (1,0,1) must share same BrickInstance")
	# Verify stored colour and rotation.
	assert_eq(inst_00.colour_index, 5, "colour_index should be 5 as placed")
	assert_eq(inst_00.rotation, 2, "rotation should be 2 as placed")

# ─── Test 13: removing one cell of multi-cell brick removes all cells ──────────

func test_remove_multi_cell_erases_all_cells() -> void:
	var footprint: Array[Vector3i] = [
		Vector3i(0, 0, 0), Vector3i(1, 0, 0), Vector3i(2, 0, 0)
	]
	var anchor := Vector3i(10, 5, 10)
	_grid.place_multi(anchor, footprint, _brick_def, -1, 0)
	assert_eq(_grid.size(), 3, "3 cells should be occupied after place_multi")

	# Remove via the second cell — should erase the whole brick.
	_grid.remove(anchor + Vector3i(1, 0, 0))
	assert_eq(_grid.size(), 0, "all 3 cells should be removed when removing any cell of multi-cell brick")
	assert_null(_grid.query(anchor + Vector3i(0, 0, 0)), "first cell should be null after remove")
	assert_null(_grid.query(anchor + Vector3i(1, 0, 0)), "second cell should be null after remove")
	assert_null(_grid.query(anchor + Vector3i(2, 0, 0)), "third cell should be null after remove")
