# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# wildlife.gd — Passive wildlife entity: harmless roaming animal.
#
# Instantiated by main_scene.spawn_wildlife() when a chunk is loaded.
# Loads the creature .glb by kind, adds it as a child mesh, and runs a
# SIMPLE timer-driven wander behaviour (no nav-mesh, no pathfinding).
#
# Behaviour categories:
#   LAND  — CharacterBody3D, applies gravity, picks random heading, walks
#            slowly a few seconds, idles, repeats. Gentle idle bob on the mesh.
#   WATER — Node3D (no gravity), drifts/bobs within a small radius of its
#            spawn point using a sine-phase wander.
#   AIR   — Node3D (no gravity), hovers/bobs slightly above spawn Y.
#
# Harmless design:
#   - No HP, no damage, never interacts with hostile-mob or Spawning systems.
#   - Collision layer 0 (no layer), mask 1 only (terrain) for land animals so
#     they sit on terrain but do not push the player.
#   - Water/air animals have no CollisionShape at all (pure Node3D).
#
# Scale policy:
#   - All creature .glb assets are approximately 1 unit tall.
#   - SCALE_OVERRIDE map below bumps large mammals to believable sizes.
#
# References:
#   src/world/wildlife_spawner.gd — determines kind + spawn position per chunk
#   src/world/main_scene.gd       — instantiates and positions this node
#   assets/meshes/creatures/*.glb — passive creature mesh assets

class_name Wildlife
extends Node3D

# ─── Behaviour type constants ─────────────────────────────────────────────────

const _TYPE_LAND  := "land"
const _TYPE_WATER := "water"
const _TYPE_AIR   := "air"

# ─── Creature → behaviour type mapping ───────────────────────────────────────

## Maps each passive creature kind to its movement behaviour type.
const _KIND_TYPE: Dictionary = {
	"panda":       _TYPE_LAND,
	"monkey":      _TYPE_LAND,
	"elephant":    _TYPE_LAND,
	"giraffe":     _TYPE_LAND,
	"gnu":         _TYPE_LAND,
	"desert_mouse":_TYPE_LAND,
	"reindeer":    _TYPE_LAND,
	"snowman":     _TYPE_LAND,
	"pig":         _TYPE_LAND,
	"dog":         _TYPE_LAND,
	"sheep":       _TYPE_LAND,
	# Desert-biome wildlife (art-wildlife desert set).
	"camel":        _TYPE_LAND,
	"fennec_fox":   _TYPE_LAND,
	"desert_lizard":_TYPE_LAND,
	"scorpion":     _TYPE_LAND,
	"meerkat":      _TYPE_LAND,
	"rattlesnake":  _TYPE_LAND,
	"vulture":      _TYPE_LAND,
	# Snow-biome wildlife (art-wildlife snow set).
	"polar_bear":  _TYPE_LAND,
	"caribou":     _TYPE_LAND,
	"husky_dog":   _TYPE_LAND,
	"arctic_wolf": _TYPE_LAND,
	"arctic_fox":  _TYPE_LAND,
	"snow_rabbit": _TYPE_LAND,
	"penguin":     _TYPE_LAND,
	"snowy_owl":   _TYPE_AIR,
	"toucan":      _TYPE_AIR,
	"fish_blue":   _TYPE_WATER,
	"fish_orange": _TYPE_WATER,
	"fish_yellow": _TYPE_WATER,
	"orca":        _TYPE_WATER,
	"manta":       _TYPE_WATER,
	"jellyfish":   _TYPE_WATER,
	# Beach/ocean wildlife (art-wildlife-beach). WATER/AIR types stay at the water surface
	# (flamingo reads as wading); crabs are LAND (placed for future beach decor, not in the
	# ocean roster — they'd otherwise float on open water).
	"dolphin":     _TYPE_WATER,
	"turtle_sea":  _TYPE_WATER,
	"flamingo":    _TYPE_WATER,
	"seagull":     _TYPE_AIR,
	"crab_red":    _TYPE_LAND,
	"crab_hermit": _TYPE_LAND,
}

## Target in-world HEIGHT (metres) per creature, against a ~1.8 m builder. The mesh
## is scaled so its tallest extent equals this — independent of the source mesh's
## native size (the .glb meshes vary wildly, e.g. elephant.glb is 2.7 u, panda 1 u).
const _TARGET_HEIGHT: Dictionary = {
	"panda":        2.0,
	"monkey":       1.0,
	"toucan":       0.8,
	"elephant":     3.6,
	"giraffe":      5.0,
	"gnu":          2.6,
	"desert_mouse": 0.7,
	"reindeer":     2.1,
	"snowman":      1.9,
	"pig":          1.3,
	"dog":          0.7,
	"sheep":        1.0,
	# Desert-biome wildlife.
	"camel":        2.0,
	"fennec_fox":   0.5,
	"desert_lizard":0.5,
	"scorpion":     0.4,
	"meerkat":      0.55,
	"rattlesnake":  0.6,
	"vulture":      0.9,
	# Snow-biome wildlife.
	"polar_bear":   1.4,
	"caribou":      2.0,
	"husky_dog":    0.8,
	"arctic_wolf":  1.0,
	"arctic_fox":   0.5,
	"snow_rabbit":  0.45,
	"penguin":      0.8,
	"snowy_owl":    0.5,
	"fish_blue":    0.6,
	"fish_orange":  0.6,
	"fish_yellow":  0.6,
	"orca":         3.8,
	"manta":        1.6,
	"jellyfish":    1.0,
	# Beach/ocean wildlife.
	"dolphin":      1.6,
	"turtle_sea":   0.9,
	"flamingo":     1.7,
	"seagull":      0.55,
	"crab_red":     0.5,
	"crab_hermit":  0.5,
}

