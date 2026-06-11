# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# world_structure.gd — A scattered biome landmark building (windmill, lighthouse, castle,
# ruins, …) from the art-structures set.
#
# Spawned rarely by main_scene._dispatch_structures via StructureSpawner. Loads the model
# named by structure_id from assets/meshes/structures/, scales its longest axis to
# TARGET_SIZE_M, grounds its base at the entity origin, and generates trimesh collision so
# the builder can't walk through it. Purely a world prop — no interaction.
#
# References:
#   src/world/structure_spawner.gd — per-chunk spawn helper
#   src/world/crop.gd              — sibling spawn-entity pattern

class_name WorldStructure
extends Node3D

const _MODEL_DIR: String = "res://assets/meshes/structures/"

## Longest-axis world size (m) every structure is scaled to (big, walkable-up-to landmarks).
## Bumped 6 -> 10 (v1.1 QA): castle tower / igloo / generic landmarks read too small.
const TARGET_SIZE_M: float = 10.0

## Per-structure size override (longest-axis metres). Ocean structures (lighthouse, ship-
## wreck) were dwarfed at 6 m — a shipwreck should read as a big landmark. Keyed by the
## model id (file name without .glb).
const SIZE_OVERRIDE: Dictionary = {
	"structure_1_03": 28.0,  # OCEAN lighthouse — big + walkable to the top (v1.1 QA #18)
	"structure_3_02": 16.0,  # OCEAN landmark
	"structure_ice_castle": 22.0,  # SNOW ice castle landmark (wired in v1.1)
}

## Model id (file name without .glb); set by main_scene.spawn_structure before add_child.
@export var structure_id: String = ""

## Optional pre-loaded scene. When the proximity streamer hands us an already-(thread-)loaded
## PackedScene we instantiate THAT instead of load()ing by id on the main thread — that's
## what makes streaming freeze-free. Falls back to load()-by-id (pre-stamp / tests).
@export var preloaded_scene: PackedScene = null


func _ready() -> void:
	add_to_group("structure")
	var ps: PackedScene = preloaded_scene
	if ps == null:
		var path: String = _MODEL_DIR + structure_id + ".glb"
		if not ResourceLoader.exists(path):
			return
		ps = load(path) as PackedScene
	if ps == null:
		return
	var m := ps.instantiate() as Node3D
	if m == null:
		return
	add_child(m)
	var ab: AABB = _aabb(m)
	var longest: float = maxf(ab.size.x, maxf(ab.size.y, ab.size.z))
	var target: float = float(SIZE_OVERRIDE.get(structure_id, TARGET_SIZE_M))
	var sc: float = target / maxf(longest, 0.01)
	m.scale = Vector3(sc, sc, sc)
	# Ground the base at y=0, centre on X/Z.
	m.position = Vector3(-ab.get_center().x * sc, -ab.position.y * sc, -ab.get_center().z * sc)
	# Trimesh (concave) collision that follows the actual geometry, so the builder can walk UP
	# TO and INSIDE hollow structures through their doorways — a box collider sealed them off.
	# The earlier freeze was the synchronous GLB *decode* on chunk-load; that's now done off the
	# main thread by the proximity streamer, so the trimesh build (deferred a frame to spread it)
	# is a manageable per-structure cost rather than a hard stall.
	call_deferred("_build_collision", m)


## Build trimesh collision for EVERY MeshInstance3D under the model, recursively, so the
## full geometry is collidable — tall multi-mesh towers (interior stairs/ramps) included,
## not just the first/root mesh.
##
## find_children(owned=false) is required: an instantiated .glb scene's mesh nodes are owned
## by the .glb root, not by `m`, so owned=true would miss every sub-mesh. owned=false walks
## the whole subtree and create_trimesh_collision() builds concave collision in each mesh's
## local space, which inherits `m`'s scale via the node transform chain — so the collision
## tracks the scaled-up geometry exactly (v1.1 QA #18: lighthouse walkable to the top).
##
## Note: a single-mesh model (e.g. the lighthouse, one mesh) is fully covered by this loop —
## the single MeshInstance3D still gets trimesh collision following its whole surface. If a
## structure has no modeled interior (a solid exterior shell), there is simply nothing inside
## to climb; the collision build is still correct and complete.
func _build_collision(m: Node3D) -> void:
	if not is_instance_valid(m):
		return
	for child: Node in m.find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		# Skip empty MeshInstance3D nodes — create_trimesh_collision() on a null mesh
		# logs an error and adds an empty StaticBody. Matches the _aabb() null guard.
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
