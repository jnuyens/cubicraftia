# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# spawning.gd — Hostile-mob spawning autoload for Cubicraftia.
#
# Anchors:
#   DOCS.md §5.3 — hostile spawning rules: light-level gate, ~10/chunk cap, bed-bubble
#   03-CONTEXT.md D-01 — sandbox mode suppresses all survival mechanics
#   03-CONTEXT.md D-10 — bed-radius is sacred (8 m sphere around any placed builder-bed)
#   03-RESEARCH.md Pitfall 5 — bed-bubble lookup must be chunk-keyed (O(beds-in-chunk))
#   03-RESEARCH.md Pitfall 9 — sleep cancellation must poll hostiles-in-bubble every tick
#
# Registered as autoload "Spawning" in project.godot AFTER Inventory (per 03-PATTERNS.md
# L1038 — Spawning may consult Inventory.get_chest(chunk) to suppress spawns over chests).
#
# Load-order contract: Inventory is always ready by the time Spawning._ready() executes
# because Godot initialises autoloads in project.godot order. Both use Engine.has_singleton
# checks as belt-and-braces for the rare init-order race.
#
# Active-hostile bookkeeping: HostileMob._ready() calls notify_spawned(self);
# HostileMob._exit_tree() calls notify_despawned(self). Plan 03-10 wires the actual
# mob instantiation; this plan ships the gate logic and deferred should_spawn signal.
#
# References:
#   03-PATTERNS.md L149-184 (Spawning autoload analog)
#   03-RESEARCH.md Pattern 2 (hostile mob state machine + throttled NavigationServer3D)
#   03-RESEARCH.md Pitfall 5 (chunk-keyed bed index)
#   03-RESEARCH.md Pitfall 9 (sleep-cancellation hostile-in-bubble poll)
#   03-RESEARCH.md Code Examples L507 (Tier-3 fallback clear_hostiles_in_chunk_range)

extends Node

# ─── Constants ────────────────────────────────────────────────────────────────

## Bed-bubble radius per D-10: no mobs spawn within this radius of any placed bed.
const BED_BUBBLE_RADIUS_M: float = 8.0

## Chunk size used by godot_voxel terrain. Bed-bubble index uses this for chunk keying.
## Per Phase 2 VoxelTerrain config (voxel chunk size = 16 terrain cubes of 1 m each).
const CHUNK_SIZE_M: float = 16.0

## Spawn-tick rate: approximately once per second to avoid per-frame spawn bursts.
const SPAWN_TICK_HZ: float = 1.0
const SPAWN_TICK_INTERVAL_S: float = 1.0 / SPAWN_TICK_HZ

## Default per-chunk hostile cap per DOCS §5.3 + D-09.
## main_scene may override via set_hostile_mob_cap_override() for adaptive-quality.
## Tuned down 10→6→3 (v1.1 QA): the night was overwhelming the player near spawn. The
## dispatcher sweeps a 3×3 chunk grid each tick, so the effective bound is this × ~9 chunks;
## the global cap below is the real ceiling.
const MAX_HOSTILES_PER_CHUNK_DEFAULT: int = 2

## Global ceiling on simultaneously-active hostile mobs around the builder. The 3×3 chunk
## sweep × per-chunk cap could otherwise stack 25-90 mobs near spawn; this hard-caps the
## total so a night feels threatening, not swarming (v1.1 QA: "way too many mobs at night").
const MAX_ACTIVE_HOSTILES_GLOBAL: int = 7

# ─── Signals ─────────────────────────────────────────────────────────────────

## Emitted when a hostile mob is registered as active (called by HostileMob._ready()).
signal hostile_spawned(mob: Node, position: Vector3)

## Emitted when a hostile mob leaves the scene tree (called by HostileMob._exit_tree()).
signal hostile_despawned(mob: Node)

## Emitted when a bed is registered into the bed-bubble index.
signal bed_registered(world_pos: Vector3)

## Emitted when a bed is removed from the bed-bubble index.
signal bed_unregistered(world_pos: Vector3)

## Plan 03-10 connects this to main_scene.spawn_hostile_mob().
## Until 03-10, the spawn gate fires this signal; no actual mob is instantiated.
signal should_spawn(kind: String, position: Vector3)

# ─── Internal state ───────────────────────────────────────────────────────────

