# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# conftest_helpers.gd — shared test utilities for the Cubicraftia GUT test suite
#
# Usage in test files:
#   const Helpers = preload("res://tests/conftest_helpers.gd")
#
# Provides helpers for:
#   - Enumerating .tscn files under src/ui/ (for test_no_hardcoded_strings.gd)
#   - Scanning .gd file source text for assertions
#   - Common path utilities
#   - World/terrain spawning helpers for integration tests (Plan 04)
#   - Phase 2 fixtures: deterministic_world_seed, make_biome_map, skip_if_headless_voxel

extends Object

## Spawn the main scene (src/world/main_scene.tscn) into the given test's
## scene tree, await 2 physics frames to let autoloads initialise, then return
## the root Node3D.
##
## Pass a GutTest instance as `gut_test` so helpers can call `await` on the
## engine's process frame signal.
##
## Returns null and prints a clear error message if main_scene.tscn does not
## exist yet — this is the Wave 0 explicit-gap behaviour for Task 1 RED phase.
static func spawn_test_world(gut_test: Object) -> Node3D:
	var scene_path := "res://src/world/main_scene.tscn"
	if not ResourceLoader.exists(scene_path):
		push_error("spawn_test_world: scene not found at %s (Wave 0 gap — will exist after Task 2/3)" % scene_path)
		return null
	var packed: PackedScene = load(scene_path)
	if packed == null:
		push_error("spawn_test_world: failed to load %s" % scene_path)
		return null
	var root := packed.instantiate() as Node3D
	if root == null:
		push_error("spawn_test_world: instantiated scene is not a Node3D")
		return null
	gut_test.add_child(root)
	# Wait 2 frames so autoloads finish _ready() and the terrain viewer registers
	await gut_test.get_tree().process_frame
	await gut_test.get_tree().process_frame
	return root


## Wait for `n` physics process frames before continuing.
## Must be called with `await`, e.g.:
##   await Helpers.wait_frames(30, self)
static func wait_frames(n: int, gut_test: Object) -> void:
	for _i: int in range(n):
		await gut_test.get_tree().process_frame

## Enumerate all .tscn files recursively under a given directory.
## Returns an empty array if the directory does not exist (Wave 0 placeholder
## behaviour — src/ui/ is empty at Plan 02 time; populated in Plan 06).
static func find_tscn_files(dir_path: String) -> Array[String]:
	var result: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return result
	_collect_tscn_recursive(dir_path, result)
	return result


## Enumerate all .gd files recursively under a given directory.
static func find_gd_files(dir_path: String) -> Array[String]:
	var result: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return result
	_collect_gd_recursive(dir_path, result)
	return result


## Read a text file and return its contents as a String.
## Returns "" if the file does not exist or cannot be opened.
static func read_text_file(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var content := f.get_as_text()
	f.close()
	return content


## Parse project.godot (INI-style) and extract the application/config/name value.
## Returns "" if not found.
static func get_project_name() -> String:
	var content := read_text_file("res://project.godot")
	for line: String in content.split("\n"):
		line = line.strip_edges()
		if line.begins_with('config/name="'):
			var value := line.substr(len('config/name="'))
			value = value.trim_suffix('"')
			return value
	return ""


## ─── Private helpers ─────────────────────────────────────────────────────────

static func _collect_tscn_recursive(dir_path: String, result: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if name == "." or name == "..":
			name = dir.get_next()
			continue
		var full_path := dir_path + "/" + name
		if dir.current_is_dir():
			_collect_tscn_recursive(full_path, result)
		elif name.ends_with(".tscn"):
			result.append(full_path)
		name = dir.get_next()
	dir.list_dir_end()


static func _collect_gd_recursive(dir_path: String, result: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if name == "." or name == "..":
			name = dir.get_next()
			continue
		var full_path := dir_path + "/" + name
		if dir.current_is_dir():
			_collect_gd_recursive(full_path, result)
		elif name.ends_with(".gd"):
			result.append(full_path)
		name = dir.get_next()
	dir.list_dir_end()


# ─── Phase 2 fixtures ─────────────────────────────────────────────────────────
# Added in Plan 02-02 (Wave 0 test infrastructure).

## Return the canonical deterministic seed used across Phase 2 unit tests.
## Tests that need a different seed should pass it explicitly to make_biome_map().
static func deterministic_world_seed() -> int:
	return 1234


## Return a BiomeMap initialised with the given seed.
##
## Plan 06 shipped BiomeMap — this fixture constructs a real instance.
static func make_biome_map(seed: int = 1234) -> Object:
	return preload("res://src/world/biome_map.gd").new(seed)


## Return true when the current environment cannot instantiate VoxelTerrain safely.
##
## godot_voxel crashes in headless mode without a GPU (see 01-RESEARCH.md
## §"headless-integration-test-gap" and 02-VALIDATION.md §"Headless caveat").
## Integration tests that set up live VoxelTerrain nodes should call this at the
## top of their test method and early-return with `pending('headless-skip')`.
##
## Usage:
##   func test_something() -> void:
##       if Helpers.skip_if_headless_voxel():
##           pending("headless-skip")
##           return
##       # ... rest of test ...
##
## Returns true when a GPU / display server is not available.
static func skip_if_headless_voxel() -> bool:
	# Godot exposes "movie" feature on headless export templates.
	# DisplayServer.get_name() returns "headless" in --headless mode.
	var display_server_name := DisplayServer.get_name()
	if display_server_name == "headless":
		return true
	# Fallback: check for the movie-writer feature flag used by CI export runs.
	if OS.has_feature("movie"):
		return true
	return false
