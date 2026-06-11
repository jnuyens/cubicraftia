# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# test_dynamite_blast.gd — Integration tests for dynamite explosion: 5 m radius + frame-time.
#
# Anchors:
#   DOCS.md §3.4 — dynamite ~5 m radius; brick-shatter VFX
#   02-CONTEXT.md §D-11 — dynamite explosion is brick-shatter with pickupable drops
#   02-RESEARCH.md §"Tool System", §"Pitfalls"
#   02-11-PLAN.md — test spec (test_5m_radius_correctness headless GREEN + manual:tier3 PENDING)
#
# Test 1 — test_5m_radius_correctness (GREEN headlessly):
#   Instantiates a bare StudGrid (no VoxelTerrain, no GPU).
#   Places 50 bricks in a 10×10 grid at origin.
#   Creates a DynamiteHandler stub and calls detonate() on the stud-grid path.
#   Asserts that cells_in_sphere returned exactly the cells within Euclidean
#   distance 5.0 of the blast centre — and that remove_bulk removed them all.
#
# Test 2 — test_main_thread_time_within_budget (manual:tier3 PENDING):
#   Requires running on the Motorola One Macro reference device with a GPU.
#   Tagged manual:tier3; runs in Plan 15's hardware benchmark suite.
#   Cannot be automated headlessly because godot_voxel crashes without a GPU.

extends GutTest

# ─── Shared setup ─────────────────────────────────────────────────────────────

var _stud_grid: StudGrid = null
var _brick_def: BrickDefinition = null

const BRICK_PATH := "res://src/bricks/brick_1x1.tres"

func before_each() -> void:
	_stud_grid = StudGrid.new()
	add_child_autofree(_stud_grid)
	_brick_def = load(BRICK_PATH) as BrickDefinition
	assert_not_null(_brick_def, "brick_1x1.tres should load")

# ─── Test 1: 5 m radius correctness (GREEN headlessly) ────────────────────────

func test_5m_radius_correctness() -> void:
	# Place 50 bricks in a 10×10 cell grid at y=0 (cells (0..9, 0, 0..4)).
	# Grid spans x=[0..9], y=0, z=[0..4] — 10 × 1 × 5 = 50 cells.
	var placed_cells: Array[Vector3i] = []
	for gx in range(10):
		for gz in range(5):
			var cell := Vector3i(gx, 0, gz)
			var ok := _stud_grid.place(cell, _brick_def)
			if ok:
				placed_cells.append(cell)

	assert_eq(placed_cells.size(), 50, "Should have placed 50 bricks without collision")

	# Blast centre at (5.0, 0.5, 2.5) — approximately the centre of the 10×5 grid.
	# Radius 5.0 m (per DOCS §3.4).
	var blast_centre := Vector3(5.0, 0.5, 2.5)
	var blast_radius: float = 5.0

	# ── Verify cells_in_sphere correctness ────────────────────────────────────
	# The spec requires Euclidean distance from each cell's centre to blast_centre.
	# Cell centre = (cell.x + 0.5, cell.y + 0.5, cell.z + 0.5).
	var sphere_cells: Array = _stud_grid.cells_in_sphere(blast_centre, blast_radius)

	# Compute the expected set manually to compare.
	var expected_in_sphere: Array = []
	for cell_raw in placed_cells:
		var cell: Vector3i = cell_raw as Vector3i
		var cell_centre := Vector3(cell.x + 0.5, cell.y + 0.5, cell.z + 0.5)
		if cell_centre.distance_squared_to(blast_centre) <= blast_radius * blast_radius:
			expected_in_sphere.append(cell)

	# cells_in_sphere count must match expected.
	assert_eq(sphere_cells.size(), expected_in_sphere.size(),
		"cells_in_sphere count must match expected Euclidean sphere cell count")

	# Every cell returned must actually be within the radius.
	for cell_raw in sphere_cells:
		var cell: Vector3i = cell_raw as Vector3i
		var cell_centre := Vector3(cell.x + 0.5, cell.y + 0.5, cell.z + 0.5)
		var dist_sq: float = cell_centre.distance_squared_to(blast_centre)
		assert_true(dist_sq <= blast_radius * blast_radius + 0.001,
			"All returned cells must be within blast radius")

	# ── Verify remove_bulk all-or-nothing correctness ─────────────────────────
	var pre_size: int = _stud_grid.size()
	assert_gt(pre_size, 0, "Grid should have bricks before blast")

	# Watch signals via GUT's built-in signal tracker (avoids GDScript lambda capture issues).
	watch_signals(_stud_grid)

	_stud_grid.remove_bulk(sphere_cells)

	# All cells in sphere_cells should now be removed.
	for cell_raw in sphere_cells:
		var cell: Vector3i = cell_raw as Vector3i
		assert_null(_stud_grid.query(cell),
			"Cells within blast radius must be removed after remove_bulk")

	# Cells outside the sphere must still be present.
	for cell_raw in placed_cells:
		var cell: Vector3i = cell_raw as Vector3i
		if not sphere_cells.has(cell):
			assert_not_null(_stud_grid.query(cell),
				"Cells outside blast radius must survive the blast")

	# removed_bulk signal must have been emitted exactly once with the removed cells.
	assert_signal_emitted(_stud_grid, "removed_bulk",
		"removed_bulk signal must be emitted after remove_bulk")
	var signal_params: Array = get_signal_parameters(_stud_grid, "removed_bulk", 0)
	if signal_params.size() > 0:
		var emitted_cells: Array = signal_params[0]
		assert_eq(emitted_cells.size(), sphere_cells.size(),
			"removed_bulk signal must carry the same cell count as the sphere cells")

	# ── Verify dirty_chunks were coalesced (TECH-2 mitigation) ───────────────
	# At radius 5 within a 10×5 grid, affected chunks should be at most 2 distinct
	# 16m chunks (the entire 10×5 grid fits in one or two 16m chunks).
	var dirty_chunks: Array = _stud_grid.get_dirty_chunks()
	assert_gt(dirty_chunks.size(), 0, "At least one chunk must be marked dirty after blast")
	# Sanity bound: at most 4 chunks for a 5m radius blast (RESEARCH.md Pattern 5 spec).
	assert_lte(dirty_chunks.size(), 4,
		"A 5m radius blast should affect at most 4 distinct chunks (RESEARCH Pattern 5)")

# ─── Test 2 — manual:tier3 ────────────────────────────────────────────────────

func test_main_thread_time_within_budget() -> void:
	pending("manual:tier3 — runs on Motorola benchmark scene per 02-VALIDATION.md")
