# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# test_biome_map.gd — Unit tests for BiomeMap determinism and Whittaker classification.
#
# Anchors:
#   DOCS.md §2.1 — biome generation (6 v1 biomes, deterministic per seed)
#   02-CONTEXT.md §D-04 — strong biome identity
#   02-RESEARCH.md §"Biome Generation Pipeline"
#
# Tests:
#   1. test_biome_is_deterministic_per_seed       — same seed → identical biome IDs
#   2. test_biome_classification_matches_whittaker_table — classify() corner cases

extends GutTest

const BiomeMapScript = preload("res://src/world/biome_map.gd")

# ─── Fixtures ──────────────────────────────────────────────────────────────────

var _map_a: BiomeMap = null
var _map_b: BiomeMap = null

func before_each() -> void:
	_map_a = BiomeMapScript.new(1234)
	_map_b = BiomeMapScript.new(1234)


func after_each() -> void:
	_map_a = null
	_map_b = null


# ─── Test 1: Determinism across instances with the same seed ────────────────────

func test_biome_is_deterministic_per_seed() -> void:
	# Sample 100 deterministic world XZ positions and assert that two BiomeMap
	# instances with the same seed return bit-identical biome IDs.
	var rng := RandomNumberGenerator.new()
	rng.seed = 42  # Fixed RNG so test positions are themselves deterministic

	for i: int in range(100):
		var wx: float = rng.randf_range(-5000.0, 5000.0)
		var wz: float = rng.randf_range(-5000.0, 5000.0)
		var biome_a: BiomeMap.Biome = _map_a.biome_at(wx, wz)
		var biome_b: BiomeMap.Biome = _map_b.biome_at(wx, wz)
		assert_eq(biome_a, biome_b,
			"biome_at(%s, %s) must be identical for same seed (determinism)" % [wx, wz])


# ─── Test 2: Whittaker classification corner cases ──────────────────────────────

func test_biome_classification_matches_whittaker_table() -> void:
	# Verify classify() against the 7 Whittaker corner cases from RESEARCH Pattern 1
	# lines 489-497.

	# OCEAN: cold+wet polar ocean (m > 0.3 and t < -0.4)
	assert_eq(_map_a.classify(-0.5, 0.4), BiomeMap.Biome.OCEAN,
		"cold+wet should classify as OCEAN")

	# OCEAN: very wet (m > 0.5)
	assert_eq(_map_a.classify(0.2, 0.8), BiomeMap.Biome.OCEAN,
		"very wet should classify as OCEAN")

	# SNOW: cold (t < -0.3), not cold+wet ocean
	assert_eq(_map_a.classify(-0.5, 0.0), BiomeMap.Biome.SNOW,
		"cold+moderate-moisture should classify as SNOW")

	# DESERT: hot + very dry (t > 0.4 and m < -0.2)
	assert_eq(_map_a.classify(0.6, -0.5), BiomeMap.Biome.DESERT,
		"hot+dry should classify as DESERT")

	# JUNGLE: warm + wet (t > 0.2 and m > 0.0)
	assert_eq(_map_a.classify(0.3, 0.2), BiomeMap.Biome.JUNGLE,
		"warm+wet should classify as JUNGLE")

	# SAVANNAH: warm + dryish (t > 0.0 and m < 0.0)
	assert_eq(_map_a.classify(0.3, -0.3), BiomeMap.Biome.SAVANNAH,
		"warm+dry should classify as SAVANNAH")

	# GRASSLAND_FOREST: default fallback (temperate + moderate moisture)
	assert_eq(_map_a.classify(0.0, 0.0), BiomeMap.Biome.GRASSLAND_FOREST,
		"temperate+moderate should classify as GRASSLAND_FOREST (default fallback)")
