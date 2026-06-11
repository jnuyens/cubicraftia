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

## A single hot-air balloon drifting slowly across the sky in a fixed direction (so it is only
## occasionally overhead), bobbing gently up and down. Decorative-but-functional: it periodically
## LANDS so a builder can step into the basket and ride it back up ("a trip of a lifetime").
## It wraps to the far side when it leaves the drift span so it crosses now and then.
const _BALLOON_PATH: String = "res://assets/meshes/sky/hot_air_balloon.glb"
const _BALLOON_SIZE: float = 12.0  # longest-axis metres
const _BALLOON_DRIFT_SPEED: float = 1.5  # m/s, a slow glide
const _BALLOON_DRIFT_SPAN: float = 220.0  # horizontal distance from origin before it wraps

# ── Balloon ride state machine ───────────────────────────────────────────────
# DRIFTING (high, bobbing) → DESCEND (sink straight down to the ground) → LANDED (basket
# resting on terrain, ~30 s, walk in) → ASCEND (rise back to cruise height, carrying a
# standing builder up like an elevator) → DRIFTING. Roughly lands every few minutes.
enum BalloonState { DRIFTING, DESCEND, LANDED, ASCEND }

## How long the balloon drifts up high between landings (seconds). Roughly "every few minutes".
const _BALLOON_DRIFT_DURATION: float = 180.0
## How long the basket rests on the ground for a builder to walk in (seconds).
const _BALLOON_LANDED_DURATION: float = 30.0
## Vertical speed (m/s) while descending to land or ascending back to cruise height.
const _BALLOON_VERTICAL_SPEED: float = 4.0
## Cruise altitude band — randomised once per balloon; the balloon returns here after each ride.
const _BALLOON_CRUISE_MIN_Y: float = 34.0
const _BALLOON_CRUISE_MAX_Y: float = 58.0
## Fallback ground Y used when no terrain raycast hit is available (headless / unmeshed chunk).
const _BALLOON_FALLBACK_GROUND_Y: float = 2.0
## Downward ground-probe geometry (metres) used to seat the landed basket on real terrain.
const _BALLOON_GROUND_RAY_UP: float = 80.0
const _BALLOON_GROUND_RAY_DOWN: float = 240.0

# ── Basket geometry (local space, relative to the balloon root) ───────────────
# The basket hangs below the envelope. Its floor + walls are AnimatableBody3D bodies on
# collision layer 1 (the SAME terrain layer the builder already stands on), with
# sync_to_physics enabled — so a CharacterBody3D standing on the floor is carried up like an
# elevator on ASCEND via the builder's own is_on_floor() physics. NO builder.gd change needed.
## Local Y of the basket FLOOR TOP surface, relative to the balloon root origin (below envelope).
const _BASKET_FLOOR_TOP_Y: float = -6.5
## Interior footprint (metres) of the basket floor the builder stands on.
const _BASKET_INNER_SIZE: float = 3.0
## Thickness of the floor slab and of the walls (metres).
const _BASKET_FLOOR_THICKNESS: float = 0.3
const _BASKET_WALL_THICKNESS: float = 0.2
## Height of the low retaining walls (metres) so the builder does not slide off.
const _BASKET_WALL_HEIGHT: float = 1.1
## Wicker-basket colour for the floor + walls.
const _BASKET_COLOUR: Color = Color(0.55, 0.38, 0.20)

var _islands: Array[Node3D] = []
var _t: float = 0.0

# The single rideable balloon (null until spawned; absent in headless/CI without the asset).
var _balloon: Node3D = null
var _balloon_basket: Node3D = null  # container of the AnimatableBody3D floor + walls
var _balloon_state: int = BalloonState.DRIFTING
var _balloon_state_t: float = 0.0  # seconds elapsed in the current state
var _balloon_cruise_y: float = 46.0  # randomised altitude the balloon returns to after a ride
var _balloon_ground_y: float = _BALLOON_FALLBACK_GROUND_Y  # terrain top-Y captured at descent start


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
	_spawn_balloons(rng)


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


