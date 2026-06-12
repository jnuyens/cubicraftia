# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# hostile_mob.gd — Base class for all 5 hostile creatures in Cubicraftia.
#
# Anchors: DOCS.md §5.2 Creatures + §5.3 Spawning rules
# References:
#   03-CONTEXT.md D-09 — every creature has a strong, mobile-readable "tell"
#   03-CONTEXT.md D-10 — bed-radius sacred; ghost repelled at bubble boundary
#   03-RESEARCH.md Pattern 2 — Hostile Mob State Machine + Throttled NavigationServer3D
#   03-RESEARCH.md Architectural Responsibility Map — hostile AI is a separate tier
#   03-PATTERNS.md L304-385 — HostileMob analog + state-fields + scene-shell template
#
# CRITICAL: This class does NOT extend VillageNpc. Per CONTEXT D-09 + 03-RESEARCH.md
# Architectural Responsibility Map, hostile-creature AI is a separate identity from
# peaceful-NPC AI. Inherit the SHAPE only (CharacterBody3D + state timer + _physics_process
# branches + collider shell + gravity branch), NOT the IDENTITY.
#
# Subclasses (Plan 03-10) ship the 5 concrete creatures:
#   - laser_penguin.gd   (charge-up + cone laser)
#   - ghost.gd           (wall-pass + bubble-repel at D-10 boundary)
#   - vampire.gd         (transform at 50% HP → bat form)
#   - bat.gd             (regular flying bat)
#   - cube_slime.gd      (3-tier split on defeat)

class_name HostileMob
extends CharacterBody3D

# ─── State enum ──────────────────────────────────────────────────────────────

## AI state machine. Subclasses override _process_<state>(delta) virtuals.
enum State { IDLE, SEEK, ATTACK, FLEE, TRANSFORM, DEAD }

# ─── Constants ────────────────────────────────────────────────────────────────

## Path re-query rate per RESEARCH Pattern 2 (Godot nav-performance best-practice).
## Queries NavigationServer3D.map_get_path() at most every 0.25 s (4 Hz).
const PATH_REQUERY_HZ: float = 4.0
const PATH_REQUERY_INTERVAL_S: float = 1.0 / PATH_REQUERY_HZ

## Knockback distance per D-08: roughly half a terrain cube (0.5 m).
## No airborne knockback per D-08.
const KNOCKBACK_DISTANCE_M: float = 0.5

## After landing a hit on the builder, the mob recoils this far and pauses this long before
## re-engaging — giving the builder room to flee or prepare (v1.1 QA: mobs too relentless).
const POST_HIT_RECOIL_M: float = 5.0
const POST_HIT_PAUSE_S: float = 1.4

## Seconds remaining in the post-hit recoil pause (>0 = paused; skips seek/attack).
var _post_hit_pause: float = 0.0

# ─── Exported tunables ───────────────────────────────────────────────────────
# Each subclass can override these via @export on its .tres or scene inspector.

## Maximum hit-points. Plan 03-10 subclasses set this per-creature.
@export var max_hp: int = 4

## Base movement speed in metres per second.
@export var move_speed: float = 1.5

## Damage applied per hit to the builder.
@export var attack_damage: int = 1

## Detection radius for SEEK state trigger.
@export var detect_radius: float = 15.0

# ─── Signals ─────────────────────────────────────────────────────────────────

## Emitted when this mob takes damage. Subclasses (Plan 03-10) may extend with
## creature-specific signals (e.g. charge_complete for penguin, transform_initiated
## for vampire).
signal damaged(amount: int, from_pos: Vector3)

## Emitted when this mob dies (HP reaches 0 and _on_die() fires).
signal died()

# ─── Runtime fields ───────────────────────────────────────────────────────────

## Current hit-points. Set to max_hp in _ready().
var hp: int = 0

## Current AI state. Drives _physics_process dispatch.
var state: State = State.IDLE

## Time accumulator for the current state (reset on state transition).
var _state_timer: float = 0.0

## Cooldown before the next NavigationServer3D path re-query.
var _path_query_cooldown: float = 0.0

## Most recently computed navigation path. Walked between re-queries.
var _current_path: PackedVector3Array = PackedVector3Array()

## Current index into _current_path.
var _path_index: int = 0

## Reference to MainScene, injected via set_main_scene(). Used for brick-pop VFX
## on take_damage (main_scene.spawn_dropped_item API from Phase 2 L415).
## Null-safe: VFX is skipped when _main_scene is null (e.g. detached test node).
var _main_scene: Node = null

## Tween reference for the damage flash VFX. Stored to avoid creating duplicate Tweens.
var _flash_tween: Tween = null

# ─── Phase 8: Animation ───────────────────────────────────────────────────────

## Distance-squared LOD gate (ANIM-06): beyond 40 m the animator gait update is
## skipped (last pose holds — never freed/reset; all motion is parametric).
const _ANIM_LOD_DIST_SQ: float = 40.0 * 40.0

