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

# ─── Collision-based grounding (BUG: villagers float in the sky) ───────────────
# The spawn places the body origin at main_scene._terrain_surface_at (a noise FORMULA, not a
# raycast). Where that estimate sits ABOVE the real meshed voxel surface (sloped/low village
# columns, or before a chunk's collision has streamed in), the villager hangs in the air and
# only sinks down once gravity has pulled it through ~2 s of fall, so the player sees it "floating
# high in the sky" the whole time. The fix mirrors wildlife._ground_to_collision: a downward
# raycast against the REAL terrain collision (layer 1) SNAPS the body so the figure's feet rest
# on the meshed surface from frame one, rejecting tree-voxel hits so a villager never seats up a
# trunk/canopy. Re-ground while walking tracks slopes/steps. Falls back to the formula clamp +
# gravity when no collision is available (headless / chunk not yet meshed).

## Height (m) above the body the down-ray starts from. Clears a ~1.85 m figure plus headroom so
## the cast begins above all geometry and looks DOWN onto terrain.
const _GROUND_RAY_UP: float = 4.0

## Depth (m) below the body the down-ray reaches. Generous so the cast still finds the surface
## when the formula estimate placed the body several metres too high (real terrain below it).
const _GROUND_RAY_DOWN: float = 24.0

## Tree-geometry voxel ids (wood_log = 10, leaves = 12) matching terrain.tscn's VoxelBlockyLibrary
## / multipass_generator.gd. Trees are voxels in the SAME VoxelTerrain on layer 1, so a naive cast
## can land on a canopy and seat a villager up a tree; _ground_to_collision rejects these and
## keeps casting down past them to real ground.
const _TREE_VOXEL_WOOD_LOG: int = 10
const _TREE_VOXEL_LEAVES: int = 12

## Max tree-voxel hits to skip in one grounding cast (bounds the worst case; a tall tree is a few
## cells deep). On exhaustion we keep the formula clamp rather than loop forever.
const _GROUND_TREE_SKIP_MAX: int = 24

## Downward nudge (m) to restart the cast just below a rejected tree hit so it doesn't re-hit the
## same face. One voxel is 1 m; half a cell clears it.
const _GROUND_TREE_SKIP_STEP: float = 0.5

## Horizontal distance (m²) the villager must cross before a walking re-ground recast fires, so a
## per-frame raycast doesn't cost on mobile. ~1 voxel cell (enough to follow slopes/steps).
const _REGROUND_MOVE_DIST_SQ: float = 1.0 * 1.0

## Minimum seconds between re-ground recasts (throttle, belt-and-braces with the move-distance gate).
const _REGROUND_INTERVAL_S: float = 0.3

## Injected MainScene (set by spawn_village_npc), used to read terrain voxel ids for tree
## rejection. Null in tests / when spawned bare; tree rejection then degrades to "accept any hit".
var _main_scene: Node = null

## Cached Terrain VoxelTool for voxel-id lookups (tree rejection). Resolved lazily.
var _voxel_tool: Object = null

## True once a real terrain-collision raycast has grounded this villager at least once.
var _ground_cast_hit_once: bool = false

## Throttle accumulator (s) and last-grounded XZ for the walking re-ground recast.
var _reground_accum: float = 0.0
var _last_ground_xz: Vector3 = Vector3.ZERO

# ─── Public API ───────────────────────────────────────────────────────────────

## Inject the MainScene so the grounding raycast can reject tree-voxel hits via the terrain
## VoxelTool. Optional: when unset (tests / bare spawn) grounding still works, it just accepts
## the first collision hit without tree rejection.
func set_main_scene(scene: Node) -> void:
	_main_scene = scene

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

