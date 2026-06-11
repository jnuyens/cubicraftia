# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# laser_penguin.gd — LaserPenguin: ground-based hostile with a charge-up laser-cone attack.
#
# D-09 strong tell: ~0.8 s eye-glow charge-up (warm orange → red gradient) + audible whine
# before the ~3 m laser fires. Dodgeable by stepping out of the cone.
# Per 03-CONTEXT.md D-09, 03-PATTERNS.md L389-427, DOCS.md §5.2.
#
# AI: sluggish ground walker with NavigationServer3D queries throttled to 2 Hz.
# Per 03-RESEARCH.md Pattern 2 + Q1 L639 (penguin is slower than other mobs).
#
# References:
#   hostile_mob.gd (Plan 03-03 — base class)
#   03-CONTEXT.md D-09 — charge tell + laser cone
#   03-PATTERNS.md L389-427 — LaserPenguin analog assignments
#   03-RESEARCH.md Pattern 2 — throttled NavigationServer3D
#   UI-SPEC L117 — charge gradient: orange #E68A1D → red #D63828

class_name LaserPenguin
extends HostileMob

# ─── Constants ────────────────────────────────────────────────────────────────

## Charge-up duration per D-09: ~0.8 s eye-glow build before laser fires.
const CHARGE_DURATION_S: float = 0.8

## Maximum laser fire range in metres per DOCS §5.2.
const LASER_RANGE_M: float = 3.0

## Half-angle of the laser cone in degrees.
const LASER_CONE_DEGREES: float = 15.0

## NavigationServer3D re-query rate: 2 Hz (penguin is sluggish per RESEARCH Q1 L639).
const NAV_REQUERY_HZ: float = 2.0

## Cooldown between successive charge+fire cycles.
const COOLDOWN_BETWEEN_CHARGES_S: float = 3.0

# ─── Default stat overrides ───────────────────────────────────────────────────
# These constants set the default values in _ready(). The parent @export vars
# are still editable via the Godot inspector on the scene; _ready() sets the
# programmatic defaults if they haven't been changed from the base class values.
#
# LaserPenguin defaults: 3 HP, slow (1.2 m/s), 2 dmg, 12 m detect range.
const _DEFAULT_MAX_HP: int = 3
const _DEFAULT_MOVE_SPEED: float = 1.2
const _DEFAULT_ATTACK_DAMAGE: int = 1
const _DEFAULT_DETECT_RADIUS: float = 12.0

# ─── Node references ──────────────────────────────────────────────────────────

@onready var _charge_timer: Timer = $ChargeTimer
@onready var _eye_glow_particles: GPUParticles3D = $EyeGlowParticles
@onready var _whine_audio: AudioStreamPlayer3D = $WhineAudio
@onready var _laser_shape_cast: ShapeCast3D = $LaserShapeCast

# ─── Runtime fields ───────────────────────────────────────────────────────────

## Remaining cooldown before the next charge is allowed.
var _charge_cooldown: float = 0.0

## Navigation re-query cooldown at the penguin's slower 2 Hz rate.
var _nav_query_cooldown: float = 0.0

## Cached reference to the nearest builder node for targeting.
var _target: Node3D = null

# ─── Lifecycle ────────────────────────────────────────────────────────────────

func _ready() -> void:
	# Apply stat defaults before super._ready() sets hp = max_hp.
	max_hp = _DEFAULT_MAX_HP
	move_speed = _DEFAULT_MOVE_SPEED
	attack_damage = _DEFAULT_ATTACK_DAMAGE
	detect_radius = _DEFAULT_DETECT_RADIUS
	super._ready()
	if _charge_timer != null:
		_charge_timer.wait_time = CHARGE_DURATION_S
		_charge_timer.one_shot = true
		if not _charge_timer.timeout.is_connected(_on_charge_complete):
			_charge_timer.timeout.connect(_on_charge_complete)
	# Start in SEEK state — detect builder immediately when ready.
	state = State.IDLE
	# Phase 8 (ANIM-05): penguin keeps its single-mesh TripoSR art; attach the
	# procedural transform-only LAND fallback (idle bob + sway).
	_setup_procedural_anim(ProceduralCreatureAnimator.Motion.LAND)


func _art_kind() -> String:
	return "laser_penguin"


func _art_target_height() -> float:
	return 1.1


# ─── Physics process (penguin-specific) ──────────────────────────────────────

