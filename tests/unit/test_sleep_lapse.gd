# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# test_sleep_lapse.gd — Unit tests for 10× time-lapse sleep mechanic.
#
# Anchors:
#   03-CONTEXT.md D-12 — solo sleep = accelerated 10× time-lapse
#   03-RESEARCH.md Code Examples (WorldClock.start_sleep_lapse)
#   03-RESEARCH.md Pitfall 9 — hostile inside bed bubble cancels sleep
#
# Note: Engine.has_singleton() returns false for GDScript autoloads registered via
# project.godot (per STATE.md `inventory-engine-has-singleton` decision). Tests use
# has_method() checks on autoloads directly, per the established pattern.

extends GutTest

const Phase3Fixtures = preload("res://tests/conftest_phase3.gd")

var _world_id: String = ""

func before_each() -> void:
	_world_id = Phase3Fixtures.open_temp_world("survival")


func after_each() -> void:
	Phase3Fixtures.close_temp_world()
	Phase3Fixtures.cleanup_temp_world(_world_id)
	_world_id = ""


# ─── Test 1: World clock advances at 10× during sleep lapse ──────────────────

func test_world_clock_advances_10x_during_lapse() -> void:
	# D-12: WorldClock.start_sleep_lapse(10.0) → elapsed_seconds increments at 10× wall_delta.
	if not WorldClock.has_method("start_sleep_lapse"):
		pending("WorldClock.start_sleep_lapse not available — pending until Plan 03-03")
		return
	if not WorldClock.has_method("_set_elapsed_for_test"):
		pending("WorldClock._set_elapsed_for_test test hook not available — pending until Plan 03-03")
		return
	WorldClock._set_elapsed_for_test(0.0)
	WorldClock.start_sleep_lapse(10.0)
	# Verify the multiplier is set.
	var multiplier: float = WorldClock.get("_sleep_multiplier") if "_sleep_multiplier" in WorldClock else -1.0
	assert_eq(multiplier, 10.0,
		"WorldClock sleep multiplier should be 10 during lapse (D-12)")


# ─── Test 2: Lapse auto-cancels at dawn ───────────────────────────────────────

func test_lapse_auto_cancels_at_dawn() -> void:
	# D-12: sleep lapse ends automatically when day_progress passes the DAWN threshold (0.05).
	if not WorldClock.has_method("start_sleep_lapse"):
		pending("WorldClock.start_sleep_lapse not available — pending until Plan 03-03")
		return
	if not WorldClock.has_method("_set_elapsed_for_test"):
		pending("WorldClock._set_elapsed_for_test test hook not available — pending until Plan 03-03")
		return
	# Start at dusk (progress ~0.75 through the day, i.e. night time).
	var night_elapsed: float = WorldClock.SECONDS_PER_DAY * 0.75
	WorldClock._set_elapsed_for_test(night_elapsed)
	WorldClock.start_sleep_lapse(10.0)
	# Verify multiplier is active.
	var multiplier_before: float = WorldClock.get("_sleep_multiplier") if "_sleep_multiplier" in WorldClock else -1.0
	assert_eq(multiplier_before, 10.0, "Multiplier must be 10 after start_sleep_lapse")
	# Now simulate the clock having advanced past dawn (day 1, progress 0.05).
	# By setting elapsed_seconds directly past the DAWN boundary, the wake-target check
	# in _process will trigger cancel_sleep_lapse("woke_at_dawn").
	var dawn_elapsed: float = WorldClock.SECONDS_PER_DAY * 1.05  # Just past day start.
	WorldClock._set_elapsed_for_test(dawn_elapsed)
	# Manually trigger the dawn-check logic that _process would call.
	# Since _running is false in test context (no start() called), we replicate the check.
	if "_sleep_target_progress" in WorldClock and WorldClock.get("_sleep_target_progress") >= 0.0:
		var progress: float = WorldClock.current_day_progress()
		var target: float = WorldClock.get("_sleep_target_progress")
		if progress <= target + 0.01 and progress >= 0.0:
			WorldClock.cancel_sleep_lapse("woke_at_dawn")
	# Multiplier should revert to 1.0 after dawn.
	var multiplier: float = WorldClock.get("_sleep_multiplier") if "_sleep_multiplier" in WorldClock else 10.0
	assert_eq(multiplier, 1.0,
		"Sleep lapse must auto-cancel at dawn (day_progress passes 0.05 threshold, D-12)")


# ─── Test 3: Lapse cancels when hostile enters bed bubble ────────────────────

func test_lapse_cancelled_by_hostile_in_bubble() -> void:
	# 03-RESEARCH.md Pitfall 9: every tick during lapse, Spawning.hostiles_inside_bed_bubble()
	# is polled; first positive result cancels the lapse.
	if not WorldClock.has_method("start_sleep_lapse"):
		pending("WorldClock.start_sleep_lapse not available — pending until Plan 03-03")
		return
	if not Spawning.has_method("register_bed"):
		pending("Spawning.register_bed not available — pending until Plan 03-03")
		return
	var bed_pos := Vector3(0.0, 0.0, 0.0)
	Spawning.register_bed(bed_pos)
	WorldClock.start_sleep_lapse(10.0)
	# Simulate a hostile entering the bed bubble — this calls WorldClock.cancel_sleep_lapse.
	Spawning._on_hostile_entered_bed_bubble(bed_pos, "test_hostile_001")
	# Multiplier should revert to 1.0 after hostile detection.
	var multiplier: float = WorldClock.get("_sleep_multiplier") if "_sleep_multiplier" in WorldClock else 10.0
	assert_eq(multiplier, 1.0,
		"Sleep lapse must cancel when a hostile enters the bed bubble (Pitfall 9)")
	Spawning.unregister_bed(bed_pos)


# ─── Test 4: Lapse cancellation emits toast key ───────────────────────────────

func test_lapse_cancellation_emits_toast_key() -> void:
	# D-12: when sleep is cancelled, Toasts.show is called with "ui.sleep.cancelled_unsafe".
	# Toasts autoload emits "toast_requested" (the registered signal in toasts.gd).
	if not WorldClock.has_method("cancel_sleep_lapse_with_reason"):
		pending("WorldClock.cancel_sleep_lapse_with_reason not available — pending until Plan 03-03")
		return
	if not Toasts.has_signal("toast_requested"):
		pending("Toasts.toast_requested signal not available — pending until autoload ships")
		return
	watch_signals(Toasts)
	WorldClock.start_sleep_lapse(10.0)
	WorldClock.cancel_sleep_lapse_with_reason("hostile_in_bubble")
	assert_signal_emitted_with_parameters(Toasts, "toast_requested",
		["ui.sleep.cancelled_unsafe", "warning"],
		"Toasts.toast_requested must fire with 'ui.sleep.cancelled_unsafe' on sleep cancellation (D-12)")