## Spawn the single rideable hot-air balloon. Silent no-op if the asset is absent
## (headless/CI before import). The balloon root carries the envelope mesh AND a basket
## (AnimatableBody3D floor + walls) so the whole thing descends/ascends together; the ride
## state machine lives in `_process` / `_step_balloon`. It is NOT added to `_islands`: the
## generic bob/drift loop is replaced by the state machine for this node.
func _spawn_balloons(rng: RandomNumberGenerator) -> void:
	if not ResourceLoader.exists(_BALLOON_PATH):
		return
	var ps := load(_BALLOON_PATH) as PackedScene
	if ps == null:
		return
	# A root wrapper so envelope + basket move together as one unit during DESCEND/ASCEND.
	var root := Node3D.new()
	root.name = "RideableBalloon"
	add_child(root)

	var envelope := ps.instantiate() as Node3D
	if envelope == null:
		root.queue_free()
		return
	root.add_child(envelope)
	var ab: AABB = _node_aabb(envelope)
	var longest: float = maxf(ab.size.x, maxf(ab.size.y, ab.size.z))
	envelope.scale = Vector3.ONE * (_BALLOON_SIZE / maxf(longest, 0.01))

	# Fixed slow drift direction; cruise height in the visible-from-the-ground band. Start on the
	# far side so it drifts INTO view, then wraps across the sky (handled in _step_balloon).
	var dir: float = rng.randf() * TAU
	var drift := Vector3(cos(dir), 0.0, sin(dir)) * _BALLOON_DRIFT_SPEED
	_balloon_cruise_y = rng.randf_range(_BALLOON_CRUISE_MIN_Y, _BALLOON_CRUISE_MAX_Y)
	root.position = -drift.normalized() * _BALLOON_DRIFT_SPAN + Vector3(0.0, _balloon_cruise_y, 0.0)
	root.rotation.y = rng.randf() * TAU
	root.set_meta("bob_phase", rng.randf() * TAU)
	root.set_meta("bob_amp", rng.randf_range(1.5, 3.0))
	root.set_meta("yaw_speed", rng.randf_range(-0.03, 0.03))
	root.set_meta("drift", drift)

	_balloon_basket = _build_basket()
	root.add_child(_balloon_basket)

	_balloon = root
	_balloon_state = BalloonState.DRIFTING
	_balloon_state_t = 0.0


## Build the basket that hangs under the envelope: an AnimatableBody3D floor the builder stands
## on, plus three low retaining walls (also AnimatableBody3D) so it cannot slide off — with one
## OPEN side (no wall) to walk in while landed. All bodies sit on collision layer 1 (terrain
## layer) with sync_to_physics enabled so a standing CharacterBody3D is carried when the basket
## moves. Returned as a plain Node3D container parented to the balloon root.
func _build_basket() -> Node3D:
	var basket := Node3D.new()
	basket.name = "Basket"
	var half: float = _BASKET_INNER_SIZE * 0.5

	# Floor slab: its TOP surface sits at _BASKET_FLOOR_TOP_Y, so the floor centre is half a
	# thickness below that. The builder stands on this top face.
	var floor_centre_y: float = _BASKET_FLOOR_TOP_Y - _BASKET_FLOOR_THICKNESS * 0.5
	var floor_size := Vector3(_BASKET_INNER_SIZE + _BASKET_WALL_THICKNESS * 2.0,
		_BASKET_FLOOR_THICKNESS,
		_BASKET_INNER_SIZE + _BASKET_WALL_THICKNESS * 2.0)
	basket.add_child(_animatable_box(floor_size, _BASKET_COLOUR,
		Vector3(0.0, floor_centre_y, 0.0)))

	# Three low walls (the -X side is left OPEN as the doorway to walk in). Walls rest on the
	# floor top, centred at floor_top + wall_height/2.
	var wall_centre_y: float = _BASKET_FLOOR_TOP_Y + _BASKET_WALL_HEIGHT * 0.5
	var span: float = _BASKET_INNER_SIZE + _BASKET_WALL_THICKNESS * 2.0
	var wall_x := Vector3(_BASKET_WALL_THICKNESS, _BASKET_WALL_HEIGHT, span)
	var wall_z := Vector3(span, _BASKET_WALL_HEIGHT, _BASKET_WALL_THICKNESS)
	# +X wall (back), +Z and -Z walls (sides). -X stays open as the entrance.
	basket.add_child(_animatable_box(wall_x, _BASKET_COLOUR,
		Vector3(half + _BASKET_WALL_THICKNESS * 0.5, wall_centre_y, 0.0)))
	basket.add_child(_animatable_box(wall_z, _BASKET_COLOUR,
		Vector3(0.0, wall_centre_y, half + _BASKET_WALL_THICKNESS * 0.5)))
	basket.add_child(_animatable_box(wall_z, _BASKET_COLOUR,
		Vector3(0.0, wall_centre_y, -(half + _BASKET_WALL_THICKNESS * 0.5))))
	return basket


## An AnimatableBody3D box (collision + matching visual) on collision layer 1 with
## sync_to_physics enabled, so a CharacterBody3D standing on it rides along when it is moved.
func _animatable_box(size: Vector3, col: Color, pos: Vector3) -> AnimatableBody3D:
	var body := AnimatableBody3D.new()
	body.position = pos
	body.sync_to_physics = true        # carry standing CharacterBody3D bodies (elevator behaviour)
	body.collision_layer = 1           # terrain layer — builder's default mask collides with it
	body.collision_mask = 0            # the basket itself detects nothing (cheap)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	body.add_child(_box(size, col, Vector3.ZERO))
	return body


## Merged local-space AABB of every MeshInstance3D under `root` (root must be in-tree).
func _node_aabb(root: Node3D) -> AABB:
	var out := AABB()
	var first := true
	var inv: Transform3D = root.global_transform.affine_inverse()
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			var a: AABB = (inv * (n as MeshInstance3D).global_transform) * (n as MeshInstance3D).mesh.get_aabb()
			out = a if first else out.merge(a)
			first = false
		for c: Node in n.get_children():
			stack.push_back(c)
	return out


