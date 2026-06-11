# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# builder.gd — Player character controller (Phase 1 spike; extended Plans 05, 08.5, 02-09, 03-04).
#
# Extends CharacterBody3D. Handles WASD movement, mouse-look (desktop), and
# Space-to-jump. Exposes get_crosshair_position() / get_crosshair_direction() for
# Plan 05's place/break raycast and Plan 09's ghost-preview system.
#
# Plan 05 additions:
#   - _try_place() / _try_break() using VoxelTool.raycast() per RESEARCH.md Pattern 3.
#   - References to stud_grid (StudGrid) and brick_renderer (MultiMeshInstance3D).
#   - Phase 1 restriction: only top-face-of-terrain placement allowed.
#   - T-05-04: raycast checked for null before use; study out-of-bounds anchor
#     from negative voxel coords is tested in test_place_break.gd test 2.
#
# Plan 08.5 additions:
#   - CameraMode enum (FPV, CHASE) with default CHASE (user decision 2026-05-26).
#   - Direct-Orbit chase camera rig: CameraPivot / CameraRay (RayCast3D) / ChaseCamera.
#     (feat(07): SpringArm3D replaced by manual RayCast3D for instant wall collision.)
#   - toggle_camera_mode() — flips mode, persists to WorldSave.
#   - Scroll-wheel zoom (camera_zoom_in / camera_zoom_out): clamps _chase_distance [2.0, 8.0].
#   - Pitch pipeline: FPV → camera_fpv.rotation.x; CHASE → camera_pivot.rotation.x.
#   - get_crosshair_position() / get_crosshair_direction(): return active camera values.
#   - T-CAM-01: defensive parse of WorldSave camera_mode; invalid value → CHASE + warning.
#   - T-CAM-02: assertion in _ready that camera_ray.collision_mask & 1 != 0.
#
# Plan 02-09 additions:
#   - Phase 1 top-face restriction LIFTED: now supports top + side + brick-on-brick faces.
#   - _derive_rotation_from_builder_yaw(): snaps builder yaw to 90° steps (0..3).
#   - _rotated_footprint(footprint, rotation): permutes X/Z of each offset per rotation.
#   - _raycast_stud_grid(origin, direction, max_dist): DDA traversal for brick hits.
#   - _try_place() uses place_multi() via StudGrid; footprint-aware; side-face enabled.
#   - add_to_group("builder") in _ready so ghost_preview.gd can find this node.
#   - predict_placement_target(): shared raycast logic for ghost_preview.gd.
#
# Plan 02-14 additions:
#   - Stable builder UUID (Pitfall 8 mitigation): generated on first _ready, persisted to
#     user://settings.cfg under [builder] id key. Survives save/load; Phase 4 multiplayer
#     will reuse this local UUID until a server-issued account_id is available.
#   - get_stable_builder_id() -> String: returns the stable UUID (guaranteed non-empty).
#   - _generate_uuid_v4() -> String: generates a RFC 4122 v4 UUID using Crypto.generate_random_bytes(16).
#   - rain_dance() -> void: invokes Weather.trigger_rain_dance(get_stable_builder_id());
#     shows returned message_key via Toasts.show(..., "info").
#   - _unhandled_input: ui_rain_dance action → rain_dance() (R key on desktop).
#   References: 02-14-PLAN.md §Task 1, 02-RESEARCH.md §"Pitfall 8", DOCS.md §2.4.
#
# Plan 03-04 additions (survival loop — death/respawn/sleep):
#   - HP state machine: MAX_HP=10; take_damage; _on_death; respawn_at; eat_food; mark_slept.
#   - damage VFX: red vignette pulse, h_offset screen-shake, mobile haptic (D-08).
#   - DeathPile spawning via Inventory.apply_event(DEATH_DROP) on HP=0.
#   - 3-second DeathScreen fade overlay before respawn_at (D-12).
#   - Void/lethal-fall death: pile placed at surface (Y>-128) via downward raycast.
#   - Sleep interact: E near bed → start_sleep_lapse(10.0); polls hostiles each tick (Pitfall 9).
#   - get_respawn_position(): returns last-slept bed or world_spawn fallback.
#   - attack_swing signal: stub receiver for Plan 03-10 HostileMob.
#   - Input actions: ui_inventory_toggle, attack, sleep_interact.
#   References: 03-CONTEXT.md D-08, D-10, D-11, D-12, D-14; 03-RESEARCH.md Pitfall 9.
#
# Design decisions (CONTEXT.md D-01, D-12; DOCS.md §7.5):
#   - Phase 1 rough-art: no builder mesh, no animations. Capsule collider only.
#   - Mouse capture: only on desktop (not mobile — mobile uses Plan 06's touch
#     overlay). T-04-03 mitigation: `Input.MOUSE_MODE_CAPTURED` is only set when
#     `not OS.has_feature("mobile")`.
#   - Plan 05 contract: get_aim_origin() and get_aim_direction() preserved as aliases.
#   - Input actions: place, break — declared in project.godot; LMB/RMB desktop bindings.
#   - Input actions added in Plan 08.5: toggle_camera_mode (V), camera_zoom_in (wheel up),
#     camera_zoom_out (wheel down).
#   - No rotation by player input (DOCS.md §3.2 + §9 + Features.brick_rotation=false).
#     Orientation derives from builder yaw at place time only.
#   - No gravity on bricks (DOCS.md §3.2 + §9, Features.brick_gravity=false).
#
# Thread safety: not applicable (runs on main thread, physics_process).

class_name Builder
extends CharacterBody3D

# ─── Camera mode enum ─────────────────────────────────────────────────────────

## The two supported camera modes.
## FPV: traditional first-person view (camera at eye height inside the builder).
## CHASE: third-person follow camera using a manual RayCast3D for instant (no-interpolation)
##        wall collision (Direct-Orbit, feat(07)).
enum CameraMode { FPV, CHASE }

# ─── Plan 06-07: Avatar colour constants ──────────────────────────────────────
# Must match avatar_creator.gd SKIN_COLOURS and BODY_COLOURS exactly.

## Skin colour swatches (5), applied to exposed skin mesh parts (head).
## Must match avatar_creator.gd SKIN_COLOURS constant.
const SKIN_COLOURS: Array[Color] = [
	Color("#FFD21A"),  # classic builder-figure yellow (default builder head)
	Color("#D4956A"),  # tan
	Color("#A0614A"),  # medium
	Color("#6B3A2A"),  # dark
	Color("#3B1F16"),  # deep
]

## Body / leg colour swatches (10) — subset of the 18-colour brick palette.
## Must match avatar_creator.gd BODY_COLOURS constant.
const BODY_COLOURS: Array[Color] = [
	Color("#C91111"),  # red
	Color("#E8890C"),  # orange
	Color("#F5C30D"),  # yellow
	Color("#97C515"),  # lime
	Color("#3DB560"),  # green
	Color("#159195"),  # teal
	Color("#1B72D8"),  # blue
	Color("#7B2DB5"),  # purple
	Color("#D43582"),  # pink
	Color("#F1F0EA"),  # white
]

## Default avatar config — applied when user://avatar.cfg is absent.
## index 0 skin (light), square head, neutral face, blue body (6), no accessories,
## blue legs (6), no shoes. Builders hold a pickaxe by default so there is always a
## visible held tool — Cubicraftia is a mine-and-build game, so an empty hand reads as
## a bug. The avatar creator can still set this to "none".
const DEFAULT_AVATAR_CFG: Dictionary = {
	"skin_colour_index": 0,
	"head_shape": "square",
	"face_expression": "neutral",
	"body_colour_index": 6,
	"body_accessory": "none",
	"leg_colour_index": 6,
	"leg_shoes": "none",
	"hand_accessory": "pickaxe",
}

# ─── Exported properties ─────────────────────────────────────────────────────

## Walking speed in metres per second.
@export var move_speed: float = 4.5

## Jump impulse velocity.
@export var jump_velocity: float = 4.5

## Mouse look sensitivity (radians per pixel).
@export var mouse_sensitivity: float = 0.002

## Maximum place/break raycast distance in metres.
@export var raycast_distance: float = 10.0

# ─── Camera node references ───────────────────────────────────────────────────

## First-person camera at eye height (Y=1.6). Active when camera_mode == FPV.
@onready var camera_fpv: Camera3D = $Camera3D

## Pivot Node3D for the chase-cam rig. Pitch is applied here in CHASE mode so the
## camera arc sweeps over and under the builder. Positioned at Y=1.6 (eye height).
@onready var camera_pivot: Node3D = $CameraPivot

## RayCast3D — wall-collision probe for the Direct-Orbit chase camera (feat(07)).
## Replaces SpringArm3D. collision_mask=1 detects WorldStaticBody / VoxelTerrain.
## force_raycast_update() is called each physics frame; result is applied instantly
## to camera_chase.position.z with NO interpolation (T-CAM-02 mitigation).
@onready var camera_ray: RayCast3D = $CameraPivot/CameraRay

## Chase camera — direct child of CameraPivot. Active when camera_mode == CHASE.
## position.z is set each physics frame by the Direct-Orbit collision update.
@onready var camera_chase: Camera3D = $CameraPivot/ChaseCamera

# ─── Camera constants ─────────────────────────────────────────────────────────

## Minimum chase distance in metres (closest scroll-in distance).
const CHASE_DIST_MIN: float = 2.0

## Maximum chase distance in metres (furthest scroll-out distance).
const CHASE_DIST_MAX: float = 8.0

## Scroll-wheel step size in metres.
const CHASE_DIST_STEP: float = 0.5

## Clearance margin in metres subtracted from the ray-hit distance so the camera
## does not clip flush into geometry (equivalent to SpringArm3D margin=0.2).
const CHASE_MARGIN: float = 0.2

# ─── Plan 03-04: Survival constants ──────────────────────────────────────────

## Maximum HP in survival mode (0..10 range; 10 hearts in the HP bar).
const MAX_HP: int = 10

## Fall velocity (m/s) above which a landing is lethal (void-fall pile at surface).
const LETHAL_FALL_VELOCITY: float = 16.0

## Y threshold below which the builder is considered in the void.
const VOID_THRESHOLD_Y: float = -128.0

## Horizontal knockback impulse distance in metres per hit (D-08).
const KNOCKBACK_DISTANCE_M: float = 0.5

## Yaw rotation speed in radians/sec for Q/E keyboard turning (WoW-style).
const TURN_RATE_RAD_PER_S: float = deg_to_rad(135.0)

## Interaction range in metres for bed / chest / workbench walk-up (UI-SPEC L76).
const INTERACT_RANGE_M: float = 2.0

## Alpha of the damage vignette flash (D-08 + UI-SPEC L144).
const DAMAGE_VIGNETTE_ALPHA: float = 0.35

## Duration of the damage vignette flash in seconds.
const DAMAGE_VIGNETTE_DURATION_S: float = 0.2

## Duration of mobile haptic on damage in milliseconds (D-08).
const HAPTIC_MS: int = 50

# ─── Swimming constants (water buoyancy) ──────────────────────────────────────
# Tapping jump/Space in water is a swim-stroke. To make swimming practical (not
# twitchy) the builder rises a bit HIGHER per stroke than a land jump and sinks
# SLOWLY (reduced gravity) so it descends gently. These values are deliberately
# named for by-feel tuning by the owner; land jump/gravity are untouched.
# The WATER voxel id (7) is already declared once below as _WATER_VOXEL_ID and is
# reused by _is_in_water() — it matches FluidSim.WATER_ID / main_scene._WATER_VOXEL_ID.

## Height above the builder's feet (global_position is at the feet) at which we
## sample the voxel grid for water. ~mid-capsule (capsule centre is Y=0.9) so the
## builder counts as "in water" once its torso is submerged — wading through a
## shallow shoreline does not flip on swim physics, which would feel twitchy.
const _WATER_SAMPLE_HEIGHT_M: float = 0.9

## Gravity multiplier while in water. < 1.0 so the builder sinks gently rather than
## dropping like a stone. ~0.35 reads as buoyant; raise toward 1.0 for a heavier
## feel, lower toward 0 for near-neutral float.
const _WATER_GRAVITY_SCALE: float = 0.35

## Upward velocity (m/s) of a single swim-stroke. Modestly higher than the land
## jump_velocity (4.5) so each Space tap lifts the builder a bit more, and because
## strokes can repeat while submerged this gives controllable buoyant ascent.
const _WATER_STROKE_VELOCITY: float = 5.0

# ─── Camera state ─────────────────────────────────────────────────────────────

## Active camera mode. Defaults to CHASE per user decision 2026-05-26.
var camera_mode: CameraMode = CameraMode.CHASE

## Desired chase distance in metres. Adjusted by scroll-wheel zoom; the Direct-Orbit
## collision update in _physics_process may temporarily reduce camera_chase.position.z
## below this value when geometry is closer. Range: [CHASE_DIST_MIN, CHASE_DIST_MAX].
var _chase_distance: float = 4.0

# ─── Plan 03-04: Survival signals ────────────────────────────────────────────

## Emitted when HP changes (survival mode only). Drives HpBar UI update.
signal hp_changed(new_hp: int)

## Emitted when the builder dies. Payload: builder_id + pile position.
signal died(builder_id: String, position: Vector3)

## Emitted when the builder respawns (after death overlay or on new world).
signal respawned(position: Vector3)

## Emitted when the player presses the inventory-toggle action.
## Plan 03-05's inventory slide-in listens to this signal.
signal inventory_toggle_requested()

## Emitted when the player swings with a melee weapon (Plan 03-10 mobs listen).
signal attack_swing(direction: Vector3, damage: int)

# ─── Plan 06-07: Avatar mesh node references ──────────────────────────────────
# All created programmatically in _setup_avatar_mesh_nodes() called from _ready().

## AvatarMesh root Node3D (parent of all avatar sub-parts).
var _avatar_mesh_root: Node3D = null

## Head MeshInstance3D — skin colour applied here.
var _head_mesh: MeshInstance3D = null

## Body MeshInstance3D — body_colour applied here.
var _body_mesh: MeshInstance3D = null

## Legs MeshInstance3D — leg_colour applied here.
var _legs_mesh: MeshInstance3D = null

## HandItem Node3D — parent of per-accessory MeshInstance3D children.
## Keyed by hand_accessory string token → MeshInstance3D (or Node3D for "none").
var _hand_nodes: Dictionary = {}

## BodyAccessory Node3D — parent of per-accessory Node3D children.
## Keyed by body_accessory string token → Node3D.
var _body_accessory_nodes: Dictionary = {}

# ─── Phase 8: Builder rig animator (ANIM-03/04) ───────────────────────────────

## MinifigureAnimator (mesh_set "builder") — the animated builder-figure rig, sole visual
## when present. Created in _setup_avatar_mesh_nodes(); gait driven each physics
## frame from horizontal velocity (idle < 0.5 m/s, else walk).
var _rig_anim: MinifigureAnimator = null

## v1.1 art pass: textured rigged Meshy avatar (builder_avatar.glb) + its AnimationPlayer.
## When present this is the visual (rig/boxes hidden); "Walking" plays while moving, paused
## at frame 0 while idle.
var _avatar_anim: AnimationPlayer = null
var _avatar_walk_name: String = ""

## Selectable builder skins (avatar.cfg "skin" key → rigged+animated model). Default builder1.
const _AVATAR_SKINS: Dictionary = {
	"builder1": "res://assets/meshes/builder/skin_builder1.glb",
	"red": "res://assets/meshes/builder/skin_red.glb",
	"fem": "res://assets/meshes/builder/skin_fem.glb",
}
const _DEFAULT_SKIN: String = "builder1"

