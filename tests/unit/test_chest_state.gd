# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# test_chest_state.gd — Unit tests for chest types, slot counts, key types, and unlock semantics.
#
# Anchors:
#   DOCS.md §4.4 — 5 chest types, slot counts 48/48/54/60/72, 4 key types
#   03-PLAN.md 03-01 Task 2 — test_chest_state.gd scaffold
#   03-CONTEXT.md D-02 — chest UI + unlock semantics
#   03-CONTEXT.md D-04 — key types: bronze/silver/gold/diamond
#
# Plan 03-02 implements the Inventory autoload — tests 1, 3, 4 are now active.
# Test 2 (ChestEntity.REQUIRED_KEY) remains pending until Plan 03-04.

extends GutTest

const Phase3Fixtures = preload("res://tests/conftest_phase3.gd")

var _world_id: String = ""
var _builder_id: String = "test_builder_chest_001"

func before_each() -> void:
	_world_id = Phase3Fixtures.open_temp_world("survival")
	Inventory.detach_world()
	Inventory.attach_world()


func after_each() -> void:
	Phase3Fixtures.close_temp_world()
	Phase3Fixtures.cleanup_temp_world(_world_id)
	_world_id = ""


# ─── Test 1: Five chest types have correct slot counts ────────────────────────

func test_five_chest_types_have_correct_slot_counts() -> void:
	# DOCS §4.4: regular=48, bronze=48, silver=54, gold=60, diamond=72
	var expected: Dictionary = {
		"regular":  48,
		"bronze":   48,
		"silver":   54,
		"gold":     60,
		"diamond":  72,
	}
	for chest_type: String in expected:
		var slot_count: int = Inventory.get_chest_slot_count(chest_type)
		assert_eq(slot_count, expected[chest_type],
			"Chest type '%s' should have %d slots per DOCS §4.4" % [chest_type, expected[chest_type]])


# ─── Test 2: Four key types exist ─────────────────────────────────────────────

func test_four_key_types_exist() -> void:
	# DOCS §4.4: 4 key types matching chest tiers (bronze, silver, gold, diamond).
	# ChestEntity.REQUIRED_KEY maps chest type → key def_id string.
	if not ClassDB.class_exists("ChestEntity"):
		pending("ChestEntity class not available — pending until Plan 03-04")
		return
	# Use ClassDB.instantiate to get the class and access its constant dynamically.
	# Direct ChestEntity.REQUIRED_KEY would fail at parse time if class doesn't exist.
	var chest_instance: Object = ClassDB.instantiate("ChestEntity")
	if chest_instance == null:
		pending("ChestEntity could not be instantiated — pending until Plan 03-04")
		return
	var required_key_map: Dictionary = chest_instance.get("REQUIRED_KEY") if chest_instance.has_meta("REQUIRED_KEY") else {}
	if required_key_map.is_empty() and chest_instance.get_script() != null:
		# Try via script constant (class constant accessible via script).
		required_key_map = chest_instance.get_script().get_script_constant_map().get("REQUIRED_KEY", {})
	var expected_keys: Array[String] = ["bronze", "silver", "gold", "diamond"]
	for tier: String in expected_keys:
		assert_true(required_key_map.has(tier),
			"ChestEntity.REQUIRED_KEY must have an entry for '%s' chest tier" % tier)
		var key_def_id: String = str(required_key_map[tier])
		assert_false(key_def_id.is_empty(),
			"REQUIRED_KEY['%s'] must map to a non-empty key def_id" % tier)


# ─── Test 3: Unlock consumes key ──────────────────────────────────────────────

func test_unlock_consumes_key() -> void:
	# DOCS §4.4: unlocking a chest consumes exactly 1 matching key from inventory.
	# After UNLOCK event: chest.locked=false, key count in inventory decrements by 1.
	# Give builder one bronze key.
	Phase3Fixtures.populate_inventory(_builder_id, [{"def_id": "key_bronze", "count": 1}])
	var chest_pos := Vector3i(0, 0, 0)
	# Apply UNLOCK event.
	var ok: bool = Inventory.apply_event({
		"kind": "UNLOCK",
		"builder_id": _builder_id,
		"chest_coord": chest_pos,
		"chest_type": "bronze",
		"key_def_id": "key_bronze",
	})
	assert_true(ok, "UNLOCK event with matching bronze key should succeed")
	# Verify key was consumed.
	var slots: Array = Inventory.get_slots(_builder_id)
	var key_count: int = 0
	for s: Dictionary in slots:
		if s.get("def_id", "") == "key_bronze":
			key_count += s.get("count", 0)
	assert_eq(key_count, 0, "Bronze key should be consumed (count = 0) after UNLOCK")


# ─── Test 4: Persistent unlock survives close+reopen ─────────────────────────

func test_persistent_unlock_for_world_lifetime() -> void:
	# DOCS §4.4: chest unlock persists for the world's lifetime.
	# After UNLOCK + flush + close_world + open_world + attach_world: chest should still be unlocked.
	var chest_pos := Vector3i(5, 0, 5)
	Phase3Fixtures.populate_inventory(_builder_id, [{"def_id": "key_bronze", "count": 1}])
	Inventory.apply_event({
		"kind": "UNLOCK",
		"builder_id": _builder_id,
		"chest_coord": chest_pos,
		"chest_type": "bronze",
		"key_def_id": "key_bronze",
	})
	# Flush chest state to DB and reopen world.
	Inventory._flush_persistence()
	var wid := _world_id
	Phase3Fixtures.close_temp_world()
	var ok := WorldSave.open_world(wid, 42, "survival")
	assert_true(ok, "World should reopen after close")
	Inventory.attach_world()
	# Chest should still be unlocked.
	var chest_state: Dictionary = Inventory.get_chest_state(chest_pos)
	assert_false(chest_state.get("locked", true),
		"Chest unlock must persist across close+reopen (world lifetime per DOCS §4.4)")
