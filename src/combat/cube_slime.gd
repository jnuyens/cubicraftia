# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# cube_slime.gd — CubeSlime: 3-tier slime that splits on defeat.
#
# Tier split (DOCS §5.2):
#   LARGE (0) → spawns 3 MEDIUM (1) on defeat
#   MEDIUM (1) → spawns 2 SMALL (2) on defeat
#   SMALL (2) → drops loot only, no children
#
# D-09 strong tell: wobble-anticipation 'gather' (body crouches via scale tween) before
# each hop; green-particle burst + 2-3 smaller slimes on defeat.
#
# Per 03-RESEARCH.md Pitfall 3: children spawned via call_deferred to avoid spawning inside
# the parent's active CollisionShape3D.
#
# References:
#   hostile_mob.gd (Plan 03-03 — base class)
#   03-CONTEXT.md D-09 — slime wobble-anticipation + split tell
#   03-PATTERNS.md L471-507 — CubeSlime analog + RESEARCH Pitfall 3
#   src/bricks/slime_cube.tres — Phase 2 D-02 slime wobble shader material (reused)

class_name CubeSlime
extends HostileMob

# ─── Tier enum ────────────────────────────────────────────────────────────────
# IMPORTANT: LARGE=0, MEDIUM=1, SMALL=2 so tier+1 == the child tier.
# Test stubs in test_slime_split.gd fall back to these numeric values:
#   Tier_LARGE → 0, Tier_MEDIUM → 1, Tier_SMALL → 2.

enum SlimeTier { LARGE = 0, MEDIUM = 1, SMALL = 2 }

# ─── Constants ────────────────────────────────────────────────────────────────

## Cooldown between hops (seconds).
const HOP_COOLDOWN_S: float = 1.5

## Duration of the scale-down anticipation gather before each hop.
const ANTICIPATION_DURATION_S: float = 0.3

## HP per tier.
const HP_PER_TIER: Dictionary = {
	SlimeTier.LARGE: 4,
	SlimeTier.MEDIUM: 2,
	SlimeTier.SMALL: 1,
}

## Visual scale multiplier per tier (applied to Body MeshInstance3D).
const SCALE_PER_TIER: Dictionary = {
	SlimeTier.LARGE:  2.0,
	SlimeTier.MEDIUM: 1.4,
	SlimeTier.SMALL:  0.8,
}

## Number of children spawned when a LARGE dies.
const CHILD_COUNT_LARGE: int = 3

## Number of children spawned when a MEDIUM dies.
const CHILD_COUNT_MEDIUM: int = 2

## Hop velocity: horizontal speed × direction + upward component.
const HOP_HORIZONTAL_SPEED: float = 5.0
const HOP_VERTICAL_SPEED: float = 4.0

# ─── Export vars ──────────────────────────────────────────────────────────────

## Tier determines HP and split behaviour. Defaults to LARGE.
## Inspector-editable; _ready() applies HP_PER_TIER based on this value.
@export var tier: SlimeTier = SlimeTier.LARGE

# ─── Node references ──────────────────────────────────────────────────────────

@onready var _body_mesh: MeshInstance3D = $Body
@onready var _anim_player: AnimationPlayer = $AnimationPlayer

# ─── Runtime fields ───────────────────────────────────────────────────────────

## Remaining cooldown before the next hop is allowed.
var _hop_cooldown: float = 0.0

## True while the anticipation gather tween is playing.
var _anticipating: bool = false

## Active tween for the anticipation scale animation.
var _anticipation_tween: Tween = null

# ─── Lifecycle ────────────────────────────────────────────────────────────────