func _physics_process(delta: float) -> void:
	_charge_cooldown -= delta
	_nav_query_cooldown -= delta
	super._physics_process(delta)  # base drives _update_animator() after its move_and_slide()


# ─── State overrides ──────────────────────────────────────────────────────────

func _process_idle(_delta: float) -> void:
	# Look for the builder; transition to SEEK on detect.
	_target = get_tree().get_first_node_in_group("builder") as Node3D
	if _target == null:
		return
	if global_position.distance_squared_to(_target.global_position) \
			<= detect_radius * detect_radius:
		state = State.SEEK
		_state_timer = 0.0


func _process_seek(delta: float) -> void:
	_target = get_tree().get_first_node_in_group("builder") as Node3D
	if _target == null:
		state = State.IDLE
		return

	var dist: float = global_position.distance_to(_target.global_position)

	# If builder is out of detect range, return to IDLE.
	if dist > detect_radius * 1.5:
		state = State.IDLE
		return

	# Chase the builder: walk the navmesh path when one is baked, else direct beeline
	# (the procedural voxel world bakes no navmesh, so this is the live path). Stop at
	# laser range so the penguin holds its ground and charges instead of crowding in.
	# _steer_toward() issues the throttled nav query internally (base PATH_REQUERY_HZ).
	_steer_toward(_target.global_position, delta, LASER_RANGE_M)

	# Check attack condition: in range + charge ready + not already attacking.
	if dist <= LASER_RANGE_M and _charge_cooldown <= 0.0 and state == State.SEEK:
		_begin_charge()


func _process_attack(_delta: float) -> void:
	# While charging: stop moving and face the target.
	velocity = Vector3.ZERO
	if _target != null:
		var look_dir: Vector3 = (_target.global_position - global_position)
		look_dir.y = 0.0
		if look_dir.length_squared() > 0.01:
			look_at(global_position + look_dir, Vector3.UP)


# ─── Laser mechanic ───────────────────────────────────────────────────────────

## Begin the eye-glow charge-up tell (D-09). Sets ATTACK state + starts timer.
func _begin_charge() -> void:
	state = State.ATTACK
	_state_timer = 0.0
	if _eye_glow_particles != null:
		_eye_glow_particles.emitting = true
	if _whine_audio != null:
		_whine_audio.play()
	if _charge_timer != null:
		_charge_timer.start()


## Called when the charge timer fires. Fire the laser cone and reset to SEEK.
func _on_charge_complete() -> void:
	if _eye_glow_particles != null:
		_eye_glow_particles.emitting = false
	_fire_laser()
	state = State.SEEK
	_state_timer = 0.0
	_charge_cooldown = COOLDOWN_BETWEEN_CHARGES_S


## Cast a cone-shaped query forward and damage any Builder in range.
## Friendly-fire guard: HostileMob subclasses are skipped (T-03-10-MB-05).
func _fire_laser() -> void:
	if _laser_shape_cast == null:
		return
	# Orient the shape cast toward the builder.
	if _target != null:
		var aim_dir: Vector3 = (_target.global_position - global_position).normalized()
		_laser_shape_cast.global_transform.basis = Basis.looking_at(aim_dir, Vector3.UP)
	_laser_shape_cast.force_shapecast_update()
	var collider_count: int = _laser_shape_cast.get_collision_count()
	for i: int in range(collider_count):
		var collider: Object = _laser_shape_cast.get_collider(i)
		if collider == null:
			continue
		# Skip other HostileMob subclasses — no friendly fire in v1.
		if collider is HostileMob:
			continue
		# Damage the builder.
		if collider.has_method("take_damage"):
			collider.take_damage(attack_damage, global_position)


# ─── Navigation helper ────────────────────────────────────────────────────────

## Walk the currently-cached navigation path. Advances path_index when close.
func _walk_cached_path(_delta: float) -> void:
	if _current_path.is_empty() or _path_index >= _current_path.size():
		velocity.x = 0.0
		velocity.z = 0.0
		return
	var next_point: Vector3 = _current_path[_path_index]
	var to_next: Vector3 = next_point - global_position
	to_next.y = 0.0
	if to_next.length_squared() < 0.25:
		_path_index += 1
		return
	var dir: Vector3 = to_next.normalized()
	velocity.x = dir.x * move_speed
	velocity.z = dir.z * move_speed
	# Face movement direction.
	if dir.length_squared() > 0.01:
		look_at(global_position + dir, Vector3.UP)
