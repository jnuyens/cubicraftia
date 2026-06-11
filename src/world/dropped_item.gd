# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# dropped_item.gd — Floating pickupable brick entity (Phase 2 spawn, Phase 3 owns pickup).
#
# Per DOCS.md §3.3 + §4.3: a broken brick / mined ore drops as a glowing floating
# item. Phase 2 spawns these from dynamite + break; Phase 3 owns the pickup +
# despawn semantics.
#
# Lifecycle:
#   1. Spawn as RigidBody3D at the source brick/voxel position with random impulse.
#   2. Bounce for ~1.5 s (gravity + collision with terrain + bricks).
#   3. Settle: transition to a static MultiMeshInstance3D pool entry.
#
# Per RESEARCH.md §"Pitfall 7": cap concurrent active RigidBody3D items at 30;
# remainder are spawned directly into the settled MultiMesh pool.
#
# Phase 2 ships the spawning + two-phase transition; Phase 3 inherits the
# picked_up signal contract for inventory integration.
#
# Despawn semantics: Phase 3 owns the 2-Cubicraftia-day despawn timer
# (STATE.md locked decision). Phase 2 only tracks settled items in the pool.
#
# TERRAIN_TO_BRICK_DROP: maps terrain voxel IDs (from terrain_generator.gd)
# to the dropped brick def_id in BrickRegistry. Snow voxels drop nothing (null).
# Ore IDs (copper_ore=11, iron_ore=12, diamond_ore=13) are terrain voxel IDs
# defined in the extended terrain_generator.gd ore layer.
#
# References:
#   DOCS.md §3.3 — brick drops as floating pickupable item
#   DOCS.md §4.3 — dropped-item glow visual (OmniLight3D, warm white #FFFAE6)
#   02-RESEARCH.md §"Pitfall 7" — two-phase RigidBody3D → settled MultiMesh
#   02-PATTERNS.md §"src/world/dropped_item.gd" — lifecycle + signal pattern
#   02-UI-SPEC.md §"Dropped items full-stack tip" — items_dropped_nearby label
#   02-CONTEXT.md D-11 — brick-shatter VFX, every brick pops outward

class_name DroppedItem
extends RigidBody3D

# ─── Signals ──────────────────────────────────────────────────────────────────

## Emitted when this dropped item finishes spawning with physics active.
signal spawned(item_id: int)

## Emitted when this dropped item transitions to the settled MultiMesh pool.
signal settled(item_id: int)

## Emitted when this dropped item is picked up (Phase 3 emits this via inventory).
## Phase 2 does not emit this signal; it is defined here as the Phase 3 contract.
signal picked_up(item_id: int)

# ─── Terrain → dropped-brick mapping (LOCKED per plan spec) ──────────────────

## Maps terrain voxel IDs (TerrainGenerator constants) to BrickRegistry def_ids.
## Keys are integer voxel channel values from terrain_generator.gd.
## Null value means this voxel type drops nothing (e.g. snow).
##
## Terrain voxel ID sources (terrain_generator.gd):
##   GRASS_ID = 1, SAND_ID = 2, SNOW_ID = 3, STONE_ID = 4,
##   DIRT_ID = 11
## Brick def_ids must match brick_id in BrickRegistry (src/bricks/*.tres):
##   "wood_plank", "sand", "stone", "cobblestone",
##   "copper_ore", "iron_ore", "diamond_ore"
##
## This const is the SINGLE owner of the terrain→drop mapping.
## DynamiteHandler references this const for terrain cell drops.
const TERRAIN_TO_BRICK_DROP: Dictionary = {
	1: "wood_plank",      # GRASS_ID  → wood plank (grass block top layer)
	11: "wood_plank",     # DIRT_ID   → wood plank (dirt below grass)
	2: "sand",            # SAND_ID   → sand brick
	3: null,              # SNOW_ID   → nothing (snow drops nothing per spec)
	4: "stone",           # STONE_ID  → stone brick
	5: "cobblestone",     # SANDSTONE_ID → cobblestone (closest available)
	6: null,              # ICE_ID    → nothing (ice drops nothing)
	7: null,              # WATER_ID  → nothing (water drops nothing)
	8: "wood_plank",      # JUNGLE_GRASS_ID → wood plank (same as grass)
	9: "wood_plank",      # SAVANNAH_GRASS_ID → wood plank
}

