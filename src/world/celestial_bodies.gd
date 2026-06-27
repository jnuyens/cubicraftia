# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# celestial_bodies.gd — Brick sun + brick moon that arc across the sky with the day.
#
# The sun is a disc of bricks (white core, yellow rim, unshaded so it glows); the moon
# is a smaller grey-brick disc. Both ride a fixed large distance from the camera (so they
# read as "in the sky" no matter where the player roams) and follow an arc driven by
# WorldClock.current_day_progress(): sunrise at the east horizon → zenith at noon →
# sunset at the west horizon, then the moon takes the night arc. Pure visuals.

class_name CelestialBodies
extends Node3D

## Distance the bodies sit from the camera (well inside the default 4000 m far plane,
## beyond the floating-island backdrop so they never intersect it).
const SKY_DIST: float = 380.0

## Day fraction [0,1) at which the sun sets / moon rises (matches the sky shader's
## DAY→DUSK→NIGHT boundary around 0.70).
const NIGHT_START: float = 0.70

## Art-weather sky models (Meshy). Fall back to the brick discs if missing (headless/CI).
const _SUN_MODEL: String = "res://assets/meshes/sky/sun.glb"
const _MOON_MODEL: String = "res://assets/meshes/sky/moon.glb"
const _SUN_WIDTH: float = 56.0
const _MOON_WIDTH: float = 38.0

## Drifting cloud layer (Meshy clouds). Clouds follow the camera in XZ, sit at a high
## altitude, and drift slowly along +X, wrapping when they pass the far edge.
const _CLOUD_MODELS: Array[String] = [
	"res://assets/meshes/sky/cloud_1.glb", "res://assets/meshes/sky/cloud_2.glb",
	"res://assets/meshes/sky/cloud_3.glb", "res://assets/meshes/sky/cloud_4.glb",
]
const _CLOUD_COUNT: int = 12
const _CLOUD_SPREAD: float = 320.0   # half-extent of the XZ box clouds drift within
const _CLOUD_Y_MIN: float = 70.0
const _CLOUD_Y_MAX: float = 120.0
const _CLOUD_DRIFT: float = 6.0      # m/s along +X

## ─── Clouds flow around mountains ────────────────────────────────────────────
## When a cloud drifts toward a peak that reaches into its altitude band, it parts
## sideways (toward the lower flank) and lifts a little to skim over, then relaxes
## back to its lane once clear — a cheap flow-field feel, like water around a rock.
## Only mountain-biome peaks (≈ +40…+90 m) reach the cloud band, so normal terrain
## never triggers it. Heights come from main_scene._terrain_surface_at (group lookup).
const _CLOUD_LOOKAHEAD: float = 46.0   # how far ahead (along drift) to sense a peak
const _CLOUD_CLEARANCE: float = 14.0   # vertical gap a cloud wants above a peak
const _CLOUD_PROBE_SIDE: float = 34.0  # lateral probe to find the lower flank
const _CLOUD_STEER: float = 16.0       # m/s sideways push while deflecting
const _CLOUD_LIFT: float = 11.0        # m/s upward push while deflecting
const _CLOUD_RELAX: float = 3.5        # m/s drift back to base lane/altitude when clear
const _CLOUD_Z_RANGE: float = 95.0     # max lateral wander from a cloud's base lane

## ─── Mystery orb (easter egg) ────────────────────────────────────────────────
## Once every MYSTERY_PERIOD_DAYS, the green orb streaks across the sky at high speed,
## passing through everything (no collider — it lives in the sky layer) and leaving a
## trail of fading "?" marks plus a cryptic toast.
const _MYSTERY_MODEL: String = "res://assets/meshes/sky/mystery_orb.glb"
const MYSTERY_PERIOD_DAYS: int = 20
const _MYSTERY_WIDTH: float = 26.0
const _MYSTERY_DURATION: float = 3.4          # seconds to cross the whole sky (fast)
const _MYSTERY_START: Vector3 = Vector3(-380.0, 120.0, -90.0)  # local to this (cam-anchored) node
const _MYSTERY_END: Vector3 = Vector3(380.0, 175.0, 110.0)
const _MYSTERY_Q_INTERVAL: float = 0.16       # seconds between dropped "?" marks
const _MYSTERY_Q_LIFETIME: float = 6.0

