# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# conftest_phase3.gd — Shared GUT fixtures for the Phase 3 survival-loop test suite.
#
# NOT extends GutTest — this is a helper class used by test files via preload().
# NOT registered as an autoload (test-only code per T-03-01-SC).
#
# Usage in test files:
#   const Phase3Fixtures = preload("res://tests/conftest_phase3.gd")
#   Phase3Fixtures.open_temp_world()
#
# Provides:
#   - open_temp_world(mode)     — open a fresh temp world, return the world_id
#   - close_temp_world()        — close the currently-open world (no-op if none)
#   - populate_inventory(...)   — convenience over Inventory.apply_event ADD
#   - fake_survival_mode(value) — set WorldSave mode metadata for mode-gate tests
#
# Anchors:
#   03-PLAN.md 03-01 Task 2 — conftest_phase3 fixture spec
#   03-CONTEXT.md D-01 — sandbox vs survival mode split
#   03-PATTERNS.md — WorldSave EXTEND analog lifecycle pattern
#   03-PLAN.md must_haves artifacts — class_name Phase3Fixtures extends RefCounted

class_name Phase3Fixtures
extends RefCounted


# ─── Open / close helpers ──────────────────────────────────────────────────────

## Open a temporary world for test use.
##
## Creates a world in user://worlds/<uuid>/ with the given mode, calls
## WorldSave.open_world(), and returns the world_id string so the caller
## can close it later if needed.
##
## @param mode  "survival" or "sandbox" (default: "survival").
## @return      world_id string, or "" if open_world() failed.
static func open_temp_world(mode: String = "survival") -> String:
	if WorldSave.is_open():
		push_warning("Phase3Fixtures.open_temp_world: a world is already open — closing it first.")
		WorldSave.close_world()

	# Generate a pseudo-unique world_id using time + random to avoid collisions.
	var wid := "phase3_test_%d_%d" % [Time.get_ticks_msec(), randi()]
	var ok := WorldSave.open_world(wid, 42, mode)
	if not ok:
		push_error("Phase3Fixtures.open_temp_world: WorldSave.open_world('%s', 42, '%s') failed." % [wid, mode])
		return ""
	return wid


## Close the currently-open world.
##
## Safe to call even if no world is open (no-op in that case).
static func close_temp_world() -> void:
	if WorldSave.is_open():
		WorldSave.close_world()


## Clean up a temp world directory created by open_temp_world.
##
## Deletes the world.meta.sqlite file and world directory.
## Call this in after_each() to keep the filesystem tidy.
##
## @param world_id  The world_id returned by open_temp_world().
static func cleanup_temp_world(world_id: String) -> void:
	if world_id.is_empty():
		return
	var world_dir := "user://worlds/%s" % world_id
	var abs_path := ProjectSettings.globalize_path(world_dir)
	# Remove all files in the world directory, then the directory itself.
	var meta_path := abs_path + "/world.meta.sqlite"
	if FileAccess.file_exists(meta_path):
		DirAccess.remove_absolute(meta_path)
	# Remove bak files if any.
	for bak_n: int in [1, 2, 3]:
		var bak := meta_path + ".bak.%d" % bak_n
		if FileAccess.file_exists(bak):
			DirAccess.remove_absolute(bak)
	if DirAccess.dir_exists_absolute(abs_path):
		DirAccess.remove_absolute(abs_path)


# ─── Inventory helper ─────────────────────────────────────────────────────────

## Convenience wrapper over Inventory.apply_event ADD.
##
## Adds items to a builder's inventory via the Inventory autoload (Plan 03-02+).
## Note: Engine.has_singleton() does not work for GDScript autoloads registered
## via project.godot. Access the Inventory autoload directly by name.
##
## @param builder_id  The builder's stable UUID.
## @param slots       Array of Dictionaries: [{def_id: String, count: int}, ...]
static func populate_inventory(builder_id: String, slots: Array) -> void:
	for slot: Dictionary in slots:
		var def_id: String = slot.get("def_id", "")
		var count: int = slot.get("count", 1)
		if def_id.is_empty():
			push_warning("Phase3Fixtures.populate_inventory: slot missing def_id — skipping.")
			continue
		Inventory.apply_event({
			"kind": "ADD",
			"builder_id": builder_id,
			"def_id": def_id,
			"count": count,
		})


# ─── Mode gate helper ──────────────────────────────────────────────────────────

## Set the world mode so Features.is_survival_mode() returns the test value.
##
## Uses WorldSave.set_world_meta("mode", ...) which is the canonical mode storage
## per STATE.md `survival-mode-world-property` and Features.is_survival_mode().
##
## Requires a world to be open (call open_temp_world() first).
## No-op with push_warning if no world is open.
##
## @param value  true → "survival" mode; false → "sandbox" mode.
static func fake_survival_mode(value: bool) -> void:
	if not WorldSave.is_open():
		push_warning("Phase3Fixtures.fake_survival_mode: no world is open — call open_temp_world() first.")
		return
	var mode: String = "survival" if value else "sandbox"
	WorldSave.set_world_meta("mode", mode)