## Hostile mobs that ship a skinned, animated Meshy GLB (parallel to wildlife's
## _ANIMATED_GLB giraffe path). Maps _art_kind() → rigged .glb path. Each asset is a
## single-skin, textured humanoid carrying ONE baked motion clip named
## "Armature|clip0|baselayer" (no separate idle/walk — clip0 IS the creature's motion).
## That clip now carries a REAL in-place walk cycle: the limb/spine rotations from the
## builder "Walking" mocap were transplanted onto these rigs (identical 24-bone skeleton),
## with the Hips root translation frozen so the rig walks in place while AI velocity drives
## forward travel. _clip_has_motion() therefore returns true and the degenerate-clip bob
## overlay is skipped (see _setup_skinned_rig / _update_animator).
## When _setup_procedural_anim() finds the kind here, it instantiates the rigged GLB as
## the visual, scales/grounds/faces it, hides the static _art_mesh_root, and plays clip0
## while the mob is active (SEEK/ATTACK/FLEE) — pausing it (rest pose) on IDLE. The
## procedural transform animator is NOT used for these (no double-driving the transform).
const _RIGGED_GLB: Dictionary = {
	"goblin":  "res://assets/meshes/avatars/goblin/goblin_rigged.glb",
	"vampire": "res://assets/meshes/avatars/vampire/vampire_rigged.glb",
	"zombie":  "res://assets/meshes/avatars/zombie/zombie_rigged.glb",
	# GAME-READY scripted-Rigify NON-humanoid hostiles (rigify-test batch). Skinned,
	# textured meshes with ONE looping "Walk" clip (resolved via the clips[0] fallback
	# in _setup_skinned_rig — there is no baselayer/clip0 name). Wired exactly like the
	# goblin: scale by mesh-subtree AABB, ground feet at the body origin, PI-yaw facing,
	# play Walk while the mob is active (SEEK/ATTACK/FLEE) and pause (rest pose) on IDLE.
	# Keyed by _art_kind(): bat's vampire variant returns "vampire_bat" (NOT keyed here —
	# its rig failed and is excluded — so vampire-bats keep the procedural fallback).
	"bat":           "res://assets/meshes/avatars/bat/bat.glb",
	"laser_penguin": "res://assets/meshes/avatars/laser_penguin/laser_penguin.glb",
	"wolf":          "res://assets/meshes/avatars/wolf/wolf.glb",
}

## Typed animator (MinifigureAnimator / ShaderWobbleAnimator) when this mob has a
## dedicated rig/wobble asset; null when the mob uses the procedural fallback.
var _anim: Node3D = null

## Procedural transform-only fallback for single-mesh mobs (bat, laser_penguin).
var _proc_anim: ProceduralCreatureAnimator = null

## AnimationPlayer of a skinned rigged Meshy mob (_RIGGED_GLB), else null. When set,
## the baked clip plays while the mob is active and pauses (rest pose) while IDLE.
var _skinned_anim: AnimationPlayer = null

## Name of the baked motion clip on _skinned_anim (resolved at setup, e.g. clip0).
var _skinned_clip_name: String = ""

## Root Node3D of the instantiated rigged GLB (the live visual), else null.
var _rigged_root: Node3D = null

## Procedural body-motion overlay for a rigged mob whose baked clip carries NO real motion.
## Historically the Meshy "clip0" exports for the humanoid hostiles (goblin/vampire/zombie)
## baked a STATIC pose (72 channels, all zero-spread) — the AnimationPlayer "played" but no
## bone moved, so the mob slid rigidly, and this overlay gave it a visible alive-bob + sway.
## The shipped clips now carry a real transplanted walk cycle, so _clip_has_motion() returns
## true and this overlay stays null for them. It remains as a self-adapting fallback: any
## future rigged asset that still ships a degenerate (motionless) clip gets the bob overlay.
var _rigged_proc_anim: ProceduralCreatureAnimator = null

## Grounded baseline Y of the rigged root (set by _ground_rigged_to_target). The procedural
## overlay bobs AROUND this so it never un-grounds the feet-on-floor placement.
var _rigged_base_y: float = 0.0

## Cached builder node for the LOD-distance gate (resolved lazily).
var _builder_ref: Node3D = null

# ─── Lifecycle ────────────────────────────────────────────────────────────────

func _ready() -> void:
	hp = max_hp
	add_to_group("hostile_mob")
	# Swap the placeholder primitive for the TripoSR art mesh where one exists.
	_apply_art_mesh()
	# Notify Spawning autoload via thin pass-through to keep it as the single
	# signal authority for active-mob bookkeeping.
	if Engine.get_singleton_list().has("Spawning") or \
			get_tree().root.has_node("/root/Spawning"):
		var spawning: Node = get_tree().root.get_node_or_null("/root/Spawning")
		if spawning and spawning.has_method("notify_spawned"):
			spawning.notify_spawned(self)


# ─── Art-mesh swap (shared with wildlife.gd's _normalise_creature_mesh) ────────