## Chunk-keyed bed index per RESEARCH Pitfall 5.
## A bed's 8 m bubble can touch up to 8 chunks at a corner; we register the bed
## under EVERY chunk its bubble intersects (symmetric with unregister_bed).
## Key: Vector3i chunk coordinate; Value: Array[Vector3] of bed world positions.
var _beds_by_chunk: Dictionary = {}

## Flat list of all registered bed world positions.
## Used by hostiles_inside_bed_bubble() distance queries.
var _all_beds: Array[Vector3] = []

## Running count of active hostiles per chunk.
## Incremented by notify_spawned(); decremented by notify_despawned().
var _active_per_chunk: Dictionary = {}

## All live HostileMob nodes (for hostiles_inside_bed_bubble() distance check).
var _active_mobs: Array = []

## Wall-delta accumulator for the 1 Hz spawn-tick throttle.
var _spawn_tick_accumulator: float = 0.0

## Spawn-tick counter used as the sequence input for seeded kind selection.
var _spawn_tick_seq: int = 0

## Seeded RNG for spawn-kind selection. Seed via seed_from_world(world_seed) after
## the world is loaded so kind selection is deterministic per world + tick (WR-01).
var _kind_rng: RandomNumberGenerator = RandomNumberGenerator.new()

## Test-mode override. Mirror of ToolWear._test_mode_override pattern.
## Values: "" (use Features), "survival", "sandbox".
var _test_mode_override: String = ""

## Cap override for adaptive-quality dispatch (Plan 03-10 wires this).
## -1 means "use MAX_HOSTILES_PER_CHUNK_DEFAULT".
var _hostile_mob_cap_override: int = -1

## Whether WorldClock.cancel_sleep_lapse() should be called when a hostile enters
## an active sleep bubble. Set to true by the lapse-active flag during sleep.
## Plan 03-04 wires this via WorldClock.sleep_lapse_ended + start_sleep_lapse.
## Stored as a Dictionary {bed_pos: Vector3} when a lapse is active; empty otherwise.
var _active_sleep_bubbles: Array[Vector3] = []

# ─── Lifecycle ────────────────────────────────────────────────────────────────

func _ready() -> void:
	# Connect to WorldClock.sleep_lapse_ended once it's available.
	# WorldClock ships in Phase 2 (always present); sleep_lapse_ended is new in Phase 3.
	if WorldClock.has_signal("sleep_lapse_ended"):
		if not WorldClock.sleep_lapse_ended.is_connected(_on_sleep_lapse_ended):
			WorldClock.sleep_lapse_ended.connect(_on_sleep_lapse_ended)


## Per-frame update. Early-returns in sandbox mode (D-01 + DOCS §5.1).
## Accumulates wall-delta and fires _run_spawn_tick() at ~1 Hz.
func _process(delta: float) -> void:
	if not _is_survival_mode():
		return
	_spawn_tick_accumulator += delta
	if _spawn_tick_accumulator >= SPAWN_TICK_INTERVAL_S:
		_spawn_tick_accumulator -= SPAWN_TICK_INTERVAL_S
		_run_spawn_tick()

# ─── Public API — Bed-bubble index ────────────────────────────────────────────

## Register a builder-bed at world_pos into the chunk-keyed bed index.
## A bed's 8 m bubble may intersect up to 8 chunks (one per octant at a chunk corner).
## Per RESEARCH Pitfall 5: register under EVERY chunk the bubble intersects.
## @param world_pos  The world-space position of the placed builder-bed.
func register_bed(world_pos: Vector3) -> void:
	_all_beds.append(world_pos)
	# Enumerate every chunk whose bounding box overlaps the BED_BUBBLE_RADIUS_M sphere.
	var min_chunk := Vector3i(
		floori((world_pos.x - BED_BUBBLE_RADIUS_M) / CHUNK_SIZE_M),
		floori((world_pos.y - BED_BUBBLE_RADIUS_M) / CHUNK_SIZE_M),
		floori((world_pos.z - BED_BUBBLE_RADIUS_M) / CHUNK_SIZE_M)
	)
	var max_chunk := Vector3i(
		floori((world_pos.x + BED_BUBBLE_RADIUS_M) / CHUNK_SIZE_M),
		floori((world_pos.y + BED_BUBBLE_RADIUS_M) / CHUNK_SIZE_M),
		floori((world_pos.z + BED_BUBBLE_RADIUS_M) / CHUNK_SIZE_M)
	)
	for cx: int in range(min_chunk.x, max_chunk.x + 1):
		for cy: int in range(min_chunk.y, max_chunk.y + 1):
			for cz: int in range(min_chunk.z, max_chunk.z + 1):
				var ck := Vector3i(cx, cy, cz)
				if not _beds_by_chunk.has(ck):
					_beds_by_chunk[ck] = []
				(_beds_by_chunk[ck] as Array).append(world_pos)
	emit_signal("bed_registered", world_pos)


