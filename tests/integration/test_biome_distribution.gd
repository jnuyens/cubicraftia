# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# test_biome_distribution.gd — Integration tests for biome distribution across
# a 10 000-cell sample.
#
# Anchors:
#   DOCS.md §2.1 — 6 v1 biomes: grasslands+forest, desert, snow, jungle, savannah, ocean
#   02-CONTEXT.md §D-04 — strong biome identity; smooth 5m transitions
#   02-RESEARCH.md §"Biome Generation Pipeline"
#
# Tests:
#   1. test_10000_cell_distribution_per_seed — all 6 biomes appear in 10 000 samples
#   2. test_no_oceanic_biome_at_origin       — world origin (0,0) is not ocean
#
# Headless note: these tests use BiomeMap only (no VoxelTerrain instantiation),
# so they are safe to run headlessly. The skip_if_headless_voxel() guard is not needed.

extends GutTest

const Helpers = preload("res://tests/conftest_helpers.gd")
const BiomeMapScript = preload("res://src/world/biome_map.gd")

# ─── Test 1: All 6 biomes appear within a 10 000-cell grid sample ──────────────

func test_10000_cell_distribution_per_seed() -> void:
	# Instantiate BiomeMap with the canonical deterministic seed.
	var biome_map: BiomeMap = Helpers.make_biome_map(Helpers.deterministic_world_seed()) as BiomeMap
	assert_not_null(biome_map, "make_biome_map should return a valid BiomeMap")
	if biome_map == null:
		return

	# Sample a 100×100 grid with 20 m spacing → 10 000 cells in a 2 000×2 000 m area.
	# Widened from 1 000 m when BIOME_NOISE_FREQUENCY halved (0.001 → 0.0005): the sample
	# area tracks the biome wavelength so all 6 biomes still appear.
	var seen_biomes: Dictionary = {}
	var grid_size: int = 100
	var spacing: float = 20.0
	var origin_offset: float = -1000.0  # centre the grid around (0, 0)

	for ix: int in range(grid_size):
		for iz: int in range(grid_size):
			var wx: float = origin_offset + ix * spacing
			var wz: float = origin_offset + iz * spacing
			var biome: BiomeMap.Biome = biome_map.biome_at(wx, wz)
			seen_biomes[int(biome)] = true

	# Assert all 6 biome IDs appear at least once.
	for biome_id: int in range(6):
		assert_true(seen_biomes.has(biome_id),
			"Biome ID %d should appear at least once in 10 000 samples (seed=%d)" % [
				biome_id, Helpers.deterministic_world_seed()])


# ─── Test 2: World origin (0, 0) is not ocean ────────────────────────────────

func test_no_oceanic_biome_at_origin() -> void:
	# The player should spawn on land per DOCS §1.2 starter-chest pattern.
	# This is a determinism check: with seed 1234 the origin biome must not be OCEAN.
	var biome_map: BiomeMap = Helpers.make_biome_map(Helpers.deterministic_world_seed()) as BiomeMap
	assert_not_null(biome_map, "make_biome_map should return a valid BiomeMap")
	if biome_map == null:
		return

	var origin_biome: BiomeMap.Biome = biome_map.biome_at(0.0, 0.0)
	assert_ne(int(origin_biome), int(BiomeMap.Biome.OCEAN),
		"Origin (0,0) should not be OCEAN with seed=%d (player should spawn on land)" % [
			Helpers.deterministic_world_seed()])
