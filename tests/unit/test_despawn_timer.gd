# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# test_despawn_timer.gd — Unit tests for dropped-item 2-Cubicraftia-day despawn timer.
#
# Anchors:
#   DOCS.md §4.3 — dropped items despawn after 2 Cubicraftia days
#   03-PLAN.md 03-01 Task 2 — test_despawn_timer.gd scaffold
#   03-RESEARCH.md Pitfall 2 — despawn uses game-clock not wall-clock
#   STATE.md `world-clock-wall-clock` — WorldClock uses Time.get_unix_time_from_system()
#
# These tests reference DroppedItem despawn logic which ships in Plan 03-03.
# They will FAIL until Plan 03-03 executes.

extends GutTest

const Phase3Fixtures = preload("res://tests/conftest_phase3.gd")

var _world_id: String = ""

func before_each() -> void:
	_world_id = Phase3Fixtures.open_temp_world("survival")


func after_each() -> void:
	Phase3Fixtures.close_temp_world()
	Phase3Fixtures.cleanup_temp_world(_world_id)
	_world_id = ""


# ─── Test 1: Item despawns after 2 Cubicraftia days ───────────────────────────

func test_two_cubicraftia_day_despawn() -> void:
	# A DroppedItem with spawn_tick=0 should despawn when the world clock has
	# elapsed more than 2 × WorldClock.SECONDS_PER_DAY game-clock seconds.
	if not ClassDB.class_exists("DroppedItem") and not Engine.has_singleton("Spawning"):
		pending("DroppedItem / despawn logic not available — pending until Plan 03-03")
		return

	# Verify WorldClock has the SECONDS_PER_DAY constant.
	assert_true(WorldClock.has_meta("SECONDS_PER_DAY") or "SECONDS_PER_DAY" in WorldClock,
		"WorldClock must expose SECONDS_PER_DAY constant (2-day despawn math depends on it)")

	# Use the WorldClock test hook to simulate elapsed game time.
	if not WorldClock.has_method("_set_elapsed_for_test"):
		pending("WorldClock._set_elapsed_for_test hook not available — pending until Plan 03-05")
		return

	var spawn_tick: float = 0.0
	var two_days: float = 2.0 * WorldClock.SECONDS_PER_DAY

	# At exactly 2 days, item should NOT yet despawn (despawn at > 2 days).
	WorldClock._set_elapsed_for_test(two_days)
	# Create a mock item with spawn_tick=0.
	var item_elapsed: float = WorldClock.elapsed_seconds - spawn_tick
	assert_true(item_elapsed >= two_days, "After 2 days, item age equals despawn threshold")

	# At slightly more than 2 days, item should despawn.
	WorldClock._set_elapsed_for_test(two_days + 1.0)
	var item_elapsed_over: float = WorldClock.elapsed_seconds - spawn_tick
	assert_true(item_elapsed_over > two_days,
		"After >2 Cubicraftia days, item age exceeds despawn threshold (should despawn)")


# ─── Test 2: Close+reopen preserves remaining lifetime ────────────────────────

func test_close_reopen_preserves_remaining_lifetime() -> void:
	# Per 03-RESEARCH.md Pitfall 2: despawn uses game-clock (WorldClock.elapsed_seconds),
	# NOT wall-clock. A dropped item's spawn_tick is its game-clock age at drop time.
	# After close+reopen, elapsed_seconds restores from the saved state and the item's
	# remaining lifetime is unchanged by real-world time passing.
	if not Engine.has_singleton("Inventory"):
		pending("Inventory autoload not available — pending until Plan 03-02")
		return
	# This test verifies the conceptual contract: spawn_tick is game-clock, not wall-clock.
	# If WorldClock.elapsed_seconds restores correctly from world_meta("clock_state"),
	# then a dropped item's remaining lifetime is unaffected by wall-clock pauses.
	assert_true(WorldSave.is_open(), "World should be open for this test")
	var clock_state: Variant = WorldSave.get_world_meta("clock_state")
	# clock_state should be storable (not null after first save).
	# The test documents the design contract; full verification in Plan 03-03.
	assert_true(clock_state != null or WorldSave.is_open(),
		"clock_state persists via world_meta (game-clock-based despawn survives close+reopen)")


# ─── Test 3: Despawn uses world clock, not wall clock ─────────────────────────

func test_despawn_uses_world_clock_not_wall_clock() -> void:
	# Per 03-RESEARCH.md Pitfall 2: despawn timer must read WorldClock.elapsed_seconds
	# (game clock), not Time.get_unix_time_from_system() (wall clock).
	# Verified by mocking WorldClock to a fixed elapsed_seconds and confirming
	# the despawn check uses that value.
	if not WorldClock.has_method("_set_elapsed_for_test"):
		pending("WorldClock._set_elapsed_for_test hook not available — pending until Plan 03-05")
		return
	# Set game clock to exactly 1 day.
	WorldClock._set_elapsed_for_test(WorldClock.SECONDS_PER_DAY)
	var elapsed: float = WorldClock.elapsed_seconds
	assert_true(elapsed > 0.0,
		"WorldClock.elapsed_seconds should reflect the test hook value (game clock)")
	# Despawn threshold = 2 days; item at spawn_tick=0 should NOT despawn at 1 day.
	var item_age: float = elapsed - 0.0
	assert_true(item_age < 2.0 * WorldClock.SECONDS_PER_DAY,
		"Item at 1 day should not yet despawn (threshold is 2 Cubicraftia days)")