func _ready() -> void:
	# Set stat defaults. move_speed/attack_damage/detect_radius from HostileMob base.
	move_speed = 1.5
	attack_damage = 1
	detect_radius = 8.0
	# Set HP from tier BEFORE super._ready() sets hp = max_hp.
	max_hp = HP_PER_TIER.get(tier, 1)
	super._ready()
	hp = max_hp
	# Register in cube_slime group for test detection (test_slime_split.gd).
	add_to_group("cube_slime")
	# Start seeking immediately.
	state = State.IDLE
	# Phase 8 gap-closure replan (SC1 / ANIM-01): the slime is a soft-body creature, so
	# it now animates via the ShaderWobbleAnimator GPU squash/stretch wobble that ROADMAP
	# SC1 explicitly names ("via the shader-wobble system") — superseding the v1.1
	# transform-only ProceduralCreatureAnimator note. The wobble animator is the sole
	# visual for every tier; the .tscn "Body" placeholder stays hidden (kept for $Body
	# null-safety; the hop anticipation tween targets it for timing only) and the textured
	# Meshy art mesh (_art_mesh_root from _apply_art_mesh) is hidden so it does not
	# double-render behind the wobble mesh.
	if _body_mesh != null:
		_body_mesh.visible = false
	if _art_mesh_root != null:
		_art_mesh_root.visible = false
	# Attach the GPU wobble animator (BodyType.SLIME), sized per tier so a SMALL slime
	# reads visibly smaller than a LARGE one. Pattern mirrors wildlife._setup_animator
	# (FISH branch) and minifigure_animator_demo._spawn_wobble.
	var wobble := ShaderWobbleAnimator.new()
	wobble.mesh_set = "slime"
	wobble.body_type = ShaderWobbleAnimator.BodyType.SLIME
	wobble.body_colour = Color("#3DB560")  # brand slime green (matches demo)
	wobble.wobble_speed = 2.4
	wobble.wobble_amount = 0.22
	wobble.time_offset = randf() * TAU  # de-sync concurrent slimes
	# Per-tier size: the avatar wobble mesh is ~1 unit, so scaling by the tier's
	# target height (0.6 / 0.9 / 1.3) makes SMALL < MEDIUM < LARGE.
	wobble.scale = Vector3.ONE * _art_target_height()
	add_child(wobble)
	_anim = wobble


## Loads assets/meshes/creatures/slime.glb via HostileMob._apply_art_mesh (textured Meshy).
func _art_kind() -> String:
	return "slime"


func _art_target_height() -> float:
	match tier:
		SlimeTier.SMALL:  return 0.6
		SlimeTier.MEDIUM: return 0.9
		_:                return 1.3


# ─── Physics process (hop mechanic) ──────────────────────────────────────────

func _physics_process(delta: float) -> void:
	_hop_cooldown -= delta
	_state_timer += delta
	_path_query_cooldown -= delta

	# Apply gravity when airborne (mirrors HostileMob base).
	if not is_on_floor():
		velocity.y += get_gravity().y * delta
	else:
		velocity.y = 0.0

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
	if dist > detect_radius * 1.5:
		state = State.IDLE
		return

	# Contact attack if close enough and on floor.
	if dist < 1.5 and is_on_floor():
		if builder.has_method("take_damage"):
			builder.take_damage(attack_damage, global_position)
			recoil_from(builder.global_position)  # bounce back + pause so the builder can flee
		return

	# Hop mechanic: on floor + cooldown elapsed + not anticipating → gather then hop.
	if is_on_floor() and _hop_cooldown <= 0.0 and not _anticipating:
		_start_anticipation_and_hop(builder.global_position)


func _process_attack(_delta: float) -> void:
	pass


# ─── Hop mechanic ─────────────────────────────────────────────────────────────