## Fallback target height when a kind isn't in the map above.
const _TARGET_HEIGHT_DEFAULT: float = 1.4

## Per-kind extra ground lift (metres, scaled-world) added on top of the standard feet-to-
## standard grounding. Now that the base offset places feet AT the spawn surface (no more
## -0.45 capsule sink), creatures sit correctly without per-kind lifts; this stays as a
## hook for any creature whose authored mesh still dips below its AABB minimum.
const _GROUND_LIFT: Dictionary = {}

## Small downward settle (m) so feet rest ON the surface rather than hovering a hair above
## it. Removing the old -0.45 capsule sink left creatures (panda/pig/sheep) floating slightly;
## this nudges them down to contact without burying them.
const _GROUND_SETTLE: float = 0.2

## Half-height of the land collision capsule (height 0.9 / 2). The CapsuleShape3D is centred on
## its node origin; the collider is lifted by this amount so the capsule BOTTOM coincides with the
## body origin (= the feet plane). This makes is_on_floor() rest feet ON the surface for creatures
## of every size — the previous unshifted capsule floated every land animal 0.45 m above ground.
const _CAPSULE_HALF_HEIGHT: float = 0.45

## Per-creature yaw override (degrees), ADDED on top of the automatic long-axis
## alignment in _normalise_creature_mesh. Use 180 to flip a creature that walks
## tail-first, or 90/-90 for ones whose nose sits on the short axis. Empty = rely
## purely on the automatic geometry-based calibration.
const _YAW_OVERRIDE: Dictionary = {
	# "panda": 180.0,   # example: flip if it walks rump-first
}

# ─── Land wander constants ────────────────────────────────────────────────────

## Land walk speed (m/s) — slow, unthreatening.
const _LAND_WALK_SPEED: float = 1.2

## Duration of a single walk phase before next idle (seconds).
const _WALK_DURATION_MIN: float = 2.5
const _WALK_DURATION_MAX: float = 5.0

## Duration of an idle pause between walk phases (seconds).
const _IDLE_DURATION_MIN: float = 2.0
const _IDLE_DURATION_MAX: float = 5.0

## Maximum wander radius from spawn point (metres). Prevents animals from
## walking off into unloaded chunks.
const _LAND_WANDER_RADIUS: float = 12.0

## Gravity magnitude (m/s²) for land CharacterBody3D fall when airborne.
## Matches Godot default project gravity (9.8 m/s²).
const _GRAVITY: float = 9.8

# ─── Water / air bob constants ────────────────────────────────────────────────

## Amplitude of the sine drift for water animals (metres horizontal radius).
const _WATER_DRIFT_RADIUS: float = 4.0

## Amplitude of the vertical bob (metres peak-to-peak).
const _BOB_AMPLITUDE: float = 0.4

## Speed of the bob cycle (radians/second).
const _BOB_SPEED: float = 0.8

## Drift cycle speed (radians/second).
const _DRIFT_SPEED: float = 0.35

## Air hover height above spawn Y (metres).
const _AIR_HOVER_HEIGHT: float = 2.0

# ─── State ────────────────────────────────────────────────────────────────────

## Creature kind string (set by main_scene before add_child).
var kind: String = ""

## Resolved behaviour type (_TYPE_LAND / _TYPE_WATER / _TYPE_AIR).
var _behaviour_type: String = _TYPE_LAND

## Internal phase accumulator for water/air bob animations.
var _phase: float = 0.0

## Drift phase offset for water (separate from bob, decorrelated).
var _drift_phase: float = 0.0

## Spawn origin — water/air animals drift relative to this point.
var _spawn_origin: Vector3 = Vector3.ZERO

## Land wander: current walk heading (unit vector in XZ plane).
var _walk_dir: Vector3 = Vector3.FORWARD

## Land wander: remaining time in current phase (seconds).
var _phase_timer: float = 0.0

## Land wander: true = walking, false = idling.
var _is_walking: bool = false

## Land vertical velocity for gravity application.
var _vy: float = 0.0

## Known terrain top-face Y at the spawn column (set by main_scene.spawn_wildlife). Land
## creatures clamp to this until they first touch the floor, so they can't sink through a
## chunk whose collision mesh hasn't baked yet ("buried, only head out" bug). INF = unknown.
var ground_y: float = INF