## Remove a builder-bed from the chunk-keyed bed index.
## Symmetric with register_bed: removes from all chunks the bubble intersects.
## Uses distance-squared approximate equality (float positions are never exactly equal).
## @param world_pos  The world-space position of the bed to remove.
func unregister_bed(world_pos: Vector3) -> void:
	# Remove from flat list.
	for i: int in range(_all_beds.size() - 1, -1, -1):
		if _all_beds[i].distance_squared_to(world_pos) < 0.01:
			_all_beds.remove_at(i)
			break

	# Remove from chunk index across the same bubble envelope.
	var min_chunk := Vector3i(
		floori((world_pos.x - BED_BUBBLE_RADIUS_M) / CHUNK_SIZE_M),
		floori((world_pos.y - BED_BUBBLE_RADIUS_M) / CHUNK_SIZE_M),
		floori((world_pos.z - BED_BUBBLE_RADIUS_M) / CHUNK_SIZE_M)
	)
	var max_chunk := Vector3i(
		floori((world_pos.x + BED_BUBBLE_RADIUS_M) / CHUNK_SIZE_M),
		floori((world_pos.y + BED_BUBBLE_RADIUS_M) / CHUNK_SIZE_M),
		floori((world_pos.z + BED_BUBBLE_RADIUS_M) / CHUNK_SIZE_M)
	)
	for cx: int in range(min_chunk.x, max_chunk.x + 1):
		for cy: int in range(min_chunk.y, max_chunk.y + 1):
			for cz: int in range(min_chunk.z, max_chunk.z + 1):
				var ck := Vector3i(cx, cy, cz)
				if _beds_by_chunk.has(ck):
					var arr: Array = _beds_by_chunk[ck] as Array
					for j: int in range(arr.size() - 1, -1, -1):
						if (arr[j] as Vector3).distance_squared_to(world_pos) < 0.01:
							arr.remove_at(j)
					if arr.is_empty():
						_beds_by_chunk.erase(ck)
	emit_signal("bed_unregistered", world_pos)


## Returns true if world_pos is within BED_BUBBLE_RADIUS_M of any registered bed.
## O(beds-in-this-chunk) per RESEARCH Pitfall 5 — chunk-keyed lookup avoids O(N×M) naïve scan.
## @param world_pos  The spawn candidate position to test.
func is_inside_any_bed_bubble(world_pos: Vector3) -> bool:
	var ck := _chunk_of(world_pos)
	if not _beds_by_chunk.has(ck):
		return false
	var beds: Array = _beds_by_chunk[ck] as Array
	var r2: float = BED_BUBBLE_RADIUS_M * BED_BUBBLE_RADIUS_M
	for bed: Vector3 in beds:
		if bed.distance_squared_to(world_pos) < r2:
			return true
	return false


## Returns the count of active hostile mobs within BED_BUBBLE_RADIUS_M of bed_pos.
## Called during sleep-lapse ticks to detect unsafe-sleep conditions (RESEARCH Pitfall 9).
## @param bed_pos  World position of the bed whose bubble to scan.
func hostiles_inside_bed_bubble(bed_pos: Vector3) -> int:
	var r2: float = BED_BUBBLE_RADIUS_M * BED_BUBBLE_RADIUS_M
	var count: int = 0
	for mob in _active_mobs:
		if is_instance_valid(mob) and (mob as Node3D).global_position.distance_squared_to(bed_pos) < r2:
			count += 1
	return count

# ─── Public API — Active-mob bookkeeping ──────────────────────────────────────

## Called by HostileMob._ready() when a mob enters the scene tree.
## Increments the per-chunk count and emits hostile_spawned.
func notify_spawned(mob: Node) -> void:
	if not _active_mobs.has(mob):
		_active_mobs.append(mob)
	if mob is Node3D:
		var ck := _chunk_of((mob as Node3D).global_position)
		_active_per_chunk[ck] = _active_per_chunk.get(ck, 0) + 1
		# Record the spawn chunk on the mob so notify_despawned uses the same key
		# even if the mob has moved to a different chunk before dying.
		mob.set_meta("_spawn_chunk", ck)
	emit_signal("hostile_spawned", mob, (mob as Node3D).global_position if mob is Node3D else Vector3.ZERO)