## Play the anticipation gather (scale down 90%) then execute the hop.
## Per D-09: wobble-anticipation 'gather' before each hop.
func _start_anticipation_and_hop(builder_pos: Vector3) -> void:
	if _anticipating:
		return
	_anticipating = true

	# Scale body down to 90% over ANTICIPATION_DURATION_S (D-09 gather wobble).
	if _body_mesh != null:
		var base_scale: float = SCALE_PER_TIER.get(tier, 1.0)
		if _anticipation_tween != null and _anticipation_tween.is_valid():
			_anticipation_tween.kill()
		_anticipation_tween = create_tween()
		_anticipation_tween.tween_property(
			_body_mesh, "scale",
			Vector3(base_scale * 0.9, base_scale * 0.9, base_scale * 0.9),
			ANTICIPATION_DURATION_S
		).set_ease(Tween.EASE_OUT)

	# After anticipation: execute hop.
	await get_tree().create_timer(ANTICIPATION_DURATION_S).timeout
	if state == State.DEAD:
		_anticipating = false
		return

	# Restore scale.
	if _body_mesh != null:
		var base_scale: float = SCALE_PER_TIER.get(tier, 1.0)
		_body_mesh.scale = Vector3(base_scale, base_scale, base_scale)

	# Apply hop velocity.
	var dir: Vector3 = (builder_pos - global_position)
	dir.y = 0.0
	if dir.length_squared() > 0.01:
		dir = dir.normalized()
	velocity = dir * HOP_HORIZONTAL_SPEED + Vector3.UP * HOP_VERTICAL_SPEED
	_hop_cooldown = HOP_COOLDOWN_S
	_anticipating = false


# ─── Death + split ────────────────────────────────────────────────────────────

## Override _on_die: per RESEARCH Pitfall 3, spawn children via call_deferred AFTER
## the AnimationPlayer plays "die" and the physics step clears the collider.
func _on_die() -> void:
	state = State.DEAD
	emit_signal("died")

	# Play death animation if available.
	if _anim_player != null and _anim_player.has_animation("die"):
		_anim_player.play("die")
		await _anim_player.animation_finished

	# Per RESEARCH Pitfall 3: spawn children AFTER the frame to avoid collider overlap.
	if tier < SlimeTier.SMALL:
		call_deferred("_spawn_children")
	else:
		queue_free()


## Spawn child slimes of the next tier at offset positions.
## Called via call_deferred from _on_die() to avoid physics-step collision with parent.
## Per 03-RESEARCH.md Pitfall 3 + T-03-10-MB-03 (children spawn offset from parent).
func _spawn_children() -> void:
	var child_count: int = CHILD_COUNT_LARGE if tier == SlimeTier.LARGE else CHILD_COUNT_MEDIUM
	var child_tier: int = tier + 1

	for _i: int in range(child_count):
		var offset := Vector3(
			randf_range(-1.5, 1.5),
			0.5,
			randf_range(-1.5, 1.5)
		)
		# Ensure the offset is at least 0.1 m from center (Pitfall 3 / T-03-10-MB-03).
		if offset.length() < 0.1:
			offset = Vector3(0.5, 0.5, 0.0)

		var spawn_pos: Vector3 = global_position + offset

		# Prefer main_scene.spawn_hostile_mob() for full production wiring.
		if _main_scene != null and _main_scene.has_method("spawn_hostile_mob"):
			_main_scene.spawn_hostile_mob("cube_slime", spawn_pos, {"tier": child_tier})
		else:
			# Fallback for tests and detached nodes: instantiate directly into parent's tree.
			_spawn_child_directly(child_tier, spawn_pos)

	queue_free()


## Fallback child spawn when _main_scene is not available (e.g. GUT tests).
## Adds the child to the same parent as the dying slime so the tree group scan works.
func _spawn_child_directly(child_tier: int, spawn_pos: Vector3) -> void:
	var scene_path: String = "res://src/combat/cube_slime.tscn"
	if not ResourceLoader.exists(scene_path):
		# No scene yet — instantiate directly from the class for unit tests.
		var child_slime: CubeSlime = CubeSlime.new()
		child_slime.tier = child_tier as SlimeTier
		if get_parent() != null:
			get_parent().add_child(child_slime)
			child_slime.global_position = spawn_pos
		return
	var packed: PackedScene = ResourceLoader.load(scene_path) as PackedScene
	if packed == null:
		return
	var child: Node = packed.instantiate()
	if "tier" in child:
		child.tier = child_tier as SlimeTier
	if get_parent() != null:
		get_parent().add_child(child)
		if child is Node3D:
			(child as Node3D).global_position = spawn_pos
