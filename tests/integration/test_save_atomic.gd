# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# test_save_atomic.gd — Integration tests for atomic save (mid-write crash safety).
#
# Anchors:
#   DOCS.md §3 — save atomicity: mid-write crash → no torn state
#   02-RESEARCH.md §"Save Format Atomicity" — write-to-temp + atomic rename pattern
#   02-PATTERNS.md §"Persistence (net-new)"
#
# Owned by Plan 03 (save format implementation turns these GREEN).
#
# Key invariant (CRIT-3 from 02-RESEARCH.md): saving writes to a .tmp file then
# atomically renames it — interrupting the save never yields a half-written world file.

extends GutTest

const TEST_WORLD_ATOMIC   := "test_atomic_rename"
const TEST_WORLD_NOTORN   := "test_atomic_notorn"
const BRICK_PATH          := "res://src/bricks/brick_1x1.tres"

var _brick_def: BrickDefinition = null

func before_all() -> void:
	_brick_def = load(BRICK_PATH) as BrickDefinition
	assert_not_null(_brick_def, "brick_1x1.tres must load")

func before_each() -> void:
	_cleanup_world(TEST_WORLD_ATOMIC)
	_cleanup_world(TEST_WORLD_NOTORN)

func after_each() -> void:
	_cleanup_world(TEST_WORLD_ATOMIC)
	_cleanup_world(TEST_WORLD_NOTORN)

# ─── Test 1 ────────────────────────────────────────────────────────────────────

## Simulate a crash mid-rename: create a canonical file, then manually create a
## .atomic file (as if checkpoint had just renamed .tmp → .atomic but not yet
## promoted .atomic → canonical). Delete canonical. Then call load_canonical_or_bak:
## it must detect .atomic, promote it to canonical, and return the canonical path.
func test_crash_mid_rename() -> void:
	var world_dir_godot := "user://worlds/%s" % TEST_WORLD_ATOMIC
	var world_dir_abs   := ProjectSettings.globalize_path(world_dir_godot)

	# Create the world directory.
	DirAccess.make_dir_recursive_absolute(world_dir_abs)

	var meta_path   := world_dir_abs + "/world.meta.sqlite"
	var atomic_path := meta_path + ".atomic"

	# Write a valid "world file" into the .atomic path (simulates a successful
	# copy → tmp → atomic rename, but the promotion step was interrupted).
	var content := "ATOMIC_CONTENT_MARKER".to_utf8_buffer()
	var f_atomic := FileAccess.open(atomic_path, FileAccess.WRITE)
	assert_not_null(f_atomic, "must be able to create .atomic file")
	f_atomic.store_buffer(content)
	f_atomic.flush()
	f_atomic.close()

	# Canonical does NOT exist (simulates crash before promotion).
	assert_false(FileAccess.file_exists(meta_path), "canonical must NOT exist before recovery")
	assert_true(FileAccess.file_exists(atomic_path), ".atomic must exist")

	# Call load_canonical_or_bak: should detect .atomic, promote to canonical, return canonical.
	var chosen := WorldSaveIo.load_canonical_or_bak(meta_path)

	assert_eq(chosen, meta_path, "load_canonical_or_bak must return canonical path after .atomic promotion")
	assert_true(FileAccess.file_exists(meta_path), "canonical must exist after .atomic promotion")
	assert_false(FileAccess.file_exists(atomic_path), ".atomic must be gone after promotion")

	# Confirm the canonical contains the content we put in .atomic.
	var f_check := FileAccess.open(meta_path, FileAccess.READ)
	assert_not_null(f_check, "canonical must be readable after promotion")
	var recovered := f_check.get_buffer(content.size())
	f_check.close()
	assert_eq(recovered, content, "canonical content must match original .atomic content")


# ─── Test 2 ────────────────────────────────────────────────────────────────────

## Verify that atomic_write_sqlite produces a .atomic file and the original
## canonical is unchanged (i.e. no torn-file state: at any step the canonical
## is either the fully-old version or the fully-new version).
func test_atomic_rename_never_yields_torn_file() -> void:
	var world_dir_abs := ProjectSettings.globalize_path("user://worlds/%s" % TEST_WORLD_NOTORN)
	DirAccess.make_dir_recursive_absolute(world_dir_abs)

	var meta_path   := world_dir_abs + "/world.meta.sqlite"
	var atomic_path := meta_path + ".atomic"
	var tmp_path    := meta_path + ".tmp"

	# Write a "canonical" file with known content (simulates a prior checkpoint).
	var old_content := "OLD_CANONICAL_DATA_V1".to_utf8_buffer()
	var f_old := FileAccess.open(meta_path, FileAccess.WRITE)
	assert_not_null(f_old, "must be able to create canonical")
	f_old.store_buffer(old_content)
	f_old.flush()
	f_old.close()

	assert_true(FileAccess.file_exists(meta_path), "canonical must exist before atomic write")
	assert_false(FileAccess.file_exists(tmp_path), ".tmp must not exist before")
	assert_false(FileAccess.file_exists(atomic_path), ".atomic must not exist before")

	# Perform atomic_write_sqlite.
	var ok := WorldSaveIo.atomic_write_sqlite(meta_path)
	assert_true(ok, "atomic_write_sqlite should succeed")

	# After atomic_write_sqlite:
	#   .tmp must be gone (renamed to .atomic)
	#   .atomic must exist (the new version awaiting promotion)
	#   canonical must still exist unchanged (old version — promotion happens on load)
	assert_false(FileAccess.file_exists(tmp_path), ".tmp must not exist after atomic_write_sqlite")
	assert_true(FileAccess.file_exists(atomic_path), ".atomic must exist after atomic_write_sqlite")
	assert_true(FileAccess.file_exists(meta_path), "canonical must still exist (not yet promoted)")

	# Canonical must still contain the old content (not a torn file).
	var f_canon := FileAccess.open(meta_path, FileAccess.READ)
	assert_not_null(f_canon, "canonical must be readable")
	var canon_content := f_canon.get_buffer(old_content.size())
	f_canon.close()
	assert_eq(canon_content, old_content, "canonical must still have old content before promotion — no torn file")

	# .atomic must contain the same content (it's a copy of canonical in this test).
	var f_atomic_check := FileAccess.open(atomic_path, FileAccess.READ)
	assert_not_null(f_atomic_check, ".atomic must be readable")
	var atomic_content := f_atomic_check.get_buffer(old_content.size())
	f_atomic_check.close()
	assert_eq(atomic_content, old_content, ".atomic content must match the copied canonical")

	# Now promote by calling load_canonical_or_bak.
	var chosen := WorldSaveIo.load_canonical_or_bak(meta_path)
	assert_eq(chosen, meta_path, "load_canonical_or_bak must return canonical after promotion")
	assert_false(FileAccess.file_exists(atomic_path), ".atomic must be gone after promotion")
	assert_true(FileAccess.file_exists(meta_path), "canonical must exist after promotion")


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