## TripoSR art-mesh kind for this mob, e.g. "bat", "ghost", "cube_slime_large".
## Empty = keep the placeholder primitive. Subclasses override.
func _art_kind() -> String:
	return ""


## Target height (m) the art mesh is scaled to. Subclasses override per creature.
func _art_target_height() -> float:
	return 1.2


## Replace the placeholder "Body" primitive with the baked-vertex-colour TripoSR art
## mesh: expose its colours (white albedo hides them), stand it upright (-90° X), scale
## to a believable height, and recentre. No-op if the kind is empty or the glb absent —
## so mobs without art simply keep their primitive. Mirrors wildlife._normalise_creature_mesh.
func _apply_art_mesh() -> void:
	var kind: String = _art_kind()
	if kind.is_empty():
		return
	# Prefer the clean, hand-authored stylised model; TripoSR (dark blobby AI scan) is
	# only the fallback. (v1.1 QA: matches wildlife.gd's mesh preference.)
	var ps: PackedScene = null
	for suffix: String in ["", "_triposr"]:
		var p: String = "res://assets/meshes/creatures/%s%s.glb" % [kind, suffix]
		if ResourceLoader.exists(p):
			ps = load(p) as PackedScene
			break
	if ps == null:
		return
	var inst: Node3D = ps.instantiate() as Node3D
	if inst == null:
		return
	var mi: MeshInstance3D = _find_mesh_instance(inst)
	if mi == null or mi.mesh == null:
		inst.queue_free()
		return
	var mesh: Mesh = mi.mesh
	var is_art: bool = false
	for s: int in mesh.get_surface_count():
		if (mesh.surface_get_format(s) & Mesh.ARRAY_FORMAT_COLOR) != 0:
			is_art = true
			var mat := StandardMaterial3D.new()
			mat.vertex_color_use_as_albedo = true
			mat.roughness = 1.0
			mi.set_surface_override_material(s, mat)
	var target_h: float = _art_target_height()
	if not is_art:
		# Clean upright model: keep its real materials, scale the whole root, and centre
		# it on the body origin using the FULL subtree bounds (multi-part safe).
		var full: AABB = _subtree_local_aabb(inst)
		var nat: float = maxf(full.size.x, maxf(full.size.y, full.size.z))
		nat = maxf(nat, 0.001)
		var s: float = target_h / nat
		inst.scale = Vector3.ONE * s
		var c: Vector3 = full.get_center() * s
		# Stash the Y baseline so the LAND idle bob oscillates around the centred
		# position instead of zeroing it (the fallback writes position.y absolutely).
		_art_base_y = -c.y
		inst.position = Vector3(-c.x, _art_base_y, -c.z)
	else:
		# TripoSR fallback: -90X upright + 180Y + scale, recentred on the body origin.
		var sz: Vector3 = mesh.get_aabb().size
		var native: float = maxf(sz.x, maxf(sz.y, sz.z))
		native = maxf(native, 0.001)
		var scl: float = target_h / native
		var basis := Basis.from_euler(Vector3(deg_to_rad(-90.0), deg_to_rad(180.0), 0.0)).scaled(Vector3(scl, scl, scl))
		var taabb: AABB = Transform3D(basis, Vector3.ZERO) * mesh.get_aabb()
		mi.transform = Transform3D(basis, -taabb.get_center())
	add_child(inst)
	# Phase 8: remember the art mesh-root so the procedural fallback can animate it.
	# Like wildlife._normalise_creature_mesh, the upright/scale/recentre is baked onto
	# the child MeshInstance3D, so the fallback only writes inst.position.y / rotation.z.
	_art_mesh_root = inst
	# Hide the placeholder primitive now that the art mesh is in place.
	var body: Node = get_node_or_null("Body")
	if body is GeometryInstance3D:
		(body as GeometryInstance3D).visible = false


## Phase 8: top-level Node3D of the loaded art mesh (procedural fallback target).
var _art_mesh_root: Node3D = null

## Y baseline for a clean (non-art) mesh centred via mesh-root translation; the LAND
## idle bob oscillates around this instead of zeroing the centring offset.
var _art_base_y: float = 0.0


## Phase 8 LOD gate (ANIM-06): true when the builder is far enough to skip the
## animator update this frame. Holds the last pose (no free/reset).
func _anim_lod_should_skip() -> bool:
	if _builder_ref == null or not is_instance_valid(_builder_ref):
		_builder_ref = get_tree().get_first_node_in_group("builder") as Node3D
	if _builder_ref == null:
		return false
	return global_position.distance_squared_to(_builder_ref.global_position) >= _ANIM_LOD_DIST_SQ


## Phase 8: gait string from the AI state, for rigid-piece animators (vampire).
func _gait_from_state() -> String:
	match state:
		State.ATTACK:    return "attack"
		State.SEEK, State.FLEE: return "walk"
		_:               return "idle"