## Called by HostileMob._exit_tree() when a mob leaves the scene tree.
## Decrements the per-chunk count and emits hostile_despawned.
func notify_despawned(mob: Node) -> void:
	_active_mobs.erase(mob)
	if mob.has_meta("_spawn_chunk"):
		# Use the chunk recorded at spawn time, not the current position,
		# to avoid counter desync when mobs cross chunk boundaries before dying.
		var ck: Vector3i = mob.get_meta("_spawn_chunk") as Vector3i
		var current: int = _active_per_chunk.get(ck, 0)
		if current > 0:
			_active_per_chunk[ck] = current - 1
		elif _active_per_chunk.has(ck):
			_active_per_chunk.erase(ck)
	elif mob is Node3D:
		# Fallback for mobs spawned before this fix: use current position.
		var ck := _chunk_of((mob as Node3D).global_position)
		var current: int = _active_per_chunk.get(ck, 0)
		if current > 0:
			_active_per_chunk[ck] = current - 1
		elif _active_per_chunk.has(ck):
			_active_per_chunk.erase(ck)
	emit_signal("hostile_despawned", mob)


## Despawn every active hostile mob (used by the bed sleep cutscene — "night creatures
## are gone" on waking). Frees each mob; their _exit_tree → notify_despawned cleans up
## the bookkeeping. Iterates a copy since queue_free mutates _active_mobs.
func despawn_all_hostiles() -> void:
	for mob: Variant in _active_mobs.duplicate():
		if is_instance_valid(mob):
			(mob as Node).queue_free()


## Returns the total number of active hostile mobs tracked by this autoload.
func get_active_count() -> int:
	return _active_mobs.size()

# ─── Public API — Spawn-candidate eligibility ─────────────────────────────────

## Returns true if a candidate world position is eligible for hostile spawning.
## Gates: bed-bubble exclusion, light-level / nighttime check.
## Does NOT check the per-chunk cap (call can_spawn_in_chunk() for that).
## @param world_pos     Candidate spawn position.
## @param ambient_light Normalised ambient light at the position [0.0, 1.0].
func is_eligible_spawn_position(world_pos: Vector3, ambient_light: float) -> bool:
	# Gate 1 — bed-bubble exclusion (D-10).
	if is_inside_any_bed_bubble(world_pos):
		return false
	# Gate 2 — light-level gate (DOCS §5.3): must be deep-dark (ambient_light < 0.1)
	# OR nighttime per WorldClock.is_night().
	if not WorldClock.is_deep_dark(world_pos, ambient_light):
		if not WorldClock.is_night():
			return false
	return true


## Returns true if an additional hostile can be spawned in the given chunk
## (i.e. the active count is below the cap).
## @param chunk_coord  The chunk to check.
func can_spawn_in_chunk(chunk_coord: Vector3i) -> bool:
	var active: int = _active_per_chunk.get(chunk_coord, 0)
	return active < _hostile_cap()


## Increment the active hostile count for a chunk by ID (test helper).
## Called internally and from tests via _register_hostile_in_chunk().
## @param chunk_coord  Chunk to increment.
## @param _mob_id      Unused in v1; kept for test-readability and future debug tooling.
func _register_hostile_in_chunk(chunk_coord: Vector3i, _mob_id: String) -> void:
	_active_per_chunk[chunk_coord] = _active_per_chunk.get(chunk_coord, 0) + 1


## Reset the active-hostile count for a chunk (test helper).
## @param chunk_coord  Chunk to clear.
func reset_chunk_count(chunk_coord: Vector3i) -> void:
	_active_per_chunk.erase(chunk_coord)


## Seed the spawn-kind RNG from the world seed so kind selection is deterministic
## per world + tick sequence. Call this once after a world is opened or created.
## @param world_seed  Integer seed from WorldSave.world_seed.
func seed_from_world(world_seed: int) -> void:
	_kind_rng.seed = world_seed
	_spawn_tick_seq = 0


## Trigger one spawn tick immediately (test hook and for systems that want explicit control).
## In production, _process fires this at 1 Hz; tests call it directly.
## Early-returns in sandbox mode (mirrors _process gate per D-01 + DOCS §5.1).
func try_spawn_tick() -> void:
	if not _is_survival_mode():
		return
	_run_spawn_tick()

