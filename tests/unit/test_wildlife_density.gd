# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# test_wildlife_density.gd: Pins the wildlife spawn-density contract (the world must feel
# lively, not empty) while keeping the per-chunk count BOUNDED for mobile performance.
#
# Guards:
#   - General land biomes spawn a lively average per chunk (well above the old sparse rate).
#   - The SNOW biome (felt especially empty) gets a dedicated density boost, on par with OCEAN.
#   - OCEAN keeps its boost.
#   - Per-spawning-chunk creature count is hard-bounded by WILDLIFE_PER_CHUNK_MAX × the biome
#     multiplier, so a raised density can never produce unbounded per-chunk spawns.
#
# (The global live total is separately capped by main_scene._WILDLIFE_ACTIVE_CAP +
#  _cull_distant_wildlife(); this suite covers the per-chunk spawner math.)
#
# Anchors:
#   src/world/wildlife_spawner.gd
#   src/world/biome_map.gd: biome ids (SNOW = 2, OCEAN = 5)

extends GutTest

const Spawner := preload("res://src/world/wildlife_spawner.gd")

const _SEED: int = 1234
const _GRID: int = 32  # sample _GRID×_GRID chunks for a stable statistical average
const _SNOW: int = 2
const _OCEAN: int = 5
const _GRASSLAND: int = 0


## Mean creatures-per-chunk for `biome` across a deterministic grid of chunks, applying the
## exact spawner gates main_scene uses (chance roll → count → entries).
func _avg_creatures_per_chunk(biome: int) -> float:
	var total := 0
	var sampled := 0
	for cx in range(-_GRID / 2, _GRID / 2):
		for cz in range(-_GRID / 2, _GRID / 2):
			var coord := Vector3i(cx, 0, cz)
			sampled += 1
			if not Spawner.should_spawn_in_chunk(coord, biome, _SEED):
				continue
			var count: int = Spawner.spawn_count_for_chunk(coord, _SEED)
			total += Spawner.pick_spawn_entries(coord, count, biome, _SEED).size()
	return float(total) / float(sampled)


# Density must be clearly lively, not the old ~1/chunk sparse world. (Pre-density-pass the
# general land average was ~1.07; this asserts a meaningful, durable increase.)
func test_general_land_density_is_lively() -> void:
	var avg := _avg_creatures_per_chunk(_GRASSLAND)
	assert_gt(avg, 1.8,
		"general land density (%.2f /chunk) should be lively (well above the old ~1.07)" % avg)


# SNOW felt especially empty, it must now be boosted well above the general land rate and be
# on the same lively tier as OCEAN.
func test_snow_density_is_boosted() -> void:
	var snow := _avg_creatures_per_chunk(_SNOW)
	var land := _avg_creatures_per_chunk(_GRASSLAND)
	assert_gt(snow, land * 1.5,
		"SNOW density (%.2f) must be clearly boosted above general land (%.2f)" % [snow, land])
	assert_gt(snow, 4.0, "SNOW density (%.2f) should be on the lively (ocean-like) tier" % snow)


func test_ocean_density_stays_boosted() -> void:
	var ocean := _avg_creatures_per_chunk(_OCEAN)
	var land := _avg_creatures_per_chunk(_GRASSLAND)
	assert_gt(ocean, land * 1.5,
		"OCEAN density (%.2f) must stay boosted above general land (%.2f)" % [ocean, land])


# BOUNDEDNESS: no spawning chunk may exceed WILDLIFE_PER_CHUNK_MAX × the per-biome multiplier.
# This keeps the raised density mobile-safe, density rises, the per-chunk ceiling does not run away.
func test_per_chunk_count_is_bounded() -> void:
	var max_land: int = Spawner.WILDLIFE_PER_CHUNK_MAX  # general biomes are ×1
	var max_boosted: int = Spawner.WILDLIFE_PER_CHUNK_MAX * 2  # snow/ocean are ×2
	for biome in [_GRASSLAND, _SNOW, _OCEAN]:
		var ceiling: int = max_boosted if (biome == _SNOW or biome == _OCEAN) else max_land
		for cx in range(-12, 12):
			for cz in range(-12, 12):
				var coord := Vector3i(cx, 0, cz)
				if not Spawner.should_spawn_in_chunk(coord, biome, _SEED):
					continue
				var count: int = Spawner.spawn_count_for_chunk(coord, _SEED)
				var n: int = Spawner.pick_spawn_entries(coord, count, biome, _SEED).size()
				assert_true(n <= ceiling,
					"biome %d chunk (%d,%d): %d spawns exceeds ceiling %d" % [biome, cx, cz, n, ceiling])
