# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# tool_definition.gd — ToolDefinition Resource: identity + properties for a single tool type.
#
# Pattern: mirrors src/bricks/brick_definition.gd (Phase 1 Resource pattern — @export fields,
# class_name, extends Resource). See 02-PATTERNS.md §"src/tools/tool_definition.gd".
#
# DOCS.md §3.4 "v1 tool kit":
#   - Tiered pickaxe: wood (tier 0) → stone (tier 1) → iron (tier 2) → diamond (tier 3)
#   - Shovel: breaks terrain faster
#   - Dynamite: sphere blast of ~5 m radius (max_durability=1 — single-use)
#   - Handheld lantern: OmniLight3D attached to builder hand; never wears out
#
# DOCS.md §3.4 "Tool wear":
#   - Survival mode: durability decrements per use (managed by ToolWear autoload)
#   - Sandbox mode: no wear ever; ToolWear.decrement_on_use() is a no-op
#   - Lantern: max_durability=0 signals "never wears out" (exempt from wear logic)
#
# Tier-aware breaking per DOCS §3.4:
#   - Iron ore needs stone+ pickaxe (tier >= 1)
#   - Diamond ore needs iron+ pickaxe (tier >= 2)
#   - Wood pickaxe (tier 0) breaks only stone/cobblestone
#
# References:
#   DOCS.md §3.4
#   02-PATTERNS.md §"src/tools/tool_definition.gd"
#   02-CONTEXT.md §D-12 (tool durability UI)

class_name ToolDefinition
extends Resource

# ─── Category enum ────────────────────────────────────────────────────────────
## Tool category — stable integer values; never re-order (downstream binds to int value).
enum ToolCategory {
	PICKAXE  = 0,  ## Tiered pickaxe (wood/stone/iron/diamond) for breaking terrain/ore
	SHOVEL   = 1,  ## Shovel for faster terrain excavation
	DYNAMITE = 2,  ## Single-use explosive (5 m radius per DOCS §3.4)
	LANTERN  = 3,  ## Handheld lantern — OmniLight3D on builder hand, never wears out
}

# ─── Exports ──────────────────────────────────────────────────────────────────

## Unique tool identifier (e.g. "pickaxe_wood", "shovel", "dynamite", "lantern_handheld").
@export var tool_id: String = ""

## Translation key for the tool's display name (e.g. "tools.pickaxe_wood.name").
@export var display_name_key: String = ""

## Tool category.
@export var category: ToolCategory = ToolCategory.PICKAXE

## Tier level for pickaxes (0=wood, 1=stone, 2=iron, 3=diamond).
## Not meaningful for non-pickaxe tools; leave at 0.
@export var tier: int = 0

## Maximum durability in survival mode.
## 0 = never wears out (lantern). 1 = single-use (dynamite).
## Sandbox mode always ignores this value (ToolWear.decrement_on_use is a no-op).
@export var max_durability: int = 60

## Blast radius in metres for dynamite (DOCS §3.4 "~5 m radius").
## Only meaningful for DYNAMITE category.
@export var dynamite_radius_m: float = 5.0

## Light radius in metres for the handheld lantern OmniLight3D.
## Only meaningful for LANTERN category.
@export var lantern_light_radius_m: float = 8.0

## Optional mesh reference (populated at runtime if a tool has a 3D model).
@export var mesh: Mesh = null

## Path to the 2D inventory/hotbar icon texture (e.g. art-tools.png slices in
## res://assets/textures/icons/). "" = no icon yet (falls back to the empty-slot art).
@export var icon_path: String = ""
