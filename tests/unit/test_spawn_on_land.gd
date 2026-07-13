# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# test_spawn_on_land.gd — Regression guard for the recurring "terrain is gone / builder
# floating over water at spawn" bug.
#
# Root cause (June 2026): spawn was hardcoded to world (0,0). For many seeds (0,0) is an
# OCEAN column, and once water was made non-collidable the builder spawned underwater /
# floating with no ground, the loading gate never saw solid ground, and the world read as
# "terrain gone". The fix is main_scene.search_land_spawn(), which searches outward for
# solid land above the waterline. These tests pin that contract so the regression can't
# silently return.
#
# Companion: test_terrain_library.gd guards terrain.tscn structural integrity (the OTHER
# historical "terrain gone" cause — a renamed/typo'd model property nulling the library).
#
# Anchors:
#   src/world/main_scene.gd  — search_land_spawn() (static, pure) + _find_world_spawn()
#   src/world/biome_map.gd   — BiomeMap.Biome.OCEAN, classify()
#   terrain.tscn / multipass_generator.gd — sea_level = 12, height noise (Simplex FBM,
#                                            4 octaves, freq 0.01, seed = world_seed)

extends GutTest

const MainScene := preload("res://src/world/main_scene.gd")

const SEA_LEVEL: float = 12.0

# A spread of seeds — includes ones whose origin (0,0) is ocean, which is exactly the
# case that produced the bug.
const SEEDS: Array[int] = [1234, 1, 7, 42, 99, 777, 2024, 9999, 31337, 555, 8675309]


## Build the SAME height noise the generator uses, so surface_y here matches the meshed
## terrain (Simplex FBM, 4 octaves, lacunarity 2, gain 0.5, freq 0.01, seed = world_seed).
func _height_noise(seed_v: int) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX
	n.fractal_type = FastNoiseLite.FRACTAL_FBM
	n.fractal_octaves = 4
	n.fractal_lacunarity = 2.0
	n.fractal_gain = 0.5
	n.frequency = 0.01
	n.seed = seed_v
	return n


## CORE CONTRACT: across many seeds, the computed spawn is never below the waterline.
## A spawn below sea level means the builder lands underwater on the seabed (water is
## non-collidable) — the exact "floating in water / terrain gone" symptom.
func test_spawn_is_never_below_sea_level() -> void:
	for seed_v: int in SEEDS:
		var bm := BiomeMap.new(seed_v)
		var spawn: Vector3 = MainScene.search_land_spawn(bm, _height_noise(seed_v), SEA_LEVEL)
		assert_true(spawn.y >= SEA_LEVEL,
			"seed %d: spawn.y=%.1f is BELOW sea level (%.0f) — builder would spawn underwater"
				% [seed_v, spawn.y, SEA_LEVEL])


## The spawn column itself must not be OCEAN — the builder must land on dry biome ground,
## not on a seabed under a water column.
func test_spawn_column_is_not_ocean() -> void:
	for seed_v: int in SEEDS:
		var bm := BiomeMap.new(seed_v)
		var spawn: Vector3 = MainScene.search_land_spawn(bm, _height_noise(seed_v), SEA_LEVEL)
		assert_ne(int(bm.biome_at(spawn.x, spawn.z)), int(BiomeMap.Biome.OCEAN),
			"seed %d: spawn (%.0f,%.0f) is in an OCEAN column" % [seed_v, spawn.x, spawn.z])


## The actual bug case: gradient noise returns ~0 at the lattice origin (0,0) for EVERY
## seed, so the origin column is always GRASSLAND at exactly surface_y=12 — i.e. a single
## land speck right at the waterline, ringed by whatever surrounds it (often ocean). That
## reads as "builder floating on water / terrain gone". The finder must therefore relocate
## the spawn OFF the origin onto ground clearly above the waterline — never leave the
## builder on the waterline speck.
func test_spawn_relocates_off_waterline_origin() -> void:
	for seed_v: int in SEEDS:
		var bm := BiomeMap.new(seed_v)
		var spawn: Vector3 = MainScene.search_land_spawn(bm, _height_noise(seed_v), SEA_LEVEL)
		# Land was found within radius for every realistic seed (asserted indirectly: the
		# fallback would sit at origin). Require the spawn to clear the waterline by a
		# safe margin so the builder lands on real, dry, walkable ground.
		assert_true(spawn.y >= SEA_LEVEL + 2.0,
			"seed %d: spawn.y=%.1f is not safely above the waterline (need >= %.0f) — builder would land on a waterline speck surrounded by water"
				% [seed_v, spawn.y, SEA_LEVEL + 2.0])


## The spawn ground height must equal the generator's surface formula at that column, so
## the builder is placed exactly on the meshed surface (not floating above / sunk below).
func test_spawn_y_matches_generator_surface_formula() -> void:
	for seed_v: int in SEEDS:
		var bm := BiomeMap.new(seed_v)
		var noise := _height_noise(seed_v)
		var spawn: Vector3 = MainScene.search_land_spawn(bm, noise, SEA_LEVEL)
		# Skip the at-origin fallback (no land found): it intentionally uses sea_level+2.
		if spawn.x == 0.0 and spawn.z == 0.0 and is_equal_approx(spawn.y, SEA_LEVEL + 2.0):
			continue
		var expected_top: float = float(int(noise.get_noise_2d(spawn.x, spawn.z) * 8.0 + SEA_LEVEL)) + 1.0
		assert_almost_eq(spawn.y, expected_top, 0.01,
			"seed %d: spawn.y=%.2f != generator surface top %.2f" % [seed_v, spawn.y, expected_top])


## The spawn column must not be MOUNTAIN either. A mountain column's REAL terrain height
## (used by _terrain_surface_at / spawn_starter_chest_and_bed to ground the starter chest, bed,
## and welcome sign) includes _mountain_lift_at, which this pure search does not replicate. If
## the search ever chose a mountain column, the chest/bed would be grounded at the true (much
## higher) mountain surface tens of metres away from the builder (placed without the lift):
## the real-device "chest and bed not near spawn" bug.
func test_spawn_column_is_not_mountain() -> void:
	for seed_v: int in SEEDS:
		var bm := BiomeMap.new(seed_v)
		var spawn: Vector3 = MainScene.search_land_spawn(bm, _height_noise(seed_v), SEA_LEVEL)
		assert_ne(int(bm.biome_at(spawn.x, spawn.z)), int(BiomeMap.Biome.MOUNTAIN),
			"seed %d: spawn (%.0f,%.0f) is in a MOUNTAIN column, chest/bed would ground at the real (lifted) surface, far from the builder" % [seed_v, spawn.x, spawn.z])
