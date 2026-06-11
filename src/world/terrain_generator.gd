# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# terrain_generator.gd — VoxelGeneratorScript for the six-biome procedural world.
#
# Extends VoxelGeneratorScript (provided by addons/zylann.voxel GDExtension).
# Override _generate_block to produce height-based terrain using FastNoiseLite,
# with per-column biome selection via BiomeMap.
#
# Voxel IDs (VoxelBlockyLibrary index order — must match terrain.tscn):
#   0  = air              (VoxelBlockyModelEmpty — transparent/empty)
#   1  = grass            (GRASSLAND_FOREST surface — #6BB845)
#   2  = sand             (DESERT / OCEAN seabed surface — #C9A86A)
#   3  = snow             (SNOW surface — #BFEAF5-ish white)
#   4  = stone            (deep underground, all biomes — #707A82)
#   5  = sandstone        (DESERT shallow sub-surface — #C9A86A darker)
#   6  = ice              (SNOW shallow sub-surface frozen water — #BFEAF5)
#   7  = water            (OCEAN water column — #2A7BBC 60% alpha)
#   8  = jungle_grass     (JUNGLE surface — #5CE86A vivid green)
#   9  = savannah_grass   (SAVANNAH surface — #FFB84D warm amber grass)
#   10 = wood_log         (tree-column voxel; also BrickRegistry material brick)
#   11 = dirt             (sub-surface for GRASSLAND_FOREST / JUNGLE / SAVANNAH)
#
# Design decisions (DOCS.md §2, CONTEXT.md D-01, D-04, D-05):
#   - Six biomes driven by BiomeMap (temperature × moisture noise). D-04 strong identity.
#   - 1 m terrain cubes (DOCS.md §2). Chunk size is 16³ voxels = 16 m per side.
#   - FBM noise with OpenSimplex2, 4 octaves, gentle frequency for rolling terrain.
#   - Deterministic seed via world_seed (1234 default). Thread-safe per-block generation.
#   - BiomeMap is constructed once in _init() from world_seed; never mutated.
#     Worker thread calls only read noise — no set_* calls inside _generate_block.
#
# Thread safety: FastNoiseLite in Godot 4 is immutable after configuration —
# get_noise_2d() / get_noise_3d() are pure functions safe to call from worker
# threads. Do NOT call set_* methods on the noise inside _generate_block.
# BiomeMap._temperature_noise and ._moisture_noise share the same invariant.

extends VoxelGeneratorScript

# ─── Constants ────────────────────────────────────────────────────────────────

## Voxel ID for empty air cells.
const AIR_ID: int = 0

## Voxel ID for solid grass terrain cells (GRASSLAND_FOREST surface).
const GRASS_ID: int = 1

## Voxel ID for sand (DESERT surface, OCEAN seabed).
const SAND_ID: int = 2

## Voxel ID for snow (SNOW surface).
const SNOW_ID: int = 3

## Voxel ID for stone (deep underground in all biomes).
const STONE_ID: int = 4

## Voxel ID for sandstone (DESERT shallow sub-surface).
const SANDSTONE_ID: int = 5

## Voxel ID for ice (SNOW shallow sub-surface / frozen water).
const ICE_ID: int = 6

## Voxel ID for water (OCEAN water column; non-collidable).
const WATER_ID: int = 7

## Voxel ID for jungle grass (JUNGLE surface).
const JUNGLE_GRASS_ID: int = 8

## Voxel ID for savannah grass (SAVANNAH surface).
const SAVANNAH_GRASS_ID: int = 9

## Voxel ID for wood log (tree-column voxel and material brick dual-representation).
const WOOD_LOG_ID: int = 10

## Voxel ID for dirt (sub-surface for GRASSLAND_FOREST, JUNGLE, SAVANNAH — first ~3 layers).
const DIRT_ID: int = 11

## Channel used by VoxelMesherBlocky for model IDs.
## VoxelBuffer.CHANNEL_TYPE = 0 is the TYPE channel used by blocky meshing.
const CHANNEL_TYPE: int = 0

