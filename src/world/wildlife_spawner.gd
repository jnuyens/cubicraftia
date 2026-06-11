# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# wildlife_spawner.gd — Per-chunk passive wildlife spawn helper (static methods only).
#
# Called by main_scene._on_chunk_loaded() to scatter harmless roaming animals
# across the world. Mirrors the foliage_spawner.gd / strawberry_spawner.gd pattern.
#
# Design:
#   - Each biome has a curated PASSIVE roster (no hostiles: bat, cube_slime*, ghost,
#     laser_penguin, vampire*, vampire_bat, vampire_humanoid are excluded).
#   - ~15-20% chance per chunk (SPAWN_CHANCE_PER_CHUNK = 0.18).
#   - 1-2 animals per chunk when the roll succeeds (WILDLIFE_PER_CHUNK_MAX = 2).
#   - Creature kind and position are deterministic by (chunk_coord, world_seed).
#   - OCEAN chunks place water animals at water surface (Y = _OCEAN_WATER_Y).
#   - Land-biome chunks use Y = 0.0 (surface-corrected by main_scene caller).
#
# Biome → creature roster:
#   GRASSLAND_FOREST : panda, monkey
#   JUNGLE           : monkey, toucan, panda
#   SAVANNAH         : elephant, giraffe, gnu
#   DESERT           : desert_mouse, camel, fennec_fox, desert_lizard, scorpion,
#                      meerkat, rattlesnake, vulture
#   SNOW             : polar_bear, caribou, husky_dog, arctic_wolf, arctic_fox,
#                      snow_rabbit, penguin, snowy_owl, reindeer, snowman
#   OCEAN            : fish_blue, fish_orange, fish_yellow, orca, manta, jellyfish
#
# Thread safety: static methods only; no global state. Deterministic RNG via
# RandomNumberGenerator seeded from chunk_coord + world_seed (Knuth mix).
#
# References:
#   src/world/foliage_spawner.gd  — pattern source
#   src/world/biome_map.gd        — BiomeMap.Biome enum
#   src/world/wildlife.gd         — the entity instantiated per result

class_name WildlifeSpawner
extends RefCounted

# ─── Spawn tuning constants ────────────────────────────────────────────────────

## Maximum number of animals to spawn in a single chunk when the chance roll succeeds.
const WILDLIFE_PER_CHUNK_MAX: int = 2

## Per-chunk probability of spawning any wildlife (0..1). 0.25 keeps animals easy to
## encounter as you roam (the active-cap distance-cull in main_scene frees slots so
## creatures keep appearing in fresh chunks) without over-populating the world.
const SPAWN_CHANCE_PER_CHUNK: float = 0.25

## Margin (in terrain metres) from chunk edges for spawn-position sampling.
const CHUNK_EDGE_MARGIN_M: float = 2.0

## Minimum distance (m) a wildlife spawn must be from the world origin, so animals
## don't crowd the spawn point / starter chest + bed.
const _MIN_SPAWN_DIST_FROM_ORIGIN: float = 16.0

## Y position for ocean water animals (placed at/near the water surface).
## The ACTIVE generator (multipass_generator.gd) uses sea_level = 12, so water tops out at
## ~Y 13. The old 63.5 (from the retired terrain_generator's SEA_LEVEL=64) spawned orcas
## ~50 m up in the sky. Water column fills surface+1 .. sea_level(12), so 12.5 sits in it.
const _OCEAN_WATER_Y: float = 12.5

# ─── Biome → creature roster ──────────────────────────────────────────────────

## Passive creature roster per biome. Keys are BiomeMap.Biome int values.
## Hostile kinds (bat, cube_slime*, ghost, laser_penguin, vampire*) are excluded.
const _BIOME_ROSTER: Dictionary = {
	0: ["panda", "monkey", "pig", "dog", "sheep"],                 # GRASSLAND_FOREST
	1: ["desert_mouse", "camel", "fennec_fox", "desert_lizard",    # DESERT
		"scorpion", "meerkat", "rattlesnake", "vulture"],
	2: ["polar_bear", "caribou", "husky_dog", "arctic_wolf",       # SNOW
		"arctic_fox", "snow_rabbit", "penguin", "snowy_owl",
		"reindeer", "snowman"],
	3: ["monkey", "toucan", "panda"],                              # JUNGLE
	4: ["elephant", "giraffe", "gnu"],                             # SAVANNAH
	5: ["fish_blue", "fish_orange", "fish_yellow", "orca", "manta", "jellyfish",
		"dolphin", "turtle_sea", "flamingo", "seagull"],  # OCEAN (+ art-wildlife-beach)
}