## Phase 8: per-frame animator drive. Subclasses call this from _physics_process.
## Typed rig animators (MinifigureAnimator) read gait from state; the procedural
## fallback rocks the TripoSR mesh-root. Wobble animators run wholly on the GPU.
func _update_animator(delta: float) -> void:
	if _anim_lod_should_skip():
		return
	if _skinned_anim != null:
		# Skinned rigged mob (goblin/vampire/zombie): play the baked clip while the mob is
		# pursuing/attacking, pause it (rest pose) while IDLE/DEAD. The single clip0 is the
		# creature's generic motion — there's no separate idle/walk to switch between.
		var active: bool = (state == State.SEEK or state == State.ATTACK
			or state == State.FLEE or state == State.TRANSFORM)
		if active and _skinned_clip_name != "":
			if not _skinned_anim.is_playing():
				_skinned_anim.play(_skinned_clip_name)
		elif _skinned_anim.is_playing():
			_skinned_anim.pause()
		# Degenerate-clip overlay: the Meshy clip0 bakes a static pose, so the rig would slide
		# without limb/body motion. Give it a procedural bob + sway around the grounded baseline so
		# it reads as alive. We always pass walking=false (full bob amplitude): the generic
		# animator zeroes the bob while "walking" on the assumption that leg/translation motion
		# conveys the gait, but this rig has NO limb motion to lean on — so the full vertical bob IS
		# the visible cadence that replaces the missing footsteps.
		if _rigged_proc_anim != null and _rigged_root != null:
			_rigged_proc_anim.update(_rigged_root, delta, false, _rigged_base_y)
		return
	if _anim is MinifigureAnimator:
		(_anim as MinifigureAnimator).gait = _gait_from_state()
	elif _proc_anim != null:
		var walking: bool = state == State.SEEK or state == State.FLEE
		_proc_anim.update(_art_mesh_root, delta, walking, _art_base_y)


## Phase 8: attach the procedural transform-only fallback for single-mesh mobs.
## Call AFTER super._ready() (so _apply_art_mesh has populated _art_mesh_root).
##
## If the mob's _art_kind() ships a skinned rigged GLB (_RIGGED_GLB — goblin/vampire/
## zombie), route to _setup_skinned_rig() instead: the rigged skeletal visual replaces the
## static art mesh and plays its baked clip while active. The procedural transform animator
## is then NOT created (so we never double-drive the transform — the skeleton owns motion).
func _setup_procedural_anim(motion: ProceduralCreatureAnimator.Motion) -> void:
	if _RIGGED_GLB.has(_art_kind()):
		_setup_skinned_rig()
		return
	_proc_anim = ProceduralCreatureAnimator.new(motion)


## Phase 8: set up a skinned, animated Meshy mob (_RIGGED_GLB) — the HOSTILE analog of
## wildlife._setup_skinned_glb (the giraffe). Instantiates the rigged GLB as the live
## visual, faces it head-first (PI yaw, so look_at's -Z lead points at the walk dir — same
## convention as the static art path and wildlife), finds the AnimationPlayer + baked clip,
## loops the clip, and starts it PAUSED (the asset ships no separate idle clip, so IDLE shows
## the rest pose). The static _art_mesh_root is hidden so there's no doubled mesh.
##
## SCALE/GROUND is deferred one frame to _ground_rigged_to_target(): these Meshy rigs carry a
## skinned mesh whose raw mesh.get_aabb() is the PRE-SKIN local bounds (~0.017 m), NOT the
## rendered height. The mesh only reaches its real ~1.7 m height once the Skeleton3D (armature
## import scale ~0.01) deforms it. Scaling by the raw mesh AABB therefore over-scales by ~108x
## and renders a ~180 m giant. The robust fix measures the POSED-skeleton bounds (which reflect
## what actually renders) and scales from THAT — see _ground_rigged_to_target(). _update_animator
## drives play/pause.
func _setup_skinned_rig() -> void:
	var path: String = _RIGGED_GLB[_art_kind()]
	if not ResourceLoader.exists(path):
		# Asset missing (e.g. unbuilt checkout) — fall back to the procedural transform
		# animator on the static art mesh so the mob still animates instead of standing dead.
		_proc_anim = ProceduralCreatureAnimator.new(ProceduralCreatureAnimator.Motion.LAND)
		return
	var glb := (load(path) as PackedScene).instantiate() as Node3D
	if glb == null:
		_proc_anim = ProceduralCreatureAnimator.new(ProceduralCreatureAnimator.Motion.LAND)
		return
	add_child(glb)

	# Face head-first: Meshy meshes are authored +Z, but look_at()/_steer_toward point the
	# body's -Z at the movement direction, so a 180° yaw makes the model lead with its front.
	glb.rotation.y = PI

	# Wire the AnimationPlayer + baked clip. Loop it so it cycles while the mob is active;
	# start PAUSED so IDLE shows the rest pose (no separate idle clip ships on the asset).
	_rigged_root = glb
	_skinned_anim = glb.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if _skinned_anim != null:
		var clips: PackedStringArray = _skinned_anim.get_animation_list()
		# Prefer the baked baselayer/clip0 motion; else fall back to the first clip.
		for a: String in clips:
			if a.to_lower().contains("baselayer") or a.to_lower().contains("clip0"):
				_skinned_clip_name = a
				break
		if _skinned_clip_name == "" and clips.size() > 0:
			_skinned_clip_name = clips[0]
		if _skinned_clip_name != "":
			var clip: Animation = _skinned_anim.get_animation(_skinned_clip_name)
			if clip != null:
				clip.loop_mode = Animation.LOOP_LINEAR
				# The shipped humanoid clip0 now carries a real transplanted walk cycle, so
				# _clip_has_motion() returns true and no overlay is attached: the real walk
				# plays. Fallback: if a rigged asset ever ships a degenerate STATIC clip (all
				# channels flat, no bone moves so the mob would slide rigidly), attach a
				# procedural body bob/sway overlay so it still reads as walking.
				if not _clip_has_motion(clip):
					_rigged_proc_anim = ProceduralCreatureAnimator.new(
						ProceduralCreatureAnimator.Motion.LAND)
		_skinned_anim.stop()  # cancel any glTF autoplay; _update_animator starts it on motion

	# Hide the static art mesh so the rigged skinned visual is the only one shown.
	if _art_mesh_root != null:
		_art_mesh_root.visible = false

	# Scale + ground from the POSED skeleton, deferred one frame so the Skeleton3D is in-tree
	# and posed (its bind/rest pose is enough — the posed span is constant across the clip).
	call_deferred("_ground_rigged_to_target")


