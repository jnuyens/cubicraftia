# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# crop_spawner.gd — Per-chunk harvestable-crop spawn helper (static methods only).
#
# Scatters wheat and sugar_cane as harvestable Crop entities, mirroring
# strawberry_spawner / foliage_spawner:
#   - wheat      → GRASSLAND_FOREST + SAVANNAH (open grassy fields)
#   - sugar_cane → JUNGLE (wet, near water)
#   - ~18% chance per eligible chunk, 1–3 plants when it succeeds.
#   - Deterministic by (chunk_coord, world_seed).
#
# References:
#   src/world/strawberry_spawner.gd — pattern source
#   src/world/biome_map.gd          — BiomeMap.Biome enum
#   src/world/crop.gd               — the entity spawned per result

class_name CropSpawner
extends RefCounted

## Maximum crops per chunk when the chance roll succeeds.
const CROPS_PER_CHUNK_MAX: int = 3

## Per-chunk probability of spawning any crops in an eligible biome.
const SPAWN_CHANCE_PER_CHUNK: float = 0.18

## Margin (terrain metres) from chunk edges for spawn sampling.
const CHUNK_EDGE_MARGIN_M: float = 2.0

## Biome (BiomeMap.Biome int) → crop kind. Biomes absent here grow no crops.
const _BIOME_CROP: Dictionary = {
	0: "wheat",        # GRASSLAND_FOREST
	4: "wheat",        # SAVANNAH
	3: "sugar_cane",   # JUNGLE
}


## True if the given chunk/biome should spawn crops this load (biome gate + chance roll).
static func should_spawn_in_chunk(chunk_coord: Vector3i, biome: int, world_seed: int) -> bool:
	if not _BIOME_CROP.has(biome):
		return false
	var rng := RandomNumberGenerator.new()
	var coord_hash: int = (chunk_coord.x * 2654435761) ^ (chunk_coord.z * 1664525)
	rng.seed = (world_seed ^ coord_hash ^ "crop_chance".hash()) & 0x7FFFFFFFFFFFFFFF
	return rng.randf() < SPAWN_CHANCE_PER_CHUNK


## Number of crops to spawn for this chunk (1..CROPS_PER_CHUNK_MAX).
static func spawn_count_for_chunk(chunk_coord: Vector3i, world_seed: int) -> int:
	var rng := RandomNumberGenerator.new()
	var coord_hash: int = (chunk_coord.x * 2654435761) ^ (chunk_coord.z * 1664525)
	rng.seed = (world_seed ^ coord_hash ^ "crop_count".hash()) & 0x7FFFFFFFFFFFFFFF
	return rng.randi_range(1, CROPS_PER_CHUNK_MAX)


## Pick crop spawn entries for a chunk. Returns Array[Dictionary] {"kind": String, "pos": Vector3}
## with Y = 0.0 (caller surface-corrects). Kind is the biome's crop.
static func pick_spawn_entries(chunk_coord: Vector3i, count: int, biome: int,
		world_seed: int) -> Array:
	var entries: Array = []
	var kind: String = _BIOME_CROP.get(biome, "")
	if kind.is_empty():
		return entries
	var rng := RandomNumberGenerator.new()
	var coord_hash: int = (chunk_coord.x * 2654435761) ^ (chunk_coord.z * 1664525)
	rng.seed = (world_seed ^ coord_hash ^ "crop_positions".hash()) & 0x7FFFFFFFFFFFFFFF
	for _i: int in range(count):
		var x: float = chunk_coord.x * 16.0 + rng.randf_range(CHUNK_EDGE_MARGIN_M, 16.0 - CHUNK_EDGE_MARGIN_M)
		var z: float = chunk_coord.z * 16.0 + rng.randf_range(CHUNK_EDGE_MARGIN_M, 16.0 - CHUNK_EDGE_MARGIN_M)
		entries.append({"kind": kind, "pos": Vector3(x, 0.0, z)})
	return entries
