# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# welcome_sign.gd — A purely-decorative "Welcome to Cubicraftia" sign-post.
#
# The text is ENGRAVED into the artwork itself: this entity instances the
# assets/meshes/decor/welcome_post.glb model (a wooden post whose three boards
# read "WELCOME / TO / CUBICRAFTIA"), split from the art-furniture1 set. No
# code-built box/Label3D any more — the wording lives in the baked mesh, so it
# reads consistently across platforms and matches the brick-built art style.
#
# Built entirely in code (no .tscn dependency) so main_scene can spawn it with one call:
#   var sign := WelcomeSign.new(); add_child(sign); sign.global_position = ...
#
# Structure (assembled in _ready, anchored at this Node3D's origin = ground level):
#   - the welcome_post.glb instance, scaled so the post stands ~TARGET_HEIGHT_M tall,
#     grounded so its base sits at this node's origin (y = 0).
#   - a StaticBody3D trimesh collider following the geometry so the player can't walk
#     through it (gives the sign physical heft, like the old code-built post).
#
# The model's boards face +Z in local space (Meshy authored facing). The spawner
# rotates this node 180° (rotation.y = PI) so the engraving points back toward the
# spawn point — a player standing at spawn reads the text head-on.

class_name WelcomeSign
extends Node3D

# ─── Constants ────────────────────────────────────────────────────────────────

## Player-facing game name (intentionally shown to players — see CLAUDE.md). Retained
## as a group-discoverable constant for tests / tooling even though the wording is now
## baked into the mesh.
const SIGN_TEXT: String = "Welcome to Cubicraftia"

## Path to the engraved sign-post model (decor asset, split from art-furniture1.glb).
const _MODEL_PATH: String = "res://assets/meshes/decor/welcome_post.glb"

## Target standing height (m) for the whole post. The raw model is ~0.33 m tall; we
## scale its longest axis (height) to this so the boards sit at a readable adult eye-line.
const TARGET_HEIGHT_M: float = 2.2

# ─── Lifecycle ────────────────────────────────────────────────────────────────

func _ready() -> void:
	add_to_group("welcome_sign")
	if not _build_from_model():
		push_warning("WelcomeSign: '%s' missing — sign not built." % _MODEL_PATH)


# ─── Builder ──────────────────────────────────────────────────────────────────

## Instance the engraved GLB, scale it to TARGET_HEIGHT_M, ground its base at the
## node origin, and build trimesh collision. Returns false if the asset is absent
## (headless/CI without the decor mesh) so the caller can warn.
func _build_from_model() -> bool:
	if not ResourceLoader.exists(_MODEL_PATH):
		return false
	var ps: PackedScene = load(_MODEL_PATH) as PackedScene
	if ps == null:
		return false
	var m := ps.instantiate() as Node3D
	if m == null:
		return false
	add_child(m)

	# Scale the model's height to TARGET_HEIGHT_M and ground its base at y = 0.
	var ab: AABB = _aabb(m)
	var span: float = maxf(ab.size.y, 0.001)
	var sc: float = TARGET_HEIGHT_M / span
	m.scale = Vector3(sc, sc, sc)
	# Centre on X/Z, drop the base (AABB min-Y) to the origin.
	m.position = Vector3(-ab.get_center().x * sc, -ab.position.y * sc, -ab.get_center().z * sc)

	# Trimesh (concave) collision following the geometry so the builder bumps into the
	# post instead of clipping through. Deferred a frame to spread the build cost, mirroring
	# WorldStructure._build_collision.
	call_deferred("_build_collision", m)
	return true


## Build trimesh collision for every MeshInstance3D under the model (recursively).
## find_children(owned=false): the instantiated .glb's mesh nodes are owned by the .glb
## root, not by `m`, so owned=true would miss them.
func _build_collision(m: Node3D) -> void:
	if not is_instance_valid(m):
		return
	for child: Node in m.find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		if mi != null and mi.mesh != null:
			mi.create_trimesh_collision()


## Merged local-space AABB of every MeshInstance3D under `root` (static mesh, valid now).
func _aabb(root: Node3D) -> AABB:
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
