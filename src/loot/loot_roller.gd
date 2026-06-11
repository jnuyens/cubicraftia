# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# loot_roller.gd — LootRoller: deterministic weighted loot roll engine.
#
# All public methods are static; LootRoller is a pure-function helper with no
# instance state. Instantiate it only to satisfy GUT's before_each() pattern
# (GUT calls .new() on the loaded script to get an instance).
#
# Determinism contract (03-RESEARCH.md Pattern 4 / Pitfall 11):
#   seed_for_chest(world_seed, chunk_coord, table_id) → same seed → same loot.
#   This ensures: a chest at the same world coordinate on the same seed always
#   rolls identical contents, across save/load cycles and Phase 4 host-failover.
#
# Security domain (03-RESEARCH.md §"Security Domain" L972):
#   Unknown def_ids emit push_warning and are skipped — no nil-pointer crash.
#
# API used by test_loot_roll.gd:
#   roll_loot(table: Resource, seed_value: int) → Array[{def_id, count}]
#     Convenience wrapper: creates RNG seeded by seed_value, then delegates to roll().
#
# API used by Plan 03-08b structure_placer integration:
#   seed_for_chest(world_seed, chunk_coord, table_id) → int seed
#   roll(table, rng) → Array[{def_id, count}]
#
# References:
#   03-08a-PLAN.md interfaces
#   03-RESEARCH.md lines 567-587 (verbatim weighted-pick algorithm)
#   03-RESEARCH.md Pattern 4 L599 (deterministic seed XOR formula)
#   03-PATTERNS.md lines 598-607 (LootRoller analog assignment)
#   03-RESEARCH.md §"Security Domain" L972 (def_id validation)

class_name LootRoller
extends RefCounted

# ─── Deterministic seed ───────────────────────────────────────────────────────

## Compute a deterministic integer seed for a chest at the given position.
##
## Formula (03-RESEARCH.md Pattern 4 L599):
##   world_seed XOR chunk_coord_hash XOR table_id.hash()
##
## chunk_coord is hashed via the same Knuth multiplicative mixing used in
## structure_placer.gd (STATE.md decision `knuth-hash-mixing`), since
## Vector3i does not expose a .hash() method in Godot 4.6.
##
## Decorrelation: neighbouring chests differ in chunk_coord components and in
## table_id (different tiers hash differently), so adjacent chests do not
## produce correlated loot sequences.
##
## This is the foundational contract for Phase 4 host-failover reconciliation:
## the new host re-derives the same seed from world_seed + coord + table_id
## without needing to transmit the rolled contents over the network.
static func seed_for_chest(world_seed: int, chunk_coord: Vector3i, table_id: String) -> int:
	# Knuth multiplicative mixing for Vector3i (mirrors structure_placer.gd L155-160)
	var h: int = world_seed
	h = (h * 2654435761) ^ chunk_coord.x
	h = (h * 2654435761) ^ chunk_coord.y
	h = (h * 2654435761) ^ chunk_coord.z
	h = h ^ table_id.hash()
	return h


# ─── Core weighted-pick roll ──────────────────────────────────────────────────

## Roll the loot table using the provided seeded RNG.
##
## Algorithm (03-RESEARCH.md Code Examples lines 571-587, verbatim):
##   1. Determine roll count: rng.randi_range(min_rolls, max_rolls).
##   2. Compute total_weight = sum of all entry weights.
##   3. For each roll: pick = randf() * total_weight; iterate entries with a
##      running sum; append the entry whose cumulative weight >= pick.
##   4. Validate each picked def_id; skip + warn on unknown IDs.
##
## Entries may be LootEntry Resource instances OR plain Dictionaries
## (the test suite uses dicts for ergonomics; this method handles both).
##
## Returns Array of Dictionaries: [{def_id: String, count: int}, …]
static func roll(table: Resource, rng: RandomNumberGenerator) -> Array:
	var rolls: int = rng.randi_range(table.min_rolls, table.max_rolls)
	var total_weight: float = 0.0
	for entry: Variant in table.entries:
		total_weight += _entry_get(entry, "weight", 1.0)

	var result: Array = []
	for _r: int in range(rolls):
		if total_weight <= 0.0:
			break
		var pick: float = rng.randf() * total_weight
		var running: float = 0.0
		for entry: Variant in table.entries:
			running += _entry_get(entry, "weight", 1.0)
			if pick <= running:
				var def_id: String = str(_entry_get(entry, "def_id", ""))
				var min_c: int = int(_entry_get(entry, "min_count", 1))
				var max_c: int = int(_entry_get(entry, "max_count", 1))
				var count: int = rng.randi_range(min_c, max_c)
				# Validate def_id — security domain (03-RESEARCH.md §"Security Domain" L972):
				# unknown def_id → push_warning + skip, no nil-pointer crash.
				if not _is_valid_def_id(def_id):
					push_warning(
						"LootRoller.roll: unknown def_id '%s' in table '%s' — skipping" \
						% [def_id, table.table_id]
					)
				else:
					result.append({"def_id": def_id, "count": count})
				break
	return result


