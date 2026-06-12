# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# village_npc.gd — VillageNpc: peaceful wandering builder NPC.
#
# Implements CONTEXT.md D-09 "wandering builder NPCs with no interaction — patrol paths,
# no dialog, no trading, no combat. Atmosphere only. Biome-appropriate skin variants."
#
# DOC-02 implementation: this class makes DOCS.md §2 "Inhabitants" line (added by Plan 16)
# true at runtime.
#
# Architecture boundary (CONTEXT.md Integration Points):
#   NPC patrol AI MUST NOT bleed into Phase 3's hostile-mob AI. This class is intentionally
#   dependency-light (waypoint walking + idle pauses; no nav-mesh, no pathfinder autoload)
#   so Phase 3 can pick a different approach for hostile creatures without conflicts.
#
# Design decisions:
#   - Extends CharacterBody3D directly (NOT Builder). Phase 1 builder.gd uses Input.is_action_*
#     which NPCs must never touch. Separate class keeps boundaries clean.
#   - Body mesh: Phase 2 colour-tint stand-in via StandardMaterial3D.albedo_color override.
#     Full skin-variant mesh authoring is Phase 3 territory.
#   - Skin colours from biome briefs (Plan 02-01 canonical-refs):
#       desert  → warm tan (#C9A86A)  — "warm tan to medium-brown skin" (desert.md §11)
#       snow    → fair ice (#E8F0F5)  — "fair to light-pink skin" (snow.md §11)
#       savannah → medium-dark brown (#A66E3C) — "medium-dark to dark-brown skin" (savannah.md §11)
#   - No combat, no inventory, no item pickup. Never calls hostile-mob systems.
#   - T-13-01 mitigation: WAYPOINT_REACH_RADIUS=0.5m + move_and_slide() handles wall collision.
#
# Thread safety: runs on main thread (physics_process). Not safe for worker threads.
#
# References:
#   DOCS.md §2 — village inhabitants (D-09 spec expansion added by Plan 16)
#   CONTEXT.md D-09 — atmosphere-only NPC spec
#   biomes/desert.md §11, biomes/snow.md §11, biomes/savannah.md §11 — skin palette rows

class_name VillageNpc
extends CharacterBody3D

# ─── Skin colour constants (from biome briefs §11) ────────────────────────────

## Skin-tone colour map keyed by biome skin_variant identifier.
## Values sourced from the locked biome briefs (Plan 02-01).
##   desert  §11: "warm tan to medium-brown skin" → #C9A86A
##   snow    §11: "fair to light-pink skin"        → #E8F0F5
##   savannah §11: "medium-dark to dark-brown skin" → #A66E3C
const SKIN_COLOURS: Dictionary = {
	"desert":   Color("#C9A86A"),
	"snow":     Color("#E8F0F5"),
	"savannah": Color("#A66E3C"),
}

# ─── Waypoint AI constants ────────────────────────────────────────────────────

## Minimum idle pause between waypoints (seconds).
const IDLE_PAUSE_MIN: float = 1.5

## Maximum idle pause between waypoints (seconds).
const IDLE_PAUSE_MAX: float = 4.0

## Distance (metres) at which the NPC considers a waypoint reached.
## T-13-01 mitigation: 0.5 m radius prevents wall overshooting.
const WAYPOINT_REACH_RADIUS: float = 0.5

# ─── State ────────────────────────────────────────────────────────────────────

## Ordered patrol waypoints in world space. Set via set_patrol_path().
var patrol_path: PackedVector3Array = PackedVector3Array()

## Active skin variant: "desert" | "snow" | "savannah". Default: "desert".
var skin_variant: String = "desert"

## Current waypoint index in patrol_path.
var _current_waypoint: int = 0

## Idle countdown timer (seconds). NPC stands still while > 0.
var _idle_timer: float = 0.0

## Walking speed (metres per second). Gentle walk — slower than the builder's 4.5 m/s.
var _move_speed: float = 1.8

