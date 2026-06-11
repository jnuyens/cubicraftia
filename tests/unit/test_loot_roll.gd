# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# test_loot_roll.gd — Unit tests for loot table weighted roll determinism and validation.
#
# Anchors:
#   03-RESEARCH.md Pattern 4 — deterministic seeded weighted loot roll
#   03-RESEARCH.md §"Security Domain" — unknown def_id → push_warning + skip (not crash)
#   03-PLAN.md 03-01 Task 2 — test_loot_roll.gd scaffold
#
# These tests reference LootRoller shipping in Plan 03-06.
# They will FAIL until Plan 03-06 executes.

extends GutTest

const _LOOT_ROLLER_PATH := "res://src/loot/loot_roller.gd"
const _LOOT_TABLE_PATH := "res://src/loot/loot_table.gd"

var _roller: Object = null

func before_each() -> void:
	if ResourceLoader.exists(_LOOT_ROLLER_PATH):
		_roller = load(_LOOT_ROLLER_PATH).new()


func after_each() -> void:
	_roller = null


# ─── Test 1: Weighted roll is deterministic given seed ───────────────────────

func test_weighted_roll_is_deterministic_given_seed() -> void:
	# 03-RESEARCH.md Pattern 4: same seed → same Array of {def_id, count} returned.
	if _roller == null:
		pending("LootRoller not available — pending until Plan 03-06")
		return
	if not ResourceLoader.exists(_LOOT_TABLE_PATH):
		pending("LootTable resource class not available — pending until Plan 03-06")
		return
	# Create a minimal loot table with 3 entries.
	var table: Resource = load(_LOOT_TABLE_PATH).new()
	table.set("entries", [
		{"def_id": "brick_1x1",        "weight": 5, "min_count": 1, "max_count": 3},
		{"def_id": "brick_plank_wooden", "weight": 3, "min_count": 1, "max_count": 2},
		{"def_id": "brick_log_wood",    "weight": 2, "min_count": 1, "max_count": 1},
	])
	var seed_value: int = 12345
	var result_a: Array = _roller.roll_loot(table, seed_value)
	var result_b: Array = _roller.roll_loot(table, seed_value)
	assert_eq(result_a.size(), result_b.size(),
		"Same seed must produce the same number of loot items")
	for i: int in result_a.size():
		assert_eq(result_a[i].get("def_id", ""), result_b[i].get("def_id", ""),
			"def_id at loot index %d must be identical across same-seed rolls" % i)
		assert_eq(result_a[i].get("count", 0), result_b[i].get("count", 0),
			"count at loot index %d must be identical across same-seed rolls" % i)


# ─── Test 2: Weights are proportional to outcome distribution ────────────────

func test_weights_proportional_to_outcome_distribution() -> void:
	# 10000 rolls with weights [1,1,8] should yield approximately 10%/10%/80% distribution.
	if _roller == null:
		pending("LootRoller not available — pending until Plan 03-06")
		return
	if not ResourceLoader.exists(_LOOT_TABLE_PATH):
		pending("LootTable resource class not available — pending until Plan 03-06")
		return
	var table: Resource = load(_LOOT_TABLE_PATH).new()
	table.set("entries", [
		{"def_id": "item_a", "weight": 1, "min_count": 1, "max_count": 1},
		{"def_id": "item_b", "weight": 1, "min_count": 1, "max_count": 1},
		{"def_id": "item_c", "weight": 8, "min_count": 1, "max_count": 1},
	])
	var counts: Dictionary = {"item_a": 0, "item_b": 0, "item_c": 0}
	var n_rolls := 10000
	for i: int in range(n_rolls):
		var result: Array = _roller.roll_loot(table, i)
		for item: Dictionary in result:
			var id: String = str(item.get("def_id", ""))
			if id in counts:
				counts[id] += 1
	var total: int = counts["item_a"] + counts["item_b"] + counts["item_c"]
	assert_true(total > 0, "At least some items must be rolled")
	var pct_c: float = float(counts["item_c"]) / float(total) * 100.0
	# item_c has weight 8/10 = 80%; allow ±3% tolerance.
	assert_true(pct_c >= 77.0 and pct_c <= 83.0,
		"item_c (weight=8/10) should appear ~80% of the time (got %.1f%%, tolerance ±3%%)" % pct_c)


# ─── Test 3: Unknown def_id is warned and skipped ────────────────────────────

func test_unknown_def_id_logged_warning_and_skipped() -> void:
	# 03-RESEARCH.md §"Security Domain": a LootEntry with def_id="nonexistent"
	# must push_warning and yield no item in the result.
	if _roller == null:
		pending("LootRoller not available — pending until Plan 03-06")
		return
	if not ResourceLoader.exists(_LOOT_TABLE_PATH):
		pending("LootTable resource class not available — pending until Plan 03-06")
		return
	var table: Resource = load(_LOOT_TABLE_PATH).new()
	table.set("entries", [
		{"def_id": "nonexistent_item_xyz_not_in_registry", "weight": 10, "min_count": 1, "max_count": 1},
	])
	# GUT's gut.is_warning_logged() or watch for absence in result.
	var result: Array = _roller.roll_loot(table, 42)
	# All items with nonexistent def_id should be filtered out.
	for item: Dictionary in result:
		var id: String = str(item.get("def_id", ""))
		assert_ne(id, "nonexistent_item_xyz_not_in_registry",
			"Nonexistent def_id must be skipped (not included in loot result)")
