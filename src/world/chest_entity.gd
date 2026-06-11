# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# chest_entity.gd — Placed chest entity: walk-up interact, lock/unlock UX, double-chest pairing.
#
# Placed as a StaticBody3D in the world. On _ready, registers itself with the Inventory autoload
# and scans for adjacent same-tier neighbours to form double-chest pairs.
#
# Walk-up + interact pattern (03-PATTERNS.md L913-941):
#   Each ChestEntity polls Input.is_action_just_pressed("ui_inventory_toggle") (E key)
#   in _process when a builder is within INTERACT_RANGE_M. On positive: opens the slide-in
#   chest panel AND calls get_viewport().set_input_as_handled() so Builder._unhandled_input
#   does NOT also open the inventory on the same frame.
#
# Double-chest pairing (DOCS §4.4 + D-02):
#   On _ready, queries Inventory for adjacent (±X, ±Z) same-tier chests with no existing
#   partner. First match → link via Inventory.set_double_chest_partner(). Only the
#   lexicographically-smaller coord initiates the link to prevent both halves racing.
#
# Break behaviour (DOCS §4.4 + UI-SPEC L270):
#   on_break() iterates Inventory.get_chest_contents() and drops each item as a DroppedItem
#   via main_scene.spawn_dropped_item(). If part of a double-chest, only the items belonging
#   to this half drop (indices 0..half_capacity-1); partner retains the rest.
#
# Chest-id stability (03-PATTERNS.md L941):
#   _chest_id = "chest_%d_%d_%d" % [chunk.x, chunk.y, chunk.z] where chunk is computed from
#   global_position using CHUNK_SIZE_M = 16 (matching Spawning autoload + terrain chunk size).
#
# Threat mitigations:
#   T-03-06-CH-01: UNLOCK key-tier validation is entirely in Inventory._apply_unlock (Pitfall 6).
#                  ChestEntity.unlock() merely passes the event; it does NOT validate here.
#   T-03-06-CH-02: _check_for_double_chest_partner() short-circuits on first unpaired same-tier
#                  neighbour found; subsequent neighbours fail the partner check and stay singletons.
#   T-03-06-CH-05: _process polling guards on _builder_in_range to minimise redundant distance ops.
#
# References:
#   DOCS.md §4.4 — 5 chest types, 4 key types, double chests, break drops
#   03-CONTEXT.md D-02 — chest UI two stacked grids + key slot
#   03-CONTEXT.md D-03 — 5 silhouettes (placeholder mesh until art pass)
#   03-CONTEXT.md D-04 — keys are found-only loot; consumed on first unlock
#   03-PATTERNS.md L900-941 — ChestEntity walk-up + interact pattern
#   03-UI-SPEC.md L76 — walk-up prompt 1.5 m above mesh, billboarded
#   03-UI-SPEC.md L190-191 — chest walk-up prompt strings
#   03-UI-SPEC.md L267-270 — unlock animation is the commit moment; key fades 200 ms; break drops

class_name ChestEntity
extends StaticBody3D

# ─── Constants ────────────────────────────────────────────────────────────────

## Walk-up interact range in metres (UI-SPEC L76).
const INTERACT_RANGE_M: float = 2.0

## Chunk size in metres — matches Spawning autoload and terrain chunk size.
const CHUNK_SIZE_M: int = 16

## Slot counts per chest tier (DOCS §4.4).
const SLOT_COUNTS: Dictionary = {
	"regular": 48,
	"bronze":  48,
	"silver":  54,
	"gold":    60,
	"diamond": 72,
}

## Required key def_id per chest tier (Pitfall 6 + DOCS §4.4).
## Empty string for "regular" — regular chests have no lock mechanic.
const REQUIRED_KEY: Dictionary = {
	"regular": "",
	"bronze":  "key_bronze",
	"silver":  "key_silver",
	"gold":    "key_gold",
	"diamond": "key_diamond",
}

# ─── Exports ─────────────────────────────────────────────────────────────────

## Chest tier: "regular" | "bronze" | "silver" | "gold" | "diamond".
@export var tier: String = "regular"

