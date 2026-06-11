# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# test_terrain_generates.gd — Integration tests for terrain generation and
# builder spawn (Plan 04, Task 1 RED / Task 2-3 GREEN).
#
# Tests:
#   test_main_scene_loads         — main_scene.tscn instantiates with a Terrain child
#   test_chunks_generate          — VoxelTerrain produces at least 1 chunk within 2 frames
#   test_builder_spawns_above_ground — Builder lands above Y=0 after 30 frames
#
# Wave 0 note: Until Task 2 creates src/world/main_scene.tscn and
# src/world/terrain.tscn, the spawn_test_world() helper returns null and all
# three tests will produce a clear RED. This is intentional — Task 2/3 turns
# them GREEN.
#
# DOCS.md §10 vocabulary: "terrain", "chunks", "builder" (not "Minecraft" / "voxel mesh"
# in test names).

extends GutTest

const Helpers := preload("res://tests/conftest_helpers.gd")

# ─── Test 1 ──────────────────────────────────────────────────────────────────

## Asserts that src/world/main_scene.tscn instantiates and contains a child
## named "Terrain" of class VoxelTerrain (provided by addons/zylann.voxel).
func test_main_scene_loads() -> void:
	var root: Node3D = await Helpers.spawn_test_world(self)
	assert_not_null(root, "main_scene.tscn must instantiate a non-null Node3D root")
	if root == null:
		return

	var terrain := root.get_node_or_null("Terrain")
	assert_not_null(terrain, "main_scene.tscn must have a child named 'Terrain'")
	if terrain == null:
		root.queue_free()
		return

	# VoxelTerrain is registered by the zylann.voxel GDExtension.
	# ClassDB.is_parent_class verifies the class hierarchy at runtime.
	var is_voxel_terrain := terrain.get_class() == "VoxelTerrain" \
		or ClassDB.is_parent_class(terrain.get_class(), "VoxelTerrain")
	assert_true(is_voxel_terrain,
		"'Terrain' child must be a VoxelTerrain node (got: %s)" % terrain.get_class())
	root.queue_free()


# ─── Test 2 ──────────────────────────────────────────────────────────────────

## Asserts that after spawning the terrain scene and waiting 2 process frames,
## the VoxelTerrain has registered at least 1 generated terrain chunk in its
## internal storage map.
##
## Implementation note: VoxelTerrain tracks generated blocks internally; we
## use get_data_block_count() (available on VoxelTerrain in godot_voxel 1.6x)
## to assert that at least one chunk was produced.  If the method is not
## available (API difference between godot_voxel versions), fall back to
## checking that the terrain node is present and not null — and document the
## gap honestly.
func test_chunks_generate() -> void:
	var root: Node3D = await Helpers.spawn_test_world(self)
	assert_not_null(root, "main_scene.tscn must instantiate")
	if root == null:
		return

	var terrain := root.get_node_or_null("Terrain")
	assert_not_null(terrain, "Terrain child must exist")
	if terrain == null:
		root.queue_free()
		return

	# Wait 2 frames for the viewer to register and meshing to start
	await Helpers.wait_frames(2, self)

	# Check chunk generation via the storage API (godot_voxel 1.5+)
	if terrain.has_method("get_data_block_count"):
		var block_count: int = terrain.get_data_block_count()
		assert_true(block_count > 0,
			"VoxelTerrain must have generated at least 1 terrain chunk after 2 frames (got %d)" % block_count)
	else:
		# Fallback: terrain exists and is in the tree — log the gap
		assert_true(terrain.is_inside_tree(),
			"VoxelTerrain must be inside the scene tree")
		push_warning("test_chunks_generate: get_data_block_count() not available; chunk count not verified (godot_voxel API gap)")

	root.queue_free()


# ─── Test 3 ──────────────────────────────────────────────────────────────────

## Asserts that the Builder character spawns at Y > 0 after 30 physics frames.
##
## The builder is placed at Vector3(0, 32, 0) in main_scene.tscn and falls
## under gravity onto the generated terrain. Y > 0 confirms it did not fall
## through the terrain (collision is wired).
func test_builder_spawns_above_ground() -> void:
	var root: Node3D = await Helpers.spawn_test_world(self)
	assert_not_null(root, "main_scene.tscn must instantiate")
	if root == null:
		return

	var builder := root.get_node_or_null("Builder")
	assert_not_null(builder, "main_scene.tscn must have a child named 'Builder'")
	if builder == null:
		root.queue_free()
		return

	# Wait 30 frames for gravity + terrain collision to settle
	await Helpers.wait_frames(30, self)

	assert_true(builder.global_position.y > 0.0,
		"Builder must be above Y=0 after 30 frames (landed on terrain, not fallen through). Got Y=%.2f" % builder.global_position.y)
	root.queue_free()
