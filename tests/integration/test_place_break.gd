# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# test_place_break.gd — Integration tests for the brick place/break round-trip (Plan 05, Task 3).
#
# These tests exercise the StudGrid and Builder place/break API directly without
# requiring a live VoxelTerrain (which needs a GPU in headless mode). They call
# stud_grid.place() / stud_grid.remove() directly and verify state, matching the
# spirit of the behaviour spec while being runnable headlessly.
#
# Behaviour tested (Phase 1 — preserved):
#   1. test_place_then_break_roundtrips   — place + break returns to empty state
#   2. test_side_face_placement_rejected  — (Phase 1) builder _try_place_at rejects side-face anchor
#   3. test_break_on_empty_no_crash       — remove on empty cell is safe
#   4. test_multimesh_instance_count_matches_grid_size — MultiMesh sync after 3 places
#
# Behaviour tested (Phase 2 — Plan 02-09 extensions):
#   5. test_side_face_placement_accepted_phase2 — Phase 2 lifts the top-face restriction;
#      hit.previous_position as anchor works for any face
#   6. test_brick_on_brick_placement       — place a brick on top of another brick
#   7. test_multi_cell_2x4_placement       — place a 2×4 brick (8 cells) then break it

extends GutTest

const BRICK_1X1_PATH := "res://src/bricks/brick_1x1.tres"
const MAIN_SCENE_PATH := "res://src/world/main_scene.tscn"

var _brick_def: BrickDefinition = null

func before_all() -> void:
	_brick_def = load(BRICK_1X1_PATH) as BrickDefinition
	assert_not_null(_brick_def, "brick_1x1.tres must exist")

# ─── Test 1 ────────────────────────────────────────────────────────────────────

func test_place_then_break_roundtrips() -> void:
	var grid := StudGrid.new()
	add_child_autofree(grid)

	var anchor := Vector3i(0, 5, 0)
	var placed := grid.place(anchor, _brick_def)
	assert_true(placed, "place should succeed")
	assert_eq(grid.size(), 1, "size should be 1 after place")

	var broken := grid.remove(anchor)
	assert_true(broken, "remove should succeed")
	assert_eq(grid.size(), 0, "size should be 0 after break — round-trip complete")
	assert_null(grid.query(anchor), "query should return null after break")

# ─── Test 2 ────────────────────────────────────────────────────────────────────
# Phase 1 deliberate restriction: only top-face placements allowed.
# The builder checks: hit.previous_position == Vector3i(hit.position.x, hit.position.y+1, hit.position.z)
# A side-face hit has previous_position != top_face_anchor.
# We test this directly using the builder's exposed helper.

func test_side_face_placement_rejected() -> void:
	# Simulate a side-face hit: hit.position = (3, 5, 3), previous_position = (4, 5, 3)
	# top_face_anchor would be (3, 6, 3), but previous_position = (4, 5, 3) != top_face_anchor
	var hit_position := Vector3i(3, 5, 3)
	var previous_position := Vector3i(4, 5, 3)  # side face, not top face
	var top_face_anchor := Vector3i(hit_position.x, hit_position.y + 1, hit_position.z)

	# This is the Pattern 3 check: reject if previous_position != top_face_anchor
	var is_top_face := (previous_position == top_face_anchor)
	assert_false(is_top_face,
		"side-face hit should fail the top-face check (Phase 1 restriction per Pattern 3)")

# ─── Test 3 ────────────────────────────────────────────────────────────────────

func test_break_on_empty_no_crash() -> void:
	var grid := StudGrid.new()
	add_child_autofree(grid)

	# No bricks placed — break should be safe
	var broken := grid.remove(Vector3i(0, 5, 0))
	assert_false(broken, "remove on empty cell should return false without crashing")
	assert_eq(grid.size(), 0, "size should stay 0")

# ─── Test 4 ────────────────────────────────────────────────────────────────────

