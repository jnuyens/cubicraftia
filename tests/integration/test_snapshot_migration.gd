# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# test_snapshot_migration.gd — Integration tests for world snapshot schema migration.
#
# Snapshot contract (04-CONTEXT.md Area 4):
#   - WorldSave schema migrates from v2 → v3, adding a `snapshots` table
#   - Snapshot save + load roundtrip must preserve chunk state exactly
#   - Snapshot total size (inventory_blob + chunk_blob) must be < 2 MB (Q3 resolution)
#
# These are integration tests because they exercise the SQLite WorldSave
# autoload against a real database file.
#
# All tests implemented in Plan 04-10 (was previously Pending).
#
# Anchors:
#   04-CONTEXT.md Area 1 — snapshots every 30s for failover catch-up
#   04-CONTEXT.md Area 1 — old-host return: latest-snapshot-wins per chunk
#   04-01-PLAN.md Task 1 — wave-0-pending-pattern
#   04-10-PLAN.md Task 1 — snapshot full implementation + Q3 size budget

extends GutTest

const Phase4Fixtures = preload("res://tests/conftest_phase4.gd")

var _world_id: String = ""


func before_each() -> void:
	_world_id = Phase4Fixtures.open_temp_world("survival")


func after_each() -> void:
	if WorldSave.is_open():
		WorldSave.close_world()
	Phase4Fixtures.cleanup_temp_world(_world_id)
	_world_id = ""


# ─── Snapshot migration tests ──────────────────────────────────────────────────

func test_migrate_2_to_3_creates_snapshots_table() -> void:
	# The temp world is opened in before_each() which triggers open_world() → _create_schema()
	# → _migrate_schema(). Verify the snapshots table was created by querying sqlite_master.
	assert_true(WorldSave.is_open(), "World must be open before querying schema")
	# Use WorldSave's internal _db to query sqlite_master via the public snapshot API.
	# A successful save+load proves the table exists (save would fail on missing table).
	var save_ok: bool = WorldSave.save_world_snapshot("schema_check_snap")
	assert_true(save_ok, "save_world_snapshot must succeed — proves snapshots table exists")
	var snap: Dictionary = WorldSave.load_latest_snapshot()
	assert_false(snap.is_empty(), "load_latest_snapshot must return a non-empty dict after save")
	assert_eq(snap.get("snapshot_id", ""), "schema_check_snap",
		"Loaded snapshot_id must match the saved id")


func test_save_and_load_snapshot_roundtrip() -> void:
	assert_true(WorldSave.is_open(), "World must be open")
	# Save a snapshot with a known id.
	var save_ok: bool = WorldSave.save_world_snapshot("test_snap_001")
	assert_true(save_ok, "save_world_snapshot('test_snap_001') must return true")
	# Load it back and verify identity.
	var snap: Dictionary = WorldSave.load_latest_snapshot()
	assert_false(snap.is_empty(), "load_latest_snapshot must return a non-empty dict")
	assert_eq(snap.get("snapshot_id", ""), "test_snap_001",
		"Loaded snapshot_id must equal 'test_snap_001'")
	# inventory_blob must be non-empty because get_all_state() always returns a valid dict.
	var inv_blob: PackedByteArray = snap.get("inventory_blob", PackedByteArray())
	assert_gt(inv_blob.size(), 0, "inventory_blob must be non-empty after save_world_snapshot")
	# chunk_blob may be empty when _dirty_chunks is empty (no placed bricks yet) — that is valid.
	assert_true(snap.has("chunk_blob"), "Snapshot row must contain a chunk_blob key")


func test_snapshot_size_under_2mb() -> void:
	# Q3 resolution: a snapshot from a 4-player 30-minute session must fit within 2 MB
	# so it can be reliably transferred during host failover.
	#
	# WR-10: KNOWN LIMITATION — chunk_blob is always empty in this headless test
	# because WorldSave._stud_grid is null (no StudGrid node is attached in the
	# fixture). mark_chunk_dirty() queues coordinates but the serialiser skips the
	# stud-grid read when _stud_grid is null. As a result the 2 MB assertion only
	# validates the inventory_blob portion of the budget.
	#
	# TODO: Attach a stub StudGrid to WorldSave in conftest_phase4 so chunk_blob is
	# exercised. Track this as WR-10 tech debt until the stud-grid API stabilises.
	assert_true(WorldSave.is_open(), "World must be open")

	# Mark 200 synthetic chunk coordinates dirty to simulate a large session.
	# 200 chunks × 16^3 stud-grid cells is a realistic upper bound for 4 players × 30 min.
	for cx: int in range(10):
		for cz: int in range(20):
			WorldSave.mark_chunk_dirty(Vector3i(cx, 0, cz))

	# Save the snapshot (chunk_blob will be empty — see WR-10 note above).
	var save_ok: bool = WorldSave.save_world_snapshot("size_test")
	assert_true(save_ok, "save_world_snapshot must succeed for size test")

	var snap: Dictionary = WorldSave.load_latest_snapshot()
	assert_false(snap.is_empty(), "load_latest_snapshot must return a row for size_test")

	var inv_blob: PackedByteArray  = snap.get("inventory_blob", PackedByteArray())
	var chunk_blob: PackedByteArray = snap.get("chunk_blob", PackedByteArray())
	var total_bytes: int = inv_blob.size() + chunk_blob.size()
	var snapshot_size_kb: float = float(total_bytes) / 1024.0

	# A StudGrid is now attached in the fixture, so chunk_blob is populated (it was a
	# documented gap before). Assert it stays within the per-blob budget rather than the
	# old "== 0" expectation; the combined snapshot budget is asserted below.
	assert_lt(chunk_blob.size(), 2 * 1024 * 1024,
		"chunk_blob must stay under 2 MB (got %d B)" % chunk_blob.size())

	# Primary assertion: inventory_blob alone must be under 2 MB.
	# Full 2 MB budget (including chunk_blob) is verified in manual/scenario tests.
	assert_lt(snapshot_size_kb, 2048.0,
		"Snapshot inventory_blob must be under 2 MB (WR-10: chunk portion not exercised). " +
		"Got %.1f KB (inv=%d B, chunk=%d B)" % [snapshot_size_kb, inv_blob.size(), chunk_blob.size()])
