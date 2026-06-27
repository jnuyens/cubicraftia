# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# biome_map.gd — BiomeMap class: temperature × moisture FastNoiseLite composition
# → Whittaker-classified Biome enum value.
#
# Design decisions:
#   - Determinism: same world_seed produces bit-identical biome IDs across runs
#     and machines (DOCS.md §2.1, Phase 4 multiplayer pre-req).
#   - Thread safety: FastNoiseLite is immutable after _init(); get_noise_2d() is
#     pure and safe for godot_voxel worker threads. NEVER call set_* after _init().
#     (02-PATTERNS.md §"src/world/biome_map.gd" lines 480-486)
#   - Low frequency (0.002): biomes span many chunks; transitions feel continental.
#   - Decorrelated seeds: temperature seed = world_seed XOR 0x01;
#     moisture seed = world_seed XOR 0x02 (02-RESEARCH.md Pattern 1 line 473).
#   - blend_weight in sample() supports the 5m ambient-tint blend (D-05 in
#     02-CONTEXT.md): biome ID is a hard switch; visual tint blends over 5 cells.
#
# References:
#   DOCS.md §2.1 — 6 v1 biomes (grasslands+forest, desert, snow, jungle, savannah, ocean)
#   02-CONTEXT.md D-04, D-05 — strong biome identity, ~5m narrow blend
#   02-RESEARCH.md §"Pattern 1: Biome compositor" lines 449-503
#   02-PATTERNS.md §"src/world/biome_map.gd" (analog: terrain_generator.gd noise pattern)

class_name BiomeMap
extends RefCounted

# ─── Biome enum ──────────────────────────────────────────────────────────────

## Six v1 biomes locked per DOCS.md §2.1.
## Order and values are stable — stored in chunk metadata and network packets.
enum Biome {
	GRASSLAND_FOREST = 0,
	DESERT           = 1,
	SNOW             = 2,
	JUNGLE           = 3,
	SAVANNAH         = 4,
	OCEAN            = 5,
	MOUNTAIN         = 6,
}

# ─── Tuning ───────────────────────────────────────────────────────────────────

## Frequency of BOTH the temperature and moisture noise channels. Lower = larger, more
## continental biomes (you travel further between them); higher = smaller, patchier biomes.
## Wavelength ≈ 1 / frequency metres. Lowered 0.002 → 0.001 → 0.0005 (v1.1 QA) to enlarge
## every biome's surface area further — keep test_biome_distribution's sample area in sync
## (its grid was widened to 2000 m so it still contains all 6 biomes).
const BIOME_NOISE_FREQUENCY: float = 0.0005

## Frequency of the ELEVATION ("continentalness") noise channel. Lower than the biome
## frequency so mountain ranges are large continental features that span several normal
## biomes. Wavelength ≈ 1 / frequency metres (~3300 m at 0.0003) — you travel a good while
## between mountain ranges, and each range is wide enough to walk through.
const ELEVATION_NOISE_FREQUENCY: float = 0.0003

## Elevation threshold (FastNoiseLite output in [-1, 1]) above which a column is MOUNTAIN.
## ~0.42 makes mountains an occasional high-ground feature (roughly the top fraction of the
## elevation noise) rather than carpeting the world. Kept public so the height generators can
## read the SAME threshold and compute a smooth blend weight at the mountain edge (no seam).
const MOUNTAIN_ELEVATION_THRESHOLD: float = 0.42

## Width (in elevation-noise units) of the blend band just below the mountain threshold. Columns
## with elevation in [threshold - band, threshold] are still classified as their normal biome, but
## the height generator ramps their height up toward mountain height across this band so the
## mountain rises smoothly out of the surrounding terrain instead of as a vertical wall at the edge.
const MOUNTAIN_BLEND_BAND: float = 0.18

# ─── Private state ────────────────────────────────────────────────────────────

## Temperature noise instance. Immutable after _init(). Thread-safe.
var _temperature_noise: FastNoiseLite

## Moisture noise instance. Immutable after _init(). Thread-safe.
var _moisture_noise: FastNoiseLite

