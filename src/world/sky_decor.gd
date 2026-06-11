# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# sky_decor.gd — Decorative floating islands + sky cities (the splash-art backdrop).
#
# Builds a ring of low-poly floating islands high above and far from the world origin:
# a grass-topped slab, a tapering dirt underside, a few colourful brick towers (the
# "city"), and a chunky tree. Each island bobs gently and yaws slowly. Pure visuals —
# no collision, no physics, no per-vertex work — so it is mobile-cheap (≈6 islands of
# ~12 boxes each, all distant). Deterministic layout from a fixed seed.
#
# Added to the world by main_scene. Matches the floating-city look of the Cubicraftia
# splash art (art-composed_world-cubicraftia-hero.png).

class_name SkyDecor
extends Node3D

## Number of floating islands in the backdrop ring.
const ISLAND_COUNT: int = 6

## Fixed seed so the skyline is identical every session (deterministic).
const _RNG_SEED: int = 0x0C0FFEE

## Colourful brick-tower palette for the sky cities.
const _TOWER_COLOURS: Array[Color] = [
	Color(0.85, 0.40, 0.32),  # warm red brick
	Color(0.92, 0.80, 0.40),  # sand/gold
	Color(0.52, 0.62, 0.74),  # slate blue
	Color(0.83, 0.83, 0.86),  # light grey
	Color(0.45, 0.70, 0.55),  # teal-green
]

var _islands: Array[Node3D] = []
var _t: float = 0.0


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = _RNG_SEED
	for i in ISLAND_COUNT:
		var island: Node3D = _build_island(rng)
		var ang: float = (float(i) / float(ISLAND_COUNT)) * TAU + rng.randf_range(-0.35, 0.35)
		var radius: float = rng.randf_range(120.0, 250.0)
		var height: float = rng.randf_range(55.0, 125.0)
		island.position = Vector3(cos(ang) * radius, height, sin(ang) * radius)
		island.rotation.y = rng.randf() * TAU
		island.scale = Vector3.ONE * rng.randf_range(1.5, 3.4)
		island.set_meta("base_y", height)
		island.set_meta("bob_phase", rng.randf() * TAU)
		island.set_meta("bob_amp", rng.randf_range(1.5, 3.5))
		island.set_meta("yaw_speed", rng.randf_range(-0.04, 0.04))
		add_child(island)
		_islands.append(island)


## Build one floating island: grass slab + tapering dirt underside + brick city + tree.
func _build_island(rng: RandomNumberGenerator) -> Node3D:
	var root := Node3D.new()

	# Grass top slab.
	root.add_child(_box(Vector3(8.0, 1.2, 8.0), Color(0.38, 0.64, 0.27), Vector3.ZERO))

	# Tapering dirt underside (3 shrinking boxes) — the floating chunk look.
	var dirt := Color(0.46, 0.31, 0.19)
	var y: float = -0.6
	for w: float in [6.6, 4.6, 2.6]:
		var hgt: float = 1.7
		root.add_child(_box(Vector3(w, hgt, w), dirt,
			Vector3(rng.randf_range(-0.4, 0.4), y - hgt * 0.5, rng.randf_range(-0.4, 0.4))))
		y -= hgt

	# Sky city: a few colourful brick towers with dark roof caps.
	var towers: int = rng.randi_range(2, 4)
	for _t_i in towers:
		var th: float = rng.randf_range(2.2, 5.5)
		var tw: float = rng.randf_range(1.0, 1.8)
		var col: Color = _TOWER_COLOURS[rng.randi() % _TOWER_COLOURS.size()]
		var pos := Vector3(rng.randf_range(-2.6, 2.6), 0.6 + th * 0.5, rng.randf_range(-2.6, 2.6))
		root.add_child(_box(Vector3(tw, th, tw), col, pos))
		root.add_child(_box(Vector3(tw * 1.25, 0.5, tw * 1.25), Color(0.28, 0.19, 0.14),
			pos + Vector3(0.0, th * 0.5 + 0.25, 0.0)))

	# A chunky tree.
	var trunk_pos := Vector3(rng.randf_range(-3.0, 3.0), 1.6, rng.randf_range(-3.0, 3.0))
	root.add_child(_box(Vector3(0.5, 2.0, 0.5), Color(0.36, 0.24, 0.14), trunk_pos))
	root.add_child(_box(Vector3(2.4, 2.0, 2.4), Color(0.31, 0.56, 0.25),
		trunk_pos + Vector3(0.0, 1.7, 0.0)))

	return root


## A coloured box mesh at a local position (matte, no metal — reads cleanly at distance).
func _box(size: Vector3, col: Color, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 1.0
	mi.material_override = m
	return mi


func _process(delta: float) -> void:
	_t += delta
	for isl: Node3D in _islands:
		var base_y: float = isl.get_meta("base_y")
		var phase: float = isl.get_meta("bob_phase")
		var amp: float = isl.get_meta("bob_amp")
		isl.position.y = base_y + sin(_t * 0.25 + phase) * amp
		isl.rotation.y += float(isl.get_meta("yaw_speed")) * delta
