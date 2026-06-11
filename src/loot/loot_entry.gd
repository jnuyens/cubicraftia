# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# loot_entry.gd — LootEntry Resource: a single weighted entry in a loot table.
#
# Pattern: mirrors src/tools/tool_definition.gd (@export-driven Resource shape).
#
# DOCS.md §4.4 — Chest tiers + loot tables.
# 03-CONTEXT.md D-04 — per-tier key sourcing (bronze/silver/gold/diamond).
# 03-RESEARCH.md §"Loot Table Resource Pattern" — field definitions.
#
# References:
#   03-08a-PLAN.md interfaces
#   03-RESEARCH.md lines 558-565

class_name LootEntry
extends Resource

# ─── Exports ──────────────────────────────────────────────────────────────────

## Unique item identifier (BrickRegistry brick_id OR ItemDefinition id such as
## "key_bronze", "food_cooked_generic", "strawberry").
@export var def_id: String = ""

## Relative probability weight for this entry (higher = more common).
## All weights in a table are summed; each entry's probability = weight / total.
@export var weight: float = 1.0

## Minimum number of this item awarded on a single roll.
@export var min_count: int = 1

## Maximum number of this item awarded on a single roll.
@export var max_count: int = 1