## Elevation / continentalness noise instance. Immutable after _init(). Thread-safe.
## Drives MOUNTAIN classification and the mountain-height ramp.
var _elevation_noise: FastNoiseLite

## World seed driving both noise channels.
var _world_seed: int

# ─── Lifecycle ────────────────────────────────────────────────────────────────

## Construct BiomeMap with the given world seed.
## Both noise instances are built here; no mutation after _init().
func _init(world_seed: int = 1234) -> void:
	_world_seed = world_seed
	_rebuild_noises()


## Build both FastNoiseLite instances from _world_seed.
## Called only from _init(); results are read-only thereafter.
func _rebuild_noises() -> void:
	# Temperature noise — Simplex FBM at very low frequency (biome scale).
	_temperature_noise = FastNoiseLite.new()
	_temperature_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_temperature_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_temperature_noise.fractal_octaves = 4
	_temperature_noise.fractal_lacunarity = 2.0
	_temperature_noise.fractal_gain = 0.5
	_temperature_noise.frequency = BIOME_NOISE_FREQUENCY
	_temperature_noise.seed = _world_seed ^ 0x01  # decorrelated XOR salt

	# Moisture noise — same shape, independent seed.
	_moisture_noise = FastNoiseLite.new()
	_moisture_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_moisture_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_moisture_noise.fractal_octaves = 4
	_moisture_noise.fractal_lacunarity = 2.0
	_moisture_noise.fractal_gain = 0.5
	_moisture_noise.frequency = BIOME_NOISE_FREQUENCY
	_moisture_noise.seed = _world_seed ^ 0x02  # decorrelated XOR salt

	# Elevation / continentalness noise — independent seed, lower frequency (bigger features).
	_elevation_noise = FastNoiseLite.new()
	_elevation_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_elevation_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_elevation_noise.fractal_octaves = 4
	_elevation_noise.fractal_lacunarity = 2.0
	_elevation_noise.fractal_gain = 0.5
	_elevation_noise.frequency = ELEVATION_NOISE_FREQUENCY
	_elevation_noise.seed = _world_seed ^ 0x03  # decorrelated XOR salt

# ─── Public API ───────────────────────────────────────────────────────────────

## Sample temperature, moisture, and biome at world position (x, z).
## Returns a Dictionary: {"biome": Biome, "temperature": float, "moisture": float,
## "blend_weight": float}.
##
## blend_weight is in [0.0, 1.0]: the fraction of the local cell "dominated" by
## this biome. Computed from 4 neighbour samples 5 m apart — used by main_scene
## for the D-05 ambient-tint blend. Expensive; callers that only need biome_at()
## should use that cheaper method instead.
##
## Thread-safe: read-only noise access.
func sample(x: float, z: float) -> Dictionary:
	var t: float = _temperature_noise.get_noise_2d(x, z)
	var m: float = _moisture_noise.get_noise_2d(x, z)
	var e: float = _elevation_noise.get_noise_2d(x, z)
	var biome: Biome = classify_with_elevation(t, m, e)

	# Compute blend_weight: sample 4 neighbours at ±2.5 m (half of the 5m blend zone).
	var same_count: int = 1  # centre cell counts as 1
	var offsets: Array[Vector2] = [Vector2(2.5, 0.0), Vector2(-2.5, 0.0),
	                               Vector2(0.0, 2.5), Vector2(0.0, -2.5)]
	for off in offsets:
		var nt: float = _temperature_noise.get_noise_2d(x + off.x, z + off.y)
		var nm: float = _moisture_noise.get_noise_2d(x + off.x, z + off.y)
		var ne: float = _elevation_noise.get_noise_2d(x + off.x, z + off.y)
		if classify_with_elevation(nt, nm, ne) == biome:
			same_count += 1
	var blend_weight: float = float(same_count) / 5.0  # 5 = centre + 4 neighbours

	return {
		"biome": biome,
		"temperature": t,
		"moisture": m,
		"blend_weight": blend_weight,
	}