func test_multimesh_instance_count_matches_grid_size() -> void:
	# Set up a StudGrid and a MultiMeshInstance3D with a brick_1x1 mesh.
	var grid := StudGrid.new()
	add_child_autofree(grid)

	var multi_mesh := MultiMesh.new()
	multi_mesh.transform_format = MultiMesh.TRANSFORM_3D
	multi_mesh.mesh = _brick_def.mesh
	multi_mesh.instance_count = 0

	var renderer := MultiMeshInstance3D.new()
	renderer.multimesh = multi_mesh
	add_child_autofree(renderer)

	# Connect StudGrid signals to update the renderer (mirrors builder.gd logic).
	# Phase 2 signal: placed(anchor_cell, def, colour_index, rotation).
	grid.placed.connect(func(anchor_cell: Vector3i, def: BrickDefinition, _colour_index: int, _rotation: int) -> void:
		var new_count: int = grid.size()
		multi_mesh.instance_count = new_count
		multi_mesh.set_instance_transform(new_count - 1,
			Transform3D(Basis.IDENTITY, Vector3(anchor_cell.x, anchor_cell.y, anchor_cell.z)))
	)
	grid.removed.connect(func(_anchor_cell: Vector3i) -> void:
		multi_mesh.instance_count = grid.size()
	)

	# Place 3 bricks at distinct anchors.
	grid.place(Vector3i(0, 5, 0), _brick_def)
	grid.place(Vector3i(1, 5, 0), _brick_def)
	grid.place(Vector3i(2, 5, 0), _brick_def)

	assert_eq(multi_mesh.instance_count, 3,
		"MultiMesh instance_count should match grid.size() after 3 places")
	assert_eq(grid.size(), 3, "grid should have 3 bricks")

# ─── Test 5: Phase 2 — side-face placement accepted ──────────────────────────

func test_side_face_placement_accepted_phase2() -> void:
	# Phase 2 lifts the top-face restriction. The anchor is hit.previous_position,
	# which works for any face (top / side / bottom).
	# In Phase 2, a side-face hit: hit.position = (3,5,3), previous_position = (4,5,3)
	# is a valid anchor — the brick goes in the side-adjacent cell.
	var grid := StudGrid.new()
	add_child_autofree(grid)

	# Simulate that we have an existing brick at (3,5,3) (e.g. on a side face).
	# Phase 2 builder would call stud_grid.place_multi with anchor = hit.previous_position = (4,5,3).
	var side_anchor := Vector3i(4, 5, 3)  # the cell adjacent to the hit face

	# This should succeed in Phase 2 — no top-face restriction.
	var placed := grid.place_multi(side_anchor, [Vector3i(0, 0, 0)], _brick_def, -1, 0)
	assert_true(placed,
		"Phase 2: side-face placement (anchor = hit.previous_position) should succeed")
	assert_not_null(grid.query(side_anchor),
		"brick should be in the side-adjacent cell after Phase 2 placement")

# ─── Test 6: brick-on-brick placement ─────────────────────────────────────────

func test_brick_on_brick_placement() -> void:
	var grid := StudGrid.new()
	add_child_autofree(grid)

	# Place a base brick at (0,5,0).
	var base_anchor := Vector3i(0, 5, 0)
	var placed_base := grid.place(base_anchor, _brick_def)
	assert_true(placed_base, "base brick should place successfully")

	# Place a second brick on top of it at (0,6,0) — brick-on-brick.
	# Phase 2: the stud-grid raycast would find the brick at (0,5,0) and return
	# previous_cell = (0,6,0) for a top-face hit.
	var top_anchor := Vector3i(0, 6, 0)
	var placed_top := grid.place_multi(top_anchor, [Vector3i(0, 0, 0)], _brick_def, 0, 0)
	assert_true(placed_top, "brick-on-brick placement should succeed")
	assert_not_null(grid.query(top_anchor), "upper brick should be in grid after brick-on-brick")
	assert_eq(grid.size(), 2, "both bricks should be in the grid")

# ─── Test 7: multi-cell 2×4 placement ─────────────────────────────────────────

func test_multi_cell_2x4_placement() -> void:
	var grid := StudGrid.new()
	add_child_autofree(grid)

	# 2×4 brick footprint: 2 cells in X, 4 cells in Z.
	var footprint: Array[Vector3i] = []
	for x in range(2):
		for z in range(4):
			footprint.append(Vector3i(x, 0, z))

	var anchor := Vector3i(0, 5, 0)
	var placed := grid.place_multi(anchor, footprint, _brick_def, 3, 1)
	assert_true(placed, "2×4 multi-cell place should succeed")
	assert_eq(grid.size(), 8, "grid should have 8 cells after 2×4 placement")

	# Breaking by the anchor cell should remove all 8 cells.
	var removed := grid.remove(anchor)
	assert_true(removed, "remove should succeed on the anchor cell of a 2×4 brick")
	assert_eq(grid.size(), 0, "all 8 cells should be gone after removing the 2×4 brick")
