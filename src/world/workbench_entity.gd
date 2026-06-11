# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# workbench_entity.gd — Placed workbench entity: walk-up interact, opens 3×3 crafting panel.
#
# Placed as a StaticBody3D in the world. On _ready, registers itself in the "workbench_entity"
# group so the slide-in can locate it (if needed). Walk-up interact opens
# InventorySlideIn.open_workbench_mode() — the same pattern as ChestEntity from Plan 03-06.
#
# Walk-up + interact pattern (03-PATTERNS.md L913-941):
#   Each WorkbenchEntity polls Input.is_action_just_pressed("ui_inventory_toggle") (E key)
#   in _process when a builder is within INTERACT_RANGE_M. On positive: opens the slide-in
#   workbench panel AND calls get_viewport().set_input_as_handled() so Builder._unhandled_input
#   does NOT also open the inventory on the same frame.
#
# Workbench ID:
#   _workbench_id = "workbench_%d_%d_%d" % [chunk.x, chunk.y, chunk.z]
#   — stable across sessions (same as chest_id convention from Plan 03-06).
#
# Break behaviour:
#   on_break() drops the workbench brick itself as a DroppedItem (no contents to spread;
#   workbenches are stateless — they don't store items).
#
# Threat mitigations:
#   T-03-07b-UI-03: _workbench_panel_instance is reused on subsequent opens (constructed once,
#                   hidden/shown); leak prevented by InventorySlideIn._return_to_inventory_mode.
#
# References:
#   03-CONTEXT.md D-06 — workbench walk-up + interact + close on E/Esc/tap-outside
#   03-UI-SPEC.md L189 — workbench walk-up prompt
#   03-PATTERNS.md L946-947 — WorkbenchEntity analog: same shape as ChestEntity
#   DOCS.md §4.5 — workbench places as a brick; enables 3×3 crafting surface

class_name WorkbenchEntity
extends StaticBody3D

# ─── Constants ────────────────────────────────────────────────────────────────

## Walk-up interact range in metres (UI-SPEC L76 — same as ChestEntity).
const INTERACT_RANGE_M: float = 2.0

## Chunk size in metres — matches ChestEntity + Spawning autoload.
const CHUNK_SIZE_M: int = 16

# ─── Node references ─────────────────────────────────────────────────────────

@onready var _mesh: MeshInstance3D = $Mesh
@onready var _prompt_label: Label3D = $WalkupPrompt

# ─── State ────────────────────────────────────────────────────────────────────

## Back-reference to the main scene for spawn_dropped_item calls on break.
var _main_scene: Node = null

## Stable workbench identifier, keyed to chunk coord.
var _workbench_id: String = ""

## Whether a builder is currently within INTERACT_RANGE_M.
var _builder_in_range: bool = false

# ─── Lifecycle ────────────────────────────────────────────────────────────────

func _ready() -> void:
	# Compute chunk coordinate and stable workbench_id.
	var chunk: Vector3i = _world_to_chunk(global_position)
	_workbench_id = "workbench_%d_%d_%d" % [chunk.x, chunk.y, chunk.z]

	# Add to group so slide-in + other systems can locate workbench entities.
	add_to_group("workbench_entity")

	# Initialise walk-up prompt label.
	if _prompt_label != null:
		_prompt_label.visible = false
		_prompt_label.text = tr("ui.workbench.open_prompt")

	_apply_model()


## Swap the placeholder box for the textured workbench model (art pass). Falls back to the
## placeholder when the model is absent (headless/CI).
func _apply_model() -> void:
	var path := "res://assets/meshes/furniture/workbench.glb"
	if not ResourceLoader.exists(path):
		return
	var m := (load(path) as PackedScene).instantiate() as Node3D
	if m == null:
		return
	add_child(m)
	var ab: AABB = _furniture_aabb(m)
	var sc: float = 1.0 / maxf(ab.size.y, 0.01)  # ~1 m tall workbench
	m.scale = Vector3(sc, sc, sc)
	m.position = Vector3(-ab.get_center().x * sc, -ab.position.y * sc, -ab.get_center().z * sc)
	if _mesh != null:
		_mesh.visible = false


## Merged local-space AABB of every MeshInstance3D under `root` (static mesh, valid now).
func _furniture_aabb(root: Node3D) -> AABB:
	var out := AABB()
	var first := true
	var inv: Transform3D = root.global_transform.affine_inverse()
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			var a: AABB = (inv * (n as MeshInstance3D).global_transform) * (n as MeshInstance3D).mesh.get_aabb()
			if first:
				out = a
				first = false
			else:
				out = out.merge(a)
		for c: Node in n.get_children():
			stack.push_back(c)
	return out


## Set the main scene back-reference (mirrors ChestEntity.set_main_scene pattern).
## Called by main_scene.spawn_workbench immediately after instantiation.
func set_main_scene(scene: Node) -> void:
	_main_scene = scene

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

	# Input is handled in _unhandled_key_input below — NOT here — so that
	# get_viewport().set_input_as_handled() actually prevents Builder._unhandled_input
	# from also firing on the same E press (Input.is_action_just_pressed polling
	# bypasses the event system, making set_input_as_handled a no-op).


func _unhandled_key_input(event: InputEvent) -> void:
	if not _builder_in_range:
		return
	# WoW-style scheme: walk-up entities respond to "interact" (Left Shift).
	if not event.is_action_pressed("interact"):
		return
	var builder: Node3D = get_tree().get_first_node_in_group("builder") as Node3D
	if builder == null:
		return
	_open_panel(builder)
	get_viewport().set_input_as_handled()

# ─── Private helpers ──────────────────────────────────────────────────────────

## Open the slide-in workbench panel for this workbench.
func _open_panel(_builder: Node) -> void:
	var slide_in: Node = get_tree().get_first_node_in_group("inventory_slide_in")
	if slide_in == null:
		return
	if not slide_in.has_method("open_workbench_mode"):
		return

	slide_in.open_workbench_mode(_workbench_id)


## Convert world position to chunk coordinate (CHUNK_SIZE_M = 16 m per Spawning autoload).
func _world_to_chunk(world_pos: Vector3) -> Vector3i:
	return Vector3i(
		int(floor(world_pos.x / float(CHUNK_SIZE_M))),
		int(floor(world_pos.y / float(CHUNK_SIZE_M))),
		int(floor(world_pos.z / float(CHUNK_SIZE_M)))
	)

# ─── Public API ───────────────────────────────────────────────────────────────

## Called when the brick building system breaks this workbench (Phase 2 break pipeline).
## Drops the workbench brick as a DroppedItem and frees this node.
## Workbenches are stateless — they don't store items, so no contents to drop.
func on_break() -> void:
	if _main_scene != null and _main_scene.has_method("spawn_dropped_item"):
		_main_scene.spawn_dropped_item(
			"workbench",
			0,
			global_position + Vector3(0.0, 0.5, 0.0),
			true
		)
	queue_free()