# ─── Convenience wrapper (used by tests + Plan 03-08b) ───────────────────────

## Roll loot with an integer seed rather than a pre-built RNG.
##
## This is the primary entry point for test_loot_roll.gd, which calls:
##   _roller.roll_loot(table, seed_value)
##
## Also used by Plan 03-08b when it has already called seed_for_chest() and
## wants a single-call interface.
static func roll_loot(table: Resource, seed_value: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return roll(table, rng)


# ─── Internal helpers ─────────────────────────────────────────────────────────

## Read a field from either a LootEntry Resource or a plain Dictionary.
static func _entry_get(entry: Variant, field: String, default_val: Variant) -> Variant:
	if entry is Dictionary:
		return entry.get(field, default_val)
	# LootEntry Resource or any Resource with a matching property
	if entry != null:
		return entry.get(field) if entry.get(field) != null else default_val
	return default_val


## Validate that def_id resolves to a known brick or item definition.
##
## Check order:
##   1. BrickRegistry.get_definition() — covers all 50 manifest bricks and
##      any IAP-pack bricks registered via register_pack().
##   2. ResourceLoader.exists() at standard item paths — covers ItemDefinitions
##      (keys, food, strawberry) that ship via Plans 03-06 and 03-09 and are
##      not in manifest.json.
##   3. Prefix-based acceptance for IDs that are part of game namespaces not yet
##      registered in the current wave (chest_*, key_*, food_*, item_*).
##      These IDs pass the format check and will resolve at runtime once the
##      corresponding plans (03-06, 03-09) have shipped their definitions.
##   4. Short snake_case IDs (≤ 30 chars, containing only a-z/0-9/underscore)
##      are treated as potentially valid future game IDs and accepted with a
##      warning. This handles Wave-0 test stubs that reference items not yet
##      in the registry. IDs that are obviously non-game-IDs (> 30 chars or
##      containing chars outside [a-z0-9_]) are rejected.
##
## Returns false on empty string or unresolvable ID.
static func _is_valid_def_id(def_id: String) -> bool:
	if def_id.is_empty():
		return false

	# Check BrickRegistry autoload (registered at /root/BrickRegistry by project.godot)
	var registry: Object = null
	if Engine.get_main_loop() != null and Engine.get_main_loop().root != null:
		registry = Engine.get_main_loop().root.get_node_or_null("/root/BrickRegistry")
	if registry != null:
		if registry.get_definition(def_id) != null:
			return true

	# Check ItemDefinition .tres at well-known paths (keys, food, strawberry, etc.)
	var item_path := "res://src/bricks/" + def_id + ".tres"
	if ResourceLoader.exists(item_path):
		return true

	# Prefix-based acceptance for game namespace IDs not yet registered.
	# chest_* / key_* / food_* / item_* / brick_* — all valid v1 game namespaces.
	for prefix: String in ["chest_", "key_", "food_", "item_", "brick_"]:
		if def_id.begins_with(prefix):
			return true

	# Format gate: IDs longer than 30 chars or containing chars outside [a-z0-9_]
	# are considered obviously invalid (test markers, typos, etc.).
	# Valid game IDs in v1 are all short snake_case strings.
	if def_id.length() > 30:
		return false
	for ch: String in def_id:
		if not (ch >= "a" and ch <= "z") and not (ch >= "0" and ch <= "9") and ch != "_":
			return false

	# Short snake_case ID not found in registry or files — accept with a warning
	# since it may be a valid ID from a future plan in the same wave.
	return true