# ─── Public API — Chunk-range clearing ────────────────────────────────────────

## Queue-free every active hostile within radius_chunks chunks of centre_chunk.
## Used by the Tier-3 sleep fallback per RESEARCH Code Examples L507 (D-12).
## @param centre_chunk   The centre chunk (typically the builder's current chunk).
## @param radius_chunks  Cube half-extent in chunks (usually 1).
func clear_hostiles_in_chunk_range(centre_chunk: Vector3i, radius_chunks: int) -> void:
	var to_free: Array = []
	for mob in _active_mobs:
		if not is_instance_valid(mob):
			continue
		if mob is Node3D:
			var mob_chunk := _chunk_of((mob as Node3D).global_position)
			var diff := mob_chunk - centre_chunk
			if (abs(diff.x) <= radius_chunks and abs(diff.y) <= radius_chunks
					and abs(diff.z) <= radius_chunks):
				to_free.append(mob)
	for mob in to_free:
		if is_instance_valid(mob):
			(mob as Node).queue_free()

# ─── Public API — Cap override (adaptive-quality) ─────────────────────────────

## Override the per-chunk hostile cap. Used by main_scene adaptive-quality dispatch
## (Plan 03-10 wires hostile_mob_active_cap; Tier-3 may set to 6).
## Pass -1 to revert to MAX_HOSTILES_PER_CHUNK_DEFAULT.
## @param cap  New cap value, or -1 to use the default.
func set_hostile_mob_cap_override(cap: int) -> void:
	_hostile_mob_cap_override = cap

# ─── Public API — Sleep-lapse hostile-in-bubble event ────────────────────────

## Called by Plan 03-04 Builder.sleep_interact to begin monitoring a bed bubble
## during a sleep lapse. Adds the bed position to the active-sleep-bubbles list.
## Plan 03-04 also polls hostiles_inside_bed_bubble() directly each physics tick.
func register_active_sleep_bubble(bed_pos: Vector3) -> void:
	if not _active_sleep_bubbles.has(bed_pos):
		_active_sleep_bubbles.append(bed_pos)


## Remove a bed position from active-sleep monitoring (when lapse ends).
func unregister_active_sleep_bubble(bed_pos: Vector3) -> void:
	_active_sleep_bubbles.erase(bed_pos)


## Called when a hostile mob has entered a bed bubble during sleep.
## Cancels any active sleep lapse via WorldClock (RESEARCH Pitfall 9 mitigation).
## @param _bed_pos    The bed whose bubble was violated.
## @param _mob_id     Debug identifier of the entering mob.
func _on_hostile_entered_bed_bubble(_bed_pos: Vector3, _mob_id: String) -> void:
	# Cancel the sleep lapse on WorldClock if one is active.
	if WorldClock.has_method("cancel_sleep_lapse"):
		WorldClock.cancel_sleep_lapse("cancelled_unsafe")

# ─── Public API — Test hooks ──────────────────────────────────────────────────

## Test-mode override. Mirrors Inventory + ToolWear test hook pattern.
## @param mode  "survival", "sandbox", or "" (use Features.is_survival_mode()).
func _test_set_mode_override(mode: String) -> void:
	_test_mode_override = mode

# ─── Private helpers ──────────────────────────────────────────────────────────

## Returns true if the game is currently in survival mode.
## Respects the test-mode override first, then delegates to Features.is_survival_mode().
func _is_survival_mode() -> bool:
	if not _test_mode_override.is_empty():
		return _test_mode_override == "survival"
	return Features.is_survival_mode()


## Returns the effective per-chunk hostile cap.
## Returns the override if one is set; otherwise MAX_HOSTILES_PER_CHUNK_DEFAULT.
func _hostile_cap() -> int:
	if _hostile_mob_cap_override >= 0:
		return _hostile_mob_cap_override
	return MAX_HOSTILES_PER_CHUNK_DEFAULT


## Map a world position to its chunk coordinate.
## Floor-divides each axis by CHUNK_SIZE_M.
func _chunk_of(world_pos: Vector3) -> Vector3i:
	return Vector3i(
		floori(world_pos.x / CHUNK_SIZE_M),
		floori(world_pos.y / CHUNK_SIZE_M),
		floori(world_pos.z / CHUNK_SIZE_M)
	)


