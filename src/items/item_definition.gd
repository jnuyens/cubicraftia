# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# item_definition.gd — ItemDefinition Resource: identity + properties for a single non-brick item.
#
# Non-brick items (keys, cooked food, strawberry) are not part of the Phase 2 50-brick library
# and do not have placed 3D mesh representations. They exist as inventory entries only.
#
# Per 03-CONTEXT.md canonical-refs L153: "Phase 3 chests + keys + cooked food + creature-drop
# bricks are registered here as new BrickDefinition entries (or a small extension if non-brick
# items like keys + cooked food need a separate item-class hierarchy — Claude's discretion in
# planning)." Decision: keys + cooked food + strawberry use ItemDefinition (this class);
# chests use BrickDefinition (they are placed 3D objects).
#
# Item discovery: BrickRegistry.get_definition(def_id) falls back to ResourceLoader.load(
# "res://src/bricks/<def_id>.tres") for ItemDefinitions not in manifest.json (avoids same-wave
# manifest.json conflicts — see Plan 03-06 SUMMARY for convention rationale).
#
# DOCS.md §4.1 — item stacking (max 64 per slot; universal in v1)
# DOCS.md §4.4 — 4 key types: bronze/silver/gold/diamond; consumed on chest unlock
# 03-CONTEXT.md D-04 — keys are found-only loot in v1
# 03-CONTEXT.md D-13 — cooked food is a HP-restore consumable; consumed on use
# 03-CONTEXT.md D-16 — strawberries are a rare super-heal collectable; consumed on use

class_name ItemDefinition
extends Resource

# ─── Exports ──────────────────────────────────────────────────────────────────

## Unique item identifier (e.g. "key_bronze", "cooked_fish", "strawberry").
## Must match the .tres filename stem for ResourceLoader fallback lookup.
@export var item_id: String = ""

## Translation key for the item's display name (e.g. "items.key_bronze.name").
@export var display_name_key: String = ""

## Path to the 2D inventory icon texture (e.g. "res://assets/textures/icons/<item_id>.png").
## Used by InventorySlot and ChestPanel to render the item icon.
## May be "" if no icon asset exists yet (headless / placeholder path acceptable).
@export var icon_path: String = ""

## Item category. Determines which UI interactions are available.
##   "key"         — consumed on chest UNLOCK; tier-matched per REQUIRED_KEY
##   "cooked_food" — consumed on eat (right-click / long-press); restores heal_amount HP
##   "strawberry"  — super-heal consumable; consumed on eat; higher heal_amount than food
@export var category: String = ""

## Maximum items per stack (DOCS §4.1; default 64 — universal in v1).
@export var max_stack: int = 64

## Tier string for keys (maps to chest tier).
## "bronze" | "silver" | "gold" | "diamond" for category="key"; "" for all other categories.
@export var tier: String = ""

## HP restored when this item is consumed (survive mode only; 0 in sandbox).
## Meaningful for category="cooked_food" and category="strawberry" only.
## 0 for keys (not a heal item).
@export var heal_amount: int = 0

## Whether this item is consumed (quantity -1) when used.
##   true  for keys (UNLOCK event consumes 1), cooked food, strawberry
##   false for items that are reusable (none in v1; reserved for future use)
@export var consumed_on_use: bool = false

## VFX effect identifier to spawn on item use. Dispatched by Builder.eat_food via a
## hard-coded switch to prevent injection attacks (T-03-09-DR-05: only "fire_breath" maps
## to a known scene; all other values are a no-op).
##   "fire_breath" — Tom Yum signature flame-puff (D-13, cosmetic only, no damage)
##   ""            — no VFX (default for all non-Tom-Yum items)
@export var vfx_on_use: String = ""