## True once the land creature has rested on real floor at least once; the spawn-time
## ground clamp is released afterwards so it can still walk down slopes / off ledges.
var _landed_once: bool = false

## Child CharacterBody3D for land animals (null for water/air).
var _body: CharacterBody3D = null

## Child mesh root (top-level Node3D of the instantiated .glb).
var _mesh_root: Node3D = null

# ─── Phase 8: Animation ───────────────────────────────────────────────────────

## Distance-squared LOD gate (ANIM-06): beyond 40 m the animator update is
## skipped (last pose holds). All motion is parametric, so freezing is free.
const _ANIM_LOD_DIST_SQ: float = 40.0 * 40.0

## Mesh sets that ship a rigid-piece quadruped rig under assets/meshes/avatars/.
# 08 gap-closure replan (SC2 / ANIM-02): the QuadrupedAnimator leg-rig path is now LIVE
# for the panda. The value is unread — the _setup_animator QUADRUPED branch only checks
# `.has(kind)` and hardcodes `quad.mesh_set = "panda"` — so we map to `true` for clarity.
# Re-add a kind here to drive it with the 4-leg trot rig instead of the static art mesh.
const _QUADRUPED_SETS: Dictionary = {
	"panda": true,
}

## Skinned Meshy creatures with a baked walk clip. Add a kind here + drop the
## *_walking.glb to give that creature real skeletal limb animation while moving. The
## asset is a skinned, textured mesh with an AnimationPlayer carrying one looping walk
## clip; idle swaps back to the non-rigged static mesh + procedural bob (QA request).
const _ANIMATED_GLB: Dictionary = {
	"giraffe": "res://assets/meshes/avatars/giraffe/giraffe_walking.glb",
	# GAME-READY scripted-Rigify animal rigs (rigify-test batch). Each is a skinned,
	# textured mesh with ONE looping "Walk" clip and embedded textures — wired exactly
	# like the giraffe (scale by mesh-subtree AABB, ground feet, PI-yaw facing, play
	# Walk while moving / pause + static idle bob otherwise). Quadrupeds (horse metarig),
	# birds (spine+wings+legs), orca (fish spine), rattlesnake/scorpion (serpent spine).
	"arctic_fox":    "res://assets/meshes/avatars/arctic_fox/arctic_fox.glb",
	"arctic_wolf":   "res://assets/meshes/avatars/arctic_wolf/arctic_wolf.glb",
	"camel":         "res://assets/meshes/avatars/camel/camel.glb",
	"caribou":       "res://assets/meshes/avatars/caribou/caribou.glb",
	"dog":           "res://assets/meshes/avatars/dog/dog.glb",
	"elephant":      "res://assets/meshes/avatars/elephant/elephant.glb",
	"fennec_fox":    "res://assets/meshes/avatars/fennec_fox/fennec_fox.glb",
	"gnu":           "res://assets/meshes/avatars/gnu/gnu.glb",
	"husky_dog":     "res://assets/meshes/avatars/husky_dog/husky_dog.glb",
	"meerkat":       "res://assets/meshes/avatars/meerkat/meerkat.glb",
	"monkey":        "res://assets/meshes/avatars/monkey/monkey.glb",
	"pig":           "res://assets/meshes/avatars/pig/pig.glb",
	"polar_bear":    "res://assets/meshes/avatars/polar_bear/polar_bear.glb",
	"reindeer":      "res://assets/meshes/avatars/reindeer/reindeer.glb",
	"sheep":         "res://assets/meshes/avatars/sheep/sheep.glb",
	"snow_rabbit":   "res://assets/meshes/avatars/snow_rabbit/snow_rabbit.glb",
	"desert_lizard": "res://assets/meshes/avatars/desert_lizard/desert_lizard.glb",
	"desert_mouse":  "res://assets/meshes/avatars/desert_mouse/desert_mouse.glb",
	"vulture":       "res://assets/meshes/avatars/vulture/vulture.glb",
	"toucan":        "res://assets/meshes/avatars/toucan/toucan.glb",
	"snowy_owl":     "res://assets/meshes/avatars/snowy_owl/snowy_owl.glb",
	"flamingo":      "res://assets/meshes/avatars/flamingo/flamingo.glb",
	"seagull":       "res://assets/meshes/avatars/seagull/seagull.glb",
	"penguin":       "res://assets/meshes/avatars/penguin/penguin.glb",
	"orca":          "res://assets/meshes/avatars/orca/orca.glb",
	"rattlesnake":   "res://assets/meshes/avatars/rattlesnake/rattlesnake.glb",
	"scorpion":      "res://assets/meshes/avatars/scorpion/scorpion.glb",
}

