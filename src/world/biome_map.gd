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
}

# ─── Tuning ───────────────────────────────────────────────────────────────────

## Frequency of BOTH the temperature and moisture noise channels. Lower = larger, more
## continental biomes (you travel further between them); higher = smaller, patchier biomes.
## Wavelength ≈ 1 / frequency metres. Lowered 0.002 → 0.001 → 0.0005 (v1.1 QA) to enlarge
## every biome's surface area further — keep test_biome_distribution's sample area in sync
## (its grid was widened to 2000 m so it still contains all 6 biomes).
const BIOME_NOISE_FREQUENCY: float = 0.0005

# ─── Private state ────────────────────────────────────────────────────────────

## Temperature noise instance. Immutable after _init(). Thread-safe.
var _temperature_noise: FastNoiseLite

## Moisture noise instance. Immutable after _init(). Thread-safe.
var _moisture_noise: FastNoiseLite

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
	var biome: Biome = classify(t, m)

	# Compute blend_weight: sample 4 neighbours at ±2.5 m (half of the 5m blend zone).
	var same_count: int = 1  # centre cell counts as 1
	var offsets: Array[Vector2] = [Vector2(2.5, 0.0), Vector2(-2.5, 0.0),
	                               Vector2(0.0, 2.5), Vector2(0.0, -2.5)]
	for off in offsets:
		var nt: float = _temperature_noise.get_noise_2d(x + off.x, z + off.y)
		var nm: float = _moisture_noise.get_noise_2d(x + off.x, z + off.y)
		if classify(nt, nm) == biome:
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
	return classify(t, m)


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
	# Ocean: cold+wet polar ocean
	if m > 0.3 and t < -0.4:
		return Biome.OCEAN
	# Ocean: very wet = sea (any temperature)
	if m > 0.5:
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