## AnimationPlayer of a rigged figure GLB (_RIGGED_FIGURES), else null. When set, the baked
## clip0 plays while the NPC is walking and pauses (rest pose) while idle. Wired by
## _apply_figure_model() when a rigged figure is selected; null otherwise (static figure).
var _skinned_anim: AnimationPlayer = null

## Name of the baked motion clip on _skinned_anim (resolved at setup, e.g.
## "Armature|clip0|baselayer"). Empty when no rigged figure / no clip.
var _skinned_clip_name: String = ""

## Rigged figure GLB awaiting the one-frame-deferred posed-skeleton scale+ground
## (see _apply_rigged_figure / _ground_rigged_to_target).
var _rigged_glb_ref: Node3D = null

# ─── Public API ───────────────────────────────────────────────────────────────

## Set the patrol waypoints for this NPC.
##
## @param path  World-space Vector3 array. Minimum 1 point; NPC stands at path[0] if empty.
##              Waypoints cycle: after reaching the last one, the NPC returns to path[0].
func set_patrol_path(path: PackedVector3Array) -> void:
	patrol_path = path
	_current_waypoint = 0


## Apply a biome skin variant by overriding the Body MeshInstance3D material albedo.
##
## @param variant  "desert" | "snow" | "savannah". Unknown values use Color.WHITE with a warning.
func set_skin_variant(variant: String) -> void:
	skin_variant = variant
	var body_mesh: MeshInstance3D = get_node_or_null("Body") as MeshInstance3D
	if body_mesh == null:
		return
	var colour: Color = SKIN_COLOURS.get(variant, Color.WHITE)
	if not SKIN_COLOURS.has(variant):
		push_warning("VillageNpc.set_skin_variant: unknown variant '%s'; using WHITE." % variant)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = colour
	body_mesh.set_surface_override_material(0, mat)

# ─── Lifecycle ────────────────────────────────────────────────────────────────

## Directory + count of the biome NPC figure models (art-figures sheet 1). VillageNpc loads
## one as its visual, replacing the placeholder capsule "Body".
const _FIGURE_DIR: String = "res://assets/meshes/figures/"
## All friendly villager figures (art-figures sheets 1 & 2 + sheet-3 underwater/fantasy).
## Sheet 3's hostile figures (zombie/orc/etc.) are NOT here — they are mobs, not villagers.
const _FIGURE_COUNT: int = 40

## Biome-themed figure indices per village skin_variant (art-figures sheet 1, classified by
## render). Desert/snow/savannah villages pull their own themed villagers most of the time.
const _FIGURES_BY_VARIANT: Dictionary = {
	"desert":   [11, 12, 13, 14, 15],
	"snow":     [2, 5, 7, 9],
	"savannah": [1, 3, 4, 6, 8, 10],
}
## "Wanderer" figures (sheets 2 & 3: beach/jungle/ocean/underwater/fantasy) — no village
## biome of their own, so they appear occasionally as visitors in any village.
const _WANDERER_FIGURES: Array[int] = [
	16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30,
	31, 32, 33, 34, 35, 36, 37, 38, 39, 40,
]
## Chance a villager is a wanderer rather than a biome-themed local.
const _WANDERER_CHANCE: float = 0.22

# ─── Rigged (skinned + animated) figure roster ────────────────────────────────

## Directory of the 28 rigged + animated humanoid figure GLBs. Each is a skinned mesh with
## ONE baked motion clip "Armature|clip0|baselayer" (no separate idle/walk — clip0 IS the
## figure's motion). That clip now carries a REAL in-place walk cycle: the builder "Walking"
## mocap limb/spine rotations were transplanted onto these rigs (identical 24-bone skeleton),
## Hips root translation frozen so the figure walks in place while patrol velocity drives
## forward travel. When a villager's deterministically-chosen figure index has a rigged
## variant here, _apply_figure_model() loads THIS instead of the static figures/ mesh and
## drives clip0 from the NPC's walk/idle state (mirrors hostile_mob._setup_skinned_rig and
## wildlife._setup_skinned_glb).
const _RIGGED_DIR: String = "res://assets/meshes/npcs/"