## Fish kinds that use the GPU wobble shader (BodyType.FISH) with a per-kind tint.
# 08 gap-closure replan (SC1 / ANIM-01): the FISH ShaderWobble path is now LIVE. One mesh
# (fish_blue is the only avatar dir on disk) drives all three kinds; they are distinguished
# purely by this LINEAR-space body_colour tint (D-RECON-03: the shader tints ALL non-eye
# meshes). fish_blue matches minifigure_animator_demo.gd; orange/yellow are brand-aligned.
const _FISH_TINTS: Dictionary = {
	"fish_blue":   Color("#1E69C6"),
	"fish_orange": Color("#E8702A"),
	"fish_yellow": Color("#F2C037"),
}

## Typed animator (QuadrupedAnimator or ShaderWobbleAnimator) when this creature
## has a dedicated rig/wobble asset; null otherwise.
var _anim: Node3D = null

## Procedural fallback (transform-only) for single-mesh creatures with no rig.
var _proc_anim: ProceduralCreatureAnimator = null

## AnimationPlayer of a skinned Meshy walk-clip creature (_ANIMATED_GLB), else null.
## When set, the rigged walk clip plays while moving; idle swaps to the non-rigged mesh.
var _skinned_anim: AnimationPlayer = null

## Name of the looping walk clip on _skinned_anim (resolved at setup).
var _skinned_walk_name: String = ""

## Cached builder node for the LOD-distance gate (resolved lazily).
var _builder: Node3D = null

## Ground-baseline Y for a clean (non-art) land mesh centred via mesh-root translation;
## the procedural idle bob oscillates around this instead of zeroing the feet offset.
var _mesh_base_y: float = 0.0

# ─── Lifecycle ────────────────────────────────────────────────────────────────

func _ready() -> void:
	if kind.is_empty():
		# No kind set — silently do nothing; prevents errors if spawned bare.
		return

	_behaviour_type = _KIND_TYPE.get(kind, _TYPE_LAND)
	_spawn_origin = global_position

	# Stagger phases so herds don't move in sync.
	_phase = randf() * TAU
	_drift_phase = randf() * TAU

	# Load the creature mesh — prefer the clean, hand-authored stylised model
	# (`<kind>.glb`: multi-surface, real materials, authored upright). The TripoSR
	# mesh (`<kind>_triposr.glb`) is a dense, blobby AI scan with dark baked vertex
	# colours and an inconsistent forward axis — used only as a fallback when no
	# clean model exists. (v1.1 QA: switched preference to fix "too dark"/"low quality".)
	var mesh_scene: PackedScene = null
	for suffix: String in ["", "_triposr"]:
		var p: String = "res://assets/meshes/creatures/%s%s.glb" % [kind, suffix]
		if ResourceLoader.exists(p):
			mesh_scene = load(p) as PackedScene
			break

	if _behaviour_type == _TYPE_LAND:
		_setup_land(mesh_scene)
	else:
		_setup_floating(mesh_scene)

	# Start in idle phase so not all animals lurch forward simultaneously.
	_phase_timer = randf_range(_IDLE_DURATION_MIN, _IDLE_DURATION_MAX)
	_is_walking = false


## Set up a land animal: CharacterBody3D child with collision on terrain layer only.
func _setup_land(mesh_scene: PackedScene) -> void:
	_body = CharacterBody3D.new()
	# Layer 0 = no own layer; mask bit 0 = collide with terrain/statics only.
	# Player is on layer 1, hostiles on layer 2 — wildlife never blocks them.
	_body.collision_layer = 0
	_body.collision_mask = 1

	# Minimal capsule collider so move_and_slide works. The CapsuleShape3D is centred on its
	# node, so to make its BOTTOM coincide with the body origin (= the mesh feet plane, where
	# _normalise_creature_mesh grounds every land creature) we lift the shape by its half-height.
	# Without this lift the capsule bottom sat at origin − 0.45, so is_on_floor() rested the feet
	# 0.45 m ABOVE the surface — invisible on tall animals, fully floating on small ones
	# (desert_mouse/scorpion/meerkat/fennec_fox/snow_rabbit). See _CAPSULE_HALF_HEIGHT.
	var shape_node := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = 0.9
	shape_node.shape = capsule
	shape_node.position.y = _CAPSULE_HALF_HEIGHT
	_body.add_child(shape_node)

	# Attach mesh to the body.
	if mesh_scene != null:
		_mesh_root = mesh_scene.instantiate() as Node3D
		if _mesh_root != null:
			_body.add_child(_mesh_root)
			_normalise_creature_mesh(_mesh_root)

	add_child(_body)
	_body.global_position = global_position

	# Phase 8: attach the animator to the in-tree CharacterBody3D so its _ready()
	# (which loads the rig pieces) runs immediately.
	_setup_animator(_body, ProceduralCreatureAnimator.Motion.LAND)

	# Pick initial random heading.
	_pick_new_heading()


