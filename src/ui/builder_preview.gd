# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# builder_preview.gd — avatar-creator preview that shows the SELECTED character's
# textured, rigged skin .glb (the "original builder" look), matching what spawns
# in-world. Picking a builder card swaps the model. (Replaces the earlier voxel
# box-minifig, which didn't read well.)
#
# The avatar_creator rotates this node (rotation.y) for the turntable; apply_avatar_config
# swaps the model on a character change. Per-part colour customisation is limited: the skin
# GLBs are single baked-texture meshes, so skin/outfit/hair swatches don't repaint them —
# the three builder cards are the visible customisation.

extends Node3D

## Character id → rigged skin GLB (mirrors Builder._AVATAR_SKINS).
const AVATAR_SKINS: Dictionary = {
	"builder1": "res://assets/meshes/builder/skin_builder1.glb",
	"red": "res://assets/meshes/builder/skin_red.glb",
	"fem": "res://assets/meshes/builder/skin_fem.glb",
}
const DEFAULT_CHARACTER: String = "builder1"
const AVATAR_CFG_PATH: String = "user://avatar.cfg"
## Rendered height the model is scaled to (fits the creator camera framing).
const TARGET_HEIGHT: float = 2.05

var _glb_root: Node3D = null
var _cur_char: String = ""


func _ready() -> void:
	_load_glb(_read_character())


## Read the saved character id (avatar.cfg "avatar"/"character"); default builder1.
func _read_character() -> String:
	var cfg := ConfigFile.new()
	if cfg.load(AVATAR_CFG_PATH) == OK:
		return str(cfg.get_value("avatar", "character", DEFAULT_CHARACTER))
	return DEFAULT_CHARACTER


## Load (or swap to) a character's skin GLB. Non-fatal on any failure.
func _load_glb(character: String) -> void:
	if character == "":
		character = DEFAULT_CHARACTER
	_cur_char = character
	if _glb_root != null and is_instance_valid(_glb_root):
		_glb_root.queue_free()
	_glb_root = null
	var path: String = str(AVATAR_SKINS.get(character, AVATAR_SKINS.get(DEFAULT_CHARACTER, "")))
	if path == "" or not ResourceLoader.exists(path):
		return
	var packed: Resource = load(path)
	if not (packed is PackedScene):
		return
	var inst: Node = (packed as PackedScene).instantiate()
	if not (inst is Node3D):
		if inst != null:
			inst.queue_free()
		return
	_glb_root = inst as Node3D
	_glb_root.name = "SkinGLB"
	add_child(_glb_root)
	_finalize(_glb_root)


## After the skeleton has posed (a few frames), scale to TARGET_HEIGHT with feet at y=0,
## face the camera (+Z), and settle a rig clip on a natural standing frame.
func _finalize(av: Node3D) -> void:
	for _i in 8:
		await get_tree().process_frame
	if not is_instance_valid(av):
		return
	var ab: AABB = _skinned_aabb(av)
	if ab.size.y > 0.001:
		var sc: float = TARGET_HEIGHT / ab.size.y
		av.scale = Vector3(sc, sc, sc)
		av.position = Vector3(-ab.get_center().x * sc, -ab.position.y * sc, -ab.get_center().z * sc)
	# Skins are authored facing +Z (toward the creator camera) — no flip needed here.
	var ap := av.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if ap != null:
		var clips: PackedStringArray = ap.get_animation_list()
		var pick := ""
		for c in clips:
			var lc := c.to_lower()
			if lc.contains("idle") or lc.contains("walk"):
				pick = c
				break
		if pick == "" and clips.size() > 0:
			pick = clips[0]
		if pick != "":
			ap.play(pick)
			ap.seek(0.25, true)
			ap.pause()  # a natural standing pose; the node itself rotates for the turntable


## Drive point used by avatar_creator: swap the model when the chosen character changes.
## (Colour/hairstyle/accessory keys are accepted but don't repaint the baked-texture GLB.)
func apply_avatar_config(cfg: Dictionary) -> void:
	var character: String = str(cfg.get("character", _cur_char))
	if character != "" and character != _cur_char:
		_load_glb(character)


## Rendered extent from the Skeleton3D bone poses (the rest mesh AABB is a microscopic
## box for these 0.01-scale skinned imports). Falls back to the mesh AABB.
func _skinned_aabb(root: Node3D) -> AABB:
	var sk := root.find_child("Skeleton3D", true, false) as Skeleton3D
	if sk == null or sk.get_bone_count() == 0:
		return _mesh_aabb(root)
	var inv: Transform3D = root.global_transform.affine_inverse()
	var lo := Vector3(1e9, 1e9, 1e9)
	var hi := -lo
	for i in range(sk.get_bone_count()):
		var p: Vector3 = inv * ((sk.global_transform * sk.get_bone_global_pose(i)).origin)
		lo = lo.min(p)
		hi = hi.max(p)
	return AABB(lo, hi - lo)


func _mesh_aabb(root: Node) -> AABB:
	var out := AABB()
	var has := false
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			var w: AABB = (n as MeshInstance3D).global_transform * (n as MeshInstance3D).mesh.get_aabb()
			if not has:
				out = w
				has = true
			else:
				out = out.merge(w)
		for c in n.get_children():
			stack.push_back(c)
	return out
