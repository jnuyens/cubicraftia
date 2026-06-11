# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# test_terrain_library.gd — Regression guard for "terrain is gone" caused by a broken
# terrain.tscn: a mistyped/renamed model property, a null model in the library, or a
# missing mesher/generator. Several past regressions were exactly this class of bug
# (e.g. setting a property that does not exist on the resource), and they only surfaced
# at runtime because a plain parse-check never instantiates the scene or bakes the
# VoxelBlockyLibrary.
#
# These tests instantiate the REAL terrain.tscn and assert its render pipeline is intact.
# They do NOT mesh (headless can't), but a broken library / missing mesher / null model
# all fail here — before the player ever sees an empty world.
#
# Companion: test_spawn_on_land.gd guards the spawn-over-ocean cause.
#
# Anchors:
#   src/world/terrain.tscn          — VoxelTerrain + VoxelMesherBlocky + VoxelBlockyLibrary
#   src/world/multipass_generator.gd — VoxelGeneratorMultipassCB, 13 voxel IDs (0..12)

extends GutTest

const TERRAIN_SCENE := "res://src/world/terrain.tscn"

## Voxel IDs 0..12 the generator writes — the library MUST provide a model for each.
const EXPECTED_MODEL_COUNT: int = 13

var _terrain: Node = null


func before_each() -> void:
	var scn: PackedScene = load(TERRAIN_SCENE) as PackedScene
	assert_not_null(scn, "terrain.tscn failed to load as a PackedScene")
	if scn != null:
		_terrain = scn.instantiate()


func after_each() -> void:
	if is_instance_valid(_terrain):
		_terrain.free()
	_terrain = null


func test_terrain_instantiates() -> void:
	assert_not_null(_terrain, "terrain.tscn did not instantiate")
	assert_eq(_terrain.get_class(), "VoxelTerrain",
		"root node is %s, expected VoxelTerrain" % _terrain.get_class())


func test_mesher_and_generator_present() -> void:
	if _terrain == null:
		return
	var mesher: Variant = _terrain.get("mesher")
	var generator: Variant = _terrain.get("generator")
	assert_not_null(mesher, "VoxelTerrain has no mesher — terrain cannot render")
	assert_not_null(generator, "VoxelTerrain has no generator — terrain cannot generate")


## The library must hold a non-null model for every voxel ID the generator writes. A
## renamed/typo'd property (the historical failure mode) makes the model fail to bake and
## the whole library renders nothing — caught here.
func test_library_has_all_models_non_null() -> void:
	if _terrain == null:
		return
	var mesher: Variant = _terrain.get("mesher")
	assert_not_null(mesher, "no mesher; cannot reach library")
	if mesher == null:
		return
	var library: Variant = mesher.get("library")
	assert_not_null(library, "VoxelMesherBlocky has no library")
	if library == null:
		return
	assert_true(library.has_method("get_model"), "library is not a VoxelBlockyLibrary")
	for id: int in range(EXPECTED_MODEL_COUNT):
		var model: Variant = library.get_model(id)
		assert_not_null(model, "library model id=%d is null (terrain block would not render)" % id)


## Terrain must generate collision on layer 1 so the builder can stand on it — without
## this the builder falls through and the world reads as "no terrain".
func test_terrain_collision_configured() -> void:
	if _terrain == null:
		return
	assert_true(bool(_terrain.get("generate_collisions")),
		"generate_collisions is off — builder would fall through the world")
	assert_eq(int(_terrain.get("collision_layer")), 1,
		"terrain collision_layer must be 1 (builder grounding ray masks layer 1)")