var _sun: Node3D = null
var _moon: Node3D = null
var _clouds: Array[Node3D] = []
var _mystery_orb: Node3D = null
var _mystery_t: float = -1.0                  # <0 = inactive; [0,1] = flyby progress
var _mystery_q_timer: float = 0.0
var _main_scene: Node = null                  # lazily resolved (group "main_scene"), read-only


func _ready() -> void:
	# Sun: art-weather glowing model (always-visible/emissive), fallback to the brick disc.
	_sun = _load_sky_model(_SUN_MODEL, _SUN_WIDTH, true)
	if _sun == null:
		_sun = _build_brick_disc(9, Color(1.0, 0.98, 0.90), Color(1.0, 0.82, 0.16), true)
		_sun.scale = Vector3.ONE * 6.0
	add_child(_sun)
	# Moon: art-weather model (always-visible), fallback to the brick disc.
	_moon = _load_sky_model(_MOON_MODEL, _MOON_WIDTH, false)
	if _moon == null:
		_moon = _build_brick_disc(7, Color(0.80, 0.82, 0.86), Color(0.52, 0.55, 0.60), false)
		_moon.scale = Vector3.ONE * 4.5
	add_child(_moon)
	_spawn_clouds()
	# Mystery-orb easter egg: fire on every 20th day boundary.
	if WorldClock != null and WorldClock.has_signal("day_boundary"):
		WorldClock.day_boundary.connect(_on_day_boundary)


## Day rollover — trigger the mystery orb every MYSTERY_PERIOD_DAYS (day 20, 40, 60, …).
func _on_day_boundary(day_index: int) -> void:
	if day_index > 0 and day_index % MYSTERY_PERIOD_DAYS == 0:
		_start_mystery_flyby()


## Begin a mystery-orb flyby: spawn the orb (unshaded green glow), start the cross-sky
## animation, and announce it. No-op if a flyby is already running or the model is absent.
func _start_mystery_flyby() -> void:
	if _mystery_t >= 0.0:
		return
	var built: Node3D = _load_sky_model(_MYSTERY_MODEL, _MYSTERY_WIDTH, true)
	if built == null:
		return
	_mystery_orb = built
	add_child(_mystery_orb)
	_mystery_orb.position = _MYSTERY_START
	_mystery_t = 0.0
	_mystery_q_timer = 0.0
	if Toasts != null and Toasts.has_method("show"):
		Toasts.show("ui.mystery.orb", "info")


## Advance the flyby: streak the orb across the sky and drop fading "?" marks in its wake.
func _update_mystery(delta: float) -> void:
	if _mystery_t < 0.0 or _mystery_orb == null:
		return
	_mystery_t += delta / _MYSTERY_DURATION
	if _mystery_t >= 1.0:
		_mystery_orb.queue_free()
		_mystery_orb = null
		_mystery_t = -1.0
		return
	_mystery_orb.position = _MYSTERY_START.lerp(_MYSTERY_END, _mystery_t)
	_mystery_orb.rotate_y(delta * 6.0)  # spin for flair
	# Drop "?" marks into world space (parented to the scene, not this cam-anchored node).
	_mystery_q_timer -= delta
	if _mystery_q_timer <= 0.0:
		_mystery_q_timer = _MYSTERY_Q_INTERVAL
		_drop_question(_mystery_orb.global_position)


## Spawn one fading, rising "?" billboard at `pos` (lingers in world space).
func _drop_question(pos: Vector3) -> void:
	var host: Node = get_parent()
	if host == null:
		return
	var q := Label3D.new()
	q.text = "?"
	q.font_size = 220
	q.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	q.no_depth_test = true
	q.modulate = Color(0.55, 1.0, 0.55, 0.95)
	q.outline_size = 24
	q.outline_modulate = Color(0.0, 0.25, 0.0, 0.9)
	q.pixel_size = 0.05
	host.add_child(q)
	q.global_position = pos
	var tw: Tween = q.create_tween()
	tw.set_parallel(true)
	tw.tween_property(q, "global_position:y", pos.y + 18.0, _MYSTERY_Q_LIFETIME)
	tw.tween_property(q, "modulate:a", 0.0, _MYSTERY_Q_LIFETIME)
	tw.chain().tween_callback(q.queue_free)