## Deferred (one frame) scale + ground for a skinned rigged mob. Measures the posed-skeleton
## bounds in the rig-root's local frame (the bbox of every bone origin — this reflects the
## RENDERED size, unlike the pre-skin mesh.get_aabb()), scales the rig so its posed height
## equals _art_target_height(), then grounds the lowest posed bone at the body origin (y=0 =
## the collision-capsule feet plane). Robust to the armature import-scale: whatever makes the
## model render large is captured by the posed-skeleton bounds, so the result is always target
## height. Mirrors village_npc._ground_rigged_to_target so both rigged paths behave identically.
func _ground_rigged_to_target() -> void:
	var glb: Node3D = _rigged_root
	if glb == null or not is_instance_valid(glb):
		return
	var skel := glb.find_child("Skeleton3D", true, false) as Skeleton3D
	if skel == null or skel.get_bone_count() == 0:
		return
	# Reset any prior scale so the posed-bounds measurement is in the rig's native units.
	glb.scale = Vector3.ONE
	var ab: AABB = _posed_skeleton_aabb(glb, skel)
	var span: float = maxf(ab.size.y, 0.001)  # height drives the scale (humanoids are tallest in Y)
	var sc: float = _art_target_height() / span
	glb.scale = Vector3.ONE * sc
	# Ground feet: drop so the lowest posed bone (scaled) sits at the body origin (y=0).
	# 180° yaw negates x,z so the posed centre maps to +center.
	var center: Vector3 = ab.get_center() * sc
	var min_y: float = ab.position.y * sc
	glb.position = Vector3(center.x, -min_y, center.z)
	# Record the grounded Y baseline so the degenerate-clip procedural overlay bobs AROUND it
	# (writing position.y absolutely) without lifting the feet off the floor.
	_rigged_base_y = -min_y


## True when `clip` carries real motion: any track whose keyframe values vary beyond a tiny
## epsilon (rotation or translation). The shipped humanoid clip0 now carries a real transplanted
## walk cycle, so this returns true for them and the procedural bob overlay is skipped. A
## degenerate STATIC clip (all channels flat) returns false and the caller attaches the overlay.
func _clip_has_motion(clip: Animation) -> bool:
	const EPS: float = 0.0001
	for ti: int in range(clip.get_track_count()):
		var kc: int = clip.track_get_key_count(ti)
		if kc < 2:
			continue
		var first: Variant = clip.track_get_key_value(ti, 0)
		for ki: int in range(1, kc):
			var v: Variant = clip.track_get_key_value(ti, ki)
			if (first is Vector3 and v is Vector3 and (v - first).length() > EPS) \
					or (first is Quaternion and v is Quaternion and (v - first).length() > EPS):
				return true
	return false


## Posed-skeleton AABB (in `rig_root`'s local frame): the bbox of every bone's global-pose
## origin, transformed back into the rig root. Unlike the pre-skin mesh.get_aabb(), this
## reflects the height the rig actually RENDERS at (the skeleton's armature scale is baked in).
func _posed_skeleton_aabb(rig_root: Node3D, skel: Skeleton3D) -> AABB:
	var inv: Transform3D = rig_root.global_transform.affine_inverse()
	var lo := Vector3(INF, INF, INF)
	var hi := -lo
	for i: int in range(skel.get_bone_count()):
		var p: Vector3 = inv * (skel.global_transform * skel.get_bone_global_pose(i).origin)
		lo = lo.min(p)
		hi = hi.max(p)
	return AABB(lo, hi - lo)