## The 28 figure indices that ship a rigged + animated GLB under _RIGGED_DIR. Used as the
## villager APPEARANCE ROSTER: every village NPC is assigned one of these deterministically
## (hashed from its spawn position — stable across reloads, varied across NPCs).
const _RIGGED_FIGURES: Array[int] = [
	1, 2, 5, 6, 7, 8, 9, 11, 14, 15, 16, 17, 18, 19, 21,
	23, 24, 25, 26, 28, 29, 31, 32, 33, 34, 36, 37, 38,
]

## Target standing height (metres) for a rigged figure, matching the placeholder capsule
## (≈1.85 m, the same figure height the static _apply_figure_model path uses).
const _RIGGED_TARGET_HEIGHT: float = 1.85


## True once a figure model (rigged or static) has been applied, so the deferred apply
## (triggered after the spawner sets global_position) runs exactly once.
var _figure_applied: bool = false


func _ready() -> void:
	# Apply default skin variant tint (fallback if no figure model loads).
	set_skin_variant(skin_variant)
	# Swap the placeholder capsule for a real figure model. Deferred to the next frame so the
	# spawner's post-add_child `global_position = spawn_pos` (main_scene.spawn_village_npc) has
	# landed: the rigged-figure ROSTER pick is hashed from the spawn position, so it must read
	# the final position, not the origin it has during add_child(). _apply_figure_model() is
	# idempotent via _figure_applied, so a direct test-harness call still works.
	call_deferred("_apply_figure_model")
	# Stagger the initial idle so not all village NPCs step simultaneously.
	_idle_timer = randf_range(IDLE_PAUSE_MIN, IDLE_PAUSE_MAX)


## Swap the placeholder capsule for a real figure model. Prefers a RIGGED + animated figure
## from the appearance roster (_RIGGED_FIGURES) selected deterministically from the spawn
## position (stable across reloads, varied across NPCs); if the rigged asset is absent
## (unbuilt checkout / CI), falls back to the original biome-themed STATIC figure. Idempotent:
## _figure_applied gates a second call (it is invoked via call_deferred from _ready, but is
## still safe to call directly from test code).
func _apply_figure_model() -> void:
	if _figure_applied:
		return
	_figure_applied = true
	# Appearance roster: assign one of the 28 rigged figures deterministically per-NPC. Hash the
	# spawn position so the same villager always gets the same look across world reloads, while
	# different villagers vary. Falls through to the static path if the rigged asset is missing.
	if _apply_rigged_figure():
		return
	_apply_static_figure()


## Try to load a RIGGED + animated figure from the roster and wire its clip0 to walk/idle.
## Returns true on success; false (no asset / failed instantiate) so the caller can fall back
## to the static-figure path. Mirrors hostile_mob._setup_skinned_rig / wildlife._setup_skinned_glb.
func _apply_rigged_figure() -> bool:
	if _RIGGED_FIGURES.is_empty():
		return false
	# Deterministic roster pick: hash the (rounded) spawn position → stable index into the 28
	# rigged figures. Rounding to whole metres keeps the pick stable against float jitter.
	var p: Vector3 = global_position
	var seed_key: int = hash(Vector3i(roundi(p.x), roundi(p.y), roundi(p.z)))
	var idx: int = _RIGGED_FIGURES[absi(seed_key) % _RIGGED_FIGURES.size()]
	var path: String = "%sfigure_%02d.glb" % [_RIGGED_DIR, idx]
	if not ResourceLoader.exists(path):
		return false
	var glb := (load(path) as PackedScene).instantiate() as Node3D
	if glb == null:
		return false
	add_child(glb)

	# Face head-first: Meshy meshes are authored +Z, but look_at() (in _physics_process) points
	# the body's -Z at the movement direction, so a 180° yaw makes the figure lead with its front.
	glb.rotation.y = PI

	# Wire the AnimationPlayer + baked clip0. Loop it so it cycles while walking; start PAUSED so
	# idle shows the rest pose (the asset ships no separate idle clip). _physics_process drives
	# play/pause off the walk state.
	_skinned_anim = glb.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if _skinned_anim != null:
		var clips: PackedStringArray = _skinned_anim.get_animation_list()
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
		_skinned_anim.stop()  # cancel any glTF autoplay; _physics_process starts it on motion

	# Hide the placeholder capsule so the rigged visual is the only one shown.
	var body: Node = get_node_or_null("Body")
	if body is MeshInstance3D:
		(body as MeshInstance3D).visible = false

	# Scale + ground from the POSED skeleton, deferred one frame so the Skeleton3D is in-tree and
	# posed. These Meshy rigs carry a skinned mesh whose raw mesh.get_aabb() is the PRE-SKIN local
	# bounds (~0.017 m), NOT the rendered height — the mesh only reaches its real ~1.7 m once the
	# Skeleton3D (armature import scale ~0.01) deforms it. Scaling by the raw mesh AABB over-scales
	# by ~108x → a ~180 m giant villager. _ground_rigged_to_target() measures the posed-skeleton
	# bounds (which reflect what renders) and scales from THAT. Mirrors hostile_mob's rigged path.
	_rigged_glb_ref = glb
	call_deferred("_ground_rigged_to_target")
	return true


