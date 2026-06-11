# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# ghost.gd — Ghost: wall-passing hostile that phases through bricks and terrain.
#
# D-09 strong tell:
#   - Phase-shimmer VFX: semi-transparent body (modulate alpha 0.6) + shimmer particle
#     burst when inside state == SEEK (phase-through-wall visual per D-09).
#   - Soft chime audio on first detection within CHIME_DETECT_RANGE_M per D-09.
#
# D-10 bed-bubble repel: Ghost is physically pushed OUT of any bed-bubble with a
# repulsive velocity + shimmer particle burst at the boundary. This is the ONLY place
# where ghost traversal is blocked. Outside bubbles, ghost phases through everything.
#
# Wall-pass: collision_layer=0, collision_mask=0 in _ready() → ghost phases through all
# bricks AND terrain. CharacterBody3D still provides move_and_slide for movement math.
#
# Per 03-CONTEXT.md D-09 + D-10, 03-PATTERNS.md L432-440, 03-RESEARCH.md Pitfall 9.
#
# References:
#   hostile_mob.gd (Plan 03-03 — base class)
#   src/autoload/spawning.gd — is_inside_any_bed_bubble() API
#   03-CONTEXT.md D-09 — phase-shimmer tell + chime
#   03-CONTEXT.md D-10 — bed-bubble repel (sacred radius)
#   03-PATTERNS.md L432-440 — Ghost analog
#   03-RESEARCH.md Pitfall 9 — sleep cancellation when ghost enters bubble during sleep

class_name Ghost
extends HostileMob

# ─── Constants ────────────────────────────────────────────────────────────────

## Shimmer alpha for the ghost body per D-09 (partially transparent, eerie look).
const PHASE_SHIMMER_ALPHA: float = 0.6

## Detection range before playing the chime sound per D-09.
const CHIME_DETECT_RANGE_M: float = 15.0

## Repulsive velocity magnitude when bouncing off a bed-bubble (D-10).
const BUBBLE_REPEL_FORCE: float = 8.0

## Cooldown on attacks (seconds).
const ATTACK_COOLDOWN_S: float = 1.5

# ─── Default stat constants ───────────────────────────────────────────────────
# Ghost: moderate HP, medium speed, hits hard.
const _DEFAULT_MAX_HP: int = 3
const _DEFAULT_MOVE_SPEED: float = 2.0
const _DEFAULT_ATTACK_DAMAGE: int = 1
const _DEFAULT_DETECT_RADIUS: float = 15.0

# ─── Node references ──────────────────────────────────────────────────────────

@onready var _body_mesh: MeshInstance3D = $Body
@onready var _chime_audio: AudioStreamPlayer3D = $ChimeAudio
@onready var _shimmer_particles: GPUParticles3D = $ShimmerParticles

# ─── Runtime fields ───────────────────────────────────────────────────────────

## Whether the ghost was inside a bed-bubble last tick (for edge detection).
var _was_in_bubble: bool = false

## Whether the chime has played for the current detection window.
var _chime_played_this_detection: bool = false

## Remaining attack cooldown.
var _attack_cooldown: float = 0.0

# ─── Lifecycle ────────────────────────────────────────────────────────────────

func _ready() -> void:
	# Apply stat defaults before super._ready() sets hp = max_hp.
	max_hp = _DEFAULT_MAX_HP
	move_speed = _DEFAULT_MOVE_SPEED
	attack_damage = _DEFAULT_ATTACK_DAMAGE
	detect_radius = _DEFAULT_DETECT_RADIUS
	super._ready()
	# Wall-pass: set collision masks to 0 so ghost phases through all bricks + terrain.
	# Per D-09 + 03-PATTERNS.md L437 "collision_layer=0, collision_mask=0".
	collision_layer = 0
	collision_mask = 0
	state = State.IDLE
	# Phase 8 gap-closure replan (SC1 / ANIM-01): the ghost is a soft-body creature, so it
	# now animates via the ShaderWobbleAnimator GPU float + alpha-pulse wobble that ROADMAP
	# SC1 explicitly names ("via the shader-wobble system") — superseding the v1.1
	# transform-only ProceduralCreatureAnimator note. The wobble animator is the sole
	# visual; the .tscn "Body" placeholder stays hidden (kept for $Body null-safety) and the
	# textured Meshy art mesh (_art_mesh_root from _apply_art_mesh) is hidden so it does not
	# double-render behind the wobble mesh. The GHOST alpha/shimmer is driven inside
	# creature_wobble.gdshader; the PHASE_SHIMMER_ALPHA constant + D-09 shimmer particles
	# (SEEK-state VFX) are unchanged.
	if _body_mesh != null:
		_body_mesh.visible = false
	if _art_mesh_root != null:
		_art_mesh_root.visible = false
	# Attach the GPU wobble animator (BodyType.GHOST). Pattern mirrors
	# wildlife._setup_animator (FISH branch) and minifigure_animator_demo._spawn_wobble.
	var wobble := ShaderWobbleAnimator.new()
	wobble.mesh_set = "ghost"
	wobble.body_type = ShaderWobbleAnimator.BodyType.GHOST
	wobble.body_colour = Color("#F1F0EA")  # demo ghost tint (shader drives alpha pulse)
	wobble.wobble_speed = 1.6
	wobble.wobble_amount = 0.30
	wobble.time_offset = randf() * TAU  # de-sync concurrent ghosts
	add_child(wobble)
	_anim = wobble