## Number of dirt/biome-material layers below the surface before transitioning to stone.
const DIRT_LAYERS: int = 3

## Default world seed (deterministic for Phase 1; externally supplied from Plan 05+).
## Changing this property rebuilds the noise instance AND the BiomeMap.
@export var world_seed: int = 1234:
	set(v):
		world_seed = v
		if _noise != null:
			_noise.seed = world_seed
		# Rebuild BiomeMap with new seed (atomically before next _generate_block call).
		_biome_map = BiomeMap.new(world_seed)

## Terrain height amplitude in voxels (± from sea_level).
@export var height_amplitude: float = 8.0

## Sea level in voxels (centre of the height range).
@export var sea_level: int = 12

## FastNoiseLite frequency for the base terrain layer.
## 0.01 produces gently rolling hills at a scale of ~100 m per period.
## Changing this property rebuilds the noise instance.
@export var noise_frequency: float = 0.01:
	set(v):
		noise_frequency = v
		if _noise != null:
			_noise.frequency = noise_frequency

# ─── Private state ─────────────────────────────────────────────────────────

# Initialised in _init() (Resource lifecycle, not Node lifecycle).
# VoxelGeneratorScript extends Resource, not Node, so _ready() is never called.
# _init() runs when the resource is created (editor, loading, new()).
var _noise: FastNoiseLite

## BiomeMap instance seeded from world_seed. Immutable after _init().
## Thread-safe: only reads noise, never mutates it.
var _biome_map: BiomeMap

# ─── Lifecycle ────────────────────────────────────────────────────────────────

func _init() -> void:
	# Build the noise instance immediately so _generate_block() (called from a
	# godot_voxel worker thread) always has a valid _noise reference.
	_rebuild_noise()
	# Build BiomeMap with the default world_seed. If world_seed is set via the
	# property setter before _generate_block is called, BiomeMap is rebuilt.
	_biome_map = BiomeMap.new(world_seed)


func _rebuild_noise() -> void:
	_noise = FastNoiseLite.new()
	# OpenSimplex2 — closest to RESEARCH.md "TYPE_SIMPLEX (OpenSimplex2)" recommendation.
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_noise.fractal_octaves = 4
	_noise.fractal_lacunarity = 2.0
	_noise.fractal_gain = 0.5
	_noise.frequency = noise_frequency
	_noise.seed = world_seed


# ─── VoxelGeneratorScript override ────────────────────────────────────────────