## Whether the chest starts locked. Non-regular chests default to locked in loot spawns.
@export var locked: bool = false

## Initial contents — Array of {def_id: String, count: int}.
## Set by main_scene.spawn_chest (Plan 03-08b); default empty (auto-registered empty slots).
@export var initial_contents: Array = []

## If true, register_chest will overwrite any existing saved state for this
## chunk_coord. Used by the starter kit (spawn_starter_chest_and_bed) so that
## fixing the starter contents in code is reflected even on a save that
## previously persisted the wrong def_ids. Player-placed chests leave this
## false so player edits are preserved.
@export var force_replace_on_register: bool = false

# ─── Node references ─────────────────────────────────────────────────────────

@onready var _prompt_label: Label3D = $WalkupPrompt
@onready var _lock_plate: MeshInstance3D = $LockPlate
@onready var _lid_animator: AnimationPlayer = $AnimationPlayer

## Per-tier art meshes (Meshy-generated, split from art-chests.glb). Each is ~0.8 m tall
## with its base at Y=0 and centred, so it drops onto the chest origin at scale 1.
const _TIER_MESH: Dictionary = {
	"regular": "res://assets/meshes/chests/chest_regular.glb",
	"bronze":  "res://assets/meshes/chests/chest_bronze.glb",
	"silver":  "res://assets/meshes/chests/chest_silver.glb",
	"gold":    "res://assets/meshes/chests/chest_gold.glb",
	"diamond": "res://assets/meshes/chests/chest_diamond.glb",
}

# ─── State ────────────────────────────────────────────────────────────────────

## Back-reference to the main scene for spawn_dropped_item calls on break.
var _main_scene: Node = null

## Stable chest identifier, keyed to chunk coord.
var _chest_id: String = ""

## Chunk coordinate of this chest (computed from global_position in _ready).
var _chunk_coord: Vector3i = Vector3i.ZERO

## Chunk coordinate of the double-chest partner (or ZERO if singleton).
var _double_chest_partner_chunk: Vector3i = Vector3i.ZERO

## Whether this chest has a double-chest partner.
var _has_partner: bool = false

## Whether a builder is currently within INTERACT_RANGE_M.
var _builder_in_range: bool = false

# ─── Signals ─────────────────────────────────────────────────────────────────

## Emitted when this chest is opened (before the chest panel is instantiated).
## Used by ftue_overlay.gd to detect FTUE step 1 completion.
signal opened()

## Emitted when this chest's lock is toggled to unlocked.
signal unlocked(chest_id: String)

## Emitted when this chest is broken by the player.
signal broken(chest_id: String, position: Vector3)

# ─── Lifecycle ────────────────────────────────────────────────────────────────

func _ready() -> void:
	# Validate tier at entry; unknown tier falls back to "regular" with a warning.
	if not SLOT_COUNTS.has(tier):
		push_warning("ChestEntity._ready: unknown tier '%s' — treating as 'regular'." % tier)
		tier = "regular"

	# Swap in the Meshy art mesh for this tier (falls back to placeholder boxes if absent).
	_apply_tier_mesh()

	# Compute chunk coordinate and stable chest_id.
	_chunk_coord = _world_to_chunk(global_position)
	_chest_id = "chest_%d_%d_%d" % [_chunk_coord.x, _chunk_coord.y, _chunk_coord.z]

	# Register with Inventory autoload (no-op if already registered via attach_world).
	Inventory.register_chest(_chunk_coord, tier, locked, initial_contents, force_replace_on_register)

	# Add to group so slide-in + other systems can locate chest entities.
	add_to_group("chest_entity")

	# Initialise walk-up prompt label.
	if _prompt_label != null:
		_prompt_label.visible = false
		_update_prompt()

	# Show/hide lock plate.
	if _lock_plate != null:
		_lock_plate.visible = locked

	# Try to pair with an adjacent same-tier chest for double-chest mode.
	_check_for_double_chest_partner()