## Per-skin yaw correction (radians) applied in _finalize_avatar. builder1 and red are
## authored facing -Z (forward) and read correctly at 0. skin_fem was authored facing a
## different axis (showed facing the camera + strafing sideways), so it needs a half-turn.
## If fem still faces wrong, adjust ONLY this value (PI = 180°, ±PI/2 = sideways quarter-turns).
const _AVATAR_FACING_OFFSET: Dictionary = {
	# All current avatar meshes are authored facing +Z (Godot's forward is -Z), so every skin
	# needs a 180° yaw flip or it walks backwards / faces the camera (QA: "the red builder is
	# wired backwards, facing the camera while walking"). Mirrors wildlife.gd's per-mesh PI
	# flip for the same +Z-authored art. Unlisted skins default to PI for the same reason.
	"builder1": PI,
	"red": PI,
	"fem": PI,
}

## Per-skin locomotion clip override (exact animation name). Used when a skin's "Walking"
## clip reads wrong: skin_fem's "Walking" looks like a hammer/mining swing, so we drive its
## movement with the cleaner "Running" stride instead. Skins not listed use the first clip
## whose name contains "walk".
const _AVATAR_WALK_CLIP: Dictionary = {
	"fem": "Running",
}


## Read the chosen character skin from user://avatar.cfg ("avatar"/"character"); default
## builder1. ("character" not "skin" — the customiser's "skin" key is the skin-tone colour.)
func _read_selected_skin() -> String:
	var cfg := ConfigFile.new()
	if cfg.load("user://avatar.cfg") == OK:
		return str(cfg.get_value("avatar", "character", _DEFAULT_SKIN))
	return _DEFAULT_SKIN

## Avatar skeleton + the BoneAttachment3D the HandItem (pickaxe) rides on, so the tool
## follows the right hand as the walk animation swings the arm. Null when no avatar.
var _avatar_skeleton: Skeleton3D = null
var _hand_attach: BoneAttachment3D = null
var _hand_root: Node3D = null

## Held-pickaxe tier → art-tools model. The builder shows the model for its current tier
## (default wood); equip_pickaxe_tier() swaps it. Falls back to a procedural handle+head
## when the model asset is absent (headless/CI).
const _PICKAXE_TIER_MODELS: Dictionary = {
	"wood": "res://assets/meshes/tools/pickaxe_wood.glb",
	"stone": "res://assets/meshes/tools/pickaxe_stone.glb",
	"iron": "res://assets/meshes/tools/pickaxe_iron.glb",
	"diamond": "res://assets/meshes/tools/pickaxe_diamond.glb",
}
## Longest-axis size (m) the held pickaxe model is scaled to, and its grip orientation in the
## hand-item frame (tuned so it reads as carried). The HandItem rides the RightHand bone.
const _PICKAXE_HELD_SIZE_M: float = 0.95
const _PICKAXE_GRIP_ROT: Vector3 = Vector3(-20.0, 0.0, 18.0)
## Current held pickaxe tier (key into _PICKAXE_TIER_MODELS).
var _pickaxe_tier: String = "wood"

## Horizontal speed below which the rig is "idle" (ANIM-04).
const _RIG_IDLE_SPEED_THRESHOLD: float = 0.5

## Pickaxe grip pose in the avatar's RightHand-bone local frame (tuned visually so the
## tool sits in the fist rather than floating beside it).
const _HAND_GRIP_OFFSET: Vector3 = Vector3(0.0, 0.0, 0.0)
const _HAND_GRIP_ROT: Vector3 = Vector3(0.0, 0.0, 0.0)

## Last avatar colours applied (skin, body, legs) so the rig can be recoloured
## once its pivots populate (its _ready runs after this node's _ready).
var _rig_colours: Array = []  # [Color skin, Color body, Color legs]

# ─── Internals ────────────────────────────────────────────────────────────────

# Pitch is stored separately so we can clamp it.
var _camera_pitch: float = 0.0

# Plan 05 — stud grid and brick renderer wired in _ready() from main_scene siblings.
var _stud_grid: StudGrid = null
var _brick_renderer: MultiMeshInstance3D = null

# Preloaded brick definition — fallback when the hotbar has no brick equipped.
const BRICK_1X1 := preload("res://src/bricks/brick_1x1.tres")


## Resolve the brick to place from the active hotbar slot, falling back to BRICK_1X1.
## Returns {"def": BrickDefinition, "colour_index": int}. This is what makes "place a
## wooden plank" work — _try_place used to hardcode BRICK_1X1, so the FTUE step (which
## listens for StudGrid.placed with brick_id == "wood_plank") could never complete.
func _active_brick() -> Dictionary:
	var result: Dictionary = {"def": BRICK_1X1, "colour_index": -1}
	var hotbar: Node = get_tree().get_first_node_in_group("hotbar") if is_inside_tree() else null
	if hotbar != null and hotbar.has_method("get_active_brick"):
		var active: Dictionary = hotbar.get_active_brick()
		var def_id: String = str(active.get("def_id", ""))
		if not def_id.is_empty():
			var def: BrickDefinition = BrickRegistry.get_definition(def_id) as BrickDefinition
			if def != null:
				result["def"] = def
				result["colour_index"] = int(active.get("colour_index", -1))
	return result

# Terrain node reference — cached in _ready() from parent scene.
var _terrain: Node = null

# ─── Spawn-grace gate ────────────────────────────────────────────────────────
# Holds the builder in place during the first frames after world load while
# VoxelTerrain bakes collision shapes underneath them. Without this, gravity
# wins the race against async collision baking and the player falls through
# the world before they can land. Released as soon as a downward raycast hits
# terrain OR a hard timeout fires.
var _spawn_grace_done: bool = false
## -1 = not yet started. Started LAZILY on the first _physics_process frame, NOT in _ready():
## builder._ready() runs before main_scene._ready(), which used to stamp ~340k bricks
## synchronously — that multi-second block consumed the whole grace window before physics
## even ran, so the gate timed out with no collision baked and the builder fell through the
## world to the bottom (Y≈-64). Starting the clock at first physics frame measures the grace
## from when terrain actually begins meshing.
var _spawn_grace_started_msec: int = -1
const _SPAWN_GRACE_MAX_MS: int = 30000  # safety net only — terrain normally bakes in ~1-3 s.
# Raised 12 → 30 s so a slow first-load (heavy NPC/figure loads competing for the main thread)
# can't expire the gate before terrain collision bakes under the spawn — that released the
# builder into the void. The builder stays frozen at the spawn surface until ground exists.
## Terrain surface Y captured by the grace raycast; the builder is snapped here on
## release so it settles onto the ground instead of free-falling (and dying) from its
## high spawn Y. INF until a hit is found (timeout releases without a snap).
var _spawn_snap_y: float = INF
## Height above the detected surface to drop the builder from on release (a harmless
## settle, well under LETHAL_FALL_VELOCITY).
const _SPAWN_SNAP_OFFSET_M: float = 1.2

# ─── Lifecycle ────────────────────────────────────────────────────────────────

## Returns true once the spawn-grace gate should release the builder.
## Conditions (any one releases the gate):
##   1. A short downward raycast from current position hits something (terrain
##      collision shape exists below us) — the safest signal.
##   2. _SPAWN_GRACE_MAX_MS has elapsed (timeout — don't soft-lock the player
##      if for some reason raycast never hits, e.g. void biome at spawn).
func _spawn_grace_should_release() -> bool:
	# Lazily start the grace clock on the first call (first physics frame) so the timer
	# isn't consumed by main_scene's pre-stamp work that runs before physics ticks.
	if _spawn_grace_started_msec < 0:
		_spawn_grace_started_msec = Time.get_ticks_msec()
		return false
	if Time.get_ticks_msec() - _spawn_grace_started_msec >= _SPAWN_GRACE_MAX_MS:
		return true
	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	if space_state == null:
		return false
	var from: Vector3 = global_position
	var to: Vector3 = from + Vector3(0.0, -64.0, 0.0)
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 1  # Layer 1 = WorldStaticBody / VoxelTerrain
	query.exclude = [self.get_rid()]
	var result: Dictionary = space_state.intersect_ray(query)
	if result.is_empty():
		return false
	# Capture the surface Y so the release can drop the builder onto it instead of
	# letting it plunge from its (much higher) spawn Y.
	_spawn_snap_y = (result["position"] as Vector3).y
	return true


func _ready() -> void:
	# Register in "builder" group so ghost_preview.gd can find this node via
	# get_tree().get_first_node_in_group("builder") (Plan 02-09).
	add_to_group("builder")

	# NOTE: the spawn-grace clock is started lazily on the first _physics_process frame
	# (see _spawn_grace_should_release), NOT here — see _spawn_grace_started_msec docs.

	# Capture mouse on desktop so mouse-look works immediately.
	# T-04-03: on mobile, mouse capture freezes touch input — skip capture.
	# Plan 06 will set MOUSE_MODE_VISIBLE explicitly on mobile when the overlay loads.
	if not OS.has_feature("mobile"):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	# Wire stud grid and brick renderer from sibling nodes in main_scene.tscn.
	# These may be null in contexts where main_scene is not the active scene (e.g. sub-tests).
	_stud_grid = get_node_or_null("../StudGrid") as StudGrid
	_brick_renderer = get_node_or_null("../BrickRenderer") as MultiMeshInstance3D
	_terrain = get_node_or_null("../Terrain")

	# Fix(07): Assign a real mesh to the BrickRenderer MultiMesh so placed bricks
	# are visible. Uses brick_1x1 as the representative mesh (single-type simplification;
	# per-type batching is a future enhancement — do NOT rearchitect now).
	# Also enable use_colors so per-instance palette colours are applied.
	if _brick_renderer != null and _brick_renderer.multimesh != null:
		var _rep_def: BrickDefinition = BrickRegistry.get_definition("brick_1x1")
		if _rep_def != null and _rep_def.mesh != null:
			_brick_renderer.multimesh.mesh = _rep_def.mesh
			_brick_renderer.multimesh.use_colors = true
			# Give placed bricks the same brick studs as the terrain. The stud shader
			# uses a white atlas here so ALBEDO = white × per-instance COLOR = the brick's
			# palette colour, and the per-instance MODEL_MATRIX keeps studs on the world grid.
			var stud_sh: Shader = load("res://assets/shaders/brick_terrain.gdshader") as Shader
			if stud_sh != null:
				var brick_mat := ShaderMaterial.new()
				brick_mat.shader = stud_sh
				var white_img := Image.create(2, 2, false, Image.FORMAT_RGBA8)
				white_img.fill(Color.WHITE)
				brick_mat.set_shader_parameter("atlas", ImageTexture.create_from_image(white_img))
				_brick_renderer.material_override = brick_mat
		else:
			push_warning("Builder._ready: brick_1x1 mesh unavailable; BrickRenderer stays empty.")

	# Subscribe to stud_grid signals to keep the MultiMesh in sync.
	if _stud_grid != null and _brick_renderer != null:
		_stud_grid.placed.connect(_on_brick_placed)
		_stud_grid.removed.connect(_on_brick_removed)
		# The spawn-area pre-stamp places ~200k bricks under StudGrid.begin_bulk(), which
		# suppresses the per-brick `placed` signal (else _on_brick_placed's per-brick
		# instance_count growth is an O(n²) realloc that freezes the frame and leaves the
		# world an empty sky). bulk_changed fires once at end_bulk() → one O(n) resync.
		if _stud_grid.has_signal("bulk_changed"):
			_stud_grid.bulk_changed.connect(_sync_multimesh_from_stud_grid)
		# Deferred one-time sync to catch any bricks placed before this connection was made
		# (autoload ordering edge cases).
		call_deferred("_sync_multimesh_from_stud_grid")

	# T-CAM-02: assert CameraRay collision_mask includes layer 1 (bit 0).
	assert(camera_ray.collision_mask & 1 != 0,
		"T-CAM-02: camera_ray.collision_mask must include layer 1 (WorldStaticBody/terrain)")

	# Load persisted camera mode from WorldSave (T-CAM-01: defensive parse).
	if WorldSave.is_open():
		var saved_mode: Variant = WorldSave.get_world_meta("camera_mode")
		if saved_mode != null and saved_mode is String:
			var mode_str: String = str(saved_mode)
			if mode_str == "fpv":
				camera_mode = CameraMode.FPV
			elif mode_str == "chase":
				camera_mode = CameraMode.CHASE
			else:
				# T-CAM-01: unknown value — default to CHASE silently with a warning.
				push_warning("Builder._ready: unknown camera_mode '%s' in WorldSave; defaulting to CHASE." % mode_str)
				camera_mode = CameraMode.CHASE
		else:
			# No camera_mode in WorldSave yet — write the default explicitly.
			WorldSave.set_world_meta("camera_mode", "chase")

	# Activate the persisted (or default) camera.
	_apply_camera_mode()

	# ─── Plan 02-14: Stable builder UUID (Pitfall 8 mitigation) ─────────────
	# Generate or restore the per-device stable UUID from user://settings.cfg.
	# This UUID is the local identity used by rain-dance quota and Phase 4
	# peer identification before a server-issued account_id is available.
	var builder_cfg := ConfigFile.new()
	builder_cfg.load("user://settings.cfg")  # OK if file absent — returns ERR_FILE_NOT_FOUND
	var existing_id: String = builder_cfg.get_value("builder", "id", "") as String
	if existing_id == "":
		existing_id = _generate_uuid_v4()
		builder_cfg.set_value("builder", "id", existing_id)
		builder_cfg.save("user://settings.cfg")
	_stable_builder_id = existing_id

	# ─── Plan 03-04: Subscribe to sleep_lapse_ended signal (D-12) ─────────
	# WorldClock is always available (Phase 2 autoload). sleep_lapse_ended
	# was added in Plan 03-03; connect it here for the HP-restore + _is_sleeping clear.
	if WorldClock.has_signal("sleep_lapse_ended"):
		WorldClock.sleep_lapse_ended.connect(_on_sleep_lapse_ended)

	# Restore last-slept bed position from WorldSave (survives world reload).
	if WorldSave.is_open():
		var bed_raw: Variant = WorldSave.get_world_meta(
			"builder:" + _stable_builder_id + ":last_bed")
		if bed_raw is PackedByteArray:
			var decoded: Variant = bytes_to_var(bed_raw as PackedByteArray)
			if decoded is Vector3:
				_last_slept_bed_pos = decoded as Vector3
				_has_slept_in_bed = true

	# ─── Plan 06-07: Avatar mesh setup + config load ─────────────────────
	# Build the multi-part avatar mesh sub-nodes programmatically so the scene
	# works correctly in both the main world and the SubViewport preview.
	_setup_avatar_mesh_nodes()
	# Load and apply avatar config from disk; falls back to DEFAULT_AVATAR_CFG.
	load_avatar_from_file()


