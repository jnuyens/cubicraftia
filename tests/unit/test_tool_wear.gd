# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# test_tool_wear.gd — Unit tests for tool durability: sandbox never decrements, survival does.
#
# Anchors:
#   DOCS.md §3.4 — tool wear in survival / no wear in sandbox
#   DOCS.md §3.4 — v1 tool kit: tiered pickaxe / shovel / dynamite / handheld lantern
#   02-CONTEXT.md §D-12 — tool durability UI placement (survival mode only)
#   02-RESEARCH.md §"Tool System"
#
# Owned by Plan 10 (tool wear implementation turns these GREEN).
# Pattern: mirrors test_stud_grid.gd (before_each / after_each + signal watch).

extends GutTest

const PICKAXE_WOOD_PATH := "res://src/tools/pickaxe_wood.tres"
const DYNAMITE_PATH := "res://src/tools/dynamite.tres"
const LANTERN_PATH := "res://src/tools/lantern_handheld.tres"

# ToolWear instance under test (instantiated fresh each test).
var _wear: Node = null

# ToolDefinition resources loaded once.
var _pickaxe: ToolDefinition = null
var _dynamite: ToolDefinition = null
var _lantern: ToolDefinition = null

# ─── Helpers ─────────────────────────────────────────────────────────────────

## Stub WorldSave to return a specific mode without a real SQLite database.
## Sets WorldSave._db to a mock table so is_open() returns true,
## and get_world_meta("mode") returns the desired value.
func _stub_world_save_mode(mode: String) -> void:
	# We cannot easily stub WorldSave without a real database in unit tests.
	# Instead, patch Features.is_survival_mode via a local ToolWear subclass approach.
	# The simplest approach: override _db presence check in WorldSave by calling
	# a test-only helper, OR directly set a test-accessible field.
	# Since WorldSave is a global autoload we can't easily mock it without the DB.
	#
	# Strategy: we directly set a "_test_mode_override" field on ToolWear if it exists,
	# otherwise we fall back to testing via the is_survival_mode() indirection.
	# The ToolWear autoload has a method _test_set_mode_override for unit tests.
	if _wear.has_method("_test_set_mode_override"):
		_wear.call("_test_set_mode_override", mode)


# ─── Lifecycle ────────────────────────────────────────────────────────────────

func before_each() -> void:
	# Load tool definitions.
	_pickaxe = load(PICKAXE_WOOD_PATH) as ToolDefinition
	assert_not_null(_pickaxe, "pickaxe_wood.tres should load")
	assert_eq(_pickaxe.tool_id, "pickaxe_wood", "tool_id should be pickaxe_wood")
	assert_eq(_pickaxe.max_durability, 60, "max_durability for wood pickaxe should be 60")

	_dynamite = load(DYNAMITE_PATH) as ToolDefinition
	assert_not_null(_dynamite, "dynamite.tres should load")

	_lantern = load(LANTERN_PATH) as ToolDefinition
	assert_not_null(_lantern, "lantern_handheld.tres should load")
	assert_eq(_lantern.max_durability, 0, "lantern max_durability must be 0 (never wears out)")

	# Instantiate a fresh ToolWear node for each test (not the global autoload singleton,
	# to avoid test cross-contamination).
	var wear_script := load("res://src/autoload/tool_wear.gd") as Script
	_wear = Node.new()
	_wear.set_script(wear_script)
	add_child_autofree(_wear)


func after_each() -> void:
	_wear = null
	_pickaxe = null
	_dynamite = null
	_lantern = null


# ─── Test 1: sandbox mode — no decrement ─────────────────────────────────────

func test_sandbox_mode_no_decrement() -> void:
	# In sandbox mode, decrement_on_use must be a no-op (returns true, durability stays max).
	# We stub the survival mode to false by using the test override.
	_stub_world_save_mode("sandbox")

	var instance_id := "slot_1"
	# Call decrement_on_use 100 times — durability must stay at max_durability.
	for i: int in range(100):
		var still_usable: bool = _wear.decrement_on_use(_pickaxe, instance_id)
		assert_true(still_usable, "decrement_on_use should return true in sandbox mode (i=%d)" % i)

	# Durability should remain at max since no decrement occurred.
	var dur: int = _wear.get_durability(instance_id, _pickaxe)
	assert_eq(dur, _pickaxe.max_durability,
		"Durability should remain at max_durability (%d) in sandbox mode; got %d" % [
			_pickaxe.max_durability, dur])


# ─── Test 2: survival mode — decrement on use ─────────────────────────────────

func test_survival_mode_decrement_on_use() -> void:
	# In survival mode, each call to decrement_on_use reduces durability by 1.
	_stub_world_save_mode("survival")

	var instance_id := "slot_2"
	var uses := 10

	# Decrement 10 times.
	for i: int in range(uses):
		_wear.decrement_on_use(_pickaxe, instance_id)

	var dur: int = _wear.get_durability(instance_id, _pickaxe)
	var expected: int = _pickaxe.max_durability - uses
	assert_eq(dur, expected,
		"After %d uses in survival mode, durability should be %d; got %d" % [uses, expected, dur])


# ─── Test 3: durability reaching zero emits worn_out ────────────────────────

func test_durability_zero_emits_worn_out() -> void:
	_stub_world_save_mode("survival")

	var instance_id := "slot_3"
	# Set durability to 1 so the next use triggers worn_out.
	_wear.set_durability(instance_id, 1, _pickaxe)
	assert_eq(_wear.get_durability(instance_id, _pickaxe), 1,
		"set_durability to 1 should be reflected in get_durability")

	# Watch the worn_out signal.
	watch_signals(_wear)

	# One use should deplete to 0 and emit worn_out.
	var still_usable: bool = _wear.decrement_on_use(_pickaxe, instance_id)
	assert_false(still_usable, "decrement_on_use should return false when durability reaches 0")

	# Verify worn_out was emitted exactly once.
	assert_signal_emitted(_wear, "worn_out", "worn_out signal should be emitted")
	assert_eq(get_signal_emit_count(_wear, "worn_out"), 1,
		"worn_out should be emitted exactly once")

	# Verify the tool is now considered worn out.
	assert_true(_wear.is_worn_out(instance_id),
		"is_worn_out should return true after durability reaches 0")
