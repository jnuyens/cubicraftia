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
## Bumped 2 → 3 (density pass: the world read as empty). The active-cap distance-cull in
## main_scene (_WILDLIFE_ACTIVE_CAP = 16) still bounds the total, so this raises local
## density without unbounded growth; ocean multiplies this further (see _OCEAN_COUNT_MULT).
const WILDLIFE_PER_CHUNK_MAX: int = 3

## Per-chunk probability of spawning any wildlife on a LAND biome (0..1). Bumped 0.25 → 0.55
## (density pass) so animals are common as you roam rather than a rare sight; the active cap
## keeps the total sane. Ocean uses a higher chance (see _OCEAN_SPAWN_CHANCE) so the
## underwater world — which looks great but felt lifeless — is visibly populated.
const SPAWN_CHANCE_PER_CHUNK: float = 0.55

## Per-chunk wildlife chance for OCEAN biome (0..1) — higher than land so the underwater
## world is lively. Near-certain per ocean chunk; combined with _OCEAN_COUNT_MULT this fills
## reefs/open water with fish, orcas and rays (still bounded by the main_scene active cap).
const _OCEAN_SPAWN_CHANCE: float = 0.9

## Ocean animal-count multiplier applied on top of WILDLIFE_PER_CHUNK_MAX in pick_spawn_entries
## (the main_scene spawn_count_for_chunk call carries no biome, so the ocean bump lives here).
## ×2 → up to 6 sea creatures per ocean chunk, giving the underwater scene real schools of life.
const _OCEAN_COUNT_MULT: int = 2

## BiomeMap.Biome.OCEAN int value. Centralised so the ocean-specific density branches all
## reference the same constant instead of a bare literal.
const _OCEAN_BIOME: int = 5

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

	# Gate 2: deterministic per-chunk chance roll. Ocean uses a higher chance so the
	# underwater world is visibly populated (density pass).
	var rng := RandomNumberGenerator.new()
	var coord_hash: int = (chunk_coord.x * 2654435761) ^ (chunk_coord.y * 1013904223) \
		^ (chunk_coord.z * 1664525)
	rng.seed = (world_seed ^ coord_hash ^ "wildlife_chance".hash()) & 0x7FFFFFFFFFFFFFFF
	var chance: float = _OCEAN_SPAWN_CHANCE if biome == _OCEAN_BIOME else SPAWN_CHANCE_PER_CHUNK
	return rng.randf() < chance


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

	# Ocean chunks place MORE creatures than the (biome-agnostic) caller count so the
	# underwater world has real schools of life — the caller's spawn_count_for_chunk has no
	# biome, so the ocean bump lives here. Land uses the caller count unchanged. The
	# _MIN_SPAWN_DIST_FROM_ORIGIN skip below may still drop some near the world origin.
	var place_count: int = count * _OCEAN_COUNT_MULT if is_ocean else count

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