# ─── Public state ─────────────────────────────────────────────────────────────

## The BrickRegistry def_id for this dropped item ("wood_plank", "stone", etc.).
## Set at spawn time by spawn_dropped_item() in main_scene.gd.
var def_id: String = ""

## Palette colour index (-1 = natural/material colour, 0..17 = palette index).
## Set at spawn time.
var colour_index: int = -1

# ─── Phase 3 constants ───────────────────────────────────────────────────────

## Dropped items despawn after 2 Cubicraftia days (DOCS §4.3 + STATE.md locked decision).
## Measured against WorldClock.elapsed_seconds (game-clock, not wall-clock) per RESEARCH Pitfall 2.
const DESPAWN_AFTER_DAYS: float = 2.0

## Per-item cooldown before the "inventory full" toast can fire again (RESEARCH Pitfall 8).
## Prevents toast spam when a builder walks through many dropped items with a full inventory.
## Inventory.gd's _can_show_full_tip() is the authoritative cooldown; this field guards
## repeat try_pickup calls from the same item.
const REJECT_COOLDOWN_S: float = 2.0

## Auto-pickup detection radius in metres (DOCS §4.1 + ROADMAP SC#1 "auto-pick within ~1 m").
const AUTO_PICKUP_RADIUS_M: float = 1.0

# ─── Private state ────────────────────────────────────────────────────────────

## Duration of the physics-active bounce phase in seconds.
var _bounce_duration: float = 1.5

## Elapsed time in the bounce phase.
var _elapsed: float = 0.0

## Whether this item has already been settled (guard against double-settle).
var _settled: bool = false

## Reference to the main scene for transition_to_settled_pool.
## Set via set_main_scene() during spawn.
var _main_scene: Node = null

## Game-clock tick at which this item spawned (WorldClock.elapsed_seconds at _ready time).
## Used for the 2-Cubicraftia-day despawn timer (RESEARCH Pitfall 2: game-clock, not wall-clock).
var _spawn_tick: float = 0.0

## Game-clock tick before which try_pickup returns false without retrying Inventory.
## Set when inventory is full; cleared automatically after REJECT_COOLDOWN_S (RESEARCH Pitfall 8).
var _recently_rejected_until: float = -INF

# ─── Lifecycle ────────────────────────────────────────────────────────────────

func _ready() -> void:
	# Apply a random outward impulse so the item "pops" away from the blast centre.
	# The impulse combines upward + random XZ scatter for the brick-shatter effect.
	apply_impulse(
		Vector3.UP * 3.0 +
		Vector3(randf_range(-1.5, 1.5), 0.0, randf_range(-1.5, 1.5))
	)
	spawned.emit(get_instance_id())
	# Phase 3: record the game-clock tick at which this item spawned.
	# Despawn logic compares WorldClock.elapsed_seconds − _spawn_tick against
	# DESPAWN_AFTER_DAYS × WorldClock.SECONDS_PER_DAY (RESEARCH Pitfall 2).
	if Engine.has_singleton("WorldClock"):
		_spawn_tick = Engine.get_singleton("WorldClock").elapsed_seconds
	elif "WorldClock" in Engine.get_main_loop():
		_spawn_tick = Engine.get_main_loop().WorldClock.elapsed_seconds
	# If WorldClock is not available (e.g. headless test without the autoload),
	# _spawn_tick stays 0.0 — the despawn check is a no-op until the clock loads.