## Set up a water or air animal: pure Node3D child, no collision, no gravity.
func _setup_floating(mesh_scene: PackedScene) -> void:
	if mesh_scene != null:
		_mesh_root = mesh_scene.instantiate() as Node3D
		if _mesh_root != null:
			add_child(_mesh_root)
			_normalise_creature_mesh(_mesh_root)

	# Phase 8: attach the animator to self (in-tree Node3D).
	var proc_motion: ProceduralCreatureAnimator.Motion = (
		ProceduralCreatureAnimator.Motion.WATER if _behaviour_type == _TYPE_WATER
		else ProceduralCreatureAnimator.Motion.AIR)
	_setup_animator(self, proc_motion)


## Phase 8: pick + attach the right animator for this creature kind.
##   panda                       → QuadrupedAnimator   (rigid-piece rig)
##   fish_blue/orange/yellow     → ShaderWobbleAnimator FISH (GPU wobble)
## (The hostile ghost soft-body lives in plan 08-05, NOT here — "ghost" is not a wildlife
##  kind in _KIND_TYPE, so no ghost branch exists in this dispatch.)
## Anything else (single-mesh TripoSR art) → ProceduralCreatureAnimator (transform-only).
## A typed animator hides the TripoSR _mesh_root so the two don't overlap.
func _setup_animator(host: Node3D, proc_motion: ProceduralCreatureAnimator.Motion) -> void:
	if _ANIMATED_GLB.has(kind):
		_setup_skinned_glb(host)
		return
	if _QUADRUPED_SETS.has(kind):
		var quad := QuadrupedAnimator.new()
		quad.mesh_set = "panda"
		quad.gait = "idle"
		_anim = quad
		host.add_child(quad)
		# Scale the panda up (QA: "make the panda bigger") — it's a cute, chunky animal that
		# reads better clearly larger than the rig's authored size. base_y below re-grounds it.
		const _PANDA_SCALE: float = 2.0
		quad.scale = Vector3.ONE * _PANDA_SCALE
		# Ground the rig via its base_y baseline (NOT position.y directly): the walk/idle
		# gaits rewrite position.y every frame, so a one-shot position.y would be clobbered
		# the moment the panda moved — that was the "floats while walking" bug. base_y drops
		# the rig's lowest point onto the feet plane (= body origin, where the capsule bottom
		# now sits after the half-height lift); the bob rides on top of it.
		var rig_aabb: AABB = _subtree_local_aabb(quad)
		quad.base_y = -rig_aabb.position.y * _PANDA_SCALE
		quad.position.y = quad.base_y
		_hide_mesh_root()
		return
	if _FISH_TINTS.has(kind):
		var fish := ShaderWobbleAnimator.new()
		fish.mesh_set = "fish_blue"
		fish.body_type = ShaderWobbleAnimator.BodyType.FISH
		fish.body_colour = _FISH_TINTS[kind]
		fish.wobble_speed = 3.0
		fish.wobble_amount = 0.06
		fish.time_offset = randf() * TAU
		_anim = fish
		host.add_child(fish)
		_hide_mesh_root()
		return
	# Fallback: procedural transform-only idle on the existing TripoSR mesh-root.
	_proc_anim = ProceduralCreatureAnimator.new(proc_motion)


## Hide the TripoSR placeholder mesh-root once a typed animator owns the visual.
func _hide_mesh_root() -> void:
	if _mesh_root != null:
		_mesh_root.visible = false


