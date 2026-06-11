# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# strawberry_spawner.gd — Chunk-load strawberry spawn helper (static methods only).
#
# Called by main_scene._on_chunk_loaded() when a terrain chunk enters the VoxelViewer
# streaming radius. Checks per-chunk WorldSave metadata to decide whether to spawn
# strawberries, then picks deterministic positions within the chunk.
#
# Design (RESEARCH.md Pattern 5 + D-16):
#   - Only GRASSLAND_FOREST biome chunks get strawberries (D-16 "open grassy areas").
#   - 40% chance per chunk to spawn any strawberries (SPAWN_CHANCE_PER_CHUNK).
#   - 1–3 strawberries if the chance roll succeeds (STRAWBERRIES_PER_CHUNK_MAX).
#   - A chunk that was picked this session (last_picked_session_id == current_session_id)
#     does NOT respawn (RESEARCH Pitfall 10).
#   - Cross-session: respawn IS allowed — D-16 "doesn't repopulate within one session".
#
# Strawberries spawn in BOTH sandbox and survival modes (D-16 + DOCS §2 — overworld
# collectables; super-heal is survival-relevant, but the entity spawns regardless of mode).
#
# Threat mitigations:
#   T-03-11-STR-01: spawn_count_for_chunk returns 0 before any metadata is written;
#                   metadata is written only when the player picks a strawberry (Plan 03-09).
#                   Chunks that roll 0 count never write metadata.
#   Pitfall 10: last_picked_session_id check prevents within-session re-spawn.
#
# References:
#   03-CONTEXT.md D-16 — rare grassland super-heal collectables
#   03-RESEARCH.md Pattern 5 — per-chunk strawberry metadata (lines 358-364)
#   03-RESEARCH.md Pitfall 10 — last_picked_session_id semantics (lines 461-466)

class_name StrawberrySpawner
extends RefCounted

# ─── Constants ────────────────────────────────────────────────────────────────

## Maximum number of strawberries to spawn in a single chunk when the chance roll succeeds.
## v1.1 QA: 3→2 — strawberries were too common in the world.
const STRAWBERRIES_PER_CHUNK_MAX: int = 2

## Per-chunk probability of spawning any strawberries. v1.1 QA: 0.4→0.12→0.06→0.02 — still
## too common at 0.06, so cut ~3x again. Genuinely rare (D-16 "rare super-heal").
const SPAWN_CHANCE_PER_CHUNK: float = 0.02

## Margin (in terrain metres) from chunk edges for spawn-position sampling.
## Prevents strawberries from spawning right on chunk boundaries.
const CHUNK_EDGE_MARGIN_M: float = 2.0

# ─── Public static API ────────────────────────────────────────────────────────

## Returns true if the given chunk should spawn strawberries on this chunk-load.
##
## Gates:
##   1. Biome must be GRASSLAND_FOREST (BiomeMap.Biome enum).
##   2. Per-chunk WorldSave metadata must be absent OR from a prior session
##      (last_picked_session_id != current_session_id → allow respawn).
##
## @param chunk_coord        Chunk coordinate (16 m per side).
## @param biome              BiomeMap.Biome value for this chunk.
## @param current_session_id The current world session ID string.
## @return                   true if strawberries should spawn in this chunk.
static func should_spawn_in_chunk(chunk_coord: Vector3i, biome: int,
		current_session_id: String) -> bool:
	# Gate 1: grassland biome only (D-16).
	if biome != BiomeMap.Biome.GRASSLAND_FOREST:
		return false

	# Gate 2: check per-chunk session metadata.
	var key: String = "strawberries:%d_%d_%d" % [chunk_coord.x, chunk_coord.y, chunk_coord.z]
	var raw: Variant = WorldSave.get_world_meta(key)
	if raw == null:
		return true  # Chunk never visited → always eligible for spawn.

	# Decode the persisted blob (written by Strawberry._record_picked, Plan 03-09).
	if raw is PackedByteArray:
		var decoded: Variant = bytes_to_var(raw as PackedByteArray)
		if decoded is Dictionary:
			var last_sid: String = str(decoded.get("last_picked_session_id", ""))
			if last_sid == current_session_id:
				return false  # Already picked this session → no respawn (Pitfall 10).
	# Prior session or unrecognised format → allow spawn.
	return true


## Returns the number of strawberries to spawn for this chunk.
##
## Uses a deterministic RNG seeded by (world_seed XOR chunk_coord hash XOR string hash)
## so the same chunk always rolls the same result for a given world seed. Returns 0 if
## the chance roll fails (60% of the time).
##
## @param chunk_coord  The chunk coordinate being loaded.
## @param world_seed   The world seed from WorldSave.
## @return             0 (no spawn) or 1–STRAWBERRIES_PER_CHUNK_MAX.
static func spawn_count_for_chunk(chunk_coord: Vector3i, world_seed: int) -> int:
	var rng := RandomNumberGenerator.new()
	# Deterministic seed: world_seed XOR coord-mixed hash XOR "strawberries" string hash.
	# Uses Knuth multiplicative mixing for the coordinate components (same as StructurePlacer
	# and LootRoller — 03-STATE.md `knuth-hash-mixing` decision).
	var coord_hash: int = (chunk_coord.x * 2654435761) ^ (chunk_coord.y * 1013904223) \
		^ (chunk_coord.z * 1664525)
	rng.seed = (world_seed ^ coord_hash ^ "strawberries".hash()) & 0x7FFFFFFFFFFFFFFF
	if rng.randf() > SPAWN_CHANCE_PER_CHUNK:
		return 0
	return rng.randi_range(1, STRAWBERRIES_PER_CHUNK_MAX)


## Pick up to `count` spawn positions within the given chunk.
##
## Positions have X and Z within the chunk bounds (with CHUNK_EDGE_MARGIN_M inset).
## Y is always 0.0 — the caller (main_scene._on_chunk_loaded) must raycast or sample
## the terrain surface to correct the Y before placing the Strawberry node.
##
## @param chunk_coord  The chunk coordinate (16 m per side; origin at chunk_coord * 16).
## @param count        Number of positions to generate (1–STRAWBERRIES_PER_CHUNK_MAX).
## @param world_seed   The world seed for deterministic sampling.
## @return             Array of Vector3 positions (Y = 0.0, needs surface correction).
static func pick_spawn_positions(chunk_coord: Vector3i, count: int,
		world_seed: int) -> Array:
	var positions: Array = []
	var rng := RandomNumberGenerator.new()
	# Independent seed from spawn_count_for_chunk (different salt string).
	var coord_hash: int = (chunk_coord.x * 2654435761) ^ (chunk_coord.y * 1013904223) \
		^ (chunk_coord.z * 1664525)
	rng.seed = (world_seed ^ coord_hash ^ "strawberry_positions".hash()) & 0x7FFFFFFFFFFFFFFF
	for _i: int in range(count):
		var chunk_origin_x: float = chunk_coord.x * 16.0
		var chunk_origin_z: float = chunk_coord.z * 16.0
		var x: float = chunk_origin_x + rng.randf_range(CHUNK_EDGE_MARGIN_M, 16.0 - CHUNK_EDGE_MARGIN_M)
		var z: float = chunk_origin_z + rng.randf_range(CHUNK_EDGE_MARGIN_M, 16.0 - CHUNK_EDGE_MARGIN_M)
		positions.append(Vector3(x, 0.0, z))  # Y filled in by main_scene caller
	return positions