## Called by godot_voxel's worker thread for each 16³ voxel chunk.
## Must be thread-safe (read-only use of _noise).
##
## Parameters:
##   out_buffer   — VoxelBuffer to fill; size is the chunk dimensions (16³ + padding)
##   origin_in_voxels — world-space voxel coordinate of the block's (0,0,0) corner
##   lod          — level-of-detail index (0 = full resolution; ignored for non-LOD terrain)
func _generate_block(out_buffer: VoxelBuffer, origin_in_voxels: Vector3i, lod: int) -> void:
	# LOD: VoxelTerrain (non-LOD variant) always calls with lod=0.
	# We still guard it to avoid incorrect generation at coarser LODs if the
	# scene is ever migrated to VoxelLodTerrain in Phase 2.
	if lod != 0:
		return

	var buffer_size: Vector3i = out_buffer.get_size()

	# Pre-fill the whole block with air to avoid stale values from earlier calls.
	# fill_area is faster than per-voxel set_voxel in C++ (avoids repeated bounds checks).
	out_buffer.fill(AIR_ID, CHANNEL_TYPE)

	# Height-map pass: for each (x, z) column, compute the grass surface height
	# and fill air above it / grass at and below it.
	for x: int in range(buffer_size.x):
		for z: int in range(buffer_size.z):
			# World-space coordinates of this column
			var world_x: float = float(origin_in_voxels.x + x)
			var world_z: float = float(origin_in_voxels.z + z)

			# Noise returns [-1, 1]; map to a voxel height around sea_level
			var noise_val: float = _noise.get_noise_2d(world_x, world_z)
			# height is the Y of the topmost solid voxel in this column
			var surface_y: int = int(noise_val * height_amplitude + float(sea_level))
			# Clamp to buffer range to avoid writing outside allocated memory
			var fill_top: int = clampi(surface_y - origin_in_voxels.y + 1, 0, buffer_size.y)

			if fill_top <= 0:
				continue  # Entire column is air in this chunk

			# Determine biome for this (x, z) column.
			# biome_at() is read-only noise access — thread-safe.
			var biome: BiomeMap.Biome = _biome_map.biome_at(world_x, world_z)
			var surface_id: int = _surface_block_for(biome)

			# Fill the column: surface block at the top; biome sub-surface below that;
			# stone deeper down; handle ocean water column above surface.
			for y: int in range(fill_top):
				var world_y: int = origin_in_voxels.y + y
				var depth_below_surface: int = surface_y - world_y

				if depth_below_surface == 0:
					# Surface layer: place biome surface block.
					out_buffer.set_voxel(surface_id, x, y, z, CHANNEL_TYPE)
				else:
					# Sub-surface: biome material then stone.
					var sub_id: int = _underground_block_for(biome, depth_below_surface)
					out_buffer.set_voxel(sub_id, x, y, z, CHANNEL_TYPE)

			# Ocean water column: fill above the seabed surface up to sea_level with water.
			if biome == BiomeMap.Biome.OCEAN:
				var water_start_y: int = surface_y + 1
				var water_end_y: int = sea_level
				for wy: int in range(water_start_y, water_end_y + 1):
					var buf_y: int = wy - origin_in_voxels.y
					if buf_y >= 0 and buf_y < buffer_size.y:
						out_buffer.set_voxel(WATER_ID, x, buf_y, z, CHANNEL_TYPE)


## Tell godot_voxel which VoxelBuffer channels this generator writes.
## CHANNEL_TYPE_BIT = 1 << 0 = 1.
func _get_used_channels_mask() -> int:
	return 1 << CHANNEL_TYPE


# ─── Biome block helpers ────────────────────────────────────────────────────

## Return the surface voxel block ID for the given biome.
## Called once per column-per-chunk from the worker thread — pure, no mutation.
func _surface_block_for(biome: BiomeMap.Biome) -> int:
	match biome:
		BiomeMap.Biome.GRASSLAND_FOREST:
			return GRASS_ID
		BiomeMap.Biome.DESERT:
			return SAND_ID
		BiomeMap.Biome.SNOW:
			return SNOW_ID
		BiomeMap.Biome.JUNGLE:
			return JUNGLE_GRASS_ID
		BiomeMap.Biome.SAVANNAH:
			return SAVANNAH_GRASS_ID
		BiomeMap.Biome.OCEAN:
			return SAND_ID  # ocean seabed surface
	return GRASS_ID  # fallback


## Return the sub-surface voxel block ID for the given biome and depth below surface.
## depth_below_surface = 1 is the first layer under the surface, 2 the next, etc.
## Called from the worker thread — pure, no mutation.
func _underground_block_for(biome: BiomeMap.Biome, depth_below_surface: int) -> int:
	match biome:
		BiomeMap.Biome.GRASSLAND_FOREST, BiomeMap.Biome.JUNGLE, BiomeMap.Biome.SAVANNAH:
			# Dirt for the first DIRT_LAYERS layers below surface; then stone.
			if depth_below_surface <= DIRT_LAYERS:
				return DIRT_ID
			return STONE_ID
		BiomeMap.Biome.DESERT:
			# Sandstone below sand surface; stone deeper.
			if depth_below_surface <= DIRT_LAYERS:
				return SANDSTONE_ID
			return STONE_ID
		BiomeMap.Biome.SNOW:
			# Ice just below snow surface (frozen ground); stone deeper.
			if depth_below_surface <= DIRT_LAYERS:
				return ICE_ID
			return STONE_ID
		BiomeMap.Biome.OCEAN:
			# Stone below ocean seabed sand.
			return STONE_ID
	return STONE_ID  # fallback