## Recursively find the first MeshInstance3D with a mesh in a subtree.
func _find_mesh_instance(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		return node as MeshInstance3D
	for child: Node in node.get_children():
		var found: MeshInstance3D = _find_mesh_instance(child)
		if found != null:
			return found
	return null


## Merged AABB (in `root`'s local space) of every MeshInstance3D in the subtree, so a
## multi-part stylised model is centred by its full bounds rather than the first piece.
func _subtree_local_aabb(root: Node3D) -> AABB:
	var out := AABB()
	var first := true
	var stack: Array = [[root, Transform3D.IDENTITY]]
	while not stack.is_empty():
		var entry: Array = stack.pop_back()
		var node: Node = entry[0]
		var xf: Transform3D = entry[1]
		var local_xf: Transform3D = xf
		if node != root and node is Node3D:
			local_xf = xf * (node as Node3D).transform
		if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
			var a: AABB = local_xf * (node as MeshInstance3D).mesh.get_aabb()
			if first:
				out = a
				first = false
			else:
				out = out.merge(a)
		for child: Node in node.get_children():
			stack.append([child, local_xf])
	return out


func _exit_tree() -> void:
	var spawning: Node = get_tree().root.get_node_or_null("/root/Spawning")
	if spawning and spawning.has_method("notify_despawned"):
		spawning.notify_despawned(self)

# ─── Public API ───────────────────────────────────────────────────────────────

## Inject the MainScene reference so take_damage() can call spawn_dropped_item().
## Mirrors DroppedItem.set_main_scene() pattern (STATE.md dropped-item-ore-ids-actual-manifest).
func set_main_scene(scene: Node) -> void:
	_main_scene = scene


## Apply damage to this mob from a hit originating at from_pos.
## Clamps HP at 0, emits damaged signal, triggers VFX + knockback, and calls _on_die() if fatal.
## @param amount    Damage points to subtract.
## @param from_pos  World position the hit came from (for knockback direction).
func take_damage(amount: int, from_pos: Vector3) -> void:
	if state == State.DEAD:
		return
	hp = max(0, hp - amount)
	emit_signal("damaged", amount, from_pos)
	_flash_damage_vfx()
	# Pop 1-2 bricks from the creature's body as dropped items (D-08).
	_pop_brick_vfx(from_pos)
	# Apply knockback away from hit origin.
	var direction: Vector3 = (global_position - from_pos).normalized()
	apply_knockback(direction, KNOCKBACK_DISTANCE_M)
	if hp == 0:
		_on_die()


## Apply a brief knockback impulse to this mob.
## No airborne component per D-08 "no airborne knockback".
## @param direction  Direction to knock the mob (normalised externally for clarity).
## @param force      Impulse magnitude (default: KNOCKBACK_DISTANCE_M).
func apply_knockback(direction: Vector3, force: float = KNOCKBACK_DISTANCE_M) -> void:
	# Zero out Y so the mob is never launched into the air (D-08).
	var horizontal: Vector3 = Vector3(direction.x, 0.0, direction.z).normalized()
	velocity += horizontal * force


## Called by a subclass right after it deals a hit to the builder: bounce the mob back away
## from `target_pos` and start a brief pause so the builder gets breathing room. During the
## pause _physics_process skips seek/attack (the mob coasts), then resumes normally.
func recoil_from(target_pos: Vector3) -> void:
	apply_knockback(global_position - target_pos, POST_HIT_RECOIL_M)
	_post_hit_pause = POST_HIT_PAUSE_S
	state = State.IDLE


## Request a navigation path to target. Throttled at PATH_REQUERY_HZ (4 Hz).
## Between re-queries the mob walks the previously-computed _current_path.
## Per RESEARCH Pattern 2 — NavigationServer3D call at most once per 0.25 s.
func request_path_to(target: Vector3) -> void:
	if _path_query_cooldown > 0.0:
		return  # Walk cached path; no nav query this frame.
	if not is_inside_tree():
		return
	var map_rid: RID = get_world_3d().navigation_map
	_current_path = NavigationServer3D.map_get_path(map_rid, global_position, target, true)
	_path_index = 0
	_path_query_cooldown = PATH_REQUERY_INTERVAL_S


## Shared seek-locomotion helper used by every ground subclass.
##
## Refreshes the throttled navigation query toward `target_pos`, then steers the mob:
##   1. If a usable navmesh path exists, walk toward the next path point (the original
##      behaviour — kept for when a NavigationRegion3D is baked into the world later).
##   2. ELSE (the procedural voxel world currently bakes NO navmesh, so map_get_path
##      always returns an empty path) BEELINE: steer directly toward `target_pos` on the
##      XZ plane at move_speed. This is the wildlife-style direct-velocity approach applied
##      to seeking, so hostiles actually move without a baked navmesh.
##
## In both cases velocity.y is left untouched (the gravity branch in _physics_process owns
## it) and the mob faces its horizontal movement direction (matching how wildlife faces its
## walk-dir and _gait_from_state() returns "walk" while SEEKing).
##
## When already within `stop_distance` metres of the target horizontally (beeline case only),
## the mob halts (velocity.x/z → 0) so it doesn't jitter or overshoot into the builder — this
## preserves each subclass's SEEK→ATTACK / contact-attack hand-off, which fires on its own
## distance check.
##
## @param target_pos     World-space position to steer toward (typically the builder).
## @param _delta         Physics delta (unused today; kept for signature symmetry / future easing).
## @param stop_distance  Horizontal distance at which to stop advancing (default 0.0 = no stop).
func _steer_toward(target_pos: Vector3, _delta: float, stop_distance: float = 0.0) -> void:
	request_path_to(target_pos)

	var steer_target: Vector3 = target_pos
	var have_path: bool = not _current_path.is_empty() and _path_index < _current_path.size()
	if have_path:
		# Navmesh path available: aim at the next waypoint, advancing when reached.
		var next_point: Vector3 = _current_path[_path_index]
		var to_next: Vector3 = next_point - global_position
		to_next.y = 0.0
		if to_next.length_squared() < 0.25:
			_path_index += 1
			if _path_index >= _current_path.size():
				velocity.x = 0.0
				velocity.z = 0.0
				return
			next_point = _current_path[_path_index]
		steer_target = next_point

	# Horizontal vector to the steer target (path waypoint, or the goal in the beeline case).
	var to_target: Vector3 = steer_target - global_position
	to_target.y = 0.0

	# Beeline stop: when within contact/attack range, halt so we don't overshoot or jitter into
	# the builder. Skipped while walking a navmesh path (its waypoints are intermediate, not the goal).
	if not have_path and stop_distance > 0.0 \
			and to_target.length_squared() <= stop_distance * stop_distance:
		velocity.x = 0.0
		velocity.z = 0.0
		return

	if to_target.length_squared() < 0.0001:
		velocity.x = 0.0
		velocity.z = 0.0
		return

	var dir: Vector3 = to_target.normalized()
	velocity.x = dir.x * move_speed
	velocity.z = dir.z * move_speed
	# Face the movement direction (XZ only; matches wildlife facing its walk-dir).
	look_at(global_position + dir, Vector3.UP)

# ─── Default melee AI ─────────────────────────────────────────────────────────
# Generic chase-and-bite behaviour used by subclasses that don't override the state
# virtuals (wolf.gd, melee_humanoid.gd). Subclasses with special locomotion/attacks
# (penguin laser, slime hop, ghost float, bat swoop, vampire transform) override these.

## Horizontal range (m) at which the default melee AI stops to land its contact bite.
const _MELEE_CONTACT_RANGE_M: float = 1.5

## Default melee attack cadence (seconds between bites).
const _MELEE_ATTACK_COOLDOWN_S: float = 1.0

## Remaining cooldown for the default melee bite.
var _melee_attack_cooldown: float = 0.0


## Resolve the nearest builder node (the AI target). Returns null when none is in the tree.
func _find_builder() -> Node3D:
	if _builder_ref == null or not is_instance_valid(_builder_ref):
		_builder_ref = get_tree().get_first_node_in_group("builder") as Node3D
	return _builder_ref


## Default IDLE: stand still, watch for the builder, switch to SEEK once inside detect_radius.
## Subclasses (penguin, bat, slime, ghost, vampire) override with their own idle behaviour.
func _process_idle(_delta: float) -> void:
	var builder: Node3D = _find_builder()
	if builder == null:
		return
	if global_position.distance_squared_to(builder.global_position) \
			<= detect_radius * detect_radius:
		state = State.SEEK
		_state_timer = 0.0


## Default SEEK: chase the builder via _steer_toward (navmesh path when one exists, direct
## beeline otherwise), stopping at melee range to hand off to the default ATTACK bite.
func _process_seek(delta: float) -> void:
	_melee_attack_cooldown -= delta
	var builder: Node3D = _find_builder()
	if builder == null:
		state = State.IDLE
		return

	var dist: float = global_position.distance_to(builder.global_position)
	if dist > detect_radius * 1.5:
		state = State.IDLE
		return

	# Chase: navmesh path if baked, else direct beeline (stop at contact range).
	_steer_toward(builder.global_position, delta, _MELEE_CONTACT_RANGE_M)

	# Contact bite when in range (no navmesh waypoints between us and the builder).
	if dist <= _MELEE_CONTACT_RANGE_M and _melee_attack_cooldown <= 0.0:
		if builder.has_method("take_damage"):
			builder.take_damage(attack_damage, global_position)
			recoil_from(builder.global_position)  # bounce back + pause so the builder can flee
		_melee_attack_cooldown = _MELEE_ATTACK_COOLDOWN_S


## Virtual: called each physics frame while state == ATTACK.
## Default no-op (the default melee AI bites inline from SEEK). Override in subclass to
## implement a dedicated attack state (laser charge, hop, swoop, etc.).
func _process_attack(_delta: float) -> void:
	pass


## Virtual: called each physics frame while state == FLEE.
## Override in subclass to implement flee-from-builder movement.
func _process_flee(_delta: float) -> void:
	pass


## Virtual: called each physics frame while state == TRANSFORM.
## Override in subclass (vampire: bat-form transition; cube_slime: split preparation).
func _process_transform(_delta: float) -> void:
	pass


## Virtual: called each physics frame while state == DEAD.
## Default: no-op (mob is already queued for free from _on_die()).
func _process_dead(_delta: float) -> void:
	pass


## Virtual: called when HP reaches 0. Default behaviour: set DEAD state, emit died,
## queue_free. Subclasses chain super() before their own override (split / transform).
func _on_die() -> void:
	state = State.DEAD
	emit_signal("died")
	queue_free()

# ─── Physics process ──────────────────────────────────────────────────────────

func _physics_process(delta: float) -> void:
	_state_timer += delta
	_path_query_cooldown -= delta

	# Apply gravity when airborne (mirrors village_npc.gd L150-153).
	if not is_on_floor():
		velocity.y += get_gravity().y * delta
	else:
		# Ground any accumulated fall velocity once floor is reached.
		velocity.y = 0.0

	# Post-hit recoil pause: coast on the knockback impulse (with friction) and skip the AI
	# state machine so the mob doesn't immediately re-engage — the builder's window to flee.
	if _post_hit_pause > 0.0:
		_post_hit_pause -= delta
		velocity.x = move_toward(velocity.x, 0.0, move_speed * 4.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, move_speed * 4.0 * delta)
		move_and_slide()
		_update_animator(delta)
		return

	# Dispatch to the appropriate state virtual.
	match state:
		State.IDLE:      _process_idle(delta)
		State.SEEK:      _process_seek(delta)
		State.ATTACK:    _process_attack(delta)
		State.FLEE:      _process_flee(delta)
		State.TRANSFORM: _process_transform(delta)
		State.DEAD:      _process_dead(delta)

	move_and_slide()
	# Drive the animator each frame for subclasses that rely on the base _physics_process
	# (wolf, melee_humanoid). Subclasses that override _physics_process (penguin, vampire,
	# bat, ghost, slime) call _update_animator() themselves after their own move_and_slide().
	_update_animator(delta)

# ─── Private helpers ──────────────────────────────────────────────────────────

## Damage flash VFX: tween the Body MeshInstance3D surface_material_override/0
## albedo_color to white at 0.85 alpha over 80 ms, then back over 80 ms.
## Per UI-SPEC L114 + D-08 "white-flash for ~80 ms".
## Plan 03-10 subclasses .tscn supplies the Body MeshInstance3D node.
func _flash_damage_vfx() -> void:
	var body: MeshInstance3D = get_node_or_null("Body") as MeshInstance3D
	if body == null:
		return
	# Kill any in-progress flash to prevent Tween stacking.
	if _flash_tween and _flash_tween.is_running():
		_flash_tween.kill()
	_flash_tween = create_tween()
	var mat: StandardMaterial3D = body.get_surface_override_material(0) as StandardMaterial3D
	if mat == null:
		# No override yet — create one and copy the base mesh material.
		mat = StandardMaterial3D.new()
		body.set_surface_override_material(0, mat)
	var original_color: Color = mat.albedo_color
	# Flash to white at 0.85 alpha over 80 ms.
	_flash_tween.tween_property(mat, "albedo_color",
		Color(1.0, 1.0, 1.0, 0.85), 0.08).set_ease(Tween.EASE_OUT)
	# Fade back to original colour over 80 ms.
	_flash_tween.tween_property(mat, "albedo_color",
		original_color, 0.08).set_ease(Tween.EASE_IN)


## Pop 1-2 brick particles from the mob's body on take_damage (D-08).
## Uses MainScene.spawn_dropped_item() from Phase 2 L415.
## Skipped if _main_scene is null (detached test node / Scene-tree not ready).
func _pop_brick_vfx(_from_pos: Vector3) -> void:
	if _main_scene == null:
		return
	if not _main_scene.has_method("spawn_dropped_item"):
		return
	var pop_count: int = randi_range(1, 2)
	for _i: int in range(pop_count):
		var offset := Vector3(randf_range(-0.3, 0.3), 0.5, randf_range(-0.3, 0.3))
		# "brick_1x1" + colour_index 0 (primary colour placeholder; Plan 03-10 subclasses
		# set their creature-specific primary colour via primary_brick_def_id field).
		var def_id: String = "brick_1x1"
		if has_meta("primary_brick_def_id"):
			def_id = get_meta("primary_brick_def_id")
		var colour_index: int = 0
		if has_meta("primary_colour_index"):
			colour_index = int(get_meta("primary_colour_index"))
		_main_scene.spawn_dropped_item(def_id, colour_index,
			global_position + offset, true)