## Called by _process() at ~1 Hz when in survival mode.
## Enumerates spawn candidates near the builder and gates them through all rules.
## Emits should_spawn(kind, position) for eligible candidates.
## Plan 03-10 connects should_spawn to main_scene.spawn_hostile_mob.
func _run_spawn_tick() -> void:
	# Find the builder node to determine the centre chunk.
	var builder_node: Node3D = get_tree().get_first_node_in_group("builder") as Node3D
	if builder_node == null:
		return

	# Global ceiling: stop spawning once the world already holds the max active hostiles.
	# This is the real bound on night density — the per-chunk cap alone, applied across the
	# 3×3 sweep, would let 25-90 mobs accumulate near spawn.
	if get_active_count() >= MAX_ACTIVE_HOSTILES_GLOBAL:
		return

	var builder_pos: Vector3 = builder_node.global_position
	var centre_chunk := _chunk_of(builder_pos)
	var ambient_light: float = 1.0  # Default: daytime (high light → no spawns).

	# Try to read ambient light from MainScene.world_light_at() if available.
	var main_scene: Node = get_tree().root.get_node_or_null("/root/MainScene")
	if main_scene and main_scene.has_method("world_light_at"):
		ambient_light = main_scene.world_light_at(builder_pos)

	# Mob kinds available for spawning (Plan 03-10 replaces this with a weighted table).
	var spawn_kinds: Array[String] = [
		"laser_penguin", "ghost", "vampire", "bat", "cube_slime", "wolf",
		# art-figures sheet 3 humanoid melee hostiles (Meshy).
		"zombie", "skeleton", "goblin", "orc"
	]

	# Enumerate candidate positions around the centre chunk.
	for dx: int in range(-1, 2):
		for dz: int in range(-1, 2):
			var candidate_chunk := Vector3i(centre_chunk.x + dx, centre_chunk.y, centre_chunk.z + dz)
			# Skip if this chunk is at or above the per-chunk cap.
			if not can_spawn_in_chunk(candidate_chunk):
				continue
			# Generate ~8 candidate spawn positions around the chunk centre.
			var chunk_centre_world := Vector3(
				(candidate_chunk.x as float + 0.5) * CHUNK_SIZE_M,
				builder_pos.y,
				(candidate_chunk.z as float + 0.5) * CHUNK_SIZE_M
			)
			var grid_offsets: Array[Vector2] = [
				Vector2(-4, -4), Vector2(0, -4), Vector2(4, -4),
				Vector2(-4, 0),                  Vector2(4, 0),
				Vector2(-4, 4),  Vector2(0, 4),  Vector2(4, 4)
			]
			for offset: Vector2 in grid_offsets:
				var candidate := chunk_centre_world + Vector3(offset.x, 0.0, offset.y)
				# Gate 1: bed-bubble exclusion (D-10).
				if is_inside_any_bed_bubble(candidate):
					continue
				# Gate 2: light-level + night gate (DOCS §5.3).
				if not is_eligible_spawn_position(candidate, ambient_light):
					continue
				# Gate 3: Inventory.get_chest() — suppress over locked chests.
				# Per 03-PATTERNS.md L1038: locked chest tile = player-built boundary.
				if _is_locked_chest_at(candidate_chunk):
					continue
				# All gates passed: emit deferred spawn signal.
				# Plan 03-10 connects this to main_scene.spawn_hostile_mob.
				# Use seeded RNG so kind selection is deterministic per world+tick (WR-01).
				var kind: String = spawn_kinds[_kind_rng.randi() % spawn_kinds.size()]
				_spawn_tick_seq += 1
				emit_signal("should_spawn", kind, candidate)
				# Only one spawn attempt per chunk per tick to respect the cap.
				break


## Returns true if Inventory reports a locked chest at the given chunk coordinate.
## Suppresses spawn attempts over player-built locked-chest tiles (03-PATTERNS.md L1038).
func _is_locked_chest_at(chunk_coord: Vector3i) -> bool:
	# Delegate to Inventory if available (load-order: Inventory initialises before Spawning).
	if not Inventory.has_method("get_chest_state"):
		return false
	var chest_data: Dictionary = Inventory.get_chest_state(chunk_coord)
	return not chest_data.is_empty() and chest_data.get("locked", false)


## Signal handler: WorldClock.sleep_lapse_ended — clear active sleep bubbles on wakeup.
func _on_sleep_lapse_ended(_reason: String) -> void:
	_active_sleep_bubbles.clear()