## Set up a skinned Meshy walk-clip creature (_ANIMATED_GLB): instantiate the rigged
## .glb, scale it to its target height by the SKELETON bone span, ground its feet, face
## its walk direction, and wire the looping walk clip. Idle uses the NON-rigged static
## _mesh_root + procedural bob (QA request); _process_land swaps the two each frame.
func _setup_skinned_glb(host: Node3D) -> void:
	var path: String = _ANIMATED_GLB[kind]
	if not ResourceLoader.exists(path):
		# Asset missing (e.g. unbuilt checkout) — fall back to the procedural mesh path so
		# the creature still animates instead of vanishing.
		_proc_anim = ProceduralCreatureAnimator.new(ProceduralCreatureAnimator.Motion.LAND)
		return
	var glb := (load(path) as PackedScene).instantiate() as Node3D
	if glb == null:
		_proc_anim = ProceduralCreatureAnimator.new(ProceduralCreatureAnimator.Motion.LAND)
		return
	host.add_child(glb)

	# Scale + ground EXACTLY like the static mesh (_normalise_creature_mesh) so the rigged
	# walk visual and the idle static mesh are the SAME size and sit at the SAME height (QA:
	# the walking giraffe rendered much smaller than the static one). Use the MESH subtree
	# bounds, NOT the skeleton bone-span — Meshy "Unreal Take" rigs carry a root bone at the
	# armature origin that inflates the bone-span AABB and shrank the model.
	var ab: AABB = _subtree_local_aabb(glb)
	var target_h: float = _TARGET_HEIGHT.get(kind, _TARGET_HEIGHT_DEFAULT)
	var span: float = maxf(ab.size.x, maxf(ab.size.y, ab.size.z))
	span = maxf(span, 0.001)
	var sc: float = target_h / span
	glb.scale = Vector3.ONE * sc

	# Facing: Meshy meshes are authored +Z; yaw 180° makes the rig lead head-first (the body's
	# look_at points -Z at the walk dir), matching _normalise_creature_mesh's flip.
	glb.rotation.y = PI

	# Ground feet at the spawn surface (entity origin y=0), NOT a -0.45 capsule sink — mirrors
	# the static land path so walk and idle align vertically. 180° yaw maps centre to +center.
	var center: Vector3 = ab.get_center() * sc
	var min_y: float = ab.position.y * sc
	glb.position = Vector3(center.x, -min_y - _GROUND_SETTLE, center.z)

	# Wire the AnimationPlayer + walk clip. Loop the clip so it cycles while moving; start
	# PAUSED so idle shows the rest pose (the asset ships no separate idle clip).
	_skinned_anim = glb.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if _skinned_anim != null:
		for a: String in _skinned_anim.get_animation_list():
			if _skinned_walk_name == "" or a.to_lower().contains("walk") or a.to_lower().contains("baselayer"):
				_skinned_walk_name = a
				if a.to_lower().contains("walk") or a.to_lower().contains("baselayer"):
					break
		if _skinned_walk_name != "":
			var clip: Animation = _skinned_anim.get_animation(_skinned_walk_name)
			if clip != null:
				clip.loop_mode = Animation.LOOP_LINEAR
		_skinned_anim.stop()  # cancel any glTF autoplay
	# Idle = the NON-rigged version (QA request): the rigged walk GLB shows ONLY while moving;
	# when idle we hide it and show the original TripoSR _mesh_root running its gentle
	# ProceduralCreatureAnimator idle bob (the asset ships no rig idle clip, and a frozen rest
	# pose reads as dead). _process_land swaps visibility each frame off _is_walking.
	_anim = glb                                                              # rigged walk visual
	_proc_anim = ProceduralCreatureAnimator.new(ProceduralCreatureAnimator.Motion.LAND)  # idle bob
	glb.visible = false                                                      # spawn idle → static shows
	if _mesh_root != null:
		_mesh_root.visible = true


## Merged SKELETON-bone-span AABB (in `root`'s local space) for a skinned mesh, mirroring
## builder._avatar_skinned_aabb. Falls back to the mesh subtree AABB when no skeleton.
func _skinned_aabb(root: Node3D) -> AABB:
	var sk := root.find_child("Skeleton3D", true, false) as Skeleton3D
	if sk == null or sk.get_bone_count() == 0:
		return _subtree_local_aabb(root)
	var inv: Transform3D = root.global_transform.affine_inverse()
	var lo := Vector3(1e9, 1e9, 1e9)
	var hi := -lo
	for i: int in range(sk.get_bone_count()):
		var p: Vector3 = inv * ((sk.global_transform * sk.get_bone_global_pose(i)).origin)
		lo = lo.min(p)
		hi = hi.max(p)
	return AABB(lo, hi - lo)


## Phase 8 LOD gate (ANIM-06): true when the builder is far enough that the
## animator update can be skipped this frame (last pose holds — no free/reset).
func _anim_lod_should_skip() -> bool:
	if _builder == null or not is_instance_valid(_builder):
		_builder = get_tree().get_first_node_in_group("builder") as Node3D
	if _builder == null:
		return false  # no builder yet (tests / early frames) — animate normally
	return global_position.distance_squared_to(_builder.global_position) >= _ANIM_LOD_DIST_SQ


