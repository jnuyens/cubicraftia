# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# vampire.gd — Vampire: ground-based humanoid that transforms into bat form at HP ≤ 2.
#
# D-09 strong tell (0.9 s total, per 03-CONTEXT.md D-09):
#   Phase 1 (0.4 s): Eyes flicker red (#D63828 per UI-SPEC L111) — warning to player.
#   Phase 2 (0.5 s): Wing-spread animation precedes the transform.
#   During tell: collision_layer=0 (invulnerable per RESEARCH Pitfall 4).
#
# Transform HP threshold: HP ≤ TRANSFORM_HP_THRESHOLD (= 2 per D-09 "≤ 2 HP remaining").
# Transform fires once (_transforming guard prevents re-trigger).
# After transform: spawn bat_vampire form via main_scene.spawn_hostile_mob() with remaining HP.
#
# Per 03-RESEARCH.md Pitfall 4: HP carries to the bat form (capped at bat.max_hp).
# Per 03-RESEARCH.md Pitfall 4: collision_layer=0 during TRANSFORM state = invuln window.
# Per T-03-10-MB-02: _transforming=true on first transform; never resets.
#
# References:
#   hostile_mob.gd (Plan 03-03 — base class)
#   bat.gd (Plan 03-10 — spawned as "bat_vampire" variant)
#   03-CONTEXT.md D-09 — vampire transform tell (eye-flicker + wing-spread)
#   03-RESEARCH.md Pitfall 4 — invuln window + HP carry
#   03-PATTERNS.md L444-467 — Vampire analog

class_name Vampire
extends HostileMob

# ─── Constants ────────────────────────────────────────────────────────────────

## HP threshold at or below which the transform triggers per D-09.
const TRANSFORM_HP_THRESHOLD: int = 2

## Eye-flicker duration per D-09 (first phase of the tell).
const EYE_FLICKER_DURATION_S: float = 0.4

## Wing-spread animation duration per D-09 (second phase of the tell).
const WING_SPREAD_DURATION_S: float = 0.5

## Total tell duration (eye flicker + wing spread = 0.9 s per D-09).
const TRANSFORM_TELL_DURATION_S: float = EYE_FLICKER_DURATION_S + WING_SPREAD_DURATION_S

## Navigation re-query rate for vampire's ground walk (4 Hz).
const NAV_REQUERY_HZ: float = 4.0

## Attack cooldown (seconds).
const ATTACK_COOLDOWN_S: float = 1.0

# ─── Default stat constants ───────────────────────────────────────────────────
# Vampire: 5 HP, slow walk, hits hard. Transforms at ≤ 2 HP.
const _DEFAULT_MAX_HP: int = 5
const _DEFAULT_MOVE_SPEED: float = 2.0
const _DEFAULT_ATTACK_DAMAGE: int = 2
const _DEFAULT_DETECT_RADIUS: float = 10.0

# ─── Node references ──────────────────────────────────────────────────────────

@onready var _body_mesh: MeshInstance3D = $Body
@onready var _eyes_mesh: MeshInstance3D = $Eyes
@onready var _anim_player: AnimationPlayer = $AnimationPlayer

# ─── Runtime fields ───────────────────────────────────────────────────────────

## Guard to prevent re-triggering the transform (T-03-10-MB-02).
## Set to true permanently on first _begin_transform(). Never resets.
var _transforming: bool = false

## Navigation re-query cooldown for ground walk.
var _nav_query_cooldown: float = 0.0

## Attack cooldown.
var _attack_cooldown: float = 0.0

# ─── Lifecycle ────────────────────────────────────────────────────────────────

func _ready() -> void:
	# Apply stat defaults before super._ready() sets hp = max_hp.
	max_hp = _DEFAULT_MAX_HP
	move_speed = _DEFAULT_MOVE_SPEED
	attack_damage = _DEFAULT_ATTACK_DAMAGE
	detect_radius = _DEFAULT_DETECT_RADIUS
	super._ready()
	state = State.IDLE
	# v1.1 art pass: textured Meshy vampire mesh (via _apply_art_mesh) replaces the builder
	# rig. Gentle transform-only idle motion on top.
	_setup_procedural_anim(ProceduralCreatureAnimator.Motion.LAND)
	# Hide the .tscn primitive placeholders (kept present for $Body/$Eyes null-safety).
	if _body_mesh != null:
		_body_mesh.visible = false
	if _eyes_mesh != null:
		_eyes_mesh.visible = false


## Loads assets/meshes/creatures/vampire.glb via HostileMob._apply_art_mesh (textured Meshy).
func _art_kind() -> String:
	return "vampire"


func _art_target_height() -> float:
	return 1.8


# ─── Physics process ──────────────────────────────────────────────────────────

func _physics_process(delta: float) -> void:
	_nav_query_cooldown -= delta
	_attack_cooldown -= delta
	super._physics_process(delta)  # base drives _update_animator() after its move_and_slide()


# ─── Public API: take_damage override ────────────────────────────────────────

## Override take_damage with a default from_pos so tests can call take_damage(amount).
## Checks transform threshold after applying damage per D-09 + RESEARCH Pitfall 4.
## @param amount    Damage points.
## @param from_pos  Hit origin (default Vector3.ZERO for test ergonomics).
func take_damage(amount: int, from_pos: Vector3 = Vector3.ZERO) -> void:
	super.take_damage(amount, from_pos)
	# After applying damage: check transform threshold.
	if hp <= TRANSFORM_HP_THRESHOLD and hp > 0 and not _transforming:
		_begin_transform()