## Return the biome ID at world position (x, z).
## Cheaper than sample() — no blend computation.
## Thread-safe: read-only noise access.
func biome_at(x: float, z: float) -> Biome:
	var t: float = _temperature_noise.get_noise_2d(x, z)
	var m: float = _moisture_noise.get_noise_2d(x, z)
	var e: float = _elevation_noise.get_noise_2d(x, z)
	return classify_with_elevation(t, m, e)


## Raw elevation ("continentalness") noise value at (x, z), in [-1, 1].
## Public so the height generators can read the SAME elevation the classifier used and compute
## a smooth mountain-height ramp / blend weight without re-deriving the noise config.
## Thread-safe: read-only noise access.
func elevation_at(x: float, z: float) -> float:
	return _elevation_noise.get_noise_2d(x, z)


## Mountain blend weight in [0, 1] for the column's elevation value `e`:
##   0.0  well below the blend band — pure normal-biome height
##   →1.0 ramps up across [threshold - band, threshold]
##   1.0  at/above the mountain threshold — full mountain height
## The height generators multiply the extra mountain height by this so the mountain rises
## smoothly out of neighbouring terrain (no vertical seam at the biome border).
func mountain_weight(e: float) -> float:
	var lo: float = MOUNTAIN_ELEVATION_THRESHOLD - MOUNTAIN_BLEND_BAND
	if e <= lo:
		return 0.0
	if e >= MOUNTAIN_ELEVATION_THRESHOLD:
		return 1.0
	return (e - lo) / MOUNTAIN_BLEND_BAND


## Classification including the elevation channel. High-elevation LAND columns become MOUNTAIN;
## OCEAN columns are left untouched (mountains don't sprout mid-sea — keeps oceans intact).
## All non-mountain results are identical to classify(), so existing biomes are NOT reclassified.
func classify_with_elevation(t: float, m: float, e: float) -> Biome:
	var base: Biome = classify(t, m)
	if base == Biome.OCEAN:
		return base
	if e >= MOUNTAIN_ELEVATION_THRESHOLD:
		return Biome.MOUNTAIN
	return base


## Whittaker-style biome classification from temperature and moisture values.
## Both inputs are in [-1, 1] (FastNoiseLite output range).
##
## Thresholds tuned per biome briefs (02-RESEARCH.md Pattern 1 lines 489-497):
##   OCEAN:            very wet (m > 0.5) OR cold+wet (t < -0.4 and m > 0.3)
##   SNOW:             cold (t < -0.3)
##   DESERT:           hot + very dry (t > 0.4 and m < -0.2)
##   JUNGLE:           warm + wet (t > 0.2 and m > 0.0)
##   SAVANNAH:         warm + dryish (t > 0.0 and m < 0.0)
##   GRASSLAND_FOREST: default fallback
func classify(t: float, m: float) -> Biome:
	# Ocean: cold+wet polar ocean. Broadened (t<-0.4→-0.35, m>0.3→0.2) so cold coasts read
	# as sea, enlarging the OCEAN footprint (QA #7 — bigger oceans).
	if m > 0.2 and t < -0.35:
		return Biome.OCEAN
	# Ocean: wet = sea (any temperature). Threshold lowered 0.5 → 0.35 to roughly double the
	# OCEAN surface area (QA #7). Kept above JUNGLE's wet band (the jungle corner case has
	# m=0.2, still < 0.35) so the Whittaker corner tests and all-6-biomes distribution hold.
	if m > 0.35:
		return Biome.OCEAN
	# Snow: cold (not cold+wet — ocean caught that above)
	if t < -0.3:
		return Biome.SNOW
	# Desert: hot + very dry
	if t > 0.4 and m < -0.2:
		return Biome.DESERT
	# Jungle: warm-to-hot + wet
	if t > 0.2 and m > 0.0:
		return Biome.JUNGLE
	# Savannah: warm + dryish
	if t > 0.0 and m < 0.0:
		return Biome.SAVANNAH
	# Default: temperate grassland + forest
	return Biome.GRASSLAND_FOREST