# ─── Input ────────────────────────────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	# Ignore all gameplay input while the sleep cutscene holds the builder.
	if _sleep_frozen:
		return

	# Camera mode toggle (V key, desktop default).
	if event.is_action_pressed("toggle_camera_mode"):
		toggle_camera_mode()

	# Scroll-wheel zoom: only applies in CHASE mode; no-op in FPV (T-CAM contract).
	# Adjusts _chase_distance (desired distance); camera_ray.target_position.z is updated
	# so the ray length tracks the new zoom level. Actual camera_chase.position.z is set
	# each physics frame by the Direct-Orbit collision update (no interpolation).
	if camera_mode == CameraMode.CHASE:
		if event.is_action_pressed("camera_zoom_in"):
			_chase_distance = clampf(
				_chase_distance - CHASE_DIST_STEP, CHASE_DIST_MIN, CHASE_DIST_MAX)
			camera_ray.target_position.z = _chase_distance
		elif event.is_action_pressed("camera_zoom_out"):
			_chase_distance = clampf(
				_chase_distance + CHASE_DIST_STEP, CHASE_DIST_MIN, CHASE_DIST_MAX)
			camera_ray.target_position.z = _chase_distance

	# WoW-style look: mouse motion is ignored UNLESS the right mouse button
	# is held. Right-click + mouse drag is the "steer + look around" mode —
	# X rotates the builder (yaw, so walking direction follows) and Y adjusts
	# camera pitch. Without RMB, the mouse cursor is free for UI interaction.
	# Yaw via Q/E in _physics_process still works as the no-mouse fallback.
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
			rotate_y(-event.relative.x * mouse_sensitivity)
			_camera_pitch -= event.relative.y * mouse_sensitivity
			_camera_pitch = clampf(_camera_pitch, deg_to_rad(-89.0), deg_to_rad(89.0))
			if camera_mode == CameraMode.FPV:
				camera_fpv.rotation.x = _camera_pitch
			else:
				camera_pivot.rotation.x = _camera_pitch

	# Plan 02-14: Rain dance action (R key desktop; TouchScreenButton on mobile).
	if event.is_action_pressed("ui_rain_dance"):
		rain_dance()

	# Place brick action (RMB / touch place button — see CLAUDE.md §7.5).
	if event.is_action_pressed("place"):
		_try_place()

	# Break brick/terrain action (LMB / touch break button — see CLAUDE.md §7.5).
	if event.is_action_pressed("break"):
		_try_break()

	# ─── Plan 03-04: survival input actions ────────────────────────────────
	# sleep_interact is checked BEFORE ui_inventory_toggle so that pressing E
	# near a bed at night triggers sleep (and consumes the event) rather than
	# opening the inventory (T-03-04-INPUT-01 mitigation).
	if event.is_action_pressed("sleep_interact"):
		_try_sleep_interact()

	if event.is_action_pressed("ui_inventory_toggle"):
		inventory_toggle_requested.emit()

	if event.is_action_pressed("attack"):
		_try_attack()


# ─── Physics ──────────────────────────────────────────────────────────────────

func _physics_process(delta: float) -> void:
	# ─── Spawn-grace gate ────────────────────────────────────────────────────
	# VoxelTerrain meshes + collision shapes bake asynchronously after world
	# load — collision can lag ~1-3s behind voxel data. Without a gate the
	# builder spawns at y=32, gravity pulls them down faster than collision
	# bakes underneath them, and they fall through the world into the void.
	# Hold the builder in place until a raycast finds terrain below OR a hard
	# timeout fires, whichever comes first. Once released we set
	# _spawn_grace_done = true and never re-engage this gate.
	if not _spawn_grace_done:
		var release: bool = _spawn_grace_should_release()
		if release:
			_spawn_grace_done = true
			# Snap onto the detected surface so the builder settles gently instead of
			# free-falling from its high spawn Y (which triggered instant fall-death).
			if is_finite(_spawn_snap_y):
				global_position.y = _spawn_snap_y + _SPAWN_SNAP_OFFSET_M
			velocity = Vector3.ZERO
			_last_fall_velocity = 0.0
		else:
			velocity = Vector3.ZERO
			return  # skip gravity, jump, movement, fall detection this frame

	# Frozen during the bed sleep cutscene — hold still on the bed (no gravity/movement).
	if _sleep_frozen:
		velocity = Vector3.ZERO
		return

	# Swimming: when the builder's body is in a water voxel, gravity is reduced so
	# it sinks gently (buoyant) and each Space tap is a swim-stroke that lifts it a
	# bit higher than a land jump. Out of water this is false and land physics are
	# unchanged. Sampled once per frame so the same state drives gravity + stroke.
	var in_water: bool = _is_in_water()

	# Apply gravity when not on the floor. In water it is scaled down so the builder
	# descends slowly instead of dropping like a stone.
	if not is_on_floor():
		var gravity_scale: float = _WATER_GRAVITY_SCALE if in_water else 1.0
		velocity += get_gravity() * gravity_scale * delta

	# ─── Plan 03-04: track fall velocity for lethal-fall detection ─────────
	# Record the absolute downward speed each frame (positive value = falling).
	_last_fall_velocity = abs(velocity.y) if velocity.y < 0.0 else 0.0

	# Jump / swim-stroke when the jump action is just pressed.
	# In water: stroke upward from anywhere (re-stroking while submerged works via
	# repeated Space taps), with a modestly higher impulse than the land jump.
	# On land: unchanged — jump only when standing on the floor.
	if in_water:
		if Input.is_action_just_pressed("jump"):
			velocity.y = _WATER_STROKE_VELOCITY
	elif is_on_floor() and Input.is_action_just_pressed("jump"):
		velocity.y = jump_velocity

	# WoW-style yaw turning: Q rotates left, E rotates right. Smooth, framerate-
	# independent rotation around the Y axis. Camera (chase + FPV) follows
	# automatically because both are children of this CharacterBody3D.
	var turn: float = 0.0
	if Input.is_action_pressed("turn_left"):
		turn += 1.0
	if Input.is_action_pressed("turn_right"):
		turn -= 1.0
	if turn != 0.0:
		rotate_y(turn * TURN_RATE_RAD_PER_S * delta)

	# WASD movement: get_vector returns a [-1..1] normalised 2D vector.
	# We rotate it by the camera's yaw so WASD is camera-relative.
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if input_dir != Vector2.ZERO:
		# Camera yaw is the Y rotation of this CharacterBody3D (camera yaw lives here).
		var yaw := rotation.y
		var direction := Vector3(
			input_dir.x * cos(yaw) + input_dir.y * sin(yaw),
			0.0,
			input_dir.x * -sin(yaw) + input_dir.y * cos(yaw)
		).normalized()
		velocity.x = direction.x * move_speed
		velocity.z = direction.z * move_speed
	else:
		# Decelerate instantly when no input (simple friction, not a slide game).
		velocity.x = 0.0
		velocity.z = 0.0

	move_and_slide()

	# ─── Drive the avatar animation from horizontal speed (v1.1 textured rigged avatar;
	#     falls back to the MinifigureAnimator rig when the avatar asset is absent) ─
	var h_speed: float = Vector2(velocity.x, velocity.z).length()
	if _avatar_anim != null and _avatar_walk_name != "":
		if h_speed >= _RIG_IDLE_SPEED_THRESHOLD:
			if not _avatar_anim.is_playing():
				_avatar_anim.play(_avatar_walk_name)
		elif _avatar_anim.is_playing():
			# Stopped moving: end the walk cycle and snap back to the rest stand so the
			# builder doesn't freeze mid-stride.
			_avatar_anim.stop()
			_reset_avatar_rest_pose()
	elif _rig_anim != null:
		_rig_anim.gait = "idle" if h_speed < _RIG_IDLE_SPEED_THRESHOLD else "walk"

	# ─── Direct-Orbit camera collision (feat(07)) ────────────────────────────
	# Force the ray to update immediately (not deferred) so positions are current
	# after move_and_slide(). Directly set camera_chase.position.z — NO lerp/Tween.
	# This eliminates motion-sickness artefacts caused by SpringArm interpolation.
	if camera_mode == CameraMode.CHASE and camera_ray != null and camera_chase != null:
		camera_ray.force_raycast_update()
		var dist: float = _chase_distance
		if camera_ray.is_colliding():
			var hit: Vector3 = camera_ray.get_collision_point()
			var d: float = camera_pivot.global_position.distance_to(hit) - CHASE_MARGIN
			dist = clampf(d, CHASE_DIST_MIN, _chase_distance)
		camera_chase.position.z = dist

	# ─── Water-entry splash fx (art-movements) ──────────────────────────────
	_water_check_accum += delta
	if _water_check_accum >= _WATER_CHECK_INTERVAL_S:
		_water_check_accum = 0.0
		_check_water_entry()

	# ─── Plan 03-04: lethal-fall and void-fall detection ───────────────────
	if not _is_dead:
		# Lethal landing: just hit the floor after falling faster than the threshold.
		if is_on_floor() and _last_fall_velocity > LETHAL_FALL_VELOCITY:
			_fall_velocity_at_death = _last_fall_velocity
			take_damage(MAX_HP, global_position)
		# Void fall: below the void threshold.
		elif global_position.y < VOID_THRESHOLD_Y:
			_fall_velocity_at_death = LETHAL_FALL_VELOCITY + 1.0  # treat as lethal
			take_damage(MAX_HP, global_position)

	# Sleeping is the player's escape from the night. _try_sleep_interact already
	# clears hostiles around the bed before the lapse, and the bed bubble suppresses
	# new spawns nearby — so we do NOT cancel an in-progress sleep on hostile presence.
	# (The old mid-sleep cancel fired "too dangerous" right after lying down whenever a
	# straggler lingered, making it impossible to sleep next to the bed at night.)


# ─── Swimming (water buoyancy) ────────────────────────────────────────────────

## True when the builder's body is inside a WATER voxel.
##
## Mirrors main_scene._voxel_is_water_at(): we query the Terrain VoxelTool (the
## authoritative voxel grid, which the FluidSim writes its water levels into) for
## the voxel id at the builder's mid-body. WATER is id 7 (see FluidSim.WATER_ID /
## main_scene._WATER_VOXEL_ID). We sample mid-capsule (feet + _WATER_SAMPLE_HEIGHT_M)
## rather than at the feet so wading through ankle-deep shoreline does not flip on
## swim physics — only genuine submersion does. Returns false (= land physics) when
## no terrain / VoxelTool is available (headless tests, terrain not yet streamed).
func _is_in_water() -> bool:
	if _terrain == null or not _terrain.has_method("get_voxel_tool"):
		return false
	var voxel_tool = _terrain.get_voxel_tool()
	if voxel_tool == null:
		return false
	voxel_tool.channel = VoxelBuffer.CHANNEL_TYPE
	var sample: Vector3 = global_position + Vector3(0.0, _WATER_SAMPLE_HEIGHT_M, 0.0)
	var cell := Vector3i(floori(sample.x), floori(sample.y), floori(sample.z))
	return voxel_tool.get_voxel(cell) == _WATER_VOXEL_ID


# ─── Camera API (Plan 08.5) ───────────────────────────────────────────────────

## Return the currently active Camera3D — camera_fpv in FPV mode, camera_chase in CHASE mode.
func get_active_camera() -> Camera3D:
	return camera_fpv if camera_mode == CameraMode.FPV else camera_chase


## Toggle between FPV and CHASE modes, persist the new mode to WorldSave (if open).
func toggle_camera_mode() -> void:
	camera_mode = CameraMode.CHASE if camera_mode == CameraMode.FPV else CameraMode.FPV
	_apply_camera_mode()
	if WorldSave.is_open():
		WorldSave.set_world_meta("camera_mode",
			"fpv" if camera_mode == CameraMode.FPV else "chase")


## Activate the camera that corresponds to the current camera_mode.
## Safe to call from tests without triggering _ready (no WorldSave dependency).
func _apply_camera_mode() -> void:
	camera_fpv.current = (camera_mode == CameraMode.FPV)
	camera_chase.current = (camera_mode == CameraMode.CHASE)


# ─── Crosshair / aim API — Plan 05 + Plan 08.5 refactor ──────────────────────

## Returns the world-space position of the active camera (ray origin for placement / breaking).
## Works identically in first-person and chase-cam — Plan 09 ghost preview uses this.
func get_crosshair_position() -> Vector3:
	return get_active_camera().global_position


## Returns the world-space direction the active camera is looking (-Z of its basis).
## Works identically in first-person and chase-cam — Plan 09 ghost preview uses this.
func get_crosshair_direction() -> Vector3:
	return -get_active_camera().global_basis.z.normalized()


## Alias preserved for Plan 05 compatibility (maps to get_crosshair_position).
func get_aim_origin() -> Vector3:
	return get_crosshair_position()


## Alias preserved for Plan 05 compatibility (maps to get_crosshair_direction).
func get_aim_direction() -> Vector3:
	return get_crosshair_direction()


# ─── Plan 02-09: rotation helpers ─────────────────────────────────────────────

## Derive a 0..3 rotation step from the builder's current yaw.
## Snaps the builder Y-rotation to the nearest 90° step.
## 0 = 0°, 1 = 90°, 2 = 180°, 3 = 270°.
## Called at place time; DOCS.md §3.2 — orientation derived from builder yaw, not player input.
func _derive_rotation_from_builder_yaw() -> int:
	var yaw: float = global_basis.get_euler().y
	return int(round(yaw / (PI / 2.0))) & 3


## Rotate a footprint of Vector3i offsets by a rotation step (0..3).
## Permutes X and Z only; Y is never affected (DOCS.md §3.2: bricks don't tilt).
##
## Rotation matrix applied around Y axis (right-hand rule, Godot convention):
##   step 0 (  0°): (x, y, z) →  (x, y, z)
##   step 1 ( 90°): (x, y, z) →  (z, y,-x)   [same as rotating CW viewed from above]
##   step 2 (180°): (x, y, z) → (-x, y,-z)
##   step 3 (270°): (x, y, z) → (-z, y, x)
##
## @param footprint  Array[Vector3i] of per-cell offsets from the anchor.
## @param rotation   0..3 rotation step.
## @return           New Array[Vector3i] with permuted offsets.
func _rotated_footprint(footprint: Array, rotation: int) -> Array:
	var result: Array = []
	rotation = rotation & 3
	for offset_raw: Variant in footprint:
		var o: Vector3i = offset_raw as Vector3i
		var rotated: Vector3i
		match rotation:
			0:
				rotated = Vector3i(o.x, o.y, o.z)
			1:
				rotated = Vector3i(o.z, o.y, -o.x)
			2:
				rotated = Vector3i(-o.x, o.y, -o.z)
			3:
				rotated = Vector3i(-o.z, o.y, o.x)
			_:
				rotated = o
		result.append(rotated)
	return result


# ─── Plan 02-09: stud-grid raycast ────────────────────────────────────────────

