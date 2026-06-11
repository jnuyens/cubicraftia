# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# test_chest_unlock_validation.gd — Unit tests for chest tier key validation.
#
# Anchors:
#   DOCS.md §4.4 — keys are tier-matched; wrong tier key is rejected
#   03-PLAN.md 03-01 Task 2 — test_chest_unlock_validation.gd scaffold
#   03-RESEARCH.md Pitfall 6 — wrong-tier key rejected by Inventory event validation
#
# Plan 03-02 implements the Inventory autoload — tests are now active.

extends GutTest

const Phase3Fixtures = preload("res://tests/conftest_phase3.gd")

var _world_id: String = ""
var _builder_id: String = "test_builder_unlock_001"

func before_each() -> void:
	_world_id = Phase3Fixtures.open_temp_world("survival")
	Inventory.detach_world()
	Inventory.attach_world()


func after_each() -> void:
	Phase3Fixtures.close_temp_world()
	Phase3Fixtures.cleanup_temp_world(_world_id)
	_world_id = ""


# ─── Test 1: Wrong-tier key is rejected ───────────────────────────────────────

func test_wrong_tier_key_rejected_by_inventory_event() -> void:
	# Per 03-RESEARCH.md Pitfall 6: UNLOCK event with wrong-tier key must return false;
	# chest must remain locked.
	var chest_pos := Vector3i(10, 0, 10)
	# Give builder a silver key (wrong tier for a gold chest).
	Phase3Fixtures.populate_inventory(_builder_id, [{"def_id": "key_silver", "count": 1}])
	# Attempt to unlock a gold chest with a silver key.
	var ok: bool = Inventory.apply_event({
		"kind": "UNLOCK",
		"builder_id": _builder_id,
		"chest_coord": chest_pos,
		"chest_type": "gold",
		"key_def_id": "key_silver",
	})
	assert_false(ok,
		"UNLOCK with silver key on gold chest must return false (wrong tier per DOCS §4.4)")
	# Chest must remain locked.
	var chest_state: Dictionary = Inventory.get_chest_state(chest_pos)
	assert_true(chest_state.get("locked", true),
		"Gold chest must remain locked after rejected silver key attempt")
	# Silver key must NOT be consumed.
	var slots: Array = Inventory.get_slots(_builder_id)
	var key_count: int = 0
	for s: Dictionary in slots:
		if s.get("def_id", "") == "key_silver":
			key_count += s.get("count", 0)
	assert_eq(key_count, 1, "Silver key should NOT be consumed after failed unlock attempt")


# ─── Test 2: Correct-tier key is accepted ─────────────────────────────────────

func test_correct_tier_key_accepted() -> void:
	# DOCS §4.4: UNLOCK with matching gold key on gold chest succeeds; chest unlocked.
	var chest_pos := Vector3i(20, 0, 20)
	# Give builder a gold key (correct tier).
	Phase3Fixtures.populate_inventory(_builder_id, [{"def_id": "key_gold", "count": 1}])
	var ok: bool = Inventory.apply_event({
		"kind": "UNLOCK",
		"builder_id": _builder_id,
		"chest_coord": chest_pos,
		"chest_type": "gold",
		"key_def_id": "key_gold",
	})
	assert_true(ok,
		"UNLOCK with gold key on gold chest must return true (correct tier per DOCS §4.4)")
	# Chest must now be unlocked.
	var chest_state: Dictionary = Inventory.get_chest_state(chest_pos)
	assert_false(chest_state.get("locked", true),
		"Gold chest must be unlocked after correct gold key used")
