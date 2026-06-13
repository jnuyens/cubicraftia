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
#   OCEAN            : fish_blue, fish_orange, fish_yellow, orca, manta, jellyfish,
#                      dolphin, turtle_sea, flamingo, seagull, + art-ocean deep-sea set
#                      (shark_great_white, whale_blue, whale_sperm, squid, octopus_red,
#                      seahorse, pufferfish, hammerhead, eel, stingray)
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

## Maximum number of animals to spawn in a single LAND chunk when the chance roll succeeds.
## Bumped 2 → 3 → 5 (density passes: the world kept reading as empty). The active-cap
## distance-cull in main_scene (_WILDLIFE_ACTIVE_CAP) still bounds the TOTAL alive at once,
## so this raises LOCAL density without unbounded growth; ocean and snow multiply this further
## (see _OCEAN_COUNT_MULT / _SNOW_COUNT_MULT). spawn_count_for_chunk rolls 1..this, so the
## average per spawning chunk is ~ (1+this)/2 = 3 before any per-biome multiplier.
const WILDLIFE_PER_CHUNK_MAX: int = 5

## Per-chunk probability of spawning any wildlife on a LAND biome (0..1). Bumped 0.25 → 0.55
## → 0.80 (density passes) so animals are a common, lively sight as you roam rather than rare;
## the active cap keeps the total sane. Ocean and snow use higher chances (see
## _OCEAN_SPAWN_CHANCE / _SNOW_SPAWN_CHANCE) so those biomes (which read as especially empty)
## are visibly populated.
const SPAWN_CHANCE_PER_CHUNK: float = 0.80

## Per-chunk wildlife chance for OCEAN biome (0..1) — higher than land so the underwater
## world is lively. Near-certain per ocean chunk; combined with _OCEAN_COUNT_MULT this fills
## reefs/open water with fish, orcas and rays (still bounded by the main_scene active cap).
const _OCEAN_SPAWN_CHANCE: float = 0.92

## Ocean animal-count multiplier applied on top of WILDLIFE_PER_CHUNK_MAX in pick_spawn_entries
## (the main_scene spawn_count_for_chunk call carries no biome, so the ocean bump lives here).
## ×2 → up to 10 sea creatures per ocean chunk, giving the underwater scene real schools of life.
const _OCEAN_COUNT_MULT: int = 2

## Per-chunk wildlife chance for the SNOW biome (0..1): higher than the general land rate so
## the ice/snow world (polar bears, caribou, huskies, arctic foxes/wolves, snow rabbits,
## penguins, snowy owls, reindeer, snowmen) feels inhabited rather than barren. Mirrors the
## OCEAN boost so the two "felt empty" biomes both get a dedicated lift, not the baseline land rate.
const _SNOW_SPAWN_CHANCE: float = 0.92

## SNOW animal-count multiplier on top of WILDLIFE_PER_CHUNK_MAX (same role as _OCEAN_COUNT_MULT).
## ×2 → up to 10 snow creatures per spawning snow chunk, so herds of caribou / packs of wolves
## read as a living polar biome. Still bounded by the main_scene active-cap distance cull.
const _SNOW_COUNT_MULT: int = 2

## BiomeMap.Biome.OCEAN int value. Centralised so the ocean-specific density branches all
## reference the same constant instead of a bare literal.
const _OCEAN_BIOME: int = 5

## BiomeMap.Biome.SNOW int value (id 2). Centralised for the snow-specific density branches.
const _SNOW_BIOME: int = 2

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
	# SAVANNAH also hosts the DESERT roster (BUG 3): the desert biome is a narrow, rare band
	# (~5% of the world) that for the default seed sits 780+ m from the spawn point — the player
	# roams grassland + savannah and never reaches it, so the camel/meerkat/scorpion/vulture/...
	# desert fauna never spawned even though they are fully wired. Savannah is the nearest arid
	# biome to spawn (≈ adjacent to spawn) AND shares fauna with the desert (camels, meerkats,
	# vultures, scorpions, snakes, lizards all read as savannah/arid animals), so folding the
	# desert roster into savannah surfaces those creatures in a biome the player actually reaches,
	# without touching biome generation. The DESERT roster (biome 1) is kept as-is for when the
	# player does travel into a true desert.
	4: ["elephant", "giraffe", "gnu",                              # SAVANNAH (+ arid/desert fauna)
		"desert_mouse", "camel", "fennec_fox", "desert_lizard",
		"scorpion", "meerkat", "rattlesnake", "vulture"],
	5: ["fish_blue", "fish_orange", "fish_yellow", "orca", "manta", "jellyfish",
		"dolphin", "turtle_sea", "flamingo", "seagull",          # OCEAN (+ art-wildlife-beach)
		"shark_great_white", "whale_blue", "whale_sperm", "squid",  # + art-ocean deep-sea set
		"octopus_red", "seahorse", "pufferfish", "hammerhead",
		"eel", "stingray"],
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

	# Gate 2: deterministic per-chunk chance roll. Ocean AND snow use a higher chance so those
	# biomes (which read as especially empty) are visibly populated (density pass); all other
	# land biomes use the (now raised) general SPAWN_CHANCE_PER_CHUNK.
	var rng := RandomNumberGenerator.new()
	var coord_hash: int = (chunk_coord.x * 2654435761) ^ (chunk_coord.y * 1013904223) \
		^ (chunk_coord.z * 1664525)
	rng.seed = (world_seed ^ coord_hash ^ "wildlife_chance".hash()) & 0x7FFFFFFFFFFFFFFF
	return rng.randf() < _chance_for_biome(biome)


## Per-biome per-chunk spawn chance (0..1): ocean and snow get a dedicated lift; every other
## land biome uses the general rate. Centralised so should_spawn_in_chunk and any future caller
## agree on the same per-biome probability.
static func _chance_for_biome(biome: int) -> float:
	if biome == _OCEAN_BIOME:
		return _OCEAN_SPAWN_CHANCE
	if biome == _SNOW_BIOME:
		return _SNOW_SPAWN_CHANCE
	return SPAWN_CHANCE_PER_CHUNK


## Per-biome animal-count multiplier applied to the (biome-agnostic) caller count in
## pick_spawn_entries. Ocean and snow get a ×N herd/school bump; every other biome is ×1.
static func _count_mult_for_biome(biome: int) -> int:
	if biome == _OCEAN_BIOME:
		return _OCEAN_COUNT_MULT
	if biome == _SNOW_BIOME:
		return _SNOW_COUNT_MULT
	return 1


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

	var is_ocean: bool = (biome == _OCEAN_BIOME)
	var spawn_y: float = _OCEAN_WATER_Y if is_ocean else 0.0

	# Ocean and snow chunks place MORE creatures than the (biome-agnostic) caller count so those
	# biomes have real schools/herds. The caller's spawn_count_for_chunk carries no biome, so the
	# per-biome multiplier lives here. Other land biomes use the caller count unchanged. The
	# _MIN_SPAWN_DIST_FROM_ORIGIN skip below may still drop some near the world origin.
	var place_count: int = count * _count_mult_for_biome(biome)

	for _i: int in range(place_count):
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
