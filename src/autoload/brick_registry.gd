# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# brick_registry.gd — All 50 BrickDefinitions loaded at boot via manifest.json.
#
# Registered as autoload "BrickRegistry" in project.godot (AFTER WorldSave per
# the Plan 02-04 load-order contract; Plan 02-05 will insert WorldClock/Weather
# between WorldSave and BrickRegistry).
#
# Loads every .tres listed in manifest.json on _ready(). The manifest-driven
# approach ensures deterministic load order and is the single source of truth
# for the 50-brick contract (DOCS.md §3.1).
#
# Boot budget: 50 small .tres files (no mesh assets at Phase 2); measured within
# Tier-3 constraints per RESEARCH.md §"Brick Library Schema".
#
# Phase 5 IAP extension: register_pack() appends additional BrickDefinitions
# from IAP pack installers. Phase 2 ships the stub body only.
#
# References:
#   DOCS.md §3.1 — 50-brick category contract
#   CONTEXT.md "Brick palette as IAP-pack target" — register_pack Phase-5 hook
#   02-PATTERNS.md §"src/autoload/brick_registry.gd" — iap_stub.gd analog
#   02-04-PLAN.md interfaces — get(id), get_all(), get_by_category(c), register_pack()

extends Node

# Preload-based reference to the BrickDefinition Resource subclass — avoids
# class_name registry dependency at parse time. The class_name version fails
# when .godot/global_script_class_cache.cfg is stale or partially-rebuilt.
const BrickDefinition = preload("res://src/bricks/brick_definition.gd")

# ─── Constants ───────────────────────────────────────────────────────────────

## Directory containing all BrickDefinition .tres files.
const BRICK_DIR := "res://src/bricks/"

## Manifest listing the 50 base-pack .tres filenames in canonical order.
const MANIFEST_PATH := "res://src/bricks/manifest.json"

# ─── Private state ────────────────────────────────────────────────────────────

## Internal registry: maps brick_id -> BrickDefinition.
var _registry: Dictionary = {}  # Dictionary[String, BrickDefinition]

# ─── Lifecycle ────────────────────────────────────────────────────────────────

func _ready() -> void:
	_load_base_pack()


## Load all 50 base-pack BrickDefinitions via manifest.json.
func _load_base_pack() -> void:
	var file := FileAccess.open(MANIFEST_PATH, FileAccess.READ)
	if file == null:
		push_error("BrickRegistry._load_base_pack: cannot open manifest at '%s' (err %d)" % [
			MANIFEST_PATH, FileAccess.get_open_error()])
		return

	var text := file.get_as_text()
	file.close()

	var parsed = JSON.parse_string(text)
	if not parsed is Array:
		push_error("BrickRegistry._load_base_pack: manifest is not a JSON array.")
		return

	var manifest: Array = parsed as Array
	for entry: Variant in manifest:
		if not entry is String:
			push_warning("BrickRegistry._load_base_pack: non-string entry in manifest: %s" % str(entry))
			continue
		var path := BRICK_DIR + (entry as String)
		var def := load(path) as BrickDefinition
		if def == null:
			push_error("BrickRegistry._load_base_pack: failed to load '%s' as BrickDefinition." % path)
			continue
		if def.brick_id == "":
			push_error("BrickRegistry._load_base_pack: BrickDefinition at '%s' has empty brick_id." % path)
			continue
		_registry[def.brick_id] = def

	if _registry.size() != manifest.size():
		push_error("BrickRegistry._load_base_pack: loaded %d / %d bricks — some failed." % [
			_registry.size(), manifest.size()])

	# Phase 7 fix: populate def.mesh from the companion .glb for each brick whose
	# .tres has mesh=null. Uses load() so Godot's import cache delivers materials.
	for def_raw: Variant in _registry.values():
		var def := def_raw as BrickDefinition
		if def == null or def.mesh != null:
			continue
		var glb_path := "res://assets/meshes/" + def.brick_id + ".glb"
		if not ResourceLoader.exists(glb_path):
			# Item/drop bricks (tools, food, mob drops) intentionally ship no companion
			# mesh; they render from a 2D icon or a palette-tint placeholder. Only flag a
			# brick with NO visual fallback at all (no icon AND no natural-colour tint).
			if def.icon_path == "" and def.natural_colour_token < 0:
				push_warning("BrickRegistry: '%s' has no .glb (%s), no icon, and no colour tint; it will be invisible." % [
					def.brick_id, glb_path])
			continue
		var packed := load(glb_path)
		if not packed is PackedScene:
			push_warning("BrickRegistry: '%s' did not load as PackedScene — skipping." % glb_path)
			continue
		var temp: Node = (packed as PackedScene).instantiate()
		if temp == null:
			push_warning("BrickRegistry: instantiation failed for '%s' — skipping." % glb_path)
			continue
		var mi: MeshInstance3D = _find_first_mesh_instance(temp)
		if mi != null and mi.mesh != null:
			def.mesh = mi.mesh
		else:
			push_warning("BrickRegistry: no non-null MeshInstance3D in '%s' — mesh stays null." % glb_path)
		temp.free()


## Recursively find the first MeshInstance3D with a non-null mesh in a subtree.
func _find_first_mesh_instance(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		return node as MeshInstance3D
	for child: Node in node.get_children():
		var found := _find_first_mesh_instance(child)
		if found != null:
			return found
	return null


# ─── Public API ───────────────────────────────────────────────────────────────

## Return the BrickDefinition for a given brick_id, or null if unknown.
## Named get_definition() (not get()) to avoid shadowing Node.get(StringName) built-in
## which causes a GDScript parse error in Godot 4.6 (warning-as-error).
func get_definition(brick_id: String) -> BrickDefinition:
	return _registry.get(brick_id, null)


## Return all loaded BrickDefinitions as an Array.
func get_all() -> Array:
	return _registry.values()


## Return all BrickDefinitions matching a given category integer.
## Category values are defined by BrickDefinition.Category enum:
##   0=RECTANGULAR, 1=PLATE, 2=SLOPE, 3=TILE, 4=ROUND, 5=FUNCTIONAL,
##   6=DECORATIVE, 7=MATERIAL_ORE, 8=ACCESSORY, 9=MOB_DROP
func get_by_category(category: int) -> Array:
	var out: Array = []
	for def in _registry.values():
		if (def as BrickDefinition).category == category:
			out.append(def)
	return out


## Phase 5 IAP stub: register additional BrickDefinitions from an IAP pack.
##
## @param defs  Array of BrickDefinition resources from the IAP pack installer.
## @return      Count of definitions successfully added to the registry.
##
## Note: calling this with base-pack bricks (iap_pack_origin == "") is a misuse;
## the warning guards against accidental re-registration of the base set.
func register_pack(defs: Array) -> int:
	var added := 0
	for entry: Variant in defs:
		var def := entry as BrickDefinition
		if def == null:
			push_warning("BrickRegistry.register_pack: non-BrickDefinition entry skipped.")
			continue
		if def.iap_pack_origin == "":
			push_warning("BrickRegistry.register_pack: '%s' has empty iap_pack_origin — base bricks should not be re-registered via register_pack." % def.brick_id)
		if _registry.has(def.brick_id):
			push_warning("BrickRegistry.register_pack: brick_id '%s' already registered — skipping." % def.brick_id)
			continue
		_registry[def.brick_id] = def
		added += 1
	return added