# ─── Transform mechanic ───────────────────────────────────────────────────────

## Begin the eye-flicker + wing-spread tell, then spawn bat form.
## Sets state=TRANSFORM and collision_layer=0 (invuln window) SYNCHRONOUSLY.
## The 0.9 s tell + bat spawn is async (via await). Per RESEARCH Pitfall 4.
func _begin_transform() -> void:
	_transforming = true
	state = State.TRANSFORM
	_state_timer = 0.0
	# Invulnerability window: collision_layer=0 during transform tell (Pitfall 4).
	collision_layer = 0
	# Async: perform the 0.9 s tell then spawn bat form.
	_run_transform_async()


## Async coroutine for the transform tell sequence.
## Uses individual awaits so it's cleanly cancellable in tests.
func _run_transform_async() -> void:
	if not is_inside_tree():
		return
	# Phase 1: Eye-flicker red (#D63828) for EYE_FLICKER_DURATION_S per D-09.
	if _eyes_mesh != null:
		var eye_tween: Tween = create_tween()
		eye_tween.tween_property(_eyes_mesh, "modulate",
			Color("#D63828"), EYE_FLICKER_DURATION_S * 0.5).set_ease(Tween.EASE_OUT)
		eye_tween.tween_property(_eyes_mesh, "modulate",
			Color("#D63828"), EYE_FLICKER_DURATION_S * 0.5).set_ease(Tween.EASE_IN)

	await get_tree().create_timer(EYE_FLICKER_DURATION_S).timeout

	if not is_inside_tree() or state == State.DEAD:
		return

	# Phase 2: Wing-spread animation for WING_SPREAD_DURATION_S per D-09.
	if _anim_player != null and _anim_player.has_animation("wing_spread"):
		_anim_player.play("wing_spread")

	await get_tree().create_timer(WING_SPREAD_DURATION_S).timeout

	if not is_inside_tree() or state == State.DEAD:
		return

	# Spawn bat form with remaining HP (RESEARCH Pitfall 4 HP carry).
	# Per 03-PATTERNS.md L444: spawn via main_scene.spawn_hostile_mob("bat_vampire", ...).
	if _main_scene != null and _main_scene.has_method("spawn_hostile_mob"):
		_main_scene.spawn_hostile_mob("bat_vampire", global_position,
			{"hp": hp, "variant": "vampire"})
	else:
		# Fallback for tests: instantiate bat directly into parent scene tree.
		_spawn_bat_directly()

	# Self-destruct after transform. Note: Spawning.notify_despawned fires via _exit_tree().
	queue_free()


## Fallback bat spawn when _main_scene is not available (e.g. GUT tests).
## Spawns a Bat instance into the parent scene tree with the current HP.
func _spawn_bat_directly() -> void:
	var scene_path: String = "res://src/combat/bat.tscn"
	if not ResourceLoader.exists(scene_path):
		# Scene doesn't exist yet; instantiate from class directly.
		var bat: Bat = Bat.new()
		bat.variant = "vampire"
		bat.max_hp = 2
		bat._hp_override = hp
		if get_parent() != null:
			get_parent().add_child(bat)
			bat.global_position = global_position
		return
	var packed: PackedScene = ResourceLoader.load(scene_path) as PackedScene
	if packed == null:
		return
	var bat: Node = packed.instantiate()
	if "variant" in bat:
		bat.variant = "vampire"
	if "_hp_override" in bat:
		bat._hp_override = hp
	if get_parent() != null:
		get_parent().add_child(bat)
		if bat is Node3D:
			(bat as Node3D).global_position = global_position


# ─── State overrides ──────────────────────────────────────────────────────────

func _process_idle(_delta: float) -> void:
	var builder: Node3D = get_tree().get_first_node_in_group("builder") as Node3D
	if builder == null:
		return
	if global_position.distance_squared_to(builder.global_position) \
			<= detect_radius * detect_radius:
		state = State.SEEK
		_state_timer = 0.0


func _process_seek(_delta: float) -> void:
	if _transforming:
		return  # Don't move during transform.

	var builder: Node3D = get_tree().get_first_node_in_group("builder") as Node3D
	if builder == null:
		state = State.IDLE
		return

	var dist: float = global_position.distance_to(builder.global_position)
	if dist > detect_radius * 1.5:
		state = State.IDLE
		return

	# Chase the builder: walk the navmesh path when one is baked, else direct beeline
	# (the procedural voxel world bakes no navmesh, so this is the live path). Stop at
	# contact range so the vampire doesn't overshoot before its bite lands.
	# _steer_toward() issues the throttled nav query internally (base PATH_REQUERY_HZ).
	_steer_toward(builder.global_position, _delta, 1.5)

	# Contact attack.
	if dist < 1.5 and _attack_cooldown <= 0.0:
		if builder.has_method("take_damage"):
			builder.take_damage(attack_damage, global_position)
			recoil_from(builder.global_position)  # bounce back + pause so the builder can flee
		_attack_cooldown = ATTACK_COOLDOWN_S


func _process_transform(_delta: float) -> void:
	# Stop moving during transform tell.
	velocity = Vector3.ZERO


# ─── Navigation helper ────────────────────────────────────────────────────────

func _walk_cached_path() -> void:
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
	if dir.length_squared() > 0.01:
		look_at(global_position + dir, Vector3.UP)
