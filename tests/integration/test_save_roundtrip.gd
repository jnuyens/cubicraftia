# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# test_save_roundtrip.gd — Integration tests for world save round-trip byte-equality.
#
# Anchors:
#   DOCS.md §3 — save / load world state
#   02-RESEARCH.md §"Save Format Atomicity", §"Spec contradiction: LZ4"
#   02-PATTERNS.md §"Persistence (net-new)"
#
# Owned by Plan 03 (save format implementation turns these GREEN).
#
# Headless note: save/load tests do not require a GPU. No headless guard needed.

extends GutTest

const BRICK_PATH := "res://src/bricks/brick_1x1.tres"
const TEST_WORLD_ID_1 := "test_roundtrip_100"
const TEST_WORLD_ID_2 := "test_roundtrip_delta"

var _brick_def: BrickDefinition = null

func before_all() -> void:
	_brick_def = load(BRICK_PATH) as BrickDefinition
	assert_not_null(_brick_def, "brick_1x1.tres must load")

func before_each() -> void:
	# Clean up any leftover world directories from prior test runs.
	_cleanup_world(TEST_WORLD_ID_1)
	_cleanup_world(TEST_WORLD_ID_2)

func after_each() -> void:
	_cleanup_world(TEST_WORLD_ID_1)
	_cleanup_world(TEST_WORLD_ID_2)

# ─── Test 1 ────────────────────────────────────────────────────────────────────

## Place 100 bricks across multiple chunks, save, reload, assert all 100 are present.
func test_100_brick_roundtrip() -> void:
	# --- Phase A: save -------------------------------------------------------
	var ws1: Node = preload("res://src/autoload/world_save.gd").new()
	add_child_autofree(ws1)
	var sg1 := StudGrid.new()
	add_child_autofree(sg1)

	var ok: bool = ws1.open_world(TEST_WORLD_ID_1, 9999, "sandbox")
	assert_true(ok, "open_world should succeed")
	ws1.attach_stud_grid(sg1)

	# Place 100 bricks at distinct anchor cells spanning multiple chunks.
	var anchors_saved: Array = []
	for i in range(100):
		var cell := Vector3i(i * 2, 0, 0)   # stride 2 to keep cells distinct
		var placed := sg1.place(cell, _brick_def)
		assert_true(placed, "place %d should succeed" % i)
		anchors_saved.append(cell)

	var cp_ok: bool = ws1.checkpoint()
	assert_true(cp_ok, "checkpoint should succeed")
	ws1.close_world()

	# --- Phase B: reload -----------------------------------------------------
	var ws2: Node = preload("res://src/autoload/world_save.gd").new()
	add_child_autofree(ws2)
	var sg2 := StudGrid.new()
	add_child_autofree(sg2)

	var ok2: bool = ws2.open_world(TEST_WORLD_ID_1, 9999, "sandbox")
	assert_true(ok2, "second open_world should succeed")

	# Load all saved chunks into the grid.
	var brick_defs := { "brick_1x1": _brick_def }
	var saved_chunks: Array = ws2.get_saved_chunk_coords()
	assert_true(saved_chunks.size() > 0, "at least one chunk should be saved")
	for chunk_coord: Vector3i in saved_chunks:
		ws2.load_chunk_into_grid(chunk_coord, sg2, brick_defs)

	ws2.close_world()

	# All 100 anchor cells must be present in the reloaded grid.
	assert_eq(sg2.size(), 100, "reloaded grid must contain 100 bricks")
	for cell: Vector3i in anchors_saved:
		var instance := sg2.query(cell)
		assert_not_null(instance, "brick at %s must be present after reload" % str(cell))


# ─── Test 2 ────────────────────────────────────────────────────────────────────

## Place 10 bricks across exactly 2 chunks; checkpoint must create exactly 2 rows
## in stud_grid_chunks (not 10) — TECH-4 mitigation: per-chunk delta, not per-brick.
func test_per_chunk_delta_only_modified() -> void:
	var ws: Node = preload("res://src/autoload/world_save.gd").new()
	add_child_autofree(ws)
	var sg := StudGrid.new()
	add_child_autofree(sg)

	var ok: bool = ws.open_world(TEST_WORLD_ID_2, 1234, "sandbox")
	assert_true(ok, "open_world should succeed")
	ws.attach_stud_grid(sg)

	# CHUNK_SIZE = 16; place 5 bricks in chunk (0,0,0) and 5 in chunk (1,0,0).
	var chunk_size: int = 16
	for i in range(5):
		sg.place(Vector3i(i, 0, 0), _brick_def)             # chunk (0,0,0)
	for i in range(5):
		sg.place(Vector3i(chunk_size + i, 0, 0), _brick_def)  # chunk (1,0,0)

	var cp_ok: bool = ws.checkpoint()
	assert_true(cp_ok, "checkpoint should succeed")

	# Exactly 2 rows must be in stud_grid_chunks (one per chunk, not one per brick).
	var saved_chunks: Array = ws.get_saved_chunk_coords()
	assert_eq(saved_chunks.size(), 2, "only 2 chunk rows must be saved — not 10 individual-brick rows")

	ws.close_world()
	_cleanup_world(TEST_WORLD_ID_2)

# ─── Helpers ─────────────────────────────────────────────────────────────────

func _cleanup_world(world_id: String) -> void:
	var world_dir := ProjectSettings.globalize_path("user://worlds/%s" % world_id)
	if DirAccess.dir_exists_absolute(world_dir):
		_rm_dir_recursive(world_dir)


func _rm_dir_recursive(path: String) -> void:
	var da := DirAccess.open(path)
	if da == null:
		return
	da.list_dir_begin()
	var name := da.get_next()
	while name != "":
		var full := path + "/" + name
		if da.current_is_dir():
			_rm_dir_recursive(full)
		else:
			DirAccess.remove_absolute(full)
		name = da.get_next()
	da.list_dir_end()
	DirAccess.remove_absolute(path)
