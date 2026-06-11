# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# crop.gd — Generic harvestable crop collectible (wheat, sugar_cane).
#
# Mirrors the strawberry pickup pattern but is kind-parameterised and lighter-weight:
#   - crop_kind is the BrickRegistry def_id (also the model file name in assets/meshes/crops/).
#   - Walk within INTERACT_RANGE_M → harvest prompt; Shift (sleep_interact) → +1 of crop_kind
#     to the builder's inventory, then queue_free.
#   - No WorldSave persistence: main_scene's per-chunk dedup cache prevents same-session
#     respawn (same model as the flower/foliage dispatch); crops repopulate on reload.
#
# Spawned by main_scene._dispatch_crops() via CropSpawner. Visual-only collision
# (layer/mask 0) so it never blocks the builder.
#
# References:
#   src/world/strawberry.gd      — collectible pattern this generalises
#   src/world/crop_spawner.gd     — per-chunk spawn helper
#   assets/meshes/crops/<kind>.glb — the textured crop model

class_name Crop
extends StaticBody3D

## Walk-up interact range in metres (mirrors Strawberry / ChestEntity).
const INTERACT_RANGE_M: float = 2.0

## Directory holding crop models (file name == crop_kind).
const _MODEL_DIR: String = "res://assets/meshes/crops/"

## Per-kind display height (m) the model is scaled to.
const _MODEL_HEIGHT_M: Dictionary = {"wheat": 0.7, "sugar_cane": 1.0}
const _DEFAULT_HEIGHT_M: float = 0.7

## BrickRegistry def_id of this crop; set by main_scene.spawn_crop before add_child.
@export var crop_kind: String = "wheat"

var _builder_in_range: bool = false
var _prompt: Label3D = null


func _ready() -> void:
	add_to_group("crop")
	collision_layer = 0
	collision_mask = 0
	_build_collision()
	_apply_model()
	_build_prompt()


func _build_collision() -> void:
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.5, 0.8, 0.5)
	cs.shape = box
	cs.position = Vector3(0.0, 0.4, 0.0)
	add_child(cs)


func _apply_model() -> void:
	var path: String = _MODEL_DIR + crop_kind + ".glb"
	if not ResourceLoader.exists(path):
		return
	var m := (load(path) as PackedScene).instantiate() as Node3D
	if m == null:
		return
	add_child(m)
	var ab: AABB = _model_aabb(m)
	var target: float = float(_MODEL_HEIGHT_M.get(crop_kind, _DEFAULT_HEIGHT_M))
	var sc: float = target / maxf(ab.size.y, 0.01)
	m.scale = Vector3(sc, sc, sc)
	# Feet at the entity origin (y=0), centred on X/Z.
	m.position = Vector3(-ab.get_center().x * sc, -ab.position.y * sc, -ab.get_center().z * sc)


func _build_prompt() -> void:
	_prompt = Label3D.new()
	_prompt.text = tr("ui.crop.harvest_prompt")
	_prompt.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_prompt.font_size = 20
	_prompt.position = Vector3(0.0, 1.0, 0.0)
	_prompt.visible = false
	add_child(_prompt)


func _process(_delta: float) -> void:
	var builder: Node3D = get_tree().get_first_node_in_group("builder") as Node3D
	if builder == null:
		return
	var in_range: bool = global_position.distance_to(builder.global_position) <= INTERACT_RANGE_M
	if in_range != _builder_in_range:
		_builder_in_range = in_range
		if _prompt != null:
			_prompt.visible = in_range
	if in_range and Input.is_action_just_pressed("sleep_interact"):
		_harvest(builder)
		get_viewport().set_input_as_handled()


## Harvest: add 1 of crop_kind to the builder's inventory and consume the entity.
func _harvest(builder: Node) -> void:
	var builder_id: String = ""
	if builder.has_method("get_stable_builder_id"):
		builder_id = builder.get_stable_builder_id()
	var ok: bool = Inventory.apply_event({
		"kind": "ADD",
		"builder_id": builder_id,
		"def_id": crop_kind,
		"count": 1,
	})
	if ok:
		queue_free()
	# else: Inventory shows its own ui.inventory.full toast.


## Merged AABB (model-local) of every MeshInstance3D under `root` — static mesh, valid now.
func _model_aabb(root: Node3D) -> AABB:
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