## Deferred (one frame) scale + ground for the rigged figure. Measures the posed-skeleton bounds
## in the rig-root's local frame (the bbox of every bone origin — this reflects the RENDERED size,
## unlike the pre-skin mesh.get_aabb()), scales so the posed height equals _RIGGED_TARGET_HEIGHT,
## then grounds the lowest posed bone at the NPC origin (y=0 = capsule bottom). Robust to the
## armature import-scale: whatever makes the model render large is captured by the posed bounds, so
## the result is always target height. Mirrors hostile_mob._ground_rigged_to_target.
func _ground_rigged_to_target() -> void:
	var glb: Node3D = _rigged_glb_ref
	if not is_instance_valid(glb):
		return
	var skel: Skeleton3D = glb.find_child("Skeleton3D", true, false) as Skeleton3D
	if skel == null or skel.get_bone_count() == 0:
		return
	# Reset any prior scale so the posed-bounds measurement is in the rig's native units.
	glb.scale = Vector3.ONE
	var ab: AABB = _posed_skeleton_aabb(glb, skel)
	var span: float = maxf(ab.size.y, 0.001)  # height drives the scale (humanoids are tallest in Y)
	var sc: float = _RIGGED_TARGET_HEIGHT / span
	glb.scale = Vector3.ONE * sc
	# Ground feet: drop so the lowest posed bone (scaled) sits at the NPC origin (y=0).
	# 180° yaw negates x,z so the posed centre maps to +center.
	var center: Vector3 = ab.get_center() * sc
	var min_y: float = ab.position.y * sc
	glb.position = Vector3(center.x, -min_y, center.z)


## Posed-skeleton AABB (in `rig_root`'s local frame): the bbox of every bone's global-pose origin,
## transformed back into the rig root. Unlike the pre-skin mesh.get_aabb(), this reflects the height
## the rig actually RENDERS at (the skeleton's armature scale is baked in). Mirrors
## hostile_mob._posed_skeleton_aabb.
func _posed_skeleton_aabb(rig_root: Node3D, skel: Skeleton3D) -> AABB:
	var inv: Transform3D = rig_root.global_transform.affine_inverse()
	var lo := Vector3(INF, INF, INF)
	var hi := -lo
	for i: int in range(skel.get_bone_count()):
		var p: Vector3 = inv * (skel.global_transform * skel.get_bone_global_pose(i).origin)
		lo = lo.min(p)
		hi = hi.max(p)
	return AABB(lo, hi - lo)


