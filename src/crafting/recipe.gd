# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# recipe.gd — Recipe Resource: identity + shaped/shapeless ingredient grid for a single recipe.
#
# Pattern: mirrors src/tools/tool_definition.gd (@export-driven Resource shape).
#
# DOCS.md §4.5 Crafting — ~10 v1 recipes (11 with workbench-craft extension per 03-07a).
# 03-CONTEXT.md D-07 — recipe ingredient ratios at Claude's discretion.
#
# Slot indexing:
#   2×2 grid: slot 0=top-left, 1=top-right, 2=bottom-left, 3=bottom-right
#   3×3 grid: slot 0=top-left … slot 8=bottom-right (row-major)
#
# `inputs` Array entries are Dictionaries:
#   {def_id: String, count: int, slot: int}
#   - shaped=true:  slot indexes into the grid (0..3 for 2×2, 0..8 for 3×3)
#   - shaped=false: slot=-1 (Inventory.match_recipe ignores position)
#
# References:
#   DOCS.md §4.5
#   03-PATTERNS.md Recipe + recipe .tres analog assignments (lines 511-566)
#   03-CONTEXT.md D-07

class_name Recipe
extends Resource

# ─── Exports ──────────────────────────────────────────────────────────────────

## Unique recipe identifier (e.g. "wooden_plank", "pickaxe_wood").
@export var recipe_id: String = ""

## Translation key for the recipe's display name (e.g. "recipes.wooden_plank.name").
@export var display_name_key: String = ""

## Ingredient list. Each entry: {def_id: String, count: int, slot: int (-1 = shapeless)}.
## For shaped recipes, slot indexes into the grid; for shapeless, slot is -1.
@export var inputs: Array = []

## Output brick/item def_id (must resolve in BrickRegistry or non-brick allow-list).
@export var output_def_id: String = ""

## Number of output items produced per craft.
@export var output_count: int = 1

## true = ingredient positions matter; false = bag-of-ingredients matching.
@export var shaped: bool = true

## Grid size this recipe targets: 2 for the portable 2×2, 3 for the workbench 3×3.
## The 2×2 inline grid and 3×3 workbench share the same shaped semantics (D-07 §truths).
@export var grid_size: int = 2
