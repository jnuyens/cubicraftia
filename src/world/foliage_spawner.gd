# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# foliage_spawner.gd — Chunk-load flower/foliage decoration helper (static methods only).
#
# Called by main_scene._on_chunk_loaded() when a terrain chunk enters the VoxelViewer
# streaming radius. Scatters decorative flower.glb MeshInstance3D instances on grass
# and jungle_grass surface cells at low density. Purely visual — no physics, no items.
#
# Design (mirrors strawberry_spawner.gd pattern):
#   - GRASSLAND_FOREST and JUNGLE biome chunks get flowers.
#   - 25% chance per chunk to spawn any flowers (SPAWN_CHANCE_PER_CHUNK).
#   - 1–4 flowers if the chance roll succeeds (FLOWERS_PER_CHUNK_MAX).
#   - Positions are deterministic by (chunk_coord, world_seed).
#   - Flowers are purely decorative Node3D children of main_scene — not pickable,
#     not persistent. Re-created on each session's chunk-load. No WorldSave metadata.
#
# Thread safety: static methods only; no global state. Deterministic RNG via
# RandomNumberGenerator seeded from chunk coord + world_seed (same Knuth mix as
# strawberry_spawner).

class_name FoliageSpawner
extends RefCounted

# ─── Constants ────────────────────────────────────────────────────────────────

## Maximum number of flowers to spawn in a single chunk when the chance roll succeeds.
const FLOWERS_PER_CHUNK_MAX: int = 4

## Per-chunk probability of spawning any flowers (0..1).
const SPAWN_CHANCE_PER_CHUNK: float = 0.25

## Margin (in terrain metres) from chunk edges for spawn-position sampling.
const CHUNK_EDGE_MARGIN_M: float = 1.5

# ─── Public static API ────────────────────────────────────────────────────────

## Returns true if the given chunk should spawn flowers on this chunk-load.
##
## Gates:
##   1. Biome must be GRASSLAND_FOREST or JUNGLE.
##   2. Per-chunk chance roll (deterministic) must succeed.
##
## @param chunk_coord  Chunk coordinate (16 m per side).
## @param biome        BiomeMap.Biome value for this chunk.
## @param world_seed   The world seed for deterministic sampling.
## @return             true if flowers should spawn in this chunk.
static func should_spawn_in_chunk(chunk_coord: Vector3i, biome: int, world_seed: int) -> bool:
	# Gate 1: only grass/jungle biomes.
	if biome != BiomeMap.Biome.GRASSLAND_FOREST and biome != BiomeMap.Biome.JUNGLE:
		return false

	# Gate 2: deterministic per-chunk chance roll.
	var rng := RandomNumberGenerator.new()
	var coord_hash: int = (chunk_coord.x * 2654435761) ^ (chunk_coord.y * 1013904223) \
		^ (chunk_coord.z * 1664525)
	rng.seed = (world_seed ^ coord_hash ^ "foliage_chance".hash()) & 0x7FFFFFFFFFFFFFFF
	return rng.randf() < SPAWN_CHANCE_PER_CHUNK


## Returns the number of flowers to spawn for this chunk (0 = no spawn).
##
## @param chunk_coord  The chunk coordinate being loaded.
## @param world_seed   The world seed for deterministic sampling.
## @return             0 or 1–FLOWERS_PER_CHUNK_MAX.
static func spawn_count_for_chunk(chunk_coord: Vector3i, world_seed: int) -> int:
	var rng := RandomNumberGenerator.new()
	var coord_hash: int = (chunk_coord.x * 2654435761) ^ (chunk_coord.y * 1013904223) \
		^ (chunk_coord.z * 1664525)
	rng.seed = (world_seed ^ coord_hash ^ "foliage_count".hash()) & 0x7FFFFFFFFFFFFFFF
	return rng.randi_range(1, FLOWERS_PER_CHUNK_MAX)


## Pick up to `count` spawn positions within the given chunk.
##
## Positions have X and Z within the chunk bounds (with CHUNK_EDGE_MARGIN_M inset).
## Y is always 0.0 — the caller must surface-correct Y before placing the node.
##
## @param chunk_coord  The chunk coordinate (16 m per side; origin at chunk_coord * 16).
## @param count        Number of positions to generate (1–FLOWERS_PER_CHUNK_MAX).
## @param world_seed   The world seed for deterministic sampling.
## @return             Array of Vector3 positions (Y = 0.0, needs surface correction).
static func pick_spawn_positions(chunk_coord: Vector3i, count: int,
		world_seed: int) -> Array:
	var positions: Array = []
	var rng := RandomNumberGenerator.new()
	var coord_hash: int = (chunk_coord.x * 2654435761) ^ (chunk_coord.y * 1013904223) \
		^ (chunk_coord.z * 1664525)
	rng.seed = (world_seed ^ coord_hash ^ "foliage_positions".hash()) & 0x7FFFFFFFFFFFFFFF
	for _i: int in range(count):
		var chunk_origin_x: float = chunk_coord.x * 16.0
		var chunk_origin_z: float = chunk_coord.z * 16.0
		var x: float = chunk_origin_x + rng.randf_range(CHUNK_EDGE_MARGIN_M, 16.0 - CHUNK_EDGE_MARGIN_M)
		var z: float = chunk_origin_z + rng.randf_range(CHUNK_EDGE_MARGIN_M, 16.0 - CHUNK_EDGE_MARGIN_M)
		positions.append(Vector3(x, 0.0, z))  # Y filled in by main_scene caller
	return positions