## Normalise a freshly-instantiated creature mesh: surface its baked vertex colours
## (the TripoSR art is stored in vertex colours but hidden behind a white albedo) and
## scale it to a believable per-creature height regardless of the mesh's native size.
func _normalise_creature_mesh(root: Node3D) -> void:
	var mi: MeshInstance3D = _find_mesh_instance(root)
	if mi == null or mi.mesh == null:
		return
	var mesh: Mesh = mi.mesh
	# Show baked vertex colours where present (TripoSR meshes). Primitive meshes have
	# no COLOR array — leave their imported per-part materials untouched.
	var is_art_mesh: bool = false
	for s: int in mesh.get_surface_count():
		if (mesh.surface_get_format(s) & Mesh.ARRAY_FORMAT_COLOR) != 0:
			is_art_mesh = true
			var mat := StandardMaterial3D.new()
			mat.vertex_color_use_as_albedo = true
			mat.roughness = 1.0
			mi.set_surface_override_material(s, mat)
	# Scale by the LARGEST extent so size is correct regardless of orientation.
	var sz: Vector3 = mesh.get_aabb().size
	var native: float = maxf(sz.x, maxf(sz.y, sz.z))
	native = maxf(native, 0.001)
	var target_h: float = _TARGET_HEIGHT.get(kind, _TARGET_HEIGHT_DEFAULT)
	var s: float = target_h / native

	if not is_art_mesh:
		# Clean multi-surface stylised model: authored UPRIGHT with real materials, so
		# no -90X / vertex-colour work. Scale + ground using the FULL subtree bounds —
		# a multi-part model's first-mesh AABB is NOT the whole creature, so deriving the
		# scale from it (the `native`/`s` above) sized animals wrong and left them floating.
		var full: AABB = _subtree_local_aabb(root)
		var fnative: float = maxf(full.size.x, maxf(full.size.y, full.size.z))
		fnative = maxf(fnative, 0.001)
		var fs: float = target_h / fnative
		root.scale = Vector3.ONE * fs
		# Meshy models are authored facing +Z, but the body's look_at() points its -Z at the
		# walk direction — so without this flip every creature walks backwards. Yaw 180° makes
		# the model's front (-Z after the flip) lead. The flip maps the X/Z centring offset to
		# +center (a 180° Y-rotation negates x,z); Y is unaffected.
		root.rotation.y = PI
		var center: Vector3 = full.get_center() * fs
		var min_y: float = full.position.y * fs
		if _behaviour_type == _TYPE_LAND:
			# Feet (AABB min-Y) to the SPAWN SURFACE (the entity origin = surface_y), so the
			# animal stands on the ground. The old -0.45 "capsule bottom" offset sank every
			# land creature ~0.45 m (hidden on tall ones, obvious on pig/sheep/giraffe — they
			# showed half-buried). Stash the baseline so the idle bob oscillates around it.
			_mesh_base_y = -min_y - _GROUND_SETTLE + float(_GROUND_LIFT.get(kind, 0.0))
			root.position = Vector3(center.x, _mesh_base_y, center.z)
		else:
			# Water/air: centre on all axes (the fallback only rocks rotation.z here).
			root.position = Vector3(center.x, -center.y, center.z)
		return

	# TripoSR art meshes import lying on their back. -90° pitch about X stands them upright.
	# Yaw is calibrated PER CREATURE (_YAW_OVERRIDE, degrees) so the nose points -Z (the
	# body's look_at points -Z at the walk direction, so the animal leads with its head).
	# These AI-generated meshes have no consistent forward axis, so the values are read off
	# a top-down render per creature; default 180 matches the prior facing.
	var yaw_deg: float = float(_YAW_OVERRIDE.get(kind, 180.0))
	var orient := Basis.from_euler(Vector3(deg_to_rad(-90.0), deg_to_rad(yaw_deg), 0.0))

	# Compose rotation + uniform scale on the single art surface, then recentre. Without
	# recentring the mesh pivots about the glb origin (mid-body, not the feet) and ends
	# up offset or buried — the root cause of every prior "tilted/sunk" report.
	var basis := orient.scaled(Vector3(s, s, s))
	var taabb: AABB = Transform3D(basis, Vector3.ZERO) * mesh.get_aabb()
	var off := Vector3(-taabb.get_center().x, 0.0, -taabb.get_center().z)
	if _behaviour_type == _TYPE_LAND:
		# Drop feet (min-Y) to the spawn surface (entity origin) so they stand on terrain.
		off.y = -taabb.position.y - _GROUND_SETTLE
	else:
		# Water/air animals: centre vertically too — they float free.
		off.y = -taabb.get_center().y
	# Apply everything on the mesh instance; leave root clean for movement/look_at.
	mi.transform = Transform3D(basis, off)
	root.rotation = Vector3.ZERO
	root.scale = Vector3.ONE


## Merged AABB (in `root`'s local space) of every MeshInstance3D in the subtree —
## so multi-part stylised models are centred/grounded by their full bounds, not the
## first piece. Accumulates each mesh's AABB through its transform relative to root.
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