## DDA raycast across the stud grid to find the first occupied cell.
##
## Returns a Dictionary with:
##   "cell"          : Vector3i — the occupied cell that was hit
##   "previous_cell" : Vector3i — the empty cell adjacent on the face that was hit
##                                (used as the anchor for brick-on-brick placement)
## Returns null (Variant) if no brick is found within max_dist.
##
## Implementation: integer DDA stepping one cell at a time along the ray.
## The stud grid is sparse so most steps find empty cells quickly.
func _raycast_stud_grid(origin: Vector3, direction: Vector3, max_dist: float) -> Variant:
	if direction.is_zero_approx():
		return null

	var dir: Vector3 = direction.normalized()

	# Step sizes along each axis.
	var delta_x: float = abs(1.0 / dir.x) if dir.x != 0.0 else INF
	var delta_y: float = abs(1.0 / dir.y) if dir.y != 0.0 else INF
	var delta_z: float = abs(1.0 / dir.z) if dir.z != 0.0 else INF

	# Current integer cell.
	var cell_x: int = int(floor(origin.x))
	var cell_y: int = int(floor(origin.y))
	var cell_z: int = int(floor(origin.z))

	# Step direction for each axis.
	var step_x: int = 1 if dir.x > 0.0 else -1
	var step_y: int = 1 if dir.y > 0.0 else -1
	var step_z: int = 1 if dir.z > 0.0 else -1

	# Distance to next cell boundary on each axis.
	var t_max_x: float
	var t_max_y: float
	var t_max_z: float

	if dir.x > 0.0:
		t_max_x = (float(cell_x + 1) - origin.x) / dir.x
	elif dir.x < 0.0:
		t_max_x = (float(cell_x) - origin.x) / dir.x
	else:
		t_max_x = INF

	if dir.y > 0.0:
		t_max_y = (float(cell_y + 1) - origin.y) / dir.y
	elif dir.y < 0.0:
		t_max_y = (float(cell_y) - origin.y) / dir.y
	else:
		t_max_y = INF

	if dir.z > 0.0:
		t_max_z = (float(cell_z + 1) - origin.z) / dir.z
	elif dir.z < 0.0:
		t_max_z = (float(cell_z) - origin.z) / dir.z
	else:
		t_max_z = INF

	var prev_cell := Vector3i(cell_x, cell_y, cell_z)
	var current_t: float = 0.0

	while current_t < max_dist:
		var current_cell := Vector3i(cell_x, cell_y, cell_z)

		if _stud_grid != null and _stud_grid.query(current_cell) != null:
			return {"cell": current_cell, "previous_cell": prev_cell}

		prev_cell = current_cell

		# Advance to the next cell boundary.
		if t_max_x < t_max_y and t_max_x < t_max_z:
			current_t = t_max_x
			cell_x += step_x
			t_max_x += delta_x
		elif t_max_y < t_max_z:
			current_t = t_max_y
			cell_y += step_y
			t_max_y += delta_y
		else:
			current_t = t_max_z
			cell_z += step_z
			t_max_z += delta_z

	return null


# ─── Plan 02-09: predict_placement_target (shared with ghost_preview) ─────────

## Predict where the next brick would be placed without actually placing it.
## Used by ghost_preview.gd (Plan 02-09) and _try_place internals.
##
## Returns a Dictionary:
##   "valid"       : bool — whether placement would succeed
##   "target_cell" : Vector3i — the cell where the brick would land (only valid if valid==true)
##   "footprint"   : Array[Vector3i] — all cells the brick occupies (rotated, anchor-relative)
##   "rotation"    : int — the 0..3 rotation step
##
## Returns {"valid": false, "target_cell": Vector3i.ZERO, "footprint": [], "rotation": 0}
## if no valid placement target exists.
func predict_placement_target() -> Dictionary:
	var none_result: Dictionary = {
		"valid": false,
		"target_cell": Vector3i.ZERO,
		"footprint": [],
		"rotation": 0
	}

	if _stud_grid == null:
		return none_result

	var origin: Vector3 = get_crosshair_position()
	var direction: Vector3 = get_crosshair_direction()

	# ── Step 1: Try VoxelTerrain raycast ────────────────────────────────────
	var anchor := Vector3i.ZERO
	var found_anchor := false

	if _terrain != null and _terrain.has_method("get_voxel_tool"):
		var voxel_tool = _terrain.get_voxel_tool()
		if voxel_tool != null:
			var hit = voxel_tool.raycast(origin, direction, raycast_distance)
			if hit != null:
				# Phase 2: hit.previous_position is the empty cell adjacent to the hit face.
				# Works for top / side / bottom faces uniformly (Pattern 4, RESEARCH.md line 780).
				anchor = hit.previous_position
				found_anchor = true

	# ── Step 2: Try stud-grid raycast (brick-on-brick) ──────────────────────
	if not found_anchor:
		var brick_hit: Variant = _raycast_stud_grid(origin, direction, raycast_distance)
		if brick_hit != null and brick_hit is Dictionary:
			anchor = brick_hit["previous_cell"]
			found_anchor = true

	if not found_anchor:
		return none_result

	# ── Step 3: Footprint + rotation ────────────────────────────────────────
	# Use the equipped brick's footprint so multi-cell bricks validate correctly.
	var def: BrickDefinition = _active_brick()["def"] as BrickDefinition
	var rotation: int = _derive_rotation_from_builder_yaw()
	var footprint: Array = _rotated_footprint(def.footprint_cells, rotation)

	# ── Step 4: Validate every footprint cell is free ───────────────────────
	for offset_raw: Variant in footprint:
		var offset: Vector3i = offset_raw as Vector3i
		if _stud_grid.query(anchor + offset) != null:
			return {"valid": false, "target_cell": anchor, "footprint": footprint, "rotation": rotation}

	# ── Step 5: Bounds check (T-05-04) ─────────────────────────────────────
	if (abs(anchor.x) > 2048 or abs(anchor.y) > 2048 or abs(anchor.z) > 2048):
		return none_result

	return {"valid": true, "target_cell": anchor, "footprint": footprint, "rotation": rotation}


# ─── Plan 02-09: _try_place / _try_break (Phase 2 — lifts top-face restriction) ───

## Try to place a brick at the terrain/stud-grid face under the crosshair.
## Phase 2: supports top + side + brick-on-brick faces; multi-cell footprint;
## builder-yaw-derived rotation. No manual rotation (DOCS.md §3.2).
##
## Plan 02-11: if the active hotbar slot is the dynamite tool, instantiate
## DynamiteHandler at the hit position and call light_fuse(world_pos).
## The dynamite is consumed via ToolWear.decrement_on_use() (max_durability=1).
func _try_place() -> void:
	# ── Plan 02-11: dynamite tool dispatch ──────────────────────────────────
	if _active_tool_is_dynamite:
		_try_place_dynamite()
		return

	if _stud_grid == null:
		Toasts.show("ui.builder.no_tool", "info")
		return

	var prediction: Dictionary = predict_placement_target()
	if not prediction["valid"]:
		Toasts.show("ui.builder.cant_place_there", "info")
		return

	var anchor: Vector3i = prediction["target_cell"]
	var footprint: Array = prediction["footprint"]
	var rotation: int = prediction["rotation"]
	# Place whatever brick is equipped in the active hotbar slot (e.g. wood_plank),
	# falling back to BRICK_1X1 when nothing is equipped.
	var active: Dictionary = _active_brick()
	var def: BrickDefinition = active["def"] as BrickDefinition
	var colour_index: int = int(active["colour_index"])

	_stud_grid.place_multi(anchor, footprint, def, colour_index, rotation)
	# Visible confirmation that a brick was placed (and which one) — also a quick way to
	# tell, in QA, whether the place input is reaching here at all.
	Toasts.show("ui.builder.placed", "info")


## Try to place dynamite at the terrain/stud-grid face under the crosshair.
##
## Instantiates DynamiteHandler at the hit position in the scene tree, calls
## light_fuse(world_pos, radius) to start the 3 s countdown, and consumes the
## dynamite from the hotbar slot via ToolWear.decrement_on_use().
##
## If no valid placement target is found (e.g. no terrain in range), shows the
## "Can't place there." toast and does nothing.
##
## Called by _try_place() when _active_tool_is_dynamite is true.
func _try_place_dynamite() -> void:
	# We need a hit position; use VoxelTerrain raycast.
	var hit_pos: Vector3 = Vector3.ZERO
	var found_target := false

	if _terrain != null and _terrain.has_method("get_voxel_tool"):
		var voxel_tool = _terrain.get_voxel_tool()
		if voxel_tool != null:
			var hit = voxel_tool.raycast(get_crosshair_position(), get_crosshair_direction(),
				raycast_distance)
			if hit != null:
				hit_pos = Vector3(hit.position.x, hit.position.y, hit.position.z)
				found_target = true

	if not found_target:
		Toasts.show("ui.builder.cant_place_there", "info")
		return

	# Consume the dynamite via ToolWear (dynamite max_durability=1 → one use).
	# Slot-based instance_id so ToolWear tracks it per hotbar slot.
	var instance_id: String = "slot_%d" % max(_active_hotbar_slot, 0)
	var dynamite_tool_res := load("res://src/tools/dynamite.tres") as Resource
	if dynamite_tool_res != null:
		ToolWear.decrement_on_use(dynamite_tool_res, instance_id)

	# Instantiate DynamiteHandler and parent it to the main scene root.
	var handler: DynamiteHandler = _DYNAMITE_HANDLER_SCENE.instantiate() as DynamiteHandler
	var parent_node: Node = get_parent()
	if parent_node == null:
		parent_node = get_tree().get_root()
	parent_node.add_child(handler)

	# Light the fuse at the hit position with the default 5 m radius.
	handler.light_fuse(hit_pos, 5.0)


## Try to break the brick or terrain voxel under the crosshair.
## Phase 2: checks stud-grid first (brick-on-brick), then terrain.
## Water voxel id (not minable) and voxel-id → dropped material item mapping.
## Only def_ids registered in BrickRegistry are awarded; others just clear the voxel.
const _WATER_VOXEL_ID: int = 7
const _VOXEL_DROP: Dictionary = {
	1: "dirt", 8: "dirt", 9: "dirt",       # grass variants → dirt
	2: "sand", 3: "snow", 4: "cobblestone", 5: "sandstone", 6: "ice",
	10: "wood_log", 11: "dirt",            # tree trunk → wood_log (mined stone → cobblestone)
}

## Depth-gated bonus ore drops when mining stone/sandstone: deeper = rarer + better. Listed
## rarest-first so the roll awards at most one ore per block (the best the depth allows). This
## is the world source for minerals — coal/copper/iron shallow, gold/diamond/obsidian deep.
const _ORE_TIERS: Array = [
	{"max_y": -8, "chance": 0.030, "def_id": "obsidian"},
	{"max_y": -3, "chance": 0.040, "def_id": "diamond_ore"},
	{"max_y":  2, "chance": 0.060, "def_id": "gold_ingot"},
	{"max_y":  6, "chance": 0.090, "def_id": "iron_ore"},
	{"max_y":  9, "chance": 0.110, "def_id": "copper_ore"},
	{"max_y": 13, "chance": 0.160, "def_id": "coal"},
]

## Voxel IDs that yield bonus ore when mined (STONE_ID 4, SANDSTONE_ID 5).
const _ORE_BEARING_VOXELS: Array = [4, 5]

## Water-entry detection state for the splash fx (throttled voxel sample at the feet).
var _was_in_water: bool = false
var _water_check_accum: float = 0.0
const _WATER_CHECK_INTERVAL_S: float = 0.15

## Active torch campfire flames, keyed by anchor cell (Vector3i) → fire_flame fx node, so a
## removed torch clears its flame.
var _torch_flames: Dictionary = {}


func _try_break() -> void:
	if _stud_grid == null or _terrain == null:
		return

	var origin: Vector3 = get_crosshair_position()
	var direction: Vector3 = get_crosshair_direction()

	# ── Try stud-grid hit first ──────────────────────────────────────────────
	var brick_hit: Variant = _raycast_stud_grid(origin, direction, raycast_distance)
	if brick_hit != null and brick_hit is Dictionary:
		var hit_cell: Vector3i = brick_hit["cell"]
		_stud_grid.remove(hit_cell)
		_spawn_break_dust(Vector3(hit_cell.x + 0.5, hit_cell.y + 0.5, hit_cell.z + 0.5))
		return

	# ── Fall back to VoxelTerrain hit ────────────────────────────────────────
	if not _terrain.has_method("get_voxel_tool"):
		return
	var voxel_tool = _terrain.get_voxel_tool()
	if voxel_tool == null:
		return
	var hit = voxel_tool.raycast(origin, direction, raycast_distance)
	if hit == null:
		return
	# Real terrain mining: read the voxel type, remove it (set to AIR), and award the
	# matching material item so mining feeds the inventory + survival loop — and the
	# FTUE "mine a tree" step (which advances on item_added 'wood_log').
	var vpos := Vector3i(hit.position.x, hit.position.y, hit.position.z)
	voxel_tool.channel = VoxelBuffer.CHANNEL_TYPE
	var vid: int = voxel_tool.get_voxel(vpos)
	if vid == 0 or vid == _WATER_VOXEL_ID:
		return  # air or water — nothing to mine
	voxel_tool.set_voxel(vpos, 0)  # remove the voxel
	# ─── WATER overhaul: let water flow into the mined (damming) block ─────────
	# If this block bordered water, notify the FluidSim so the water floods the
	# newly-opened space over the next ticks (volume-conserving, animated). The
	# sim lives as a sibling "FluidSim" node under main_scene; resolved lazily.
	_notify_fluid_block_mined(vpos)
	var block_centre := Vector3(vpos.x + 0.5, vpos.y + 0.5, vpos.z + 0.5)
	_spawn_break_dust(block_centre)
	# Mined items don't pop straight into the bag — a shrinking icon floats up for ~2 s first
	# (gives the mine a tactile "collect" beat), then the item is added.
	_spawn_mined_pickup(_VOXEL_DROP.get(vid, ""), block_centre)
	# Mining stone/sandstone has a depth-gated chance of yielding an ore on top of the block.
	if vid in _ORE_BEARING_VOXELS:
		_spawn_mined_pickup(_roll_ore_bonus(vpos.y), block_centre)


## Cached FluidSim sibling (resolved lazily from main_scene). May stay null in
## test/headless contexts where no FluidSim exists; the notify call no-ops then.
var _fluid_sim: Node = null

## Notify the FluidSim that the terrain voxel at `vpos` was mined so any bordering
## water flows into the opened space (WATER overhaul behaviour 2). Resolves the sim
## lazily (sibling "FluidSim" under main_scene); silently no-ops when absent.
func _notify_fluid_block_mined(vpos: Vector3i) -> void:
	if _fluid_sim == null or not is_instance_valid(_fluid_sim):
		_fluid_sim = get_node_or_null("../FluidSim")
	if _fluid_sim != null and _fluid_sim.has_method("notify_block_mined"):
		_fluid_sim.notify_block_mined(vpos)


## Award one of a mined item to the local builder's inventory (no-op for "" / unknown defs).
func _award_mined_item(def_id: String) -> void:
	if def_id != "" and BrickRegistry.get_definition(def_id) != null:
		Inventory.apply_event({
			"kind": "ADD",
			"builder_id": get_stable_builder_id(),
			"def_id": def_id,
			"count": 1,
		})


## Spawn a small icon of the mined item that floats up + shrinks + fades over ~2 s, THEN adds
## the item to the inventory. Fire-and-forget coroutine. Falls back to an instant award if the
## item has no icon (so nothing is ever lost). Parented to the world so it outlives this frame.
func _spawn_mined_pickup(def_id: String, world_pos: Vector3) -> void:
	if def_id == "" or BrickRegistry.get_definition(def_id) == null:
		return
	var def: Resource = BrickRegistry.get_definition(def_id)
	var ip_v: Variant = def.get("icon_path")
	var ip: String = str(ip_v) if ip_v != null else ""
	var tex: Texture2D = load(ip) as Texture2D if (not ip.is_empty() and ResourceLoader.exists(ip, "Texture2D")) else null
	var world: Node = get_tree().current_scene
	if tex == null or world == null:
		_award_mined_item(def_id)  # no visual possible — award immediately
		return
	var spr := Sprite3D.new()
	spr.texture = tex
	spr.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	spr.pixel_size = 0.004  # ~0.4 m for a 100px icon
	spr.no_depth_test = false
	world.add_child(spr)
	spr.global_position = world_pos
	var tw := spr.create_tween()
	tw.set_parallel(true)
	tw.tween_property(spr, "global_position:y", world_pos.y + 1.2, 2.0)
	tw.tween_property(spr, "scale", Vector3(0.15, 0.15, 0.15), 2.0)
	tw.tween_property(spr, "modulate:a", 0.0, 2.0).set_ease(Tween.EASE_IN)
	await tw.finished
	_award_mined_item(def_id)
	if is_instance_valid(spr):
		spr.queue_free()


