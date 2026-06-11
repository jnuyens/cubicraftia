# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# ocean_decor_spawner.gd — Chunk-load ocean-floor decoration helper (static methods only).
#
# Called by main_scene._on_chunk_loaded() (via the deferred decoration dispatch) when an
# OCEAN-biome terrain chunk streams in. Scatters static coral / kelp / shell decor meshes on
# the seabed (below the water surface). Purely visual — no physics, no items, not persistent.
#
# Design (mirrors foliage_spawner.gd / wildlife_spawner.gd):
#   - OCEAN biome chunks only (biome int 5).
#   - DECOR_CHANCE_PER_CHUNK chance per chunk to spawn any decor.
#   - 1..DECOR_PER_CHUNK_MAX clumps if the chance roll succeeds.
#   - Kind + position are deterministic by (chunk_coord, world_seed) — same Knuth mix as the
#     sibling spawners — so a given seed always decorates a given reef the same way.
#   - Placed on the meshed seabed (caller surface-corrects Y and rejects above-water cells), so
#     the decor sits on the ocean floor rather than floating in the water column.
#   - Mobile-cheap: the caller batches a chunk's decor into MultiMesh draw calls per kind.
#
# Thread safety: static methods only; no global state.
#
# References:
#   src/world/foliage_spawner.gd  — pattern source (MultiMesh decoration)
#   src/world/wildlife_spawner.gd — ocean biome int + deterministic RNG seeding
#   src/world/main_scene.gd       — instantiates the decor meshes per returned entry

class_name OceanDecorSpawner
extends RefCounted

# ─── Tuning ───────────────────────────────────────────────────────────────────

## BiomeMap.Biome.OCEAN int value. Only ocean chunks get seabed decor.
const _OCEAN_BIOME: int = 5

## Maximum number of decor clumps in a single ocean chunk when the chance roll succeeds.
const DECOR_PER_CHUNK_MAX: int = 5

## Per-chunk probability of spawning any seabed decor (0..1). High like the ocean wildlife
## chance so the underwater world reads as a living reef, not bare sand.
const DECOR_CHANCE_PER_CHUNK: float = 0.85

## Margin (in terrain metres) from chunk edges for spawn-position sampling.
const CHUNK_EDGE_MARGIN_M: float = 2.0

## Minimum distance (m) a decor clump must be from the world origin, so the seabed under
## the spawn point / starter chest stays clear (mirrors wildlife_spawner).
const _MIN_SPAWN_DIST_FROM_ORIGIN: float = 16.0

## Decor mesh kinds (resolved to res://assets/meshes/decor/<kind>.glb by the caller). A mix
## of tall plants and low floor critters so a reef reads varied; weighted toward plants.
const _DECOR_KINDS: Array = [
	"kelp_strand", "kelp_strand",
	"seaweed_bush", "seaweed_bush",
	"coral_branch", "coral_branch",
	"coral_bush",
	"coral_tall",
	"sea_anemone",
	"clam_shell",
	"sea_star",
	"sea_urchin",
]

# ─── Public static API ────────────────────────────────────────────────────────

## Returns true if the given chunk should spawn ocean-floor decor on this chunk-load.
##
## @param chunk_coord  Chunk coordinate (16 m per side).
## @param biome        BiomeMap.Biome int value for this chunk.
## @param world_seed   The world seed for deterministic sampling.
static func should_spawn_in_chunk(chunk_coord: Vector3i, biome: int, world_seed: int) -> bool:
	if biome != _OCEAN_BIOME:
		return false
	var rng := RandomNumberGenerator.new()
	var coord_hash: int = (chunk_coord.x * 2654435761) ^ (chunk_coord.y * 1013904223) \
		^ (chunk_coord.z * 1664525)
	rng.seed = (world_seed ^ coord_hash ^ "ocean_decor_chance".hash()) & 0x7FFFFFFFFFFFFFFF
	return rng.randf() < DECOR_CHANCE_PER_CHUNK


## Returns the number of decor clumps to spawn for this chunk (1..DECOR_PER_CHUNK_MAX).
static func spawn_count_for_chunk(chunk_coord: Vector3i, world_seed: int) -> int:
	var rng := RandomNumberGenerator.new()
	var coord_hash: int = (chunk_coord.x * 2654435761) ^ (chunk_coord.y * 1013904223) \
		^ (chunk_coord.z * 1664525)
	rng.seed = (world_seed ^ coord_hash ^ "ocean_decor_count".hash()) & 0x7FFFFFFFFFFFFFFF
	return rng.randi_range(1, DECOR_PER_CHUNK_MAX)


## Pick decor kinds + positions for a chunk.
##
## Returns an Array of Dictionaries, each { "kind": String, "pos": Vector3 } with Y = 0.0
## (the caller surface-corrects Y to the seabed and rejects above-water cells).
##
## @param chunk_coord  The chunk coordinate (16 m per side; origin = chunk_coord * 16).
## @param count        Number of clumps to place.
## @param world_seed   The world seed for deterministic sampling.
static func pick_spawn_entries(chunk_coord: Vector3i, count: int, world_seed: int) -> Array:
	var entries: Array = []
	var rng := RandomNumberGenerator.new()
	var coord_hash: int = (chunk_coord.x * 2654435761) ^ (chunk_coord.y * 1013904223) \
		^ (chunk_coord.z * 1664525)
	rng.seed = (world_seed ^ coord_hash ^ "ocean_decor_positions".hash()) & 0x7FFFFFFFFFFFFFFF

	for _i: int in range(count):
		var chunk_origin_x: float = chunk_coord.x * 16.0
		var chunk_origin_z: float = chunk_coord.z * 16.0
		var x: float = chunk_origin_x + rng.randf_range(CHUNK_EDGE_MARGIN_M, 16.0 - CHUNK_EDGE_MARGIN_M)
		var z: float = chunk_origin_z + rng.randf_range(CHUNK_EDGE_MARGIN_M, 16.0 - CHUNK_EDGE_MARGIN_M)
		if Vector2(x, z).length() < _MIN_SPAWN_DIST_FROM_ORIGIN:
			continue
		var kind: String = _DECOR_KINDS[rng.randi_range(0, _DECOR_KINDS.size() - 1)]
		entries.append({"kind": kind, "pos": Vector3(x, 0.0, z)})
	return entries