## Recursively find the first MeshInstance3D with a mesh in a subtree.
func _find_mesh_instance(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		return node as MeshInstance3D
	for child: Node in node.get_children():
		var found: MeshInstance3D = _find_mesh_instance(child)
		if found != null:
			return found
	return null


# ─── Process ──────────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	if kind.is_empty():
		return
	_phase += _BOB_SPEED * delta
	_drift_phase += _DRIFT_SPEED * delta

	match _behaviour_type:
		_TYPE_LAND:
			_process_land(delta)
		_TYPE_WATER:
			_process_water(delta)
		_TYPE_AIR:
			_process_air(delta)


## Land animal wander: timer-driven walk/idle cycle + gravity via CharacterBody3D.
func _process_land(delta: float) -> void:
	if _body == null:
		return

	_phase_timer -= delta
	if _phase_timer <= 0.0:
		_is_walking = not _is_walking
		if _is_walking:
			_phase_timer = randf_range(_WALK_DURATION_MIN, _WALK_DURATION_MAX)
			_pick_new_heading()
		else:
			_phase_timer = randf_range(_IDLE_DURATION_MIN, _IDLE_DURATION_MAX)

	# Horizontal velocity.
	if _is_walking:
		_body.velocity.x = _walk_dir.x * _LAND_WALK_SPEED
		_body.velocity.z = _walk_dir.z * _LAND_WALK_SPEED
		# Face walking direction.
		if _walk_dir.length_squared() > 0.01:
			var look_target: Vector3 = _body.global_position + _walk_dir
			look_target.y = _body.global_position.y
			_body.look_at(look_target, Vector3.UP)
	else:
		_body.velocity.x = 0.0
		_body.velocity.z = 0.0

	# Apply gravity.
	if not _body.is_on_floor():
		_vy -= _GRAVITY * delta
	else:
		_vy = 0.0
	_body.velocity.y = _vy

	_body.move_and_slide()

	# Spawn-time ground clamp: until the creature has landed on real collision once, never let
	# its feet (= body origin, now that the capsule bottom is lifted to the origin) drop below the
	# known terrain top. This stops it sinking through a chunk whose collision mesh hasn't finished
	# baking — the cause of the "buried, only head sticking out" reports. Released after the first
	# real floor contact so slopes/ledges still work normally. Snapping origin → ground_y rests the
	# feet ON the surface (the old +0.45 left them floating a capsule-half-height above it).
	if not _landed_once:
		if _body.is_on_floor():
			_landed_once = true
		elif ground_y != INF and _body.global_position.y <= ground_y:
			_body.global_position.y = ground_y
			_vy = 0.0
			_landed_once = true

	# Phase 8: drive the animator. Skip when the builder is far (ANIM-06 LOD).
	if _anim_lod_should_skip():
		return
	if _skinned_anim != null:
		# Walk = rigged skeletal clip; idle = the NON-rigged static mesh + procedural bob
		# (QA request — a frozen rest pose reads as dead). Swap which visual is shown each
		# frame off _is_walking: rigged GLB while moving, TripoSR _mesh_root while idle.
		if _is_walking and _skinned_walk_name != "":
			if _anim != null:
				_anim.visible = true
			if _mesh_root != null:
				_mesh_root.visible = false
			if not _skinned_anim.is_playing():
				_skinned_anim.play(_skinned_walk_name)
		else:
			if _skinned_anim.is_playing():
				_skinned_anim.pause()
			if _anim != null:
				_anim.visible = false
			if _mesh_root != null:
				_mesh_root.visible = true
			if _proc_anim != null:
				_proc_anim.update(_mesh_root, delta, false, _mesh_base_y)
	elif _anim is QuadrupedAnimator:
		(_anim as QuadrupedAnimator).gait = "walk" if _is_walking else "idle"
	elif _proc_anim != null:
		_proc_anim.update(_mesh_root, delta, _is_walking, _mesh_base_y)


## Water animal drift: sine-based circular drift + vertical bob.
## No physics — all motion computed from spawn_origin.
func _process_water(delta: float) -> void:
	var drift_x: float = sin(_drift_phase) * _WATER_DRIFT_RADIUS
	var drift_z: float = cos(_drift_phase * 0.7) * _WATER_DRIFT_RADIUS
	var bob_y: float = sin(_phase) * _BOB_AMPLITUDE
	global_position = Vector3(
		_spawn_origin.x + drift_x,
		_spawn_origin.y + bob_y,
		_spawn_origin.z + drift_z
	)
	# Face direction of motion.
	var motion_dir: Vector3 = Vector3(
		cos(_drift_phase) * _WATER_DRIFT_RADIUS * _DRIFT_SPEED,
		0.0,
		-sin(_drift_phase * 0.7) * _WATER_DRIFT_RADIUS * _DRIFT_SPEED * 0.7
	)
	if motion_dir.length_squared() > 0.001:
		var look_target: Vector3 = global_position + motion_dir.normalized()
		look_target.y = global_position.y
		look_at(look_target, Vector3.UP)

	# Phase 8: procedural rock (typed wobble fish animate on the GPU — no work here).
	if _proc_anim != null and not _anim_lod_should_skip():
		_proc_anim.update(_mesh_root, delta)


## Air animal (toucan): hover above spawn Y with gentle bob and slow yaw.
func _process_air(delta: float) -> void:
	var bob_y: float = sin(_phase) * _BOB_AMPLITUDE
	var drift_x: float = sin(_drift_phase * 0.5) * 1.5
	var drift_z: float = cos(_drift_phase * 0.4) * 1.5
	global_position = Vector3(
		_spawn_origin.x + drift_x,
		_spawn_origin.y + _AIR_HOVER_HEIGHT + bob_y,
		_spawn_origin.z + drift_z
	)

	# Phase 8: procedural rock for single-mesh air creatures (toucan).
	if _proc_anim != null and not _anim_lod_should_skip():
		_proc_anim.update(_mesh_root, delta)


# ─── Helpers ─────────────────────────────────────────────────────────────────

## Pick a new random walk heading, biased toward spawn origin if too far away.
func _pick_new_heading() -> void:
	if _body == null:
		return
	var to_origin: Vector3 = _spawn_origin - _body.global_position
	to_origin.y = 0.0
	if to_origin.length() > _LAND_WANDER_RADIUS:
		# Too far — head back toward spawn origin.
		_walk_dir = to_origin.normalized()
	else:
		var angle: float = randf() * TAU
		_walk_dir = Vector3(cos(angle), 0.0, sin(angle))
