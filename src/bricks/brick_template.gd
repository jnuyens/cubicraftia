# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# brick_template.gd — BrickTemplate Resource: composite-of-placements file format
# for all v1 generated structures (villages, temples, shipwrecks, dungeons).
#
# Design decisions:
#   - Extends Resource so .tres serialisation works natively (CONTEXT.md D-65:
#     "exact brick-template file format — pick the one most reusable").
#   - Uses plain Array (not typed) for bricks/terrain_overrides/loot_chests/npc_spawns
#     because Godot 4 .tres does not serialise typed Arrays of Dictionary correctly;
#     the Dictionary schema is enforced at load time in validate().
#   - BrickRegistry.get_definition(id) (not .get(id)) per Plan 04 API contract.
#   - bbox AABB covers the template footprint in template-local cells.
#   - allowed_biomes uses BiomeMap.Biome int values; empty = any biome (dungeons).
#
# Brick entry schema (each Dict in bricks):
#   { "def_id": String, "colour_index": int, "cell": Vector3i }
#
# Terrain override schema (each Dict in terrain_overrides):
#   { "voxel_id": int, "cell": Vector3i }
#
# Loot chest schema (each Dict in loot_chests):
#   { "chest_type": String ("regular"|"bronze"|"silver"|"gold"|"diamond"), "cell": Vector3i }
#   Phase 3 fills actual loot tables; Phase 2 records chest_type + cell only.
#
# NPC spawn schema (each Dict in npc_spawns):
#   { "patrol_path": PackedVector3Array, "skin_variant": String }
#   Plan 13 fills patrol_path arrays; Phase 2 declares the slot with empty path.
#
# References:
#   DOCS.md §2 — v1 generated structures contract
#   02-CONTEXT.md D-07 — 3-5 variants per structure type
#   02-CONTEXT.md D-08 — structure rarity tiers
#   02-RESEARCH.md §"Pattern 2: Structure placement" lines 516-548 — BrickTemplate shape
#   02-PATTERNS.md §"src/bricks/brick_template.gd" — resource exporter analog

class_name BrickTemplate
extends Resource

# ─── Bricks list ─────────────────────────────────────────────────────────────

## Bricks placed in this template, in template-local coordinates.
## Each entry: { "def_id": String, "colour_index": int, "cell": Vector3i }
## colour_index uses BrickPalette indices (0..17); -1 = natural/material colour.
@export var bricks: Array = []

# ─── Terrain overrides ────────────────────────────────────────────────────────

## Terrain voxel overrides (optional; lets a template carve a path or fill a floor).
## Each entry: { "voxel_id": int, "cell": Vector3i }
@export var terrain_overrides: Array = []

# ─── Loot chest hooks ────────────────────────────────────────────────────────

## Loot chest hooks (Phase 3 will populate tables; Phase 2 records chest_type + cell).
## Each entry: { "chest_type": String ("regular"|"bronze"|"silver"|"gold"|"diamond"),
##               "cell": Vector3i, "is_final": bool (optional — dungeon boss room only) }
@export var loot_chests: Array = []

# ─── Structure type ───────────────────────────────────────────────────────────

## Structure type identifier used by Plan 03-08b for loot table resolution.
## Must match the key in StructurePlacer.TEMPLATE_DIRS (e.g. "mineshaft", "dungeon").
## Empty string = no loot table (structure has no chest slots).
@export var structure_type: String = ""

# ─── NPC spawn hooks ─────────────────────────────────────────────────────────

## NPC spawn hooks for wandering peaceful builder NPCs (CONTEXT.md D-09).
## Each entry: { "patrol_path": PackedVector3Array, "skin_variant": String }
## Plan 13 fills patrol_path; Phase 2 declares the slot with empty PackedVector3Array.
@export var npc_spawns: Array = []

# ─── Bounding box ────────────────────────────────────────────────────────────

## Bounding box in template-local cells.
## Used by the blueprint sampler to determine how many chunks this template intersects.
@export var bbox: AABB = AABB(Vector3.ZERO, Vector3.ONE)

# ─── Biome restriction ────────────────────────────────────────────────────────

## Biome restriction using BiomeMap.Biome int values.
## Empty array = "any biome" (used by dungeons — placed by depth gate, not biome match).
## BiomeMap.Biome: GRASSLAND_FOREST=0, DESERT=1, SNOW=2, JUNGLE=3, SAVANNAH=4, OCEAN=5
@export var allowed_biomes: Array[int] = []

# ─── Validation ──────────────────────────────────────────────────────────────

## Validate all brick def_ids against BrickRegistry.
## Called by StructurePlacer._load_templates() at boot to catch authoring mistakes.
## Returns an Array of error strings; empty = valid.
## Push_error is intentional — missing brick IDs are hard authoring bugs, not runtime data.
func validate(registry: Node) -> Array:
	var errors: Array = []
	for i: int in range(bricks.size()):
		var entry: Dictionary = bricks[i] as Dictionary
		if not entry.has("def_id"):
			errors.append("bricks[%d]: missing 'def_id' key" % i)
			continue
		var def_id: String = str(entry["def_id"])
		var def = registry.get_definition(def_id)
		if def == null:
			errors.append("bricks[%d]: def_id '%s' not found in BrickRegistry" % [i, def_id])
	return errors