## Instantiate the tier's art mesh and hide the placeholder primitive boxes. If the art
## isn't present (e.g. headless tests without the asset imported), the placeholders stay.
## v1: chest is shown closed — the lid-open animation drove the placeholder $Lid, which is
## now hidden; the slide-in panel still opens on interact.
func _apply_tier_mesh() -> void:
	var path: String = _TIER_MESH.get(tier, _TIER_MESH["regular"])
	if not ResourceLoader.exists(path):
		return
	var ps: PackedScene = load(path) as PackedScene
	if ps == null:
		return
	var visual: Node = ps.instantiate()
	visual.name = "TierVisual"
	add_child(visual)
	for placeholder: String in ["Mesh", "Lid", "Latch"]:
		var node: Node = get_node_or_null(placeholder)
		if node is GeometryInstance3D:
			(node as GeometryInstance3D).visible = false


## Set the main scene back-reference (mirrors DroppedItem.set_main_scene pattern).
## Called by main_scene.spawn_chest immediately after instantiation.
func set_main_scene(scene: Node) -> void:
	_main_scene = scene


## Convenience setter for initial contents — mirrors @export var initial_contents.
func set_initial_contents(contents: Array) -> void:
	initial_contents = contents.duplicate(true)

# ─── Per-frame polling ────────────────────────────────────────────────────────

func _process(_delta: float) -> void:
	# Locate the local builder (Phase 3 is solo; get_first_node_in_group is deterministic).
	var builder: Node = get_tree().get_first_node_in_group("builder")
	if builder == null:
		return

	var dist: float = global_position.distance_to(builder.global_position)
	var in_range: bool = dist <= INTERACT_RANGE_M

	# Update prompt visibility only when the in-range state changes.
	if in_range != _builder_in_range:
		_builder_in_range = in_range
		if _prompt_label != null:
			_prompt_label.visible = in_range
		_update_prompt()

	# Input is handled in _unhandled_key_input below — NOT in _process — so that
	# get_viewport().set_input_as_handled() actually prevents Builder._unhandled_input
	# from also receiving the same E press. (Polling Input.is_action_just_pressed
	# in _process bypasses the event system, so set_input_as_handled is a no-op
	# and the inventory_toggle_requested signal fires too, opening the regular
	# inventory on top of the chest-mode call.)


func _unhandled_key_input(event: InputEvent) -> void:
	if not _builder_in_range:
		return
	# WoW-style scheme (project.godot): walk-up entities now respond to the
	# "interact" action (Left Shift) rather than ui_inventory_toggle (I).
	if not event.is_action_pressed("interact"):
		return
	var builder: Node3D = get_tree().get_first_node_in_group("builder") as Node3D
	if builder == null:
		return
	_open_panel(builder)
	get_viewport().set_input_as_handled()

# ─── Private helpers ──────────────────────────────────────────────────────────

## Update the walk-up prompt text based on locked state and tier.
func _update_prompt() -> void:
	if _prompt_label == null:
		return
	if locked:
		var key_display_name: String = tr("items.key_" + tier + ".name")
		_prompt_label.text = tr("ui.chest.locked_prompt").format({"key_name": key_display_name})
	else:
		_prompt_label.text = tr("ui.chest.open_prompt")


## Open the slide-in chest panel for this chest.
func _open_panel(_builder: Node) -> void:
	var slide_in: Node = get_tree().get_first_node_in_group("inventory_slide_in")
	if slide_in == null:
		return
	if not slide_in.has_method("open_chest_mode"):
		return

	opened.emit()
	var partner_chunk: Vector3i = _double_chest_partner_chunk if _has_partner else Vector3i.ZERO
	slide_in.open_chest_mode(_chest_id, tier, locked, partner_chunk)


