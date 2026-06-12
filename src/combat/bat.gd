# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# bat.gd — Bat: flying swoop attacker. Two variants: "regular" (max_hp=1) and "vampire"
# (max_hp=2, faster/harder per DOCS §5.2).
#
# D-09 strong tell: small chitter sound committed on swoop-commit; otherwise quiet.
# AI: random wander + commit-to-swoop on detect. No gravity (bat flies).
# Per 03-CONTEXT.md D-09, 03-PATTERNS.md L444-447, DOCS.md §5.2.
#
# Variant "vampire" is spawned by Vampire._begin_transform() when HP reaches threshold.
# The variant value "vampire" sets max_hp=2, move_speed=5.0 (faster per DOCS §5.2).
#
# References:
#   hostile_mob.gd (Plan 03-03 — base class)
#   vampire.gd (Plan 03-10 — spawns "bat_vampire" variant)
#   03-CONTEXT.md D-09 — bat AI, chitter tell, flying with no gravity
#   03-PATTERNS.md L444-447 — Bat analog assignments

class_name Bat
extends HostileMob

# ─── Constants ────────────────────────────────────────────────────────────────

## Distance at which the bat commits to a swoop attack.
const SWOOP_COMMIT_RANGE_M: float = 5.0

## Cooldown between chitter sound plays (seconds).
const CHITTER_COOLDOWN_S: float = 2.0

## Minimum seconds between bat hits landing damage. Without this the bat re-entered ATTACK
## every frame on contact and dealt ~60 damage/second (an instakill). Now max 1 hit per 3 s.
const ATTACK_COOLDOWN_S: float = 3.0
var _attack_cooldown: float = 0.0

## Random wander radius around the spawn anchor.
const WANDER_RADIUS_M: float = 8.0

## Height bats prefer to fly above terrain / builder.
const PREFERRED_HEIGHT_M: float = 3.0

# ─── Default stat constants ───────────────────────────────────────────────────
# Set in _ready() before super._ready(). Inspector overrides respected if changed.
const _DEFAULT_MAX_HP: int = 1
## Cruise/seek speed. Builder run speed is 4.5 m/s (builder.gd move_speed); the bat must be
## escapable, so its cruise sits BELOW the builder so a running player pulls away over distance.
## (v1.1 QA: bat cruised at 3.5 but dived at move_speed*1.5 = 5.25 > builder, so it was
## impossible to outrun. Cruise lowered to 3.0 and the dive multiplier cut — see ATTACK_DIVE_MULT.)
const _DEFAULT_MOVE_SPEED: float = 3.0
const _DEFAULT_ATTACK_DAMAGE: int = 1
const _DEFAULT_DETECT_RADIUS: float = 10.0

## Vampire-variant cruise speed (faster + tougher per DOCS §5.2), still under builder run
## speed so the player can break line and escape. (Was 5.0 = uncatchable.)
const _VAMPIRE_MOVE_SPEED: float = 3.8

## Swoop-dive speed multiplier applied to move_speed in ATTACK. Kept low enough that the
## brief dive peak stays at/under builder run speed (3.0*1.2=3.6 regular, 3.8*1.2=4.56
## vampire) so the dive can graze the player but a sustained run still escapes — especially
## with the post-hit recoil pause that follows every landed swoop.
const ATTACK_DIVE_MULT: float = 1.2

## Variant: "regular" | "vampire". Set by main_scene.spawn_hostile_mob when kind="bat_vampire".
@export var variant: String = "regular"

# ─── Node references ──────────────────────────────────────────────────────────

@onready var _chitter_audio: AudioStreamPlayer3D = $ChitterAudio

# ─── Runtime fields ───────────────────────────────────────────────────────────

## Committed swoop target position.
var _swoop_target: Vector3 = Vector3.ZERO

## Whether the bat is currently in a committed swoop dive.
var _is_swooping: bool = false

## Chitter cooldown; prevents chitter spam.
var _chitter_cooldown: float = 0.0

## Anchor position set at _ready() for random wander bounds.
var _wander_anchor: Vector3 = Vector3.ZERO

## Carry-over HP from vampire transform (set by main_scene before bat is fully ready).
var _hp_override: int = -1

# ─── Lifecycle ────────────────────────────────────────────────────────────────

func _ready() -> void:
	# Apply stat defaults BEFORE super._ready() sets hp = max_hp.
	max_hp = _DEFAULT_MAX_HP
	move_speed = _DEFAULT_MOVE_SPEED
	attack_damage = _DEFAULT_ATTACK_DAMAGE
	detect_radius = _DEFAULT_DETECT_RADIUS
	# Apply variant overrides.
	if variant == "vampire":
		max_hp = 2
		move_speed = _VAMPIRE_MOVE_SPEED
	super._ready()
	# Apply HP carry-over from vampire transform if set before _ready().
	if _hp_override > 0:
		hp = min(_hp_override, max_hp)
	# Register in bat_mob group for test detection (test_vampire_transform.gd).
	add_to_group("bat_mob")
	_wander_anchor = global_position
	state = State.IDLE
	# Phase 8 (ANIM-05): bat keeps its single-mesh TripoSR art; attach the
	# procedural transform-only fallback (AIR motion = rock only, no Y-bob since
	# the flight path owns global_position).
	_setup_procedural_anim(ProceduralCreatureAnimator.Motion.AIR)


