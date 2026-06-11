# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# brick_definition.gd — BrickDefinition Resource (Plan 05 Task 1 + Plan 02-04 extension).
#
# Stores the identity, geometry metadata, palette info, and mesh reference for a single
# brick type. Stud-anchor data is read from the glTF `extras` dict (Pattern 2 — NOT
# EXT_structural_metadata per RESEARCH.md Pitfall 1 / Assumption A11).
#
# Phase 2 (Plan 02-04) extensions:
#   - Category enum (RECTANGULAR..MOB_DROP) — maps bricks to §3.1 categories (DOCS.md §3.1)
#   - colour_swappable / natural_colour_token — D-02 surface treatment (CONTEXT.md D-02)
#   - palette_colour_index = -1 (placed colour resolved per-instance from StudGrid record)
#   - iap_pack_origin — IAP brick-pack provenance (CONTEXT.md "Brick palette as IAP-pack target")
#   - footprint_cells — multi-cell occupancy for the StudGrid (e.g. 1×4 brick: 4 cells)
#
# stud_profile = "concave_top" invariant: MUST be preserved per CONTEXT.md D-08.
# Never rename, re-order, or remove; downstream trademark buffer depends on it.
#
# Usage:
#   var def := BrickDefinition.from_gltf("res://assets/meshes/brick_1x1.glb")
#   # def.brick_id       == "brick_1x1"
#   # def.dimensions     == Vector3i(1, 1, 1)
#   # def.studs_top      == [{"x":0.0,"y":1.0,"z":0.0,"gender":"male"}]
#   # def.stud_profile   == "concave_top"
#   # def.mesh           is Mesh
#
# RESEARCH.md Assumption A4: extras may land on mesh.get_meta("extras") OR
# mesh_instance.get_meta("extras") depending on Godot's importer version.
# from_gltf() tries both paths (mesh first, then node, then parent).
#
# Implementation note: uses GLTFDocument directly (no editor import required).
# This allows the factory to work in headless tests without a pre-imported .scn.

class_name BrickDefinition
extends Resource

# ─── Category enum ───────────────────────────────────────────────────────────
## Brick category per DOCS.md §3.1 — stable; never re-order (downstream binds to int value).
enum Category {
	RECTANGULAR  = 0,  ## 1×1 to 2×4 standard bricks
	PLATE        = 1,  ## Flat 1-plate-height bricks
	SLOPE        = 2,  ## Angled wedge bricks
	TILE         = 3,  ## Flat, no studs on top
	ROUND        = 4,  ## Cylindrical / circular bricks
	FUNCTIONAL   = 5,  ## Door, window, trapdoor, workbench, chest, wheel
	DECORATIVE   = 6,  ## Flower, lantern, torch, ladder, sign
	MATERIAL_ORE = 7,  ## Terrain material bricks and ore bricks
	ACCESSORY    = 8,  ## Held tools: pickaxe, shovel, sword, dynamite, lantern-handheld
	MOB_DROP     = 9,  ## Items dropped by creatures: bone, slime cube
}

# ─── Exports ─────────────────────────────────────────────────────────────────

## Unique identifier matching cubicraftia.brick_id in the glTF extras.
@export var brick_id: String = ""

## Human-readable display name translation key (e.g. "bricks.brick_1x1.name").
@export var display_name_key: String = ""

## Footprint in stud units (x = width, y = unused/1 for height, z = depth).
@export var dimensions: Vector3i = Vector3i(1, 1, 1)

## Height in plates (1 brick == 3 plates).
@export var height_plates: int = 3

## Male stud anchors on the top face. Each entry is a Dictionary with keys:
## x, y, z (local position), gender ("male").
@export var studs_top: Array = []

## Female stud anchors on the bottom face. Each entry: x, y, z, gender ("female").
@export var studs_bottom: Array = []

## Stud profile. Must be "concave_top" per CONTEXT.md D-08 (locked from Phase 1).
@export var stud_profile: String = "concave_top"