## Load a sky GLB, scale its longest axis to target_width, centre it, and force its
## materials UNSHADED (sky bodies must read at full brightness day or night; glowing adds
## emission). Returns null if the model is absent so the caller can fall back.
func _load_sky_model(path: String, target_width: float, glowing: bool) -> Node3D:
	if not ResourceLoader.exists(path):
		return null
	var inst := (load(path) as PackedScene).instantiate() as Node3D
	if inst == null:
		return null
	var ab: AABB = _model_aabb(inst)
	var longest: float = maxf(ab.size.x, maxf(ab.size.y, ab.size.z))
	var sc: float = target_width / maxf(longest, 0.01)
	inst.scale = Vector3.ONE * sc
	inst.position = -ab.get_center() * sc
	for child: Node in inst.find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		if mi.mesh == null:
			continue
		for s: int in mi.mesh.get_surface_count():
			var base: Material = mi.get_active_material(s)
			var mat: BaseMaterial3D = (base.duplicate() if base is BaseMaterial3D else StandardMaterial3D.new())
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			if glowing:
				mat.emission_enabled = true
				mat.emission = mat.albedo_color
				mat.emission_energy_multiplier = 0.5
			mi.set_surface_override_material(s, mat)
	var root := Node3D.new()
	root.add_child(inst)
	return root


## Merged local-space AABB of every MeshInstance3D under `root`.
func _model_aabb(root: Node3D) -> AABB:
	var out := AABB()
	var first := true
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			var a: AABB = (n as MeshInstance3D).transform * (n as MeshInstance3D).mesh.get_aabb()
			out = a if first else out.merge(a)
			first = false
		for c: Node in n.get_children():
			stack.push_back(c)
	return out


## Spawn the drifting cloud instances at random positions/altitudes in the XZ box.
func _spawn_clouds() -> void:
	var rng := RandomNumberGenerator.new()
	for i: int in _CLOUD_COUNT:
		var path: String = _CLOUD_MODELS[i % _CLOUD_MODELS.size()]
		if not ResourceLoader.exists(path):
			continue
		var inst := (load(path) as PackedScene).instantiate() as Node3D
		if inst == null:
			continue
		var ab: AABB = _model_aabb(inst)
		var longest: float = maxf(ab.size.x, maxf(ab.size.y, ab.size.z))
		var sc: float = rng.randf_range(28.0, 64.0) / maxf(longest, 0.01)
		inst.scale = Vector3.ONE * sc
		var holder := Node3D.new()
		holder.add_child(inst)
		holder.position = Vector3(
			rng.randf_range(-_CLOUD_SPREAD, _CLOUD_SPREAD),
			rng.randf_range(_CLOUD_Y_MIN, _CLOUD_Y_MAX),
			rng.randf_range(-_CLOUD_SPREAD, _CLOUD_SPREAD))
		# Base lane + altitude this cloud relaxes back to after deflecting around a peak.
		holder.set_meta("base_y", holder.position.y)
		holder.set_meta("base_z", holder.position.z)
		add_child(holder)
		_clouds.append(holder)


## Nudge one cloud so it flows AROUND a mountain peak in its path: if the terrain a bit
## ahead reaches into the cloud's altitude band, steer toward the lower flank and lift to
## skim over; otherwise relax back to the cloud's base lane + altitude. Cheap (≤3 terrain
## samples) and a no-op over normal low terrain (peaks only exist in the MOUNTAIN biome).
func _flow_around_terrain(cloud: Node3D, delta: float) -> void:
	var gx: float = global_position.x + cloud.position.x
	var gz: float = global_position.z + cloud.position.z
	var base_y: float = float(cloud.get_meta("base_y", cloud.position.y))
	var base_z: float = float(cloud.get_meta("base_z", cloud.position.z))
	var ahead: float = _surface_y(gx + _CLOUD_LOOKAHEAD, gz)
	if ahead > cloud.position.y - _CLOUD_CLEARANCE:
		# A peak blocks the lane — part toward the lower side and rise to clear it.
		var left: float = _surface_y(gx + _CLOUD_LOOKAHEAD, gz - _CLOUD_PROBE_SIDE)
		var right: float = _surface_y(gx + _CLOUD_LOOKAHEAD, gz + _CLOUD_PROBE_SIDE)
		var dir: float = -1.0 if left < right else 1.0
		cloud.position.z = clampf(cloud.position.z + dir * _CLOUD_STEER * delta,
			base_z - _CLOUD_Z_RANGE, base_z + _CLOUD_Z_RANGE)
		cloud.position.y = move_toward(cloud.position.y, maxf(ahead + _CLOUD_CLEARANCE, base_y),
			_CLOUD_LIFT * delta)
	else:
		# Clear air — ease back toward the cloud's lane and cruise altitude.
		cloud.position.z = move_toward(cloud.position.z, base_z, _CLOUD_RELAX * delta)
		cloud.position.y = move_toward(cloud.position.y, base_y, _CLOUD_RELAX * delta)