func _physics_process(delta: float) -> void:
	_elapsed += delta
	if not _settled and _elapsed >= _bounce_duration:
		_settle()
		# _settle() may call queue_free() when no main_scene pool is available.
		# Guard before running further frame work on a node pending free (WR-07).
		if not is_inside_tree():
			return
	# Phase 3: after settling, check despawn timer and auto-pickup proximity.
	if _settled:
		_check_despawn()
		_check_auto_pickup()


# ─── Public API ───────────────────────────────────────────────────────────────

## Set the main scene reference for settled-pool transition.
## Called by main_scene.gd immediately after instantiating this node.
func set_main_scene(scene: Node) -> void:
	_main_scene = scene


## Attempt to pick up this item into builder's inventory via Inventory.apply_event.
##
## Returns true if pickup succeeded (item added to inventory; item is queue_freed).
## Returns false if:
##   - The _recently_rejected_until cooldown has not yet expired (RESEARCH Pitfall 8).
##   - Inventory.apply_event returned false (inventory full).
##
## On rejection, sets a REJECT_COOLDOWN_S cooldown to prevent toast spam when the builder
## walks through many items with a full inventory (RESEARCH Pitfall 8 + T-03-09-DR-02).
##
## @param builder  The builder Node. Must expose get_stable_builder_id() → String.
func try_pickup(builder: Node) -> bool:
	# Respect the per-item reject cooldown (RESEARCH Pitfall 8).
	var clock_elapsed: float = _get_clock_elapsed()
	if clock_elapsed < _recently_rejected_until:
		return false
	var builder_id: String = ""
	if builder.has_method("get_stable_builder_id"):
		builder_id = builder.get_stable_builder_id()
	else:
		builder_id = str(builder.get_meta("builder_id", ""))
	var event: Dictionary = {
		"kind": "ADD",
		"builder_id": builder_id,
		"def_id": def_id,
		"count": 1,
	}
	var ok: bool = Inventory.apply_event(event)
	if not ok:
		_recently_rejected_until = clock_elapsed + REJECT_COOLDOWN_S
		return false
	picked_up.emit(get_instance_id())
	queue_free()
	return true


# ─── Private helpers ──────────────────────────────────────────────────────────

## Check whether the item has exceeded its 2-Cubicraftia-day lifetime and despawn it.
## Uses WorldClock.elapsed_seconds (game-clock) per RESEARCH Pitfall 2 semantics.
## Called from _physics_process after the item has settled.
func _check_despawn() -> void:
	var elapsed: float = _get_clock_elapsed()
	if elapsed - _spawn_tick > DESPAWN_AFTER_DAYS * WorldClock.SECONDS_PER_DAY:
		queue_free()


## Poll for a nearby builder and auto-pickup if within AUTO_PICKUP_RADIUS_M.
## Mirrors the proximity-poll pattern used by ChestEntity and WorkbenchEntity.
func _check_auto_pickup() -> void:
	var builder: Node = get_tree().get_first_node_in_group("builder")
	if builder == null:
		return
	var builder_node: Node3D = builder as Node3D
	if builder_node == null:
		return
	var dist: float = global_position.distance_to(builder_node.global_position)
	if dist <= AUTO_PICKUP_RADIUS_M:
		try_pickup(builder)


## Return the current WorldClock.elapsed_seconds, or 0.0 if the autoload is unavailable.
func _get_clock_elapsed() -> float:
	if Engine.get_main_loop() == null:
		return 0.0
	var root: Node = Engine.get_main_loop().root
	if root == null:
		return 0.0
	var wc: Node = root.get_node_or_null("/root/WorldClock")
	if wc != null and "elapsed_seconds" in wc:
		return wc.elapsed_seconds
	return 0.0


## Transition this item from physics-active to the settled MultiMesh pool.
## Emits settled signal, then delegates to main_scene.transition_to_settled_pool.
func _settle() -> void:
	if _settled:
		return
	_settled = true
	settled.emit(get_instance_id())
	if _main_scene != null and _main_scene.has_method("transition_to_settled_pool"):
		_main_scene.transition_to_settled_pool(self)
	else:
		# Fallback: no main_scene available (e.g. in a test context); just free self.
		queue_free()