func _art_kind() -> String:
	return "vampire_bat" if variant == "vampire" else "bat"


func _art_target_height() -> float:
	return 0.6


# ─── Physics process (no gravity — bat flies) ─────────────────────────────────

## Override base _physics_process to suppress gravity. Bats fly freely.
func _physics_process(delta: float) -> void:
	_state_timer += delta
	_path_query_cooldown -= delta
	_chitter_cooldown -= delta
	_attack_cooldown -= delta

	# NO gravity branch — bat flies. Intentional override of the base gravity logic.

	# Dispatch to state virtual.
	match state:
		State.IDLE:      _process_idle(delta)
		State.SEEK:      _process_seek(delta)
		State.ATTACK:    _process_attack(delta)
		State.FLEE:      _process_flee(delta)
		State.TRANSFORM: _process_transform(delta)
		State.DEAD:      _process_dead(delta)

	move_and_slide()
	_update_animator(delta)


# ─── State overrides ──────────────────────────────────────────────────────────

func _process_idle(_delta: float) -> void:
	# Random wander around the anchor within WANDER_RADIUS_M.
	var builder: Node3D = get_tree().get_first_node_in_group("builder") as Node3D

	# Wander: pick a random direction periodically.
	if _state_timer > 2.0:
		_state_timer = 0.0
		var rand_dir := Vector3(
			randf_range(-1.0, 1.0),
			randf_range(-0.3, 0.3),
			randf_range(-1.0, 1.0)
		).normalized()
		var wander_target := _wander_anchor + rand_dir * randf_range(2.0, WANDER_RADIUS_M)
		var to_wander := (wander_target - global_position).normalized()
		velocity = to_wander * (move_speed * 0.5)
	else:
		velocity = velocity.lerp(Vector3.ZERO, 0.05)

	# Detect builder → transition to SEEK.
	if builder != null:
		if global_position.distance_squared_to(builder.global_position) \
				<= detect_radius * detect_radius:
			state = State.SEEK
			_state_timer = 0.0


func _process_seek(_delta: float) -> void:
	var builder: Node3D = get_tree().get_first_node_in_group("builder") as Node3D
	if builder == null:
		state = State.IDLE
		return

	var dist: float = global_position.distance_to(builder.global_position)

	# Lost the builder → return to IDLE.
	if dist > detect_radius * 1.5:
		state = State.IDLE
		return

	# Direct steering toward builder at preferred height.
	var target_pos: Vector3 = builder.global_position + Vector3.UP * PREFERRED_HEIGHT_M
	var to_target: Vector3 = (target_pos - global_position).normalized()
	velocity = to_target * move_speed

	# Within swoop range → commit to swoop (D-09 tell: chitter).
	if dist <= SWOOP_COMMIT_RANGE_M and not _is_swooping:
		_is_swooping = true
		_swoop_target = builder.global_position
		# Play chitter tell per D-09.
		if _chitter_audio != null and _chitter_cooldown <= 0.0:
			_chitter_audio.play()
			_chitter_cooldown = CHITTER_COOLDOWN_S
		state = State.ATTACK
		_state_timer = 0.0


func _process_attack(_delta: float) -> void:
	var builder: Node3D = get_tree().get_first_node_in_group("builder") as Node3D
	if builder == null:
		_is_swooping = false
		state = State.SEEK
		return

	# Update swoop target to current builder pos.
	_swoop_target = builder.global_position

	# Dive toward the target.
	var to_target: Vector3 = (_swoop_target - global_position).normalized()
	velocity = to_target * move_speed * ATTACK_DIVE_MULT

	# On contact (or close enough): damage builder + reset to SEEK.
	var dist: float = global_position.distance_to(builder.global_position)
	if dist < 1.2:
		# Only land damage if the 3 s cooldown has elapsed — prevents the per-frame
		# attack-cycle from chaining hits into an instakill.
		if _attack_cooldown <= 0.0 and builder.has_method("take_damage"):
			builder.take_damage(attack_damage, global_position)
			recoil_from(builder.global_position)  # bounce back + pause so the builder can flee
			_attack_cooldown = ATTACK_COOLDOWN_S
		_is_swooping = false
		state = State.SEEK
		_state_timer = 0.0
	elif _state_timer > 3.0:
		# Abort swoop after 3 s — bat overshot or lost target.
		_is_swooping = false
		state = State.SEEK
		_state_timer = 0.0