## Deterministic generator surface height at world (x, z) via main_scene._terrain_surface_at
## (the same formula entities ground-snap to, mountain lift included). Very low fallback when
## no main_scene is reachable (detached test) so clouds never deflect over nothing.
func _surface_y(x: float, z: float) -> float:
	var scene: Node = _resolve_main_scene()
	if scene != null and scene.has_method("_terrain_surface_at"):
		return float(scene._terrain_surface_at(x, z))
	return -1000.0


## Lazily resolve + cache the MainScene node (group "main_scene"); null in a detached test.
func _resolve_main_scene() -> Node:
	if _main_scene != null and is_instance_valid(_main_scene):
		return _main_scene
	if not is_inside_tree():
		return null
	_main_scene = get_tree().get_first_node_in_group("main_scene")
	return _main_scene


## Build a disc of unit bricks in the local XY plane: cubes within `diameter`/2 of centre,
## coloured `inner_col` near the middle and `outer_col` toward the rim.
func _build_brick_disc(diameter: int, inner_col: Color, outer_col: Color, glowing: bool) -> Node3D:
	var root := Node3D.new()
	var r: float = float(diameter) / 2.0
	var inner_r: float = r * 0.5
	var ri: int = int(ceil(r))
	for x in range(-ri, ri + 1):
		for y in range(-ri, ri + 1):
			var d: float = sqrt(float(x * x + y * y))
			if d > r:
				continue
			var col: Color = inner_col if d <= inner_r else outer_col
			root.add_child(_brick(col, glowing, Vector3(float(x), float(y), 0.0)))
	return root


## One celestial brick. Slight oversize so the disc has no seams; unshaded for the sun.
func _brick(col: Color, glowing: bool, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.06, 1.06, 1.06)
	mi.mesh = bm
	mi.position = pos
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	if glowing:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.emission_enabled = true
		m.emission = col
		m.emission_energy_multiplier = 0.6
	else:
		m.roughness = 1.0
	mi.material_override = m
	return mi


func _process(delta: float) -> void:
	var cam: Camera3D = get_viewport().get_camera_3d()
	var cam_pos: Vector3 = cam.global_position if cam != null else Vector3.ZERO
	var dp: float = WorldClock.current_day_progress() if WorldClock != null else 0.3
	var is_day: bool = dp < NIGHT_START
	_sun.visible = is_day
	_moon.visible = not is_day

	# Anchor the cloud field to the camera in XZ FIRST (clouds are children with local
	# positions, so moving this node carries them along), then place the sun/moon by GLOBAL
	# position so they're unaffected by this node's transform. Order avoids a 1-frame shift.
	global_position = Vector3(cam_pos.x, 0.0, cam_pos.z)
	for cloud: Node3D in _clouds:
		cloud.position.x += _CLOUD_DRIFT * delta
		if cloud.position.x > _CLOUD_SPREAD:
			cloud.position.x = -_CLOUD_SPREAD
		_flow_around_terrain(cloud, delta)

	if is_day:
		_place(_sun, cam_pos, clampf(dp / NIGHT_START, 0.0, 1.0))
	else:
		_place(_moon, cam_pos, clampf((dp - NIGHT_START) / (1.0 - NIGHT_START), 0.0, 1.0))

	# Mystery-orb flyby (active only on its rare day) — cam-anchored, drops "?" marks.
	_update_mystery(delta)


## Position a body on the sky arc at fraction `f` (0 = east horizon, 0.5 = zenith,
## 1 = west horizon) and face it at the camera.
func _place(body: Node3D, cam_pos: Vector3, f: float) -> void:
	var ang: float = f * PI
	var dir := Vector3(-cos(ang), sin(ang), -0.35).normalized()
	body.global_position = cam_pos + dir * SKY_DIST
	body.look_at(cam_pos, Vector3.UP)