## Figure indices that ship a rigged + animated GLB under _RIGGED_DIR AND are BIPEDAL humanoids.
## Used as the villager APPEARANCE ROSTER: every village NPC is assigned one of these
## deterministically (hashed from its spawn position — stable across reloads, varied across NPCs).
##
## 4-FOOT GAIT FIX (roster prune): indices 7, 33 and 38 were removed because they are NOT bipeds —
## render-verified, 7 is an aquatic diver/creature in a horizontal swimming pose, 33 is an armored
## crab/mech creature, and 38 is a mermaid (human torso + fish tail). Driving the upright humanoid
## walk clip on them makes them sprawl/crawl on the ground (the "walks on 4 feet" report) because
## they have no two legs to stand on. They are sheet-3 fantasy/underwater figures that do not belong
## in a walking village-NPC roster. The remaining 25 are all bipedal humanoids whose hunch is fixed
## by _uprightify_torso (it pins the corrupted Hips+spine tracks to the rig's upright rest pose).
const _RIGGED_FIGURES: Array[int] = [
	1, 2, 5, 6, 8, 9, 11, 14, 15, 16, 17, 18, 19, 21,
	23, 24, 25, 26, 28, 29, 31, 32, 34, 36, 37,
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
	# Snap onto the REAL meshed terrain (raycast) so the villager stands on the ground from the
	# first frame instead of hanging at the noise-formula spawn Y and slowly falling (the "floating
	# in the sky" bug). Deferred so the figure has been applied (feet sit at the body origin) and
	# the chunk collision has a chance to be present; no-op + gravity fallback when it is not.
	call_deferred("_ground_to_collision")
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
				# 4-FOOT GAIT FIX: the transplanted walk clip drives the Hips bone to an absolute
				# rotation (~yaw -60°, roll -16° relative to the Meshy rest pose) that tips the whole
				# pelvis forward+sideways, so the figure leans onto its hands and reads as a quadruped
				# crawl. The mocap was authored against a DIFFERENT rest orientation than these Meshy
				# rigs, so its absolute Hips track is wrong here. Hold the Hips at its REST rotation
				# (upright) while leaving every limb/spine track intact — the legs + arms still swing,
				# but around an upright pelvis, giving a proper two-legged walk. Done on a per-instance
				# DUPLICATE so we never mutate the shared cached Animation resource for other entities.
				_uprightify_torso(glb, clip)
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


## Torso bones whose rotation tracks the transplant corrupted: the pelvis (Hips) AND the full spine
## chain (Spine, Spine01, Spine02) plus neck. The walk mocap was authored against a DIFFERENT rest
## orientation than these Meshy rigs, so its absolute Hips+spine rotations pitch the whole upper body
## forward — the figure hunches over and reads as a quadruped crawl. Pinning these to the rig's REST
## rotation holds the torso vertical (render-verified: pins the hunch out, see _uprightify_torso) while
## the LEG and ARM tracks still animate, giving a proper upright two-legged walk. Names cover the
## casing/variants the 28 villager rigs use (all currently use Hips/Spine/Spine01/Spine02/neck).
const _UPRIGHT_PIN_BONES: Array[String] = [
	"Hips", "hips", "Pelvis", "pelvis", "Root", "root",
	"Spine", "spine", "Spine01", "Spine1", "spine01", "Spine02", "Spine2", "spine02",
	"neck", "Neck",
]


## 4-FOOT GAIT FIX: rewrite the torso-bone rotation tracks of `clip` so they hold the skeleton's REST
## rotation for the whole cycle, keeping the pelvis + spine UPRIGHT while every LEG/ARM track animates
## normally. The transplanted walk clip stored absolute torso rotations authored against a different
## rest pose, which pitched these Meshy figures forward into a stooped, quadruped-looking crawl
## (render-verified before/after — the pinned figure stands and strides upright).
##
## Operates on a per-instance DUPLICATE of the Animation so the shared cached resource is never
## mutated (other villagers / hostile mobs that load the same .glb keep their own copy). The
## duplicated clip is swapped back into THIS instance's AnimationPlayer under the same name.
func _uprightify_torso(glb: Node3D, clip: Animation) -> void:
	var skel: Skeleton3D = glb.find_child("Skeleton3D", true, false) as Skeleton3D
	if skel == null:
		return
	# Resolve which of the candidate torso bones this rig actually has → {bone_name: rest_quat}.
	var pin_rest: Dictionary = {}
	for bn: String in _UPRIGHT_PIN_BONES:
		var bi: int = skel.find_bone(bn)
		if bi >= 0:
			pin_rest[skel.get_bone_name(bi)] = skel.get_bone_rest(bi).basis.get_rotation_quaternion()
	if pin_rest.is_empty():
		return

	var dup: Animation = clip.duplicate(true) as Animation
	var rewrote: bool = false
	for ti: int in range(dup.get_track_count()):
		if dup.track_get_type(ti) != Animation.TYPE_ROTATION_3D:
			continue
		# Track paths look like "Armature/Skeleton3D:Hips" — match on the bone-name suffix.
		var path: String = str(dup.track_get_path(ti))
		var bone_name: String = path.substr(path.rfind(":") + 1)
		if not pin_rest.has(bone_name):
			continue
		var rest_rot: Quaternion = pin_rest[bone_name]
		for ki: int in range(dup.track_get_key_count(ti)):
			dup.rotation_track_set_key(ti, ki, rest_rot)
		rewrote = true
	if not rewrote:
		return
	# Swap the corrected clip in under the same name so play(_skinned_clip_name) uses it. Replace
	# inside the existing library so the AnimationPlayer keeps resolving the name.
	var lib: AnimationLibrary = _skinned_anim.get_animation_library("")
	if lib != null and lib.has_animation(_skinned_clip_name):
		lib.remove_animation(_skinned_clip_name)
		lib.add_animation(_skinned_clip_name, dup)


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

# ─── Collision-based grounding ────────────────────────────────────────────────

## Raycast the REAL terrain collision (layer 1) straight down and snap the body so the figure's
## feet rest on the meshed surface. This is the general fix for "villagers float in the sky": the
## spawn Y is a noise FORMULA that can sit metres above the real terrain (sloped/low columns, or
## a chunk whose collision has not streamed yet), and relying on gravity to fall meant the player
## saw the villager hang in the air for ~2 s. The cast ignores the formula estimate and the capsule
## geometry; it drops the body so the lowest visible point of the figure sits on the hit. Tree
## voxels (wood_log/leaves) are rejected so a villager never seats up a trunk/canopy. No collision
## hit (headless / chunk not yet meshed) → leaves the body on the formula clamp so gravity still
## settles it. Mirrors wildlife._ground_to_collision.
func _ground_to_collision() -> void:
	if not is_inside_tree():
		return
	var world := get_world_3d()
	if world == null:
		return
	var space := world.direct_space_state
	if space == null:
		return  # headless / no physics; gravity fallback in _physics_process still applies.

	# Foot level of the VISIBLE figure as an offset from the body origin (origin-relative so it
	# survives the body translation we are about to apply). For a rigged figure this is the posed
	# bone envelope min-Y (the real rendered feet); _ground_rigged_to_target already places that at
	# the body origin, so the offset is ~0, but measuring keeps it robust for the static-figure path.
	var foot_world_y: float = _visible_figure_min_world_y()
	if foot_world_y == INF:
		# No figure mesh yet (figure load deferred / headless): ground the capsule bottom, which the
		# scene places at the body origin (CollisionShape3D height 1.8 centred at y=0.9).
		foot_world_y = global_position.y
	var foot_offset: float = foot_world_y - global_position.y

	var origin: Vector3 = global_position
	var from: Vector3 = origin + Vector3(0.0, _GROUND_RAY_UP, 0.0)
	var ray_bottom: float = origin.y - _GROUND_RAY_DOWN
	var q := PhysicsRayQueryParameters3D.create(from, Vector3(origin.x, ray_bottom, origin.z))
	q.collision_mask = 1  # terrain / statics only (the layer main_scene grounds builders on).
	q.exclude = [get_rid()]

	# Skip past tree-voxel hits (wood_log/leaves live in the SAME VoxelTerrain on layer 1) so the
	# villager only ever grounds on real terrain. Bounded by _GROUND_TREE_SKIP_MAX.
	var surface_y: float = INF
	for _attempt: int in range(_GROUND_TREE_SKIP_MAX):
		var hit: Dictionary = space.intersect_ray(q)
		if hit.is_empty():
			break  # no terrain below; keep formula clamp / gravity.
		var hit_pos: Vector3 = hit["position"] as Vector3
		if not _is_tree_voxel_at(hit_pos):
			surface_y = hit_pos.y  # real ground, accept.
			break
		var next_top: float = hit_pos.y - _GROUND_TREE_SKIP_STEP
		if next_top <= ray_bottom:
			break  # exhausted the cast depth without finding non-tree terrain.
		q.from = Vector3(origin.x, next_top, origin.z)

	if surface_y == INF:
		return  # no real terrain under the villager this frame; keep formula clamp / gravity.

	# Place the body so the figure's feet sit ON the surface, regardless of the body origin vs feet.
	global_position.y = surface_y - foot_offset
	velocity.y = 0.0
	_ground_cast_hit_once = true
	_last_ground_xz = Vector3(global_position.x, 0.0, global_position.z)
	_reground_accum = 0.0


## Lowest world-Y of the VISIBLE figure: the posed Skeleton3D bone envelope for a rigged figure
## (its child MeshInstance3D carries a degenerate pre-skin bind-pose AABB, useless while posed), or
## the merged mesh AABB min-Y for a static figure. INF when no visible figure exists yet. Mirrors
## wildlife._visible_mesh_min_world_y.
func _visible_figure_min_world_y() -> float:
	var lowest: float = INF
	var stack: Array[Node] = [self]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is Node3D and not (node as Node3D).visible:
			continue  # skip the hidden placeholder capsule "Body".
		if node is Skeleton3D:
			var sk := node as Skeleton3D
			for i: int in range(sk.get_bone_count()):
				var bw: Vector3 = sk.global_transform * sk.get_bone_global_pose(i).origin
				lowest = minf(lowest, bw.y)
			continue  # the bone envelope already covers the rig; skip its degenerate-AABB children.
		if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
			var mi := node as MeshInstance3D
			var box: AABB = mi.global_transform * mi.mesh.get_aabb()
			lowest = minf(lowest, box.position.y)
		for child: Node in node.get_children():
			stack.push_back(child)
	return lowest


## Lazily fetch (and cache) the world Terrain's VoxelTool for tree-rejection voxel-id reads.
## Returns null when the terrain/tool is unavailable (headless / no injected main_scene) so the
## caller degrades to accepting any collision hit.
func _terrain_voxel_tool() -> Object:
	if _voxel_tool != null:
		return _voxel_tool
	var scene: Node = _main_scene
	if (scene == null or not is_instance_valid(scene)) and is_inside_tree():
		scene = get_tree().get_first_node_in_group("main_scene")
	if scene == null or not is_instance_valid(scene):
		return null
	var terrain: Node = scene.get_node_or_null("Terrain")
	if terrain == null or not terrain.has_method("get_voxel_tool"):
		return null
	var tool: Object = terrain.get_voxel_tool()
	if tool == null:
		return null
	if "channel" in tool:
		tool.channel = 0  # VoxelBuffer.CHANNEL_TYPE (the block-id channel).
	_voxel_tool = tool
	return _voxel_tool


## True when the voxel containing the ground-ray hit at `hit_pos` is tree geometry (wood_log or
## leaves). The hit sits ON the struck voxel's top face, so we sample a hair BELOW it to land inside
## that cell. Returns false (accept the hit) when no terrain tool is available.
func _is_tree_voxel_at(hit_pos: Vector3) -> bool:
	var tool: Object = _terrain_voxel_tool()
	if tool == null:
		return false
	var pos: Vector3 = hit_pos - Vector3(0.0, 0.05, 0.0)
	var cell := Vector3i(floori(pos.x), floori(pos.y), floori(pos.z))
	var id: int = int(tool.get_voxel(cell))
	return id == _TREE_VOXEL_WOOD_LOG or id == _TREE_VOXEL_LEAVES

# ─── Physics ──────────────────────────────────────────────────────────────────

func _physics_process(delta: float) -> void:
	# Gravity ALWAYS applies (BUG 2 villager grounding): a villager is spawned at the FORMULA
	# surface Y (_terrain_surface_at), which can sit a fraction above the actually-meshed
	# collision, and a villager spends most of its life idle / may have no patrol path at all.
	# The old code zeroed velocity and skipped move_and_slide() in the no-path branch (and
	# applied gravity ONLY while actively walking), so an idle / pathless villager NEVER settled
	# onto the terrain — it floated at its spawn estimate (the "14 pre-stamped but the player
	# sees none / they hover" report). Applying gravity + move_and_slide() in every branch makes
	# every villager fall onto and rest on the real surface, standing visibly on the ground.

	# No patrol path → NPC stands idle, but STILL settles onto the floor under gravity.
	if patrol_path.is_empty():
		velocity.x = 0.0
		velocity.z = 0.0
		_apply_gravity(delta)
		_set_walking(false)
		move_and_slide()
		_maybe_reground(delta)
		return

	# ── Idle countdown ───────────────────────────────────────────────────────
	if _idle_timer > 0.0:
		_idle_timer -= delta
		velocity.x = 0.0
		velocity.z = 0.0
		_apply_gravity(delta)
		_set_walking(false)
		move_and_slide()
		_maybe_reground(delta)
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
		velocity.x = 0.0
		velocity.z = 0.0
		_apply_gravity(delta)
		_set_walking(false)
		move_and_slide()
		_maybe_reground(delta)
		return

	# Walking this frame → run the rigged figure's clip0 (no-op if static figure).
	_set_walking(true)

	# Horizontal movement direction; Y handled via gravity below.
	var direction: Vector3 = to_target_h.normalized()
	velocity.x = direction.x * _move_speed
	velocity.z = direction.z * _move_speed
	_apply_gravity(delta)

	# Rotate body to face movement direction (Y-up world assumption).
	if direction.length_squared() > 0.01:
		# look_at requires target != current position in the XZ plane.
		var look_target: Vector3 = global_position + direction
		look_target.y = global_position.y  # keep level to avoid tilting
		look_at(look_target, Vector3.UP)

	# T-13-01 mitigation: move_and_slide() respects StaticBody3D brick/terrain colliders.
	move_and_slide()
	# Re-snap onto the real surface as it walks (tracks slopes/steps) and retries the initial
	# ground cast if the spawn-time chunk collision was not yet meshed.
	_maybe_reground(delta)


## Accumulate gravity onto velocity.y while airborne; zero it once resting on the floor so the
## villager settles onto and stays on the terrain. Shared by every _physics_process branch so an
## idle / pathless villager grounds itself just like a walking one (BUG 2 grounding fix).
func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y += get_gravity().y * delta
	else:
		velocity.y = 0.0


## Periodically re-run the ground raycast so the villager (a) keeps its feet on the meshed surface
## as it walks across slopes/steps, and (b) snaps down the first time terrain collision becomes
## available when the spawn-time chunk had not meshed yet (until then it falls under gravity, which
## is the safe fallback). Throttled by distance + time so it stays mobile-cheap. Called from every
## _physics_process branch (idle / pathless villagers also need the not-yet-meshed retry).
func _maybe_reground(delta: float) -> void:
	_reground_accum += delta
	# Until the first successful cast, retry every interval regardless of movement (the spawn chunk
	# may still be streaming). After that, only recast once the villager has crossed ~one cell.
	var moved_enough: bool = Vector3(global_position.x, 0.0, global_position.z) \
		.distance_squared_to(_last_ground_xz) >= _REGROUND_MOVE_DIST_SQ
	if not _ground_cast_hit_once:
		if _reground_accum >= _REGROUND_INTERVAL_S:
			_reground_accum = 0.0
			_ground_to_collision()
		return
	if _reground_accum >= _REGROUND_INTERVAL_S and moved_enough:
		_reground_accum = 0.0
		_ground_to_collision()
