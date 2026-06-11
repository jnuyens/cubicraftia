# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# test_save_corruption.gd — Integration tests for save corruption recovery (bak.1 rollback).
#
# Anchors:
#   DOCS.md §3 — save atomicity; crash resilience
#   02-RESEARCH.md §"Save Format Atomicity"
#   02-PATTERNS.md §"Persistence (net-new)"
#
# Owned by Plan 03 (save format implementation turns these GREEN).
#
# Key invariant: if the canonical world file is corrupted (checksum mismatch),
# the save system transparently falls back to the bak.1 file and never exposes
# a torn state to the player.

extends GutTest

const BRICK_PATH := "res://src/bricks/brick_1x1.tres"
const TEST_WORLD_CORRUPTION := "test_corruption_fallback"
const TEST_WORLD_CHECKSUM   := "test_corruption_checksum"

var _brick_def: BrickDefinition = null

func before_all() -> void:
	_brick_def = load(BRICK_PATH) as BrickDefinition
	assert_not_null(_brick_def, "brick_1x1.tres must load")

func before_each() -> void:
	_cleanup_world(TEST_WORLD_CORRUPTION)
	_cleanup_world(TEST_WORLD_CHECKSUM)

func after_each() -> void:
	_cleanup_world(TEST_WORLD_CORRUPTION)
	_cleanup_world(TEST_WORLD_CHECKSUM)

# ─── Test 1 ────────────────────────────────────────────────────────────────────

## Place 10 bricks → checkpoint (canonical = 10 bricks; bak.1 = copy of canonical = 10 bricks).
## Corrupt the canonical file.
## Reload: WorldSave must fall back to bak.1 (10 bricks).
##
## Backup rotation mechanics (for reference):
##   After ONE checkpoint:
##     canonical = 10 bricks
##     bak.1     = 10 bricks (rotate_backups: bak.1 ← copy of canonical)
##     bak.2, bak.3 don't exist
func test_corrupted_canonical_falls_back_to_bak_1() -> void:
	var brick_defs := { "brick_1x1": _brick_def }

	# --- Create a world with 10 bricks and ONE checkpoint --------------------
	var ws1: Node = preload("res://src/autoload/world_save.gd").new()
	add_child_autofree(ws1)
	var sg1 := StudGrid.new()
	add_child_autofree(sg1)

	var ok1: bool = ws1.open_world(TEST_WORLD_CORRUPTION, 42, "sandbox")
	assert_true(ok1, "first open_world should succeed")
	ws1.attach_stud_grid(sg1)

	for i in range(10):
		sg1.place(Vector3i(i, 0, 0), _brick_def)

	# One checkpoint: canonical gets 10 bricks; rotate_backups makes bak.1 = copy of canonical.
	var cp1: bool = ws1.checkpoint()
	assert_true(cp1, "checkpoint 1 should succeed")
	ws1.close_world()

	# After close_world (which calls checkpoint again with no dirty chunks + closes DB):
	#   canonical = 10 bricks
	#   bak.1 = copy of 10-brick canonical (from the checkpoint inside close_world)

	# --- Verify bak.1 exists and has healthy content -------------------------
	var meta_path := ProjectSettings.globalize_path(
		"user://worlds/%s/world.meta.sqlite" % TEST_WORLD_CORRUPTION)
	var bak1_path := meta_path + ".bak.1"
	assert_true(FileAccess.file_exists(meta_path), "canonical must exist")
	assert_true(FileAccess.file_exists(bak1_path), "bak.1 must exist after checkpoint")

	# --- Corrupt the canonical SQLite file -----------------------------------
	# Overwrite canonical with garbage so it is no longer a valid SQLite file.
	var corrupt_file := FileAccess.open(meta_path, FileAccess.WRITE)
	assert_not_null(corrupt_file, "must be able to open canonical for corruption")
	corrupt_file.store_string("CORRUPTED GARBAGE DATA — THIS IS NOT A VALID SQLITE FILE")
	corrupt_file.flush()
	corrupt_file.close()

	# --- Reload: open_world must fall back to bak.1 --------------------------
	# WorldSave.open_world tries canonical first; it fails to open_db (corrupted SQLite).
	# It then tries bak.1, which succeeds. It copies bak.1 to canonical and opens it.
	var ws2: Node = preload("res://src/autoload/world_save.gd").new()
	add_child_autofree(ws2)
	var sg2 := StudGrid.new()
	add_child_autofree(sg2)

	var ok2: bool = ws2.open_world(TEST_WORLD_CORRUPTION, 42, "sandbox")
	assert_true(ok2, "open_world must succeed by falling back to bak.1")

	var saved_chunks: Array = ws2.get_saved_chunk_coords()
	for chunk_coord: Vector3i in saved_chunks:
		ws2.load_chunk_into_grid(chunk_coord, sg2, brick_defs)

	ws2.close_world()

	# bak.1 had 10 bricks (same as the one checkpoint we did).
	assert_eq(sg2.size(), 10, "recovered world from bak.1 must contain 10 bricks")


# ─── Test 2 ────────────────────────────────────────────────────────────────────

## Verify that ChunkCodec.verify_checksum detects tampered blob bytes.
func test_checksum_mismatch_detected() -> void:
	# Encode a payload.
	var original := PackedByteArray()
	original.append_array("hello chunk delta".to_utf8_buffer())
	var blob := ChunkCodec.encode_chunk_delta(original)
	assert_false(blob.is_empty(), "encode_chunk_delta should return non-empty blob")

	# Verify checksum on the untampered blob.
	assert_true(ChunkCodec.verify_checksum(blob), "checksum must pass for valid blob")

	# Tamper with a byte in the compressed payload section (after the 20-byte header).
	var tampered := blob.duplicate()
	if tampered.size() > 20:
		tampered[20] = tampered[20] ^ 0xFF   # flip all bits in byte 20
	else:
		tampered[blob.size() - 1] = tampered[blob.size() - 1] ^ 0xFF

	assert_false(ChunkCodec.verify_checksum(tampered), "checksum must fail for tampered blob")

	# decode_chunk_delta must return empty on tampered input.
	var decoded := ChunkCodec.decode_chunk_delta(tampered)
	assert_true(decoded.is_empty(), "decode_chunk_delta must return empty on tampered blob")


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