## Roll a depth-gated bonus ore for a mined stone block at world-Y `y`. Returns an ore def_id
## or "" (most blocks). Rarest-first so a deep block can yield obsidian/diamond, not just coal.
func _roll_ore_bonus(y: int) -> String:
	for tier: Dictionary in _ORE_TIERS:
		if y <= int(tier["max_y"]) and randf() < float(tier["chance"]):
			return str(tier["def_id"])
	return ""


## Spawn a brief dust poof (art-movements fx) at a mined brick/voxel centre. Parented to the
## world so it outlives this frame; small + short-lived so rapid mining doesn't clutter.
func _spawn_break_dust(world_pos: Vector3) -> void:
	var world: Node = get_tree().current_scene
	if world != null:
		EffectsLibrary.spawn(world, "dust_poof", world_pos,
			{"size": 0.8, "lifetime": 0.6, "float_up": 0.3})


## Sample the voxel at the builder's feet; on the rising edge of entering water, spawn a
## one-shot splash at the surface. Throttled from _physics_process (not every frame).
func _check_water_entry() -> void:
	if _terrain == null or not _terrain.has_method("get_voxel_tool"):
		return
	var voxel_tool = _terrain.get_voxel_tool()
	if voxel_tool == null:
		return
	var feet: Vector3 = global_position + Vector3(0.0, 0.1, 0.0)
	voxel_tool.channel = VoxelBuffer.CHANNEL_TYPE
	var vid: int = voxel_tool.get_voxel(Vector3i(floori(feet.x), floori(feet.y), floori(feet.z)))
	var in_water: bool = (vid == _WATER_VOXEL_ID)
	if in_water and not _was_in_water:
		var world: Node = get_tree().current_scene
		if world != null:
			# Splash at the builder's XZ, on the water surface (cell top).
			var surf_y: float = float(floori(feet.y)) + 1.0
			EffectsLibrary.spawn(world, "water_splash",
				Vector3(global_position.x, surf_y, global_position.z),
				{"size": 1.2, "lifetime": 0.9, "ground": true})
	_was_in_water = in_water


# ─── Plan 03-09: Item definition cache + fire-breath VFX dispatch ────────────

## Lazy-loaded ItemDefinition cache. Keyed by def_id → ItemDefinition Resource or null.
## Populated on first eat_food call for each def_id; avoids repeated ResourceLoader.load.
var _loaded_item_defs: Dictionary = {}

# ─── Plan 02-11: Dynamite tool dispatch ─────────────────────────────────────

## Preloaded DynamiteHandler scene for dynamite-tool dispatch.
## Instantiated when the player places a dynamite item (Plan 02-11).
const _DYNAMITE_HANDLER_SCENE := preload("res://src/tools/dynamite_handler.tscn")

## Tool ID string for the dynamite tool.
const _DYNAMITE_TOOL_ID: String = "dynamite"

## Track whether the active hotbar slot holds the dynamite tool.
## Set by hotbar.gd when the slot changes (Plan 02-12 wires this).
## Phase 2 provides a setter so DynamiteHandler tests can verify dispatch.
var _active_tool_is_dynamite: bool = false

## Active hotbar slot index (0-based). Used to decrement dynamite count after use.
## Plan 02-12 wires this from the hotbar selection signal.
var _active_hotbar_slot: int = -1

# ─── Plan 02-14: Stable builder UUID (Pitfall 8 mitigation) ──────────────────

## Stable per-device UUID (RFC 4122 v4). Generated once on first _ready if absent
## from user://settings.cfg [builder] id. Persisted to that config file.
## Rain dance quota and Phase 4 multiplayer peer identification use this value.
var _stable_builder_id: String = ""

# ─── Plan 03-04: HP + death + sleep state ─────────────────────────────────────

## Current HP (0..MAX_HP). Public read; mutations via take_damage / eat_food / respawn_at.
var hp: int = MAX_HP

## True while the death sequence is in progress (prevents double-death events T-03-04-DEATH-01).
var _is_dead: bool = false

## True while a sleep lapse is active.
var _is_sleeping: bool = false

## True while the sleep cutscene holds the builder still (lying on the bed). Separate
## from _is_sleeping, which the wake signal clears at the black moment — the freeze must
## persist until the fade-in finishes and end_sleep_pose() runs.
var _sleep_frozen: bool = false

## True while the floating sleep "Zzz" emit-loop should keep spawning glyphs (cleared by
## end_sleep_pose so the coroutine terminates).
var _sleep_zzz_active: bool = false

## World position of the bed the builder is currently sleeping at.
var _current_bed_pos: Vector3 = Vector3.ZERO

## World position of the last bed the builder slept in (persisted to WorldSave).
var _last_slept_bed_pos: Vector3 = Vector3.ZERO

## True if the builder has ever slept in a bed. Governs respawn destination.
var _has_slept_in_bed: bool = false

## Downward velocity (absolute) at the moment of lethal impact. Used for pile positioning.
var _fall_velocity_at_death: float = 0.0

## Tracks absolute downward speed every physics frame for lethal-fall detection.
var _last_fall_velocity: float = 0.0


## Notify the builder that the active hotbar slot contains the dynamite tool.
## Called by hotbar.gd when the active slot changes.
##
## @param is_dynamite  true if the active slot is a dynamite tool.
## @param slot_index   The slot index (0-7) of the active hotbar selection.
func set_active_tool_dynamite(is_dynamite: bool, slot_index: int) -> void:
	_active_tool_is_dynamite = is_dynamite
	_active_hotbar_slot = slot_index


# ─── Plan 02-10: Handheld lantern OmniLight3D ────────────────────────────────

## Toggle the handheld lantern OmniLight3D visibility.
##
## Called by hotbar.gd when the player selects/deselects a slot containing
## the "lantern_handheld" tool (Plan 02-10 / 02-12).
##
## Pitfall 9 mitigation: the OmniLight3D uses light_cull_mask = 2
## (CHANNEL_BUILDER_ONLY from Plan 06), so it illuminates only the builder's
## visual layer and does NOT suppress hostile mob spawning in dungeons/deep dark.
##
## @param lit  true = lantern on; false = lantern off.
func set_handheld_lantern(lit: bool) -> void:
	if not is_node_ready():
		return
	var light: Node = get_node_or_null("Hand/HandheldLanternLight")
	if light == null:
		push_warning("Builder.set_handheld_lantern: HandheldLanternLight node not found.")
		return
	light.visible = lit


# ─── Plan 02-14: Rain dance + stable builder UUID ────────────────────────────

## Return the stable per-device builder UUID (Pitfall 8 mitigation).
## Guaranteed non-empty after _ready() has run (generated on first launch).
## @return  RFC 4122 v4 UUID string, e.g. "550e8400-e29b-41d4-a716-446655440000".
func get_stable_builder_id() -> String:
	return _stable_builder_id


## Invoke the rain dance: calls Weather.trigger_rain_dance(get_stable_builder_id())
## and shows the returned message_key as a Toasts.show() info notification.
##
## Per DOCS.md §2.4: at most once per Cubicraftia day per builder.
##   Accepted: "ui.weather.rain_dance_summoned" toast (sky listens, rain begins).
##   Rejected: "ui.weather.sky_wont_listen_again_today" toast (quota exhausted).
func rain_dance() -> void:
	var builder_id: String = get_stable_builder_id()
	if builder_id == "":
		push_warning("Builder.rain_dance: stable builder ID is empty — rain dance skipped.")
		return
	var result: Dictionary = Weather.trigger_rain_dance(builder_id)
	var message_key: String = result.get("message_key", "ui.weather.sky_wont_listen_again_today")
	Toasts.show(message_key, "info")


## Generate a RFC 4122 version-4 UUID string using Crypto.generate_random_bytes(16).
##
## Bit layout per RFC 4122 §4.4:
##   - Version (4 bits) = 0100 at bits [12..15] of octet 6
##   - Variant (2 bits) = 10   at bits [6..7]   of octet 8
##
## Falls back to randi()-based generation if Crypto is unavailable (e.g. headless test builds).
##
## @return  String in "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx" format (lower-case hex).
func _generate_uuid_v4() -> String:
	var bytes: PackedByteArray
	# Primary path: use Crypto for cryptographic randomness (T-14-01: standard UUIDv4).
	var crypto := Crypto.new()
	bytes = crypto.generate_random_bytes(16)

	# Apply version 4 bits: octet 6 = (octet & 0x0F) | 0x40
	bytes[6] = (bytes[6] & 0x0F) | 0x40
	# Apply variant bits: octet 8 = (octet & 0x3F) | 0x80
	bytes[8] = (bytes[8] & 0x3F) | 0x80

	# Format as "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
	var hex: String = bytes.hex_encode()
	return "%s-%s-%s-%s-%s" % [
		hex.substr(0, 8),
		hex.substr(8, 4),
		hex.substr(12, 4),
		hex.substr(16, 4),
		hex.substr(20, 12),
	]


# ─── Plan 03-04: Survival HP / death / respawn / sleep / eat ─────────────────

## Apply damage to the builder (survival mode only; no-op in sandbox or while dead).
## T-03-04-HP-01 mitigation: clamps amount to ≥ 0 so negative amounts don't heal.
## @param amount   HP points to subtract (clamped to [0, MAX_HP]).
## @param from_pos World position of the damage source (for knockback direction).
func take_damage(amount: int, from_pos: Vector3) -> void:
	if not Features.is_survival_mode() or _is_dead:
		return
	# T-03-04-HP-01: guard against negative amounts (would increase HP via subtraction).
	amount = max(0, amount)
	hp = max(0, hp - amount)
	hp_changed.emit(hp)

	# ── Damage VFX ──────────────────────────────────────────────────────────
	# Red vignette flash on a DamageVignette ColorRect in the UI CanvasLayer.
	var vignette: Node = get_tree().get_first_node_in_group("damage_vignette")
	if vignette != null and vignette is CanvasItem:
		var vi := vignette as CanvasItem
		if vi.has_method("create_tween"):
			var vt: Tween = vi.create_tween()
			vt.tween_property(vi, "modulate:a", DAMAGE_VIGNETTE_ALPHA,
				DAMAGE_VIGNETTE_DURATION_S).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
			vt.tween_property(vi, "modulate:a", 0.0,
				DAMAGE_VIGNETTE_DURATION_S).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)

	# Screen-shake: tween active camera h_offset ± 0.05 then back to 0.
	var cam: Camera3D = get_active_camera()
	if cam != null:
		var st: Tween = create_tween()
		st.tween_property(cam, "h_offset",
			randf_range(-0.05, 0.05), 0.05)
		st.tween_property(cam, "h_offset", 0.0, 0.15)

	# Mobile haptic (no-op on desktop per Godot 4.x docs).
	Input.vibrate_handheld(HAPTIC_MS)

	# Knockback: push builder away from the damage source (horizontal only, D-08).
	var dir: Vector3 = (global_position - from_pos).normalized()
	dir.y = 0.0
	velocity += dir * KNOCKBACK_DISTANCE_M * 5.0

	if hp == 0:
		_on_death()


## Consume food and heal the builder. Called by Plan 03-09 cooked food / strawberry.
## In sandbox: returns true (item is consumed for flavour, no HP change per UI-SPEC L245).
## In survival: adds heal_amount to HP (clamped to MAX_HP) and shows toast.
## @return true always (caller removes 1 food item from inventory).
func eat_food(food_def_id: String, heal_amount: int) -> bool:
	if Features.is_survival_mode():
		var old_hp := hp
		hp = min(MAX_HP, hp + heal_amount)
		var gained := hp - old_hp
		if gained > 0:
			hp_changed.emit(hp)
			Toasts.show("ui.hp.gained_tick", "info")
	# Sandbox: no HP change, but item is still consumed (return true to caller).

	# ─── Plan 03-09: VFX dispatch per ItemDefinition.vfx_on_use (D-13 Tom Yum) ─
	# Load the ItemDefinition from the .tres cache and dispatch the named VFX.
	# T-03-09-DR-05 mitigation: dispatch is a hard-coded switch — only "fire_breath"
	# maps to a real scene; unknown strings are a safe no-op (no dynamic path loading).
	var item_def: Resource = _load_item_definition(food_def_id)
	if item_def != null and item_def.get("vfx_on_use") == "fire_breath":
		_spawn_fire_breath_vfx()

	return true


## Called by Plan 03-11 BedEntity when the builder sleeps in a bed.
## Records the bed position and persists to WorldSave.
func mark_slept(bed_pos: Vector3) -> void:
	_last_slept_bed_pos = bed_pos
	_has_slept_in_bed = true
	# Persist to WorldSave so the spawn point survives game close/reopen.
	if WorldSave.is_open():
		WorldSave.set_world_meta(
			"builder:" + _stable_builder_id + ":last_bed",
			var_to_bytes(bed_pos))


## Return the position the builder would respawn at right now.
## Used by test_death_respawn.gd and _on_respawn_dispatch.
func get_respawn_position() -> Vector3:
	if _has_slept_in_bed:
		return _last_slept_bed_pos
	return _read_world_spawn()


## Teleport the builder to target_pos and restore full HP. Clears the dead flag.
func respawn_at(target_pos: Vector3) -> void:
	global_position = target_pos + Vector3(0.0, 0.5, 0.0)
	hp = MAX_HP
	hp_changed.emit(MAX_HP)
	velocity = Vector3.ZERO
	_is_dead = false
	_fall_velocity_at_death = 0.0
	_last_fall_velocity = 0.0
	# Re-engage the spawn-grace gate so a respawn over un-baked collision can't
	# drop the builder into the void or trigger lethal-fall on landing.
	_spawn_grace_done = false
	_spawn_grace_started_msec = Time.get_ticks_msec()
	respawned.emit(target_pos)


# ─── Plan 03-04: Private death / sleep helpers ────────────────────────────────

## Fire the full death sequence: DEATH_DROP event → DeathScreen fade → respawn.
func _on_death() -> void:
	_is_dead = true
	var pile_pos: Vector3 = _compute_death_pile_position(global_position)
	Inventory.apply_event({
		"kind": "DEATH_DROP",
		"builder_id": _stable_builder_id,
		"position": pile_pos,
	})
	# Show the DeathScreen overlay (Task 2 ships this scene).
	var death_screen: Node = get_tree().get_first_node_in_group("death_screen")
	if death_screen != null and death_screen.has_method("start_fade"):
		death_screen.start_fade(_has_slept_in_bed, _on_respawn_dispatch)
	else:
		# Fallback if DeathScreen not in scene yet (e.g. early tests):
		# respawn after a short simulated delay via a one-shot timer.
		var fallback_timer := get_tree().create_timer(3.0)
		fallback_timer.timeout.connect(_on_respawn_dispatch)
	died.emit(_stable_builder_id, pile_pos)