# ─── Public static API ────────────────────────────────────────────────────────

## Returns true if the given chunk should spawn wildlife on this chunk-load.
##
## Gates:
##   1. Biome must have a roster (all 6 biomes do; this future-proofs additions).
##   2. Per-chunk chance roll (deterministic) must succeed.
##
## @param chunk_coord  Chunk coordinate (16 m per side).
## @param biome        BiomeMap.Biome int value for this chunk.
## @param world_seed   The world seed for deterministic sampling.
## @return             true if wildlife should spawn in this chunk.
static func should_spawn_in_chunk(chunk_coord: Vector3i, biome: int, world_seed: int) -> bool:
	# Gate 1: biome must have a defined roster.
	if not _BIOME_ROSTER.has(biome):
		return false

	# Gate 2: deterministic per-chunk chance roll.
	var rng := RandomNumberGenerator.new()
	var coord_hash: int = (chunk_coord.x * 2654435761) ^ (chunk_coord.y * 1013904223) \
		^ (chunk_coord.z * 1664525)
	rng.seed = (world_seed ^ coord_hash ^ "wildlife_chance".hash()) & 0x7FFFFFFFFFFFFFFF
	return rng.randf() < SPAWN_CHANCE_PER_CHUNK


## Returns the number of animals to spawn for this chunk (always 1..WILDLIFE_PER_CHUNK_MAX
## when called — caller should only invoke after should_spawn_in_chunk returns true).
##
## @param chunk_coord  The chunk coordinate being loaded.
## @param world_seed   The world seed for deterministic sampling.
## @return             1–WILDLIFE_PER_CHUNK_MAX.
static func spawn_count_for_chunk(chunk_coord: Vector3i, world_seed: int) -> int:
	var rng := RandomNumberGenerator.new()
	var coord_hash: int = (chunk_coord.x * 2654435761) ^ (chunk_coord.y * 1013904223) \
		^ (chunk_coord.z * 1664525)
	rng.seed = (world_seed ^ coord_hash ^ "wildlife_count".hash()) & 0x7FFFFFFFFFFFFFFF
	return rng.randi_range(1, WILDLIFE_PER_CHUNK_MAX)


## Pick spawn positions and creature kinds for a chunk.
##
## Returns an Array of Dictionaries, each with:
##   { "kind": String, "pos": Vector3 }
##
## Y is set to 0.0 for land biomes (caller surface-corrects) and to
## _OCEAN_WATER_Y for ocean biomes.
##
## @param chunk_coord  The chunk coordinate (16 m per side; origin = chunk_coord * 16).
## @param count        Number of animals to place.
## @param biome        BiomeMap.Biome int value for this chunk.
## @param world_seed   The world seed for deterministic sampling.
## @return             Array[Dictionary] with "kind" and "pos" keys.
static func pick_spawn_entries(chunk_coord: Vector3i, count: int,
		biome: int, world_seed: int) -> Array:
	var entries: Array = []
	var roster: Array = _BIOME_ROSTER.get(biome, [])
	if roster.is_empty():
		return entries

	var rng := RandomNumberGenerator.new()
	var coord_hash: int = (chunk_coord.x * 2654435761) ^ (chunk_coord.y * 1013904223) \
		^ (chunk_coord.z * 1664525)
	rng.seed = (world_seed ^ coord_hash ^ "wildlife_positions".hash()) & 0x7FFFFFFFFFFFFFFF

	var is_ocean: bool = (biome == 5)  # BiomeMap.Biome.OCEAN
	var spawn_y: float = _OCEAN_WATER_Y if is_ocean else 0.0

	for _i: int in range(count):
		var chunk_origin_x: float = chunk_coord.x * 16.0
		var chunk_origin_z: float = chunk_coord.z * 16.0
		var x: float = chunk_origin_x + rng.randf_range(CHUNK_EDGE_MARGIN_M, 16.0 - CHUNK_EDGE_MARGIN_M)
		var z: float = chunk_origin_z + rng.randf_range(CHUNK_EDGE_MARGIN_M, 16.0 - CHUNK_EDGE_MARGIN_M)
		# Keep animals away from the spawn point / starter chest + bed.
		if Vector2(x, z).length() < _MIN_SPAWN_DIST_FROM_ORIGIN:
			continue
		var kind_idx: int = rng.randi_range(0, roster.size() - 1)
		entries.append({
			"kind": roster[kind_idx],
			"pos": Vector3(x, spawn_y, z),
		})
	return entries
