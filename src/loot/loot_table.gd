# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# loot_table.gd — LootTable Resource: a weighted collection of loot entries.
#
# Pattern: mirrors src/tools/tool_definition.gd (@export-driven Resource shape).
#
# DOCS.md §4.4 — Chest tiers + loot tables (5 chest tiers + structure type tables).
# 03-CONTEXT.md D-04 — per-tier key sourcing.
# 03-RESEARCH.md §"Loot Table Resource Pattern" — field definitions.
#
# Two-step roll model (03-08a two-table design):
#   1. structure_<type>.tres: rolls which chest TIER spawns at each slot.
#   2. chest_<tier>.tres: rolls the actual CONTENTS for a chest of that tier.
# Plan 03-08b wires these tables into structure_placer + main_scene.spawn_chest.
#
# References:
#   03-08a-PLAN.md interfaces
#   03-RESEARCH.md lines 547-587

class_name LootTable
extends Resource

# ─── Exports ──────────────────────────────────────────────────────────────────

## Ordered list of LootEntry Resources describing possible loot items.
## LootRoller performs a weighted pick per roll. Entries may be LootEntry
## Resources or plain Dictionaries (duck-typed, for test ergonomics).
@export var entries: Array = []

## Minimum number of rolls performed when opening this chest.
@export var min_rolls: int = 1

## Maximum number of rolls performed when opening this chest.
@export var max_rolls: int = 3

## Unique table identifier used in LootRoller.seed_for_chest XOR computation.
## Must match the filename stem (e.g. "chest_regular", "structure_mineshaft").
@export var table_id: String = ""