## Material palette identifier (e.g. "plastic_solid"). Per CONTEXT.md D-02.
@export var material_id: String = "plastic_solid"

## Imported mesh from the glTF scene. Used by MultiMeshInstance3D in stud_grid rendering.
@export var mesh: Mesh = null

## Path to the 2D inventory/hotbar icon texture (e.g. art sheet slices in
## res://assets/textures/icons/). "" = no icon yet (falls back to the empty-slot art).
@export var icon_path: String = ""

## Phase 2 — Plan 02-04 new exports ──────────────────────────────────────────

## Category per DOCS.md §3.1. Stable integer value; never re-order the enum.
@export var category: Category = Category.RECTANGULAR

## Palette colour index for placed instances (-1 = colour resolved at place-time per StudGrid
## record; material/ore bricks use -1 to signal natural colour, set via natural_colour_token).
@export var palette_colour_index: int = -1

## Whether the brick can be colour-swapped using the 18-colour palette (CONTEXT.md D-03).
## false for material/ore bricks and mob-drops that have baked-in natural colours.
@export var colour_swappable: bool = true

## Index into BrickPalette.COLOURS representing the brick's natural colour (0..17).
## Only meaningful when colour_swappable == false. -1 = mesh has baked-in material (no mapping).
@export var natural_colour_token: int = -1

## IAP pack origin identifier. Empty string = base pack (ships with the game).
## Populated by IAP-pack installer in Phase 5 (CONTEXT.md "Brick palette as IAP-pack target").
@export var iap_pack_origin: String = ""

## Multi-cell occupancy list in local stud-grid space (anchor = cells[0]).
## Single-cell bricks: [Vector3i(0,0,0)]. 1×4 brick: 4 entries along Z axis, etc.
@export var footprint_cells: Array[Vector3i] = [Vector3i(0, 0, 0)]

# ─── Factory ─────────────────────────────────────────────────────────────────

## Loads a BrickDefinition from a .glb/.gltf scene path.
## Reads stud-anchor metadata from the glTF `extras` dictionary per Pattern 2.
##
## Strategy (two-pass for compatibility):
##   1. Try GLTFDocument.append_from_file() — works in headless mode without import cache.
##   2. If that fails, fall back to load(scene_path) (requires editor import pass).
## Returns null if both fail or the scene contains no MeshInstance3D.
static func from_gltf(scene_path: String) -> BrickDefinition:
	# Resolve to absolute filesystem path for GLTFDocument.
	var abs_path: String = ProjectSettings.globalize_path(scene_path)

	# ── Path 1: GLTFDocument (no import cache required, works headless) ──────
	var gltf_doc := GLTFDocument.new()
	var gltf_state := GLTFState.new()
	# GLTFState.handle_binary_image controls embedded image import;
	# HANDLE_BINARY_DISCARD avoids GPU texture upload issues in headless mode.
	gltf_state.handle_binary_image = GLTFState.HANDLE_BINARY_DISCARD_TEXTURES
	var err := gltf_doc.append_from_file(abs_path, gltf_state)
	if err != OK:
		# ── Path 2: load() fallback (requires editor import of the .glb first) ─
		push_warning("BrickDefinition.from_gltf: GLTFDocument failed (%d), trying load() for '%s'" % [err, scene_path])
		return _from_gltf_via_load(scene_path)

	var scene: Node = gltf_doc.generate_scene(gltf_state)
	if scene == null:
		push_error("BrickDefinition.from_gltf: GLTFDocument.generate_scene returned null for '%s'" % scene_path)
		return _from_gltf_via_load(scene_path)

	var result := _build_from_scene(scene, scene_path)
	scene.queue_free()
	return result