## Determine where the death pile should spawn.
## For void/lethal-fall deaths: cast downward from above to find terrain surface.
## Otherwise: spawn at the death position.
func _compute_death_pile_position(death_pos: Vector3) -> Vector3:
	var is_lethal: bool = (
		death_pos.y < VOID_THRESHOLD_Y or
		_fall_velocity_at_death > LETHAL_FALL_VELOCITY
	)
	if not is_lethal:
		return death_pos

	# Downward raycast from Y=256 to find terrain surface (T-03-04-DEATH-03:
	# use mask=1 so player-built bricks on layer 2 are ignored).
	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		Vector3(death_pos.x, 256.0, death_pos.z),
		Vector3(death_pos.x, -256.0, death_pos.z)
	)
	query.collision_mask = 1  # Terrain layer only (T-03-04-DEATH-03 mitigation).
	var result: Dictionary = space_state.intersect_ray(query)
	if not result.is_empty():
		return (result["position"] as Vector3) + Vector3(0.0, 0.5, 0.0)
	# Fallback: no terrain found — place pile at (x, 0, z).
	return Vector3(death_pos.x, 0.0, death_pos.z)


## Called by DeathScreen at the end of the 3-second fade (or by the fallback timer).
func _on_respawn_dispatch() -> void:
	respawn_at(get_respawn_position())


## Read world_spawn from WorldSave. Fallback = Vector3(0, 64, 0) (D-CONTEXT).
func _read_world_spawn() -> Vector3:
	if not WorldSave.is_open():
		return Vector3(0.0, 64.0, 0.0)
	var raw: Variant = WorldSave.get_world_meta("world_spawn")
	if raw is PackedByteArray:
		var decoded: Variant = bytes_to_var(raw as PackedByteArray)
		if decoded is Vector3:
			return decoded as Vector3
	elif raw is Vector3:
		return raw as Vector3
	return Vector3(0.0, 64.0, 0.0)


## Handle the end of a sleep lapse (Plan 03-03 WorldClock.sleep_lapse_ended signal).
## "woke_at_dawn" → restore HP to MAX; "cancelled_unsafe" → no HP restore.
func _on_sleep_lapse_ended(reason: String) -> void:
	_is_sleeping = false
	if reason == "woke_at_dawn":
		hp = MAX_HP
		hp_changed.emit(MAX_HP)
	# No toast on success — sky transition IS the feedback (D-12).
	# Unsafe-cancellation toast is emitted by the poll in _physics_process.


## Sleep cutscene — lie the builder flat on the bed and freeze it. Called by
## main_scene.sleep_in_bed() before the fade-to-black.
func start_sleep_pose(bed_pos: Vector3) -> void:
	_sleep_frozen = true
	velocity = Vector3.ZERO
	# Rest on top of the bed surface.
	global_position = Vector3(bed_pos.x, bed_pos.y + 0.35, bed_pos.z)
	# Tip the avatar flat onto its back (visual only — the body stays put).
	if _avatar_mesh_root != null:
		var tw: Tween = create_tween()
		tw.tween_property(_avatar_mesh_root, "rotation:x", deg_to_rad(-90.0), 0.5)
	# Drift "Zzz" up from the sleeper's head (art-movements fx) until they wake.
	_sleep_zzz_active = true
	_emit_sleep_zzz()


## Sleep cutscene — stand the builder back up. Called by main_scene.sleep_in_bed()
## after the fade-back-in.
func end_sleep_pose() -> void:
	if _avatar_mesh_root != null:
		var tw: Tween = create_tween()
		tw.tween_property(_avatar_mesh_root, "rotation:x", 0.0, 0.4)
	_sleep_frozen = false
	_sleep_zzz_active = false


## Spawn a floating "Zzz" above the sleeper roughly once a second while asleep. Parented to
## the world (not the avatar) so the lie-down tilt doesn't rotate the glyphs. Self-terminates
## when end_sleep_pose() clears _sleep_zzz_active.
func _emit_sleep_zzz() -> void:
	while _sleep_zzz_active and is_inside_tree():
		var world: Node = get_tree().current_scene
		if world != null:
			EffectsLibrary.spawn(world, "sleep_zzz",
				global_position + Vector3(0.0, 1.0, 0.0),
				{"size": 0.6, "lifetime": 2.0, "float_up": 0.5, "ground": false})
		await get_tree().create_timer(1.1).timeout


## Attempt to interact with a nearby bed to start sleeping (D-12 + Pitfall 9).
func _try_sleep_interact() -> void:
	# Find all BedEntity nodes within INTERACT_RANGE_M.
	var beds: Array = get_tree().get_nodes_in_group("bed_entity")
	for bed: Variant in beds:
		var bed_node: Node3D = bed as Node3D
		if bed_node == null:
			continue
		if bed_node.global_position.distance_to(global_position) > INTERACT_RANGE_M:
			continue
		# Bed in range: only night-gated. Sleeping is the player's escape from the night,
		# so reaching the bed always works — we CLEAR nearby hostiles rather than refuse
		# (the old "cancelled_unsafe" block created a death loop: night spawns hostiles,
		# hostiles block sleep, player dies before morning).
		if not WorldClock.is_night():
			Toasts.show("ui.bed.too_early_prompt", "info")
			get_viewport().set_input_as_handled()
			return
		# Clear hostiles around the bed so the lapse can't be cancelled mid-sleep.
		if Spawning.has_method("clear_hostiles_in_chunk_range"):
			var builder_chunk := Vector3i(
				floori(global_position.x / 16.0),
				floori(global_position.y / 16.0),
				floori(global_position.z / 16.0)
			)
			Spawning.clear_hostiles_in_chunk_range(builder_chunk, 1)
		# Play the sleep cutscene (lie down → fade to black → skip to morning + despawn
		# night creatures → fade back into day → stand up). Orchestrated by main_scene.
		_current_bed_pos = bed_node.global_position
		_is_sleeping = true
		mark_slept(_current_bed_pos)
		var ms: Node = get_tree().current_scene
		if ms != null and ms.has_method("sleep_in_bed"):
			ms.call("sleep_in_bed", self, bed_node.global_position)
		else:
			# No cutscene host (e.g. tests): fall back to an instant morning skip.
			WorldClock.skip_to_morning()
		get_viewport().set_input_as_handled()
		return
	# No bed in range: no-op (do NOT consume the event so inventory-toggle fires).


## Stub for Plan 03-10 melee attack dispatch. Emits attack_swing for mob systems.
func _try_attack() -> void:
	attack_swing.emit(get_crosshair_direction(), 1)


# ─── Plan 03-09: Item definition loading + fire-breath VFX ──────────────────

## Load (or retrieve from cache) the ItemDefinition Resource for the given def_id.
## Returns null if the .tres file does not exist.
## Cache key: def_id → ItemDefinition Resource | null.
func _load_item_definition(def_id: String) -> Resource:
	if _loaded_item_defs.has(def_id):
		return _loaded_item_defs[def_id]
	var path: String = "res://src/bricks/" + def_id + ".tres"
	var result: Resource = null
	if ResourceLoader.exists(path):
		result = ResourceLoader.load(path)
	_loaded_item_defs[def_id] = result
	return result


## Spawn a FireBreathVfx instance in front of the active camera.
## The VFX is added as a child of this builder node so it moves with the builder
## while alive; FireBreathVfx.gd self-destructs via internal timer after ~0.8 s.
##
## No damage, no Area3D, no hitbox — cosmetic flavour-gag only (T-03-09-DR-04).
func _spawn_fire_breath_vfx() -> void:
	var vfx_scene: PackedScene = load("res://src/world/fire_breath_vfx.tscn")
	if vfx_scene == null:
		push_warning("Builder._spawn_fire_breath_vfx: fire_breath_vfx.tscn not found.")
		return
	var vfx: Node3D = vfx_scene.instantiate() as Node3D
	if vfx == null:
		return
	var camera: Camera3D = get_active_camera()
	add_child(vfx)
	# Position 0.5 m in front of the camera along its forward (-Z) axis.
	var forward: Vector3 = -camera.global_transform.basis.z.normalized()
	vfx.global_position = camera.global_position + forward * 0.5
	# Orient VFX to face in the camera's forward direction.
	var look_target: Vector3 = vfx.global_position + forward
	if look_target.distance_to(vfx.global_position) > 0.001:
		vfx.look_at(look_target, Vector3.UP)


# ─── Plan 06-07: Avatar mesh setup and config application ────────────────────

## Create the programmatic avatar sub-mesh nodes if they do not already exist.
## Called from _ready(). Safe to call multiple times (idempotent).
##
## Fix(07): If res://assets/meshes/builder/builder_default.glb exists it is
## instantiated and added as the visible avatar. The legacy box-mesh nodes
## (_head_mesh, _body_mesh, _legs_mesh) are still created but hidden so that
## apply_avatar_config() (which reads their materials to apply colours) keeps
## working without changes.
##
## Node hierarchy created:
##   AvatarMesh (Node3D, Y=0)
##   ├── BuilderGLB  (Node3D, visible if .glb loaded — the real model)
##   ├── Head (MeshInstance3D, BoxMesh 0.5×0.5×0.5, Y=1.4, hidden when GLB present)
##   ├── Body (MeshInstance3D, BoxMesh 0.4×0.6×0.3, Y=0.9, hidden when GLB present)
##   ├── Legs (MeshInstance3D, BoxMesh 0.4×0.5×0.3, Y=0.35, hidden when GLB present)
##   ├── HandItem (Node3D, Y=0.9, X=0.3, Z=-0.25)
##   │   ├── none    (Node3D — invisible placeholder)
##   │   ├── pickaxe (MeshInstance3D, BoxMesh 0.08×0.3×0.08)
##   │   ├── lantern (MeshInstance3D, BoxMesh 0.12×0.12×0.12)
##   │   ├── flower  (MeshInstance3D, BoxMesh 0.1×0.15×0.1)
##   │   └── blank   (MeshInstance3D, BoxMesh 0.08×0.2×0.08)
##   └── BodyAccessory (Node3D)
##       ├── none    (Node3D — invisible placeholder)
##       ├── backpack (MeshInstance3D, BoxMesh 0.25×0.3×0.1, Y=0.9, Z=0.2)
##       └── cape    (MeshInstance3D, BoxMesh 0.4×0.55×0.04, Y=0.9, Z=0.17)
## Merged AABB (in `root`'s local space) of every MeshInstance3D under it — used to
## scale/ground the imported avatar regardless of its native export size/origin.
func _avatar_subtree_aabb(root: Node3D) -> AABB:
	var out := AABB()
	var first := true
	var inv: Transform3D = root.global_transform.affine_inverse()
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			var mi := n as MeshInstance3D
			var a: AABB = (inv * mi.global_transform) * mi.mesh.get_aabb()
			if first:
				out = a
				first = false
			else:
				out = out.merge(a)
		for c: Node in n.get_children():
			stack.push_back(c)
	return out


## True rendered extent of a skinned avatar, in `root`-local units. Uses the Skeleton3D
## bone world poses (which reflect the skin's real size) rather than mesh.get_aabb()
## (the rest box, which ignores the import's bone scale). Falls back to the mesh-AABB
## walk if no skeleton is present.
func _avatar_skinned_aabb(root: Node3D) -> AABB:
	var sk := root.find_child("Skeleton3D", true, false) as Skeleton3D
	if sk == null or sk.get_bone_count() == 0:
		return _avatar_subtree_aabb(root)
	var inv: Transform3D = root.global_transform.affine_inverse()
	var lo := Vector3(1e9, 1e9, 1e9)
	var hi := -lo
	for i: int in range(sk.get_bone_count()):
		var p: Vector3 = inv * ((sk.global_transform * sk.get_bone_global_pose(i)).origin)
		lo = lo.min(p)
		hi = hi.max(p)
	return AABB(lo, hi - lo)


## Scale + ground the textured Meshy avatar and wire its AnimationPlayer, AFTER the
## skeleton has posed. Called fire-and-forget from _setup_avatar_mesh_nodes; the await
## lets the skin settle so _avatar_subtree_aabb returns real bounds (at _ready it
## returns a microscopic rest box, which produced the giant-avatar bug).
func _finalize_avatar(av: Node3D) -> void:
	for _i: int in range(6):
		await get_tree().process_frame
	if not is_instance_valid(av):
		return
	# Size off the SKELETON bone span, not mesh.get_aabb(): this avatar imports with a
	# 0.01 skeleton scale, so mesh.get_aabb() (the rest box) ×skeleton-scale reads ~0.025 m
	# while the skinned bones actually span ~1.9 m. Scaling by 1.8/mesh_aabb blew the
	# character up 72×; the bone span is the true rendered extent.
	var ab: AABB = _avatar_skinned_aabb(av)
	if ab.size.y > 0.0001:
		var sc: float = 1.8 / ab.size.y
		av.scale = Vector3(sc, sc, sc)
		# Avatar facing: all skins are authored +Z, so each needs a 180° flip to face the
		# walk direction (default PI for unlisted skins). See _AVATAR_FACING_OFFSET.
		av.rotation.y = float(_AVATAR_FACING_OFFSET.get(_read_selected_skin(), PI))
		# ab is in av-local units; place feet at y=0 and centre on X/Z, scaled to match.
		av.position = Vector3(-ab.get_center().x * sc, -ab.position.y * sc, -ab.get_center().z * sc)
	_avatar_anim = av.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if _avatar_anim != null:
		var clips: PackedStringArray = _avatar_anim.get_animation_list()
		# Per-skin walk-clip override: skin_fem's "Walking" clip reads as a mining/hammer
		# swing, so use its "Running" clip (a clean stride) for locomotion instead.
		var override: String = str(_AVATAR_WALK_CLIP.get(_read_selected_skin(), ""))
		if override != "" and clips.has(override):
			_avatar_walk_name = override
		else:
			for a: String in clips:
				if a.to_lower().contains("walk"):
					_avatar_walk_name = a
					break
		# Idle = the skeleton's rest pose (a clean stand with the pickaxe held in the
		# right fist). Walking plays only while moving (driven from _physics_process);
		# stop() here cancels any glTF autoplay so the builder spawns in the rest pose.
		_avatar_anim.stop()
		_reset_avatar_rest_pose()
	# The HandItem rides the RightHand BoneAttachment3D, which inherits the skeleton's tiny
	# import scale. Divide that out so the pickaxe renders at its authored ~0.3 m size, then
	# nudge it into the fist (offset/rotation in the hand-bone's local frame).
	if is_instance_valid(_hand_attach) and is_instance_valid(_hand_root):
		var ws: Vector3 = _hand_attach.global_transform.basis.get_scale()
		_hand_root.scale = Vector3(
			1.0 / maxf(ws.x, 1e-6), 1.0 / maxf(ws.y, 1e-6), 1.0 / maxf(ws.z, 1e-6))
		_hand_root.position = _HAND_GRIP_OFFSET
		_hand_root.rotation_degrees = _HAND_GRIP_ROT
		# v1.1 QA #5: on the textured avatars the held tool's RightHand-bone-local grip is not yet
		# tuned, so the default wood pickaxe reads as a stray block behind the builder. Hide the
		# held item until tool-in-hand is implemented + tuned properly (#16), rather than show a
		# mis-placed block on the back.
		_hand_root.visible = false


