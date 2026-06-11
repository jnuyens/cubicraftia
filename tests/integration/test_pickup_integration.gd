# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# test_pickup_integration.gd — Integration tests for DroppedItem pickup → Inventory ADD.
#
# Anchors:
#   DOCS.md §4.3 — dropped item pickup adds to builder inventory
#   03-PLAN.md 03-01 Task 2 — test_pickup_integration.gd scaffold
#   03-RESEARCH.md Pitfall 8 — full inventory blocks pickup with 2-second cooldown
#   03-CONTEXT.md — DroppedItem.picked_up signal → Inventory.apply_event ADD
#
# These tests reference DroppedItem.try_pickup() and Inventory autoload shipping in Plan 03-03.
# They will FAIL until Plan 03-03 and Plan 03-02 execute.

extends GutTest

const Phase3Fixtures = preload("res://tests/conftest_phase3.gd")

var _world_id: String = ""
var _builder_id: String = "test_builder_pickup_001"

func before_each() -> void:
	_world_id = Phase3Fixtures.open_temp_world("survival")


func after_each() -> void:
	Phase3Fixtures.close_temp_world()
	Phase3Fixtures.cleanup_temp_world(_world_id)
	_world_id = ""


# ─── Test 1: Picked-up signal adds item to inventory ─────────────────────────

func test_dropped_item_picked_up_signal_adds_to_inventory() -> void:
	# DroppedItem.try_pickup(builder) → emits picked_up + queue_frees
	# → Inventory.get_slots(builder).has(item.def_id)
	var dropped_item_path := "res://src/world/dropped_item.tscn"
	if not ResourceLoader.exists(dropped_item_path):
		pending("dropped_item.tscn not available — pending until Plan 03-03")
		return
	if not Engine.has_singleton("Inventory"):
		pending("Inventory autoload not available — pending until Plan 03-02")
		return
	var inventory = Engine.get_singleton("Inventory")
	# Spawn a DroppedItem with def_id = "brick_1x1".
	var dropped_packed: PackedScene = load(dropped_item_path)
	var dropped: Node = dropped_packed.instantiate()
	dropped.set("def_id", "brick_1x1")
	dropped.set("count", 1)
	add_child(dropped)
	await get_tree().process_frame
	# Mock a builder node with the correct ID.
	var builder_node := Node.new()
	builder_node.set_meta("builder_id", _builder_id)
	add_child(builder_node)
	# Try pickup.
	watch_signals(dropped)
	var pickup_ok: bool = dropped.try_pickup(builder_node)
	assert_true(pickup_ok, "try_pickup should succeed (non-full inventory)")
	assert_signal_emitted(dropped, "picked_up",
		"DroppedItem should emit 'picked_up' signal on successful pickup")
	# Verify item is now in inventory.
	await get_tree().process_frame
	var slots: Array = inventory.get_slots(_builder_id)
	var found: bool = false
	for s: Dictionary in slots:
		if s.get("def_id", "") == "brick_1x1" and s.get("count", 0) > 0:
			found = true
			break
	assert_true(found, "brick_1x1 should be in builder inventory after pickup")
	builder_node.queue_free()


# ─── Test 2: Pickup blocked when inventory is full ───────────────────────────

func test_pickup_blocked_when_inventory_full() -> void:
	# 03-RESEARCH.md Pitfall 8: fill 48 slots with non-stackable bricks; try_pickup returns false;
	# a 2-second cooldown is set to prevent spam toast.
	var dropped_item_path := "res://src/world/dropped_item.tscn"
	if not ResourceLoader.exists(dropped_item_path):
		pending("dropped_item.tscn not available — pending until Plan 03-03")
		return
	if not Engine.has_singleton("Inventory"):
		pending("Inventory autoload not available — pending until Plan 03-02")
		return
	var inventory = Engine.get_singleton("Inventory")
	# Fill all 48 slots with unique non-stackable items.
	for slot_idx: int in range(48):
		inventory.apply_event({
			"kind": "ADD",
			"builder_id": _builder_id,
			"def_id": "brick_1x1_slot_%d" % slot_idx,  # Unique IDs → non-stackable.
			"count": 64,
			"slot": slot_idx,
		})
	# Spawn a DroppedItem.
	var dropped_packed: PackedScene = load(dropped_item_path)
	var dropped: Node = dropped_packed.instantiate()
	dropped.set("def_id", "brick_slope_outer")
	dropped.set("count", 1)
	add_child(dropped)
	await get_tree().process_frame
	var builder_node := Node.new()
	builder_node.set_meta("builder_id", _builder_id)
	add_child(builder_node)
	var pickup_ok: bool = dropped.try_pickup(builder_node)
	assert_false(pickup_ok,
		"try_pickup must return false when inventory is full (Pitfall 8)")
	dropped.queue_free()
	builder_node.queue_free()


# ─── Test 3: Inventory-full toast shown once, not per item ───────────────────

func test_inventory_full_toast_shown_once_not_per_item() -> void:
	# Walking through 30 dropped items should emit "ui.inventory.full" toast exactly once.
	if not Engine.has_singleton("Inventory"):
		pending("Inventory autoload not available — pending until Plan 03-02")
		return
	if not Engine.has_singleton("Toasts"):
		pending("Toasts autoload not available — pending until Plan 03-05")
		return
	var toasts = Engine.get_singleton("Toasts")
	watch_signals(toasts)
	# Fill inventory completely.
	var inventory = Engine.get_singleton("Inventory")
	for slot_idx: int in range(48):
		inventory.apply_event({
			"kind": "ADD",
			"builder_id": _builder_id,
			"def_id": "filler_item_%d" % slot_idx,
			"count": 64,
			"slot": slot_idx,
		})
	# Simulate walking through 30 dropped items.
	var builder_node := Node.new()
	builder_node.set_meta("builder_id", _builder_id)
	add_child(builder_node)
	var dropped_item_path := "res://src/world/dropped_item.tscn"
	if not ResourceLoader.exists(dropped_item_path):
		pending("dropped_item.tscn not available — pending until Plan 03-03")
		builder_node.queue_free()
		return
	var dropped_packed: PackedScene = load(dropped_item_path)
	for _i: int in range(30):
		var dropped: Node = dropped_packed.instantiate()
		dropped.set("def_id", "brick_1x1")
		dropped.set("count", 1)
		add_child(dropped)
		dropped.try_pickup(builder_node)
		dropped.queue_free()
	await get_tree().process_frame
	# The toast "ui.inventory.full" should have been emitted exactly once (tip-tick debounce).
	var emit_count: int = get_signal_emit_count(toasts, "toast_shown")
	var full_toast_count: int = 0
	# Count only "ui.inventory.full" toast emissions.
	for i: int in range(emit_count):
		var params: Array = get_signal_parameters(toasts, "toast_shown", i)
		if params.size() > 0 and str(params[0]) == "ui.inventory.full":
			full_toast_count += 1
	assert_eq(full_toast_count, 1,
		"'ui.inventory.full' toast must fire exactly once, not per item (tip-tick debounce)")
	builder_node.queue_free()