## Internal: same logic using load() — requires pre-imported asset.
static func _from_gltf_via_load(scene_path: String) -> BrickDefinition:
	var packed = load(scene_path)
	if packed == null:
		push_error("BrickDefinition._from_gltf_via_load: cannot load '%s'" % scene_path)
		return null
	var scene: Node = (packed as PackedScene).instantiate()
	if scene == null:
		push_error("BrickDefinition._from_gltf_via_load: instantiation failed for '%s'" % scene_path)
		return null
	var result := _build_from_scene(scene, scene_path)
	scene.queue_free()
	return result


## Build a BrickDefinition from an instantiated scene tree.
static func _build_from_scene(scene: Node, scene_path: String) -> BrickDefinition:
	var mesh_instance: MeshInstance3D = _find_mesh_instance(scene)
	if mesh_instance == null:
		push_error("BrickDefinition._build_from_scene: no MeshInstance3D in '%s'" % scene_path)
		return null

	# RESEARCH.md Assumption A4: extras may land on mesh, node, or parent node.
	var extras: Dictionary = {}

	if mesh_instance.mesh != null:
		var mesh_extras = mesh_instance.mesh.get_meta("extras", {})
		if mesh_extras is Dictionary and not (mesh_extras as Dictionary).is_empty():
			extras = mesh_extras as Dictionary

	if extras.is_empty():
		var node_extras = mesh_instance.get_meta("extras", {})
		if node_extras is Dictionary and not (node_extras as Dictionary).is_empty():
			extras = node_extras as Dictionary

	if extras.is_empty():
		var parent: Node = mesh_instance.get_parent()
		while parent != null and not (parent == scene):
			var parent_extras = parent.get_meta("extras", {})
			if parent_extras is Dictionary and not (parent_extras as Dictionary).is_empty():
				extras = parent_extras as Dictionary
				break
			parent = parent.get_parent()
		# Also check the scene root itself.
		if extras.is_empty():
			var root_extras = scene.get_meta("extras", {})
			if root_extras is Dictionary and not (root_extras as Dictionary).is_empty():
				extras = root_extras as Dictionary

	var def := BrickDefinition.new()
	def.brick_id        = str(extras.get("cubicraftia.brick_id", ""))
	def.stud_profile    = str(extras.get("cubicraftia.stud_profile", "concave_top"))
	def.material_id     = str(extras.get("cubicraftia.material", "plastic_solid"))

	# Blender 5.x glTF exporter stores Array-typed custom properties as JSON strings.
	# Parse them back; fall back to treating as native Array if already parsed.
	var raw_dims = extras.get("cubicraftia.dimensions", "[1, 1, 1]")
	raw_dims = _parse_json_if_string(raw_dims, [1, 1, 1])
	if raw_dims is Array and (raw_dims as Array).size() >= 3:
		def.dimensions = Vector3i(int(raw_dims[0]), int(raw_dims[1]), int(raw_dims[2]))

	var raw_top = extras.get("cubicraftia.studs_top", "[]")
	raw_top = _parse_json_if_string(raw_top, [])
	if raw_top is Array:
		def.studs_top = (raw_top as Array).duplicate()

	var raw_bottom = extras.get("cubicraftia.studs_bottom", "[]")
	raw_bottom = _parse_json_if_string(raw_bottom, [])
	if raw_bottom is Array:
		def.studs_bottom = (raw_bottom as Array).duplicate()

	def.mesh = mesh_instance.mesh
	return def


## Recursively find the first MeshInstance3D in a node subtree.
static func _find_mesh_instance(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node as MeshInstance3D
	for child in node.get_children():
		var found := _find_mesh_instance(child)
		if found != null:
			return found
	return null


## Parse value as JSON if it is a String, otherwise return it as-is.
## If parsing fails, returns the provided default.
static func _parse_json_if_string(value: Variant, default_val: Variant) -> Variant:
	if value is String:
		var json := JSON.new()
		var parse_err := json.parse(value as String)
		if parse_err == OK:
			return json.get_data()
		return default_val
	return value