## Snap the avatar skeleton back to its bind/rest pose (clean standing idle). Called when
## the builder stops moving so it doesn't freeze on the last walk frame.
func _reset_avatar_rest_pose() -> void:
	if _avatar_skeleton == null:
		return
	for i: int in range(_avatar_skeleton.get_bone_count()):
		_avatar_skeleton.reset_bone_pose(i)


## Build (or rebuild) the held-pickaxe visual under the "pickaxe" HandItem node for the
## current tier. Uses the art-tools pickaxe model when imported, else a procedural fallback.
func _apply_pickaxe_model() -> void:
	var node: Variant = _hand_nodes.get("pickaxe")
	if node == null or not is_instance_valid(node):
		return
	var pickaxe_mi := node as MeshInstance3D
	# Clear any previous visual (model child and/or fallback mesh+head).
	pickaxe_mi.mesh = null
	pickaxe_mi.rotation = Vector3.ZERO
	for c: Node in pickaxe_mi.get_children():
		c.queue_free()
	var path: String = _PICKAXE_TIER_MODELS.get(_pickaxe_tier, _PICKAXE_TIER_MODELS["wood"])
	if ResourceLoader.exists(path):
		var pm := (load(path) as PackedScene).instantiate() as Node3D
		pm.name = "model"
		pickaxe_mi.add_child(pm)
		# Static mesh: AABB is valid immediately. Scale longest axis to the held size and
		# centre on the grip, then orient as carried (grip rot tuned in _PICKAXE_GRIP_ROT).
		var ab: AABB = _avatar_subtree_aabb(pm)
		var longest: float = maxf(ab.size.x, maxf(ab.size.y, ab.size.z))
		var sc: float = _PICKAXE_HELD_SIZE_M / maxf(longest, 0.001)
		pm.scale = Vector3(sc, sc, sc)
		pm.position = Vector3(-ab.get_center().x * sc, -ab.get_center().y * sc, -ab.get_center().z * sc)
		pm.rotation_degrees = _PICKAXE_GRIP_ROT
	else:
		_build_procedural_pickaxe(pickaxe_mi)


## Equip a pickaxe tier ("wood" | "stone" | "iron" | "diamond") and rebuild the held model.
func equip_pickaxe_tier(tier: String) -> void:
	if not _PICKAXE_TIER_MODELS.has(tier):
		return
	_pickaxe_tier = tier
	_apply_pickaxe_model()


## Procedural fallback pickaxe (wood handle + steel head crossbar) when no model is imported.
func _build_procedural_pickaxe(pickaxe_mi: MeshInstance3D) -> void:
	if pickaxe_mi == null:
		return
	var handle_box := BoxMesh.new()
	handle_box.size = Vector3(0.045, 0.5, 0.045)
	pickaxe_mi.mesh = handle_box
	pickaxe_mi.rotation_degrees = Vector3(-18.0, 0.0, 14.0)
	var handle_mat := StandardMaterial3D.new()
	handle_mat.albedo_color = Color(0.45, 0.32, 0.2)
	handle_mat.roughness = 1.0
	pickaxe_mi.set_surface_override_material(0, handle_mat)
	var pickaxe_head_box := BoxMesh.new()
	pickaxe_head_box.size = Vector3(0.32, 0.045, 0.045)
	var pickaxe_head := MeshInstance3D.new()
	pickaxe_head.name = "head"
	pickaxe_head.mesh = pickaxe_head_box
	pickaxe_head.position = Vector3(0.0, 0.23, 0.0)
	pickaxe_head.rotation_degrees = Vector3(12.0, 0.0, 0.0)
	var pickaxe_head_mat := StandardMaterial3D.new()
	pickaxe_head_mat.albedo_color = Color(0.6, 0.62, 0.66)
	pickaxe_head_mat.metallic = 0.4
	pickaxe_head_mat.roughness = 0.55
	pickaxe_head.set_surface_override_material(0, pickaxe_head_mat)
	pickaxe_mi.add_child(pickaxe_head)


func _setup_avatar_mesh_nodes() -> void:
	# Idempotent: if already set up, skip.
	if _avatar_mesh_root != null:
		return

	# ── Create root container ───────────────────────────────────────────────
	_avatar_mesh_root = Node3D.new()
	_avatar_mesh_root.name = "AvatarMesh"
	add_child(_avatar_mesh_root)

	# ── Fix(07): Real builder model from .glb ───────────────────────────────
	# Try to load builder_default.glb; if successful, add it as the visible model.
	# The box-mesh nodes below are still created but hidden when the GLB is loaded.
	const _BUILDER_GLB := "res://assets/meshes/builder/builder_default.glb"
	var _glb_loaded: bool = false
	if ResourceLoader.exists(_BUILDER_GLB):
		var packed_builder := load(_BUILDER_GLB)
		if packed_builder is PackedScene:
			var glb_instance: Node3D = (packed_builder as PackedScene).instantiate() as Node3D
			if glb_instance != null:
				glb_instance.name = "BuilderGLB"
				# builder_default.glb is designed at ~1.8 m height in Blender-export scale.
				# Verify it isn't microscopic: typical Blender export is at 1:1 (1 unit = 1 m).
				# No scale adjustment needed if the model was exported correctly; apply a
				# safety scale of 0.01→1.0 normalisation if the model appears < 0.1 m tall.
				# We measure AABB after adding to get world bounds — simpler: trust the artist
				# and leave scale as-is; the builder's capsule is ~1.8 m tall by convention.
				_avatar_mesh_root.add_child(glb_instance)
				_glb_loaded = true

	# ── Phase 8 (ANIM-03/04): animated builder-figure rig ────────────────────────
	# Attach the MinifigureAnimator to _avatar_mesh_root (in-tree, so its _ready()
	# loads the 7 rig pieces). When the rig loads it is the sole visual, so the
	# BuilderGLB static model is hidden. Gait is driven from velocity each physics
	# frame. The box nodes below stay (hidden) for apply_avatar_config back-compat.
	# v1.1 art pass: the textured rigged Meshy avatar (builder_avatar.glb) is the visual
	# when present — scaled to ~1.8 m, feet at the body origin, with its AnimationPlayer
	# driving Walking/idle from velocity. Falls back to the MinifigureAnimator rig (then box
	# meshes) when the avatar asset is absent (headless/CI).
	# Selectable skin (avatar.cfg "skin", default builder1). Falls back to the legacy
	# builder_avatar.glb, then to the rig/box meshes, if the chosen skin is missing.
	var _AVATAR_GLB: String = _AVATAR_SKINS.get(_read_selected_skin(), _AVATAR_SKINS[_DEFAULT_SKIN])
	if not ResourceLoader.exists(_AVATAR_GLB):
		_AVATAR_GLB = "res://assets/meshes/builder/builder_avatar.glb"
	if ResourceLoader.exists(_AVATAR_GLB):
		var av := (load(_AVATAR_GLB) as PackedScene).instantiate() as Node3D
		av.name = "BuilderAvatar"
		_avatar_mesh_root.add_child(av)
		_glb_loaded = true
		_avatar_skeleton = av.find_child("Skeleton3D", true, false) as Skeleton3D
		# The avatar is a skinned mesh: at _ready the skeleton has not posed yet, so
		# its world-space AABB is garbage (a microscopic rest box → a huge 1.8/size
		# scale, which is why the avatar rendered enormous). Defer scaling, grounding
		# and anim wiring to _finalize_avatar, which waits a few frames for the pose
		# to settle before measuring. Fire-and-forget coroutine (await inside) so the
		# rest of _setup keeps building the fallback box nodes.
		_finalize_avatar(av)
		var static_glb0 := _avatar_mesh_root.get_node_or_null("BuilderGLB")
		if static_glb0 is Node3D:
			(static_glb0 as Node3D).visible = false
	elif ResourceLoader.exists("res://assets/meshes/avatars/builder/layout.json"):
		_rig_anim = MinifigureAnimator.new()
		_rig_anim.mesh_set = "builder"
		_rig_anim.gait = "idle"
		_avatar_mesh_root.add_child(_rig_anim)
		# Hide the static GLB now that the animated rig owns the visual.
		var static_glb := _avatar_mesh_root.get_node_or_null("BuilderGLB")
		if static_glb is Node3D:
			(static_glb as Node3D).visible = false

	# Hide the rough-art capsule placeholder (builder.tscn MeshInstance3D). The avatar
	# is now the .glb builder-figure (or the box fallback); the opaque capsule would otherwise
	# enclose and hide the real mesh — which is exactly the "no builder-figure" symptom.
	var _capsule_placeholder := get_node_or_null("MeshInstance3D")
	if _capsule_placeholder is GeometryInstance3D:
		(_capsule_placeholder as GeometryInstance3D).visible = false

	# ── Head — skin colour target (kept for apply_avatar_config compatibility) ─
	var head_box := BoxMesh.new()
	head_box.size = Vector3(0.5, 0.5, 0.5)
	_head_mesh = MeshInstance3D.new()
	_head_mesh.name = "Head"
	_head_mesh.mesh = head_box
	_head_mesh.position = Vector3(0.0, 1.4, 0.0)
	var head_mat := StandardMaterial3D.new()
	head_mat.albedo_color = SKIN_COLOURS[0]
	_head_mesh.set_surface_override_material(0, head_mat)
	_head_mesh.visible = not _glb_loaded   # hide box when real model is present
	_avatar_mesh_root.add_child(_head_mesh)

	# ── Body — body_colour target (kept for apply_avatar_config compatibility) ─
	var body_box := BoxMesh.new()
	body_box.size = Vector3(0.4, 0.6, 0.3)
	_body_mesh = MeshInstance3D.new()
	_body_mesh.name = "Body"
	_body_mesh.mesh = body_box
	_body_mesh.position = Vector3(0.0, 0.9, 0.0)
	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = BODY_COLOURS[6]  # default blue
	_body_mesh.set_surface_override_material(0, body_mat)
	_body_mesh.visible = not _glb_loaded
	_avatar_mesh_root.add_child(_body_mesh)

	# ── Legs — leg_colour target (kept for apply_avatar_config compatibility) ──
	var legs_box := BoxMesh.new()
	legs_box.size = Vector3(0.4, 0.5, 0.3)
	_legs_mesh = MeshInstance3D.new()
	_legs_mesh.name = "Legs"
	_legs_mesh.mesh = legs_box
	_legs_mesh.position = Vector3(0.0, 0.35, 0.0)
	var legs_mat := StandardMaterial3D.new()
	legs_mat.albedo_color = BODY_COLOURS[6]  # default blue
	_legs_mesh.set_surface_override_material(0, legs_mat)
	_legs_mesh.visible = not _glb_loaded
	_avatar_mesh_root.add_child(_legs_mesh)

	# ── HandItem — accessory visibility group ───────────────────────────────
	var hand_root := Node3D.new()
	hand_root.name = "HandItem"
	# Attach the tool to the animated rig's right-arm pivot when the rig is present, so it
	# sits in the fist and swings with the arm during walk/mine (the old fixed offset on
	# _avatar_mesh_root left the pickaxe floating beside the body, untethered to the hand).
	# The arm hangs ~0.24 m down from the shoulder pivot; the fist is at its tip, tipped out
	# in front (-Z is forward) so the tool reads as gripped.
	_hand_root = hand_root
	var _rig_hand: Node3D = null
	if _rig_anim != null:
		_rig_hand = _rig_anim.get_right_hand_pivot()
	if _avatar_skeleton != null and _avatar_skeleton.find_bone("RightHand") != -1:
		# Textured avatar: ride the RightHand bone via a BoneAttachment3D so the pickaxe
		# stays in the fist and swings with the walk animation. The bone inherits the
		# skeleton's tiny import scale, so _finalize_avatar divides that out (sets
		# hand_root world-scale ~1) and applies the grip offset/rotation once settled.
		_hand_attach = BoneAttachment3D.new()
		_hand_attach.name = "HandBone"
		_avatar_skeleton.add_child(_hand_attach)
		_hand_attach.bone_name = "RightHand"
		_hand_attach.add_child(hand_root)
		hand_root.position = Vector3.ZERO
	elif _rig_hand != null:
		_rig_hand.add_child(hand_root)
		hand_root.position = Vector3(0.0, -0.22, -0.05)
	else:
		# Box-mesh fallback (no rig): sit the tool past the right hand, in front of the torso.
		_avatar_mesh_root.add_child(hand_root)
		hand_root.position = Vector3(0.46, 0.72, -0.3)

	# "none" placeholder (invisible empty Node3D)
	var hand_none := Node3D.new()
	hand_none.name = "none"
	hand_none.visible = false
	hand_root.add_child(hand_none)
	_hand_nodes["none"] = hand_none

	# "pickaxe" — the held tool. This MeshInstance3D is the visibility-toggle + bone-attach
	# anchor (registered in _hand_nodes); its actual visual is the art-tools pickaxe model
	# for the current tier (built by _apply_pickaxe_model, with a procedural fallback).
	var pickaxe_mi := MeshInstance3D.new()
	pickaxe_mi.name = "pickaxe"
	pickaxe_mi.visible = false
	hand_root.add_child(pickaxe_mi)
	_hand_nodes["pickaxe"] = pickaxe_mi
	_apply_pickaxe_model()

	# "lantern" — small cube stub
	var lantern_box := BoxMesh.new()
	lantern_box.size = Vector3(0.12, 0.12, 0.12)
	var lantern_mi := MeshInstance3D.new()
	lantern_mi.name = "lantern"
	lantern_mi.mesh = lantern_box
	lantern_mi.visible = false
	var lantern_mat := StandardMaterial3D.new()
	lantern_mat.albedo_color = Color(0.96, 0.77, 0.05)  # warm yellow
	lantern_mi.set_surface_override_material(0, lantern_mat)
	hand_root.add_child(lantern_mi)
	_hand_nodes["lantern"] = lantern_mi

	# "flower" — small flat cube stub
	var flower_box := BoxMesh.new()
	flower_box.size = Vector3(0.1, 0.15, 0.1)
	var flower_mi := MeshInstance3D.new()
	flower_mi.name = "flower"
	flower_mi.mesh = flower_box
	flower_mi.visible = false
	var flower_mat := StandardMaterial3D.new()
	flower_mat.albedo_color = Color(1.0, 0.3, 0.5)  # pink-red
	flower_mi.set_surface_override_material(0, flower_mat)
	hand_root.add_child(flower_mi)
	_hand_nodes["flower"] = flower_mi

	# "blank" — thin stick stub
	var blank_box := BoxMesh.new()
	blank_box.size = Vector3(0.08, 0.2, 0.08)
	var blank_mi := MeshInstance3D.new()
	blank_mi.name = "blank"
	blank_mi.mesh = blank_box
	blank_mi.visible = false
	var blank_mat := StandardMaterial3D.new()
	blank_mat.albedo_color = Color(0.7, 0.7, 0.7)  # grey
	blank_mi.set_surface_override_material(0, blank_mat)
	hand_root.add_child(blank_mi)
	_hand_nodes["blank"] = blank_mi

	# ── BodyAccessory — accessory visibility group ──────────────────────────
	var body_acc_root := Node3D.new()
	body_acc_root.name = "BodyAccessory"
	_avatar_mesh_root.add_child(body_acc_root)

	# "none" placeholder
	var body_none := Node3D.new()
	body_none.name = "none"
	body_none.visible = false
	body_acc_root.add_child(body_none)
	_body_accessory_nodes["none"] = body_none

	# "backpack" — flat box stub behind body
	var backpack_box := BoxMesh.new()
	backpack_box.size = Vector3(0.25, 0.3, 0.1)
	var backpack_mi := MeshInstance3D.new()
	backpack_mi.name = "backpack"
	backpack_mi.mesh = backpack_box
	backpack_mi.position = Vector3(0.0, 0.9, 0.2)
	backpack_mi.visible = false
	var backpack_mat := StandardMaterial3D.new()
	backpack_mat.albedo_color = Color(0.55, 0.35, 0.15)  # brown
	backpack_mi.set_surface_override_material(0, backpack_mat)
	body_acc_root.add_child(backpack_mi)
	_body_accessory_nodes["backpack"] = backpack_mi

	# "cape" — thin flat rectangle stub behind body
	var cape_box := BoxMesh.new()
	cape_box.size = Vector3(0.4, 0.55, 0.04)
	var cape_mi := MeshInstance3D.new()
	cape_mi.name = "cape"
	cape_mi.mesh = cape_box
	cape_mi.position = Vector3(0.0, 0.9, 0.17)
	cape_mi.visible = false
	var cape_mat := StandardMaterial3D.new()
	cape_mat.albedo_color = Color(0.8, 0.1, 0.1)  # red cape stub
	cape_mi.set_surface_override_material(0, cape_mat)
	body_acc_root.add_child(cape_mi)
	_body_accessory_nodes["cape"] = cape_mi