## Load a STATIC (non-rigged) biome-themed figure GLB and stand it on the NPC origin (feet at
## y=0 — the capsule bottom), scaled to ~1.85 m, then hide the placeholder capsule Body. Used
## when the rigged roster asset is absent. Falls back silently (keeps the tinted capsule) if the
## static figures are also absent (headless/CI).
func _apply_static_figure() -> void:
	# Biome-map: mostly pull a figure themed to this village's biome (skin_variant), with a
	# small chance of a "wanderer" from the other sheets so all the art still shows up.
	var themed: Array = _FIGURES_BY_VARIANT.get(skin_variant, [])
	var idx: int
	if themed.is_empty() or randf() < _WANDERER_CHANCE:
		idx = _WANDERER_FIGURES[randi() % _WANDERER_FIGURES.size()] if not _WANDERER_FIGURES.is_empty() else 1
	else:
		idx = int(themed[randi() % themed.size()])
	var path: String = "%sfigure_%02d.glb" % [_FIGURE_DIR, idx]
	if not ResourceLoader.exists(path):
		return
	var m := (load(path) as PackedScene).instantiate() as Node3D
	if m == null:
		return
	add_child(m)
	var ab: AABB = _figure_aabb(m)
	var sc: float = 1.85 / maxf(ab.size.y, 0.01)
	m.scale = Vector3(sc, sc, sc)
	# Feet (AABB min-Y) to the NPC origin (y=0 = capsule bottom), centred on X/Z.
	m.position = Vector3(-ab.get_center().x * sc, -ab.position.y * sc, -ab.get_center().z * sc)
	var body: Node = get_node_or_null("Body")
	if body is MeshInstance3D:
		(body as MeshInstance3D).visible = false


## Merged local-space AABB of every MeshInstance3D under `root` (static mesh, valid now).
func _figure_aabb(root: Node3D) -> AABB:
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


## Drive the rigged figure's baked clip0 from the NPC's walk/idle state: play (looping) while
## walking, pause (rest pose) while idle. No-op when this NPC uses a static figure or the
## capsule fallback (_skinned_anim == null). Mirrors hostile_mob._update_animator's clip gate.
func _set_walking(walking: bool) -> void:
	if _skinned_anim == null or _skinned_clip_name == "":
		return
	if walking:
		if not _skinned_anim.is_playing():
			_skinned_anim.play(_skinned_clip_name)
	elif _skinned_anim.is_playing():
		_skinned_anim.pause()

# ─── Physics ──────────────────────────────────────────────────────────────────

func _physics_process(delta: float) -> void:
	# No patrol path → NPC stands idle forever.
	if patrol_path.is_empty():
		velocity = Vector3.ZERO
		_set_walking(false)
		return

	# ── Idle countdown ───────────────────────────────────────────────────────
	if _idle_timer > 0.0:
		_idle_timer -= delta
		velocity = Vector3.ZERO
		_set_walking(false)
		move_and_slide()
		return

	# ── Walk toward current waypoint ─────────────────────────────────────────
	var target: Vector3 = patrol_path[_current_waypoint]
	var to_target: Vector3 = target - global_position
	# Ignore vertical distance for horizontal approach check (terrain steps allowed).
	var to_target_h: Vector3 = Vector3(to_target.x, 0.0, to_target.z)

	if to_target_h.length() < WAYPOINT_REACH_RADIUS:
		# Reached waypoint — advance to next and begin idle pause.
		_current_waypoint = (_current_waypoint + 1) % patrol_path.size()
		_idle_timer = randf_range(IDLE_PAUSE_MIN, IDLE_PAUSE_MAX)
		velocity = Vector3.ZERO
		_set_walking(false)
		move_and_slide()
		return

	# Walking this frame → run the rigged figure's clip0 (no-op if static figure).
	_set_walking(true)

	# Horizontal movement direction; Y handled via gravity below.
	var direction: Vector3 = to_target_h.normalized()
	velocity.x = direction.x * _move_speed
	velocity.z = direction.z * _move_speed

	# Apply gravity when airborne.
	if not is_on_floor():
		velocity.y += get_gravity().y * delta
	else:
		velocity.y = 0.0

	# Rotate body to face movement direction (Y-up world assumption).
	if direction.length_squared() > 0.01:
		# look_at requires target != current position in the XZ plane.
		var look_target: Vector3 = global_position + direction
		look_target.y = global_position.y  # keep level to avoid tilting
		look_at(look_target, Vector3.UP)

	# T-13-01 mitigation: move_and_slide() respects StaticBody3D brick/terrain colliders.
	move_and_slide()