## Try to find an adjacent same-tier ChestEntity that has no partner.
## Links both halves via Inventory.set_double_chest_partner (T-03-06-CH-02: first match wins).
func _check_for_double_chest_partner() -> void:
	var my_chunk: Vector3i = _world_to_chunk(global_position)
	var offsets: Array = [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]

	for offset: Vector3i in offsets:
		var neighbour_chunk: Vector3i = my_chunk + offset
		var neighbour_state: Dictionary = Inventory.get_chest_state(neighbour_chunk)

		if neighbour_state.is_empty():
			continue
		if neighbour_state.get("type", "") != tier:
			continue
		if not neighbour_state.get("double_chest_partner", "").is_empty():
			continue  # Neighbour already has a partner (T-03-06-CH-02 guard).

		# Link the two halves.
		var ok: bool = Inventory.set_double_chest_partner(my_chunk, neighbour_chunk)
		if ok:
			_double_chest_partner_chunk = neighbour_chunk
			_has_partner = true
			break


## Convert world position to chunk coordinate (CHUNK_SIZE_M = 16 m per Spawning autoload).
func _world_to_chunk(world_pos: Vector3) -> Vector3i:
	return Vector3i(
		int(floor(world_pos.x / float(CHUNK_SIZE_M))),
		int(floor(world_pos.y / float(CHUNK_SIZE_M))),
		int(floor(world_pos.z / float(CHUNK_SIZE_M)))
	)

# ─── Public API ───────────────────────────────────────────────────────────────

## Attempt to unlock this chest using a key from the builder's inventory.
## Delegates entirely to Inventory.apply_event(UNLOCK) for validation (Pitfall 6 + T-03-06-CH-01).
##
## @param key_def_id  The item def_id of the key being used (e.g. "key_bronze").
## @param builder_id  The builder UUID.
## @return            true on success; false if wrong tier, already unlocked, or no key.
func unlock(key_def_id: String, builder_id: String) -> bool:
	var ok: bool = Inventory.apply_event({
		"kind":       "UNLOCK",
		"builder_id": builder_id,
		"chest_id":   _chest_id,
		"chest_type": tier,
		"key_def_id": key_def_id,
	})

	if ok:
		locked = false
		if _lock_plate != null:
			_lock_plate.visible = false
		if _lid_animator != null and _lid_animator.has_animation("unlock_lid"):
			_lid_animator.play("unlock_lid")
		_update_prompt()
		unlocked.emit(_chest_id)

	return ok


## Called when the brick building system breaks this chest (Phase 2 break pipeline).
## Drops chest contents as DroppedItems, unregisters from Inventory, and frees this node.
##
## For double-chests: only the items indexed below half_capacity drop from this half;
## the partner half retains its share (proportional split per DOCS §4.4).
func on_break() -> void:
	var half_capacity: int = SLOT_COUNTS.get(tier, 48)

	if _has_partner:
		# Double-chest: items below half_capacity belong to this half (slot index < half_cap).
		# Items at [half_capacity..end) remain in the partner half.
		# Read half contents before unregistering so they can be dropped.
		var contents: Array = Inventory.get_chest_contents(_chunk_coord)
		for i: int in range(mini(half_capacity, contents.size())):
			var entry: Dictionary = contents[i]
			var def_id: String = entry.get("def_id", "")
			var count: int = entry.get("count", 0)
			if def_id.is_empty() or count <= 0:
				continue
			if _main_scene != null and _main_scene.has_method("spawn_dropped_item"):
				_main_scene.spawn_dropped_item(
					def_id,
					0,
					global_position + Vector3(randf_range(-0.5, 0.5), 0.5, randf_range(-0.5, 0.5)),
					true
				)
		# We break the pairing after dropping so the partner becomes standalone.
		Inventory.unregister_chest_half(_chunk_coord)
	else:
		# Single chest: drop all contents.
		var contents: Array = Inventory.get_chest_contents(_chunk_coord)
		for entry: Dictionary in contents:
			var def_id: String = entry.get("def_id", "")
			var count: int = entry.get("count", 0)
			if def_id.is_empty() or count <= 0:
				continue
			if _main_scene != null and _main_scene.has_method("spawn_dropped_item"):
				_main_scene.spawn_dropped_item(
					def_id,
					0,
					global_position + Vector3(randf_range(-0.5, 0.5), 0.5, randf_range(-0.5, 0.5)),
					true
				)
		Inventory.unregister_chest(_chunk_coord)

	broken.emit(_chest_id, global_position)
	queue_free()