func _process(delta: float) -> void:
	_t += delta
	for isl: Node3D in _islands:
		var base_y: float = isl.get_meta("base_y")
		var phase: float = isl.get_meta("bob_phase")
		var amp: float = isl.get_meta("bob_amp")
		isl.position.y = base_y + sin(_t * 0.25 + phase) * amp
		isl.rotation.y += float(isl.get_meta("yaw_speed")) * delta


## The balloon carries an AnimatableBody3D basket, whose sync_to_physics carry-the-rider
## behaviour requires the body to be moved on the PHYSICS tick (so the engine derives its
## velocity from the motion). Driving the state machine here (not in _process) is what makes
## a builder standing in the basket ride up on ASCEND.
func _physics_process(delta: float) -> void:
	_step_balloon(delta)


## Advance the rideable balloon's state machine and move it. Driving the whole balloon root
## (envelope + basket together) keeps them attached; the basket's AnimatableBody3D floor carries
## a standing builder on ASCEND. No-op when the balloon is absent (headless/CI without the asset).
func _step_balloon(delta: float) -> void:
	if _balloon == null:
		return
	_balloon_state_t += delta
	var phase: float = _balloon.get_meta("bob_phase")
	var amp: float = _balloon.get_meta("bob_amp")
	var drift: Vector3 = _balloon.get_meta("drift")

	match _balloon_state:
		BalloonState.DRIFTING:
			# Glide slowly + bob high; wrap to the far side when it leaves the span.
			_balloon.position.y = _balloon_cruise_y + sin(_t * 0.25 + phase) * amp
			_balloon.position.x += drift.x * delta
			_balloon.position.z += drift.z * delta
			_balloon.rotation.y += float(_balloon.get_meta("yaw_speed")) * delta
			if Vector2(_balloon.position.x, _balloon.position.z).length() > _BALLOON_DRIFT_SPAN:
				_balloon.position.x = -_balloon.position.x
				_balloon.position.z = -_balloon.position.z
			if _balloon_state_t >= _BALLOON_DRIFT_DURATION:
				# Begin landing: capture the real ground under the balloon NOW (before it sinks).
				_balloon_ground_y = _probe_ground_y(_balloon.global_position)
				_enter_balloon_state(BalloonState.DESCEND)

		BalloonState.DESCEND:
			# Sink straight down (no drift / no bob) until the basket floor rests on the ground.
			var target_y: float = _balloon_landed_root_y()
			_balloon.position.y = maxf(target_y, _balloon.position.y - _BALLOON_VERTICAL_SPEED * delta)
			if _balloon.position.y <= target_y + 0.001:
				_balloon.position.y = target_y
				_enter_balloon_state(BalloonState.LANDED)

		BalloonState.LANDED:
			# Hold still on the ground so a builder can walk into the open basket side.
			_balloon.position.y = _balloon_landed_root_y()
			if _balloon_state_t >= _BALLOON_LANDED_DURATION:
				_enter_balloon_state(BalloonState.ASCEND)

		BalloonState.ASCEND:
			# Rise back to cruise height. The AnimatableBody3D floor carries a standing builder up.
			_balloon.position.y = minf(_balloon_cruise_y,
				_balloon.position.y + _BALLOON_VERTICAL_SPEED * delta)
			if _balloon.position.y >= _balloon_cruise_y - 0.001:
				_balloon.position.y = _balloon_cruise_y
				_enter_balloon_state(BalloonState.DRIFTING)


## Switch balloon state and reset the per-state timer.
func _enter_balloon_state(next: int) -> void:
	_balloon_state = next
	_balloon_state_t = 0.0


## The balloon root Y at which the basket floor TOP rests on the captured ground.
## The basket floor top sits at root.y + _BASKET_FLOOR_TOP_Y in local space, so to put that
## surface at ground level we set root.y = ground_y - _BASKET_FLOOR_TOP_Y.
func _balloon_landed_root_y() -> float:
	return _balloon_ground_y - _BASKET_FLOOR_TOP_Y


## Cast a ray straight down from above the balloon to find the terrain top Y under it
## (collision layer 1 = VoxelTerrain, the same layer the builder stands on). Falls back to a
## sensible low Y when no physics / no hit is available (headless / unmeshed chunk).
func _probe_ground_y(from_world: Vector3) -> float:
	var world := get_world_3d()
	if world == null:
		return _BALLOON_FALLBACK_GROUND_Y
	var space := world.direct_space_state
	if space == null:
		return _BALLOON_FALLBACK_GROUND_Y
	var from := Vector3(from_world.x, from_world.y + _BALLOON_GROUND_RAY_UP, from_world.z)
	var to := Vector3(from_world.x, from_world.y - _BALLOON_GROUND_RAY_DOWN, from_world.z)
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collision_mask = 1  # terrain / statics only (same layer main_scene + wildlife probe ground).
	var hit: Dictionary = space.intersect_ray(q)
	if hit.is_empty():
		return _BALLOON_FALLBACK_GROUND_Y
	return (hit["position"] as Vector3).y
