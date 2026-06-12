# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# structure_spawner.gd — Per-chunk biome-landmark spawn helper (static methods only).
#
# Scatters the art-structures buildings RARELY across the world, one biome-appropriate
# building at most per eligible chunk. Mirrors crop_spawner / wildlife_spawner.
#
# Biome assignment (curated from the art-structures set):
#   GRASSLAND_FOREST : cottages, windmill, blacksmith, wooden bridge
#   DESERT           : desert ruins / treasure rooms
#   SNOW             : stone keep + gatehouse, stone house, ice castle, IGLOO
#   JUNGLE           : grey castles, overgrown ruins, mossy arch
#   SAVANNAH         : market stall, watchtower, tent, lookout tower
#   OCEAN            : lighthouse, SHIPWRECK + UNDERWATER RUIN (below sea level),
#                      SANDCASTLE (on the beach / sand-water edge)
#
# QA #4 (wrong-biome structures): the desert/jungle/ocean lists previously held the
# MULTI-OBJECT source GLBs structure_3_00/3_01/3_02 — each baked a sandcastle, an
# underwater ruin, a shipwreck and an igloo into one mesh, so a shipwreck/igloo/ruin
# showed up in the desert. Those three sources are now SPLIT into individual landmarks
# (structure_sandcastle / _underwater_ruin / _shipwreck / _igloo) and each is placed in
# its correct biome below. structure_3_03 / 3_04 (the stone treasure-room ruins) remain
# valid desert structures.
#
# References:
#   src/world/crop_spawner.gd     — pattern source
#   src/world/world_structure.gd  — the entity spawned per result

class_name StructureSpawner
extends RefCounted

## Per-chunk probability of spawning a structure in an eligible biome. Very low — these are
## rare landmarks, not common props.
const SPAWN_CHANCE_PER_CHUNK: float = 0.011

## Don't spawn structures within this many metres of the world origin (keeps the spawn area
## clear of big buildings on top of the starter chest/bed).
const _MIN_DIST_FROM_ORIGIN: float = 40.0

## Placement type per structure id, read by main_scene._eval_structure_chunk to decide HOW to
## ground it. Ids not listed default to "land" (sit on the dry surface, above sea level).
##   "land"       — on the dry surface (default).
##   "beach"      — at the sand/water edge: ground near sea level, just above the waterline.
##   "underwater" — on the seabed, BELOW sea level (the chunk surface must be under water).
const _PLACEMENT: Dictionary = {
	"structure_sandcastle":      "beach",
	"structure_underwater_ruin": "underwater",
	"structure_shipwreck":       "underwater",
}

## Biome (BiomeMap.Biome int) → list of structure model ids (file names in structures/).
const _BIOME_STRUCTURES: Dictionary = {
	0: ["structure_1_00", "structure_1_01", "structure_1_02", "structure_1_06", "structure_1_08"],  # GRASSLAND
	1: ["structure_3_04", "structure_3_03"],                                                         # DESERT (treasure-room ruins)
	2: ["structure_1_04", "structure_2_04", "structure_2_06", "structure_ice_castle", "structure_igloo"],  # SNOW (+ ice castle + igloo)
	3: ["structure_2_03", "structure_2_05", "structure_2_02"],                                       # JUNGLE (grey castles + overgrown ruin)
	4: ["structure_1_05", "structure_2_00", "structure_2_01", "structure_1_07"],                     # SAVANNAH
	5: ["structure_1_03", "structure_shipwreck", "structure_underwater_ruin", "structure_sandcastle"],  # OCEAN
}


## Placement type for a structure id ("land" | "beach" | "underwater"). Used by main_scene to
## ground underwater / beach structures correctly (QA #4).
static func placement_for(id: String) -> String:
	return _PLACEMENT.get(id, "land")


## True if the chunk/biome should spawn a structure this load (biome gate + rare roll +
## origin-distance gate).
static func should_spawn_in_chunk(chunk_coord: Vector3i, biome: int, world_seed: int) -> bool:
	if not _BIOME_STRUCTURES.has(biome):
		return false
	# Keep the spawn area clear.
	var cx: float = (chunk_coord.x + 0.5) * 16.0
	var cz: float = (chunk_coord.z + 0.5) * 16.0
	if Vector2(cx, cz).length() < _MIN_DIST_FROM_ORIGIN:
		return false
	var rng := RandomNumberGenerator.new()
	var coord_hash: int = (chunk_coord.x * 2654435761) ^ (chunk_coord.z * 1664525)
	rng.seed = (world_seed ^ coord_hash ^ "structure_chance".hash()) & 0x7FFFFFFFFFFFFFFF
	return rng.randf() < SPAWN_CHANCE_PER_CHUNK


## Pick a single structure id + position for the chunk (centre-ish, surface-corrected by
## the caller). Returns {} if the biome has no structures.
static func pick_structure(chunk_coord: Vector3i, biome: int, world_seed: int) -> Dictionary:
	var list: Array = _BIOME_STRUCTURES.get(biome, [])
	if list.is_empty():
		return {}
	var rng := RandomNumberGenerator.new()
	var coord_hash: int = (chunk_coord.x * 2654435761) ^ (chunk_coord.z * 1664525)
	rng.seed = (world_seed ^ coord_hash ^ "structure_pick".hash()) & 0x7FFFFFFFFFFFFFFF
	var id: String = list[rng.randi() % list.size()]
	# Place near the chunk centre with a little jitter.
	var x: float = chunk_coord.x * 16.0 + rng.randf_range(5.0, 11.0)
	var z: float = chunk_coord.z * 16.0 + rng.randf_range(5.0, 11.0)
	return {"id": id, "pos": Vector3(x, 0.0, z)}