## Loads assets/meshes/creatures/ghost.glb via HostileMob._apply_art_mesh (textured Meshy).
func _art_kind() -> String:
	return "ghost"


func _art_target_height() -> float:
	return 1.3


# ─── Physics process (ghost-specific — no gravity, bed-bubble check per tick) ──

## Override base _physics_process.
## Ghost floats (no gravity). Bed-bubble check every physics tick per D-10 + Pitfall 9.
func _physics_process(delta: float) -> void:
	_state_timer += delta
	_path_query_cooldown -= delta
	_attack_cooldown -= delta

	# NO gravity — ghost floats. Intentional override of base gravity branch.

	# ─── Bed-bubble repel (D-10 + RESEARCH Pitfall 9) ─────────────────────────
	# Per D-10: bed-bubble is sacred; ghost bounces off with shimmer at boundary.
	# Polled every physics tick per 03-PATTERNS.md Ghost analog.
	var in_bubble: bool = false
	if Spawning.has_method("is_inside_any_bed_bubble"):
		in_bubble = Spawning.is_inside_any_bed_bubble(global_position)

	if in_bubble and not _was_in_bubble:
		# Ghost just entered a bed-bubble: apply repulsive impulse.
		var builder: Node3D = get_tree().get_first_node_in_group("builder") as Node3D
		if builder != null:
			var to_builder: Vector3 = (builder.global_position - global_position).normalized()
			velocity = -to_builder * BUBBLE_REPEL_FORCE
		else:
			# No builder reference: push back along current velocity direction.
			velocity = -velocity.normalized() * BUBBLE_REPEL_FORCE

		# Shimmer burst at boundary per D-10 + UI-SPEC L79 + L116.
		if _shimmer_particles != null:
			_shimmer_particles.emitting = true

		# Per RESEARCH Pitfall 9: cancel sleep lapse if one is active.
		# WorldClock.cancel_sleep_lapse is the API (per 03-03 SUMMARY).
		if WorldClock.has_method("cancel_sleep_lapse"):
			WorldClock.cancel_sleep_lapse("ghost_entered_bubble")

	_was_in_bubble = in_bubble

	# Dispatch state machine.
	match state:
		State.IDLE:      _process_idle(delta)
		State.SEEK:      _process_seek(delta)
		State.ATTACK:    _process_attack(delta)
		State.FLEE:      _process_flee(delta)
		State.TRANSFORM: _process_transform(delta)
		State.DEAD:      _process_dead(delta)

	move_and_slide()
	_update_animator(delta)  # drive the GPU wobble animator each frame (parity with bat.gd)


# ─── State overrides ──────────────────────────────────────────────────────────

func _process_idle(_delta: float) -> void:
	var builder: Node3D = get_tree().get_first_node_in_group("builder") as Node3D
	if builder == null:
		return
	var dist: float = global_position.distance_to(builder.global_position)
	if dist <= detect_radius:
		# Play chime on first detection per D-09.
		if not _chime_played_this_detection:
			_chime_played_this_detection = true
			if _chime_audio != null:
				_chime_audio.play()
		state = State.SEEK
		_state_timer = 0.0
	else:
		_chime_played_this_detection = false


func _process_seek(_delta: float) -> void:
	var builder: Node3D = get_tree().get_first_node_in_group("builder") as Node3D
	if builder == null:
		state = State.IDLE
		return

	var dist: float = global_position.distance_to(builder.global_position)

	# Return to IDLE if builder is far away.
	if dist > detect_radius * 1.5:
		state = State.IDLE
		_chime_played_this_detection = false
		return

	# Direct steering toward builder (no nav mesh — ghost flies through walls).
	# Per 03-PATTERNS.md L437 "direct steering toward Builder".
	var dir: Vector3 = (builder.global_position - global_position).normalized()
	velocity = dir * move_speed

	# Contact attack: within 1.0 m.
	if dist < 1.0 and _attack_cooldown <= 0.0:
		if builder.has_method("take_damage"):
			builder.take_damage(attack_damage, global_position)
			recoil_from(builder.global_position)  # bounce back + pause so the builder can flee
		_attack_cooldown = ATTACK_COOLDOWN_S


func _process_attack(_delta: float) -> void:
	# Ghost attacks are handled inline in SEEK (contact attack).
	state = State.SEEK