## Apply an avatar configuration dictionary to the builder's mesh sub-nodes.
## Safe to call on the SubViewport preview instance as well as the in-world builder.
##
## Required keys (all 8 must be present or defaults are used via .get()):
##   skin_colour_index : int  0-4
##   head_shape        : String "square" | "round" | "tall"
##   face_expression   : String "neutral" | "happy" | "cool" | "surprised" | "sleepy"
##   body_colour_index : int  0-9
##   body_accessory    : String "none" | "backpack" | "cape"
##   leg_colour_index  : int  0-9
##   leg_shoes         : String "none" | "boots" | "sneakers"
##   hand_accessory    : String "none" | "pickaxe" | "lantern" | "flower" | "blank"
##
## T-06-B1 mitigation: all indices are clamped with clampi() before array access.
func apply_avatar_config(cfg: Dictionary) -> void:
	# Guard: avatar mesh must be set up (is_inside_tree() ensures SubViewport timing).
	if _head_mesh == null or _body_mesh == null or _legs_mesh == null:
		return

	# ── Skin colour → Head ─────────────────────────────────────────────────
	var skin_idx: int = clampi(int(cfg.get("skin_colour_index", 0)), 0, SKIN_COLOURS.size() - 1)
	var head_mat: StandardMaterial3D = _head_mesh.get_active_material(0) as StandardMaterial3D
	if head_mat != null:
		head_mat.albedo_color = SKIN_COLOURS[skin_idx]

	# ── Head shape → Head scale ────────────────────────────────────────────
	var head_shape: String = str(cfg.get("head_shape", "square"))
	match head_shape:
		"round":
			_head_mesh.scale = Vector3(0.9, 1.0, 0.9)
		"tall":
			_head_mesh.scale = Vector3(1.0, 1.2, 1.0)
		_:  # "square" (default)
			_head_mesh.scale = Vector3(1.0, 1.0, 1.0)

	# ── Body colour → Body ──────────────────────────────────────────────────
	var body_idx: int = clampi(int(cfg.get("body_colour_index", 6)), 0, BODY_COLOURS.size() - 1)
	var body_mat: StandardMaterial3D = _body_mesh.get_active_material(0) as StandardMaterial3D
	if body_mat != null:
		body_mat.albedo_color = BODY_COLOURS[body_idx]

	# ── Leg colour → Legs ───────────────────────────────────────────────────
	var leg_idx: int = clampi(int(cfg.get("leg_colour_index", 6)), 0, BODY_COLOURS.size() - 1)
	var legs_mat: StandardMaterial3D = _legs_mesh.get_active_material(0) as StandardMaterial3D
	if legs_mat != null:
		legs_mat.albedo_color = BODY_COLOURS[leg_idx]

	# ── Apply the same palette colours to the real .glb builder-figure surfaces ─────
	# builder_default.glb ships pale placeholder materials; recolour its surfaces
	# from the avatar config so the in-world builder-figure matches the chosen preset.
	# Surface order (verified): 0 = legs, 1 = body, 2 = skin.
	_apply_glb_avatar_colours(SKIN_COLOURS[skin_idx], BODY_COLOURS[body_idx], BODY_COLOURS[leg_idx])

	# ── Phase 8: recolour the animated builder-figure rig (deferred so pivots exist) ─
	_rig_colours = [SKIN_COLOURS[skin_idx], BODY_COLOURS[body_idx], BODY_COLOURS[leg_idx]]
	if _rig_anim != null:
		call_deferred("_apply_rig_colours", _rig_colours[0], _rig_colours[1], _rig_colours[2])

	# ── Hand accessory visibility ────────────────────────────────────────────
	var hand_acc: String = str(cfg.get("hand_accessory", "none"))
	for key: String in _hand_nodes.keys():
		var node: Node = _hand_nodes[key]
		if node != null:
			node.visible = (key == hand_acc)

	# ── Body accessory visibility ────────────────────────────────────────────
	var body_acc: String = str(cfg.get("body_accessory", "none"))
	for key: String in _body_accessory_nodes.keys():
		var node: Node = _body_accessory_nodes[key]
		if node != null:
			node.visible = (key == body_acc)

	# Note: face_expression and leg_shoes are stored for Phase 999.1 mesh work.
	# In Phase 6, head_shape scaling (above) and colour changes are the visual result.


## Recolour the loaded builder_default.glb builder-figure surfaces from the avatar palette.
## Surface order is verified: 0 = legs, 1 = body, 2 = skin. No-op if the glb isn't loaded.
func _apply_glb_avatar_colours(skin: Color, body: Color, legs: Color) -> void:
	if _avatar_mesh_root == null:
		return
	var glb: Node = _avatar_mesh_root.get_node_or_null("BuilderGLB")
	if glb == null:
		return
	var mi: MeshInstance3D = _find_first_mesh_instance(glb)
	if mi == null or mi.mesh == null:
		return
	var surface_colours: Array[Color] = [legs, body, skin]
	for i: int in mini(mi.mesh.get_surface_count(), surface_colours.size()):
		var mat := StandardMaterial3D.new()
		mat.albedo_color = surface_colours[i]
		mi.set_surface_override_material(i, mat)


## Phase 8: recolour the animated builder-figure rig from the avatar palette.
## Walks the MinifigureAnimator's pivot subtree (pivots are named "<piece>_pivot",
## each parenting the piece's instantiated .glb) and applies a StandardMaterial3D
## override to every MeshInstance3D under each pivot:
##   head                       → skin
##   torso, arm_l, arm_r        → body
##   pelvis, legs_l, legs_r     → legs
## No-op if the rig isn't present. Called deferred so the rig's _ready() (which
## builds the pivots) has run.
func _apply_rig_colours(skin: Color, body: Color, legs: Color) -> void:
	if _rig_anim == null or not is_instance_valid(_rig_anim):
		return
	for pivot: Node in _rig_anim.get_children():
		var pname: String = pivot.name
		var col: Color
		if pname.begins_with("builder_head"):
			col = skin
		elif pname.begins_with("builder_torso") or pname.begins_with("builder_arm"):
			col = body
		elif pname.begins_with("builder_pelvis") or pname.begins_with("builder_legs"):
			col = legs
		else:
			continue
		_recolour_subtree(pivot, col)


## Apply a StandardMaterial3D albedo override to every MeshInstance3D surface under `node`.
func _recolour_subtree(node: Node, col: Color) -> void:
	var stack: Array[Node] = [node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		# Skip accent / held-item subtrees ENTIRELY (node + descendants): hair (brown),
		# yellow hands, and the "HandItem" tool group (the wood/steel pickaxe lives here
		# now that it's parented to the rig's arm pivot — without this skip the per-piece
		# body recolour would paint the pickaxe blue). All match on "hair"/"hand".
		var lname: String = n.name.to_lower()
		if n != node and (lname.contains("hair") or lname.contains("hand")):
			continue
		if n is MeshInstance3D:
			var mi := n as MeshInstance3D
			if mi.mesh != null:
				for s: int in mi.mesh.get_surface_count():
					var mat := StandardMaterial3D.new()
					mat.albedo_color = col
					mat.roughness = 1.0
					mi.set_surface_override_material(s, mat)
		for child: Node in n.get_children():
			stack.push_back(child)


## Recursively find the first MeshInstance3D in a subtree (used for the .glb builder-figure).
func _find_first_mesh_instance(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node as MeshInstance3D
	for child in node.get_children():
		var found: MeshInstance3D = _find_first_mesh_instance(child)
		if found != null:
			return found
	return null


## Load avatar config from user://avatar.cfg and apply it to the builder mesh.
## Called at the end of _ready() so the in-world builder reflects the player's avatar.
## Falls back to DEFAULT_AVATAR_CFG if the file is missing or unreadable.
func load_avatar_from_file() -> void:
	var cfg := ConfigFile.new()
	if cfg.load("user://avatar.cfg") == OK:
		var loaded: Dictionary = {
			"skin_colour_index": cfg.get_value("avatar", "skin_colour_index", 0),
			"head_shape":        cfg.get_value("avatar", "head_shape", "square"),
			"face_expression":   cfg.get_value("avatar", "face_expression", "neutral"),
			"body_colour_index": cfg.get_value("avatar", "body_colour_index", 6),
			"body_accessory":    cfg.get_value("avatar", "body_accessory", "none"),
			"leg_colour_index":  cfg.get_value("avatar", "leg_colour_index", 6),
			"leg_shoes":         cfg.get_value("avatar", "leg_shoes", "none"),
			"hand_accessory":    cfg.get_value("avatar", "hand_accessory", "none"),
		}
		apply_avatar_config(loaded)
	else:
		# No avatar.cfg found — apply the default config so the builder always
		# has a valid appearance (new player, offline mode, or first launch).
		apply_avatar_config(DEFAULT_AVATAR_CFG)


# ─── MultiMesh sync signal handlers ──────────────────────────────────────────

## Called when a brick is placed — updates the MultiMeshInstance3D.
## Phase 2: updated signature matches StudGrid.placed (adds colour_index, rotation).
func _on_brick_placed(anchor_cell: Vector3i, _def: BrickDefinition,
		_colour_index: int, _rotation: int) -> void:
	if _brick_renderer == null or _brick_renderer.multimesh == null:
		return
	var new_count := _stud_grid.size()
	_brick_renderer.multimesh.instance_count = new_count
	# Place brick transform: anchor_cell is the voxel above the terrain face.
	# Y-offset of 0.5 centres the brick on its 1-m-tall cell (body height is 1.2 m,
	# so we position it so the bottom face sits on the terrain surface at anchor_cell.y).
	var t := Transform3D(Basis.IDENTITY,
		Vector3(anchor_cell.x, float(anchor_cell.y), anchor_cell.z))
	_brick_renderer.multimesh.set_instance_transform(new_count - 1, t)

	# Apply the per-instance colour. With multimesh.use_colors enabled, a new instance
	# defaults to opaque BLACK — so material/natural-colour bricks (colour_index == -1,
	# e.g. wood_plank) would render as a solid black cube unless we set the colour here.
	_brick_renderer.multimesh.set_instance_color(new_count - 1,
		_resolve_brick_instance_colour(_def, _colour_index))

	# Placeable campfire: a torch brick gets a looping decorative flame (art-movements fx)
	# on top. Cosmetic only — no light, no damage. Tracked by cell so removal clears it.
	if _def != null and _def.brick_id == "torch":
		var world: Node = get_tree().current_scene
		if world != null and not _torch_flames.has(anchor_cell):
			var flame: Node3D = EffectsLibrary.spawn(world, "fire_flame",
				Vector3(anchor_cell.x + 0.5, anchor_cell.y + 0.85, anchor_cell.z + 0.5),
				{"size": 0.5, "lifetime": 0.0, "fade": false})
			if flame != null:
				_torch_flames[anchor_cell] = flame


## Called when a brick is removed — shrinks the MultiMeshInstance3D.
## Phase 1: we simply reduce instance_count (bricks aren't uniquely indexed yet).
## Phase 2 will assign stable multi_mesh_index per BrickInstance.
func _on_brick_removed(_anchor_cell: Vector3i) -> void:
	# Clear a torch's campfire flame when the torch is removed.
	if _torch_flames.has(_anchor_cell):
		var flame: Variant = _torch_flames[_anchor_cell]
		if is_instance_valid(flame):
			flame.queue_free()
		_torch_flames.erase(_anchor_cell)
	if _brick_renderer == null or _brick_renderer.multimesh == null:
		return
	_brick_renderer.multimesh.instance_count = _stud_grid.size()


## Fix(07): Full resync of the BrickRenderer MultiMesh from the current StudGrid state.
## Called once deferred from _ready() to cover any bricks that were placed before the
## placed signal was connected (edge cases, pre-stamp ordering).
## Iterates all anchors and sets instance_count + per-instance transform and colour.
func _sync_multimesh_from_stud_grid() -> void:
	if _stud_grid == null or _brick_renderer == null or _brick_renderer.multimesh == null:
		return
	var anchors: Array = _stud_grid.get_all_anchors()
	var count: int = anchors.size()
	# Avoid resetting a MultiMesh that already matches (e.g. placed-signal already handled it).
	# Only do a full resync if the MultiMesh is out of date or empty.
	if _brick_renderer.multimesh.instance_count == count and count > 0:
		return
	_brick_renderer.multimesh.instance_count = count
	for i: int in range(count):
		var cell: Vector3i = anchors[i] as Vector3i
		var t := Transform3D(Basis.IDENTITY,
			Vector3(float(cell.x), float(cell.y), float(cell.z)))
		_brick_renderer.multimesh.set_instance_transform(i, t)
		# Apply the per-instance colour. Material/natural-colour bricks (colour_index == -1)
		# resolve to their natural_colour_token; palette-coloured bricks use the palette.
		# Always setting a colour avoids the default opaque-black instance (black-cube bug).
		var instance: StudGrid.BrickInstance = _stud_grid.query(cell)
		var def: BrickDefinition = instance.definition if instance != null else null
		var col_idx: int = instance.colour_index if instance != null else -1
		_brick_renderer.multimesh.set_instance_color(i,
			_resolve_brick_instance_colour(def, col_idx))


## Resolve the per-instance tint for a placed brick on the BrickRenderer MultiMesh.
## The shared MultiMesh runs with use_colors enabled, so EVERY instance must be given an
## explicit colour — an unset instance defaults to opaque black (the placed-plank black-cube
## bug). Resolution order:
##   1. colour_index >= 0 → BrickPalette.COLOURS[colour_index] (player/palette colour)
##   2. else def.natural_colour_token in range → that palette colour (material/ore bricks,
##      e.g. wood_plank → token 16 tan #D7B97A)
##   3. else white (the studs atlas is white, so white = the mesh's own look untinted)
func _resolve_brick_instance_colour(def: BrickDefinition, colour_index: int) -> Color:
	var palette: Array[Color] = BrickPalette.COLOURS
	if colour_index >= 0 and colour_index < palette.size():
		return palette[colour_index]
	if def != null:
		var token: int = def.natural_colour_token
		if token >= 0 and token < palette.size():
			return palette[token]
	return Color.WHITE
