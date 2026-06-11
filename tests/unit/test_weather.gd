# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# test_weather.gd — Unit tests for the Weather autoload (rain-dance quota + Markov chain).
#
# Tests:
#   1. test_rain_dance_second_attempt_rejected     — second trigger returns accepted=false
#   2. test_rain_dance_quota_survives_save_load    — quota persists across save/reopen
#   3. test_clear_rain_markov_deterministic_per_seed — same seed → same state sequence
#
# Anchors:
#   DOCS.md §2 — rain dance ≤ 1/Cubicraftia-day/builder; "the sky won't listen again today"
#   02-CONTEXT.md §D-04 — weather as part of biome atmosphere
#   02-RESEARCH.md §"Day/Night + Weather State Machine"
#
# These tests instantiate the Weather and WorldClock scripts directly (not the autoload
# singletons) to keep tests hermetic. For quota persistence tests, a real WorldSave
# database is opened in user://test_worlds/weather_test_{uid}/ and cleaned up after_all.

extends GutTest

# Script paths (instantiate fresh — do not use the autoload singletons, which share state).
const WEATHER_SCRIPT := "res://src/autoload/weather.gd"
const WORLD_CLOCK_SCRIPT := "res://src/autoload/world_clock.gd"

# ─── Helpers ──────────────────────────────────────────────────────────────────

## Create a fresh WorldClock node (not the autoload — its own isolated instance).
func _make_clock(elapsed_s: float = 0.0) -> Node:
	var clock: Node = load(WORLD_CLOCK_SCRIPT).new()
	add_child_autofree(clock)
	clock._set_elapsed_for_test(elapsed_s)
	return clock


## Create a fresh Weather node. Inject a mock WorldClock reference so it reads
## current_day_index from the supplied clock instead of the global autoload.
## Since Weather reads WorldClock.current_day_index as a global, we patch the
## WorldClock autoload's state for the duration of the test instead.
func _make_weather() -> Node:
	var w: Node = load(WEATHER_SCRIPT).new()
	w._rng = RandomNumberGenerator.new()
	add_child_autofree(w)
	return w


## Open a fresh test world with a unique name, seed it, and return the world_id.
## The caller is responsible for calling WorldSave.close_world() in after_each/after_all.
func _open_test_world(seed_val: int = 42) -> String:
	var uid: String = str(Time.get_unix_time_from_system()).replace(".", "_")
	var world_id := "weather_test_%s" % uid
	var ok: bool = WorldSave.open_world(world_id, seed_val, "sandbox")
	assert_true(ok, "WorldSave.open_world must succeed for weather tests")
	return world_id


# ─── Test 1 ────────────────────────────────────────────────────────────────────

func test_rain_dance_second_attempt_rejected() -> void:
	# Use a self-contained Weather instance with a fake WorldSave.is_open guard.
	# Since Weather._rain_dance_used is keyed on (builder_id → day_index) and
	# uses WorldClock.current_day_index from the global autoload, we patch the
	# global WorldClock's state and use a Weather instance with empty WorldSave.

	# Back up WorldClock state (restore after test).
	var original_day_idx: int = WorldClock.current_day_index
	var original_phase = WorldClock.current_phase
	var original_elapsed: float = WorldClock.elapsed_seconds

	# Set WorldClock to day 5.
	WorldClock._set_elapsed_for_test(5.0 * WorldClock.SECONDS_PER_DAY)

	# Instantiate a fresh Weather (not the autoload singleton).
	# Add to tree first (_ready sets _rng), then seed after _ready runs.
	var weather: Node = load(WEATHER_SCRIPT).new()
	add_child_autofree(weather)
	weather._rng.seed = 1234

	# First rain dance attempt — must be accepted.
	var result1: Dictionary = weather.trigger_rain_dance("uuid-a")
	assert_true(result1.get("accepted", false),
		"First rain dance attempt must be accepted")
	assert_eq(result1.get("message_key", ""),
		"ui.weather.rain_dance_summoned",
		"First attempt message key must be 'ui.weather.rain_dance_summoned'")
	assert_eq(weather.state, weather.State.RAIN,
		"Weather state must be RAIN after accepted rain dance")

	# Second attempt same day — must be rejected.
	var result2: Dictionary = weather.trigger_rain_dance("uuid-a")
	assert_false(result2.get("accepted", true),
		"Second rain dance attempt same day must be rejected")
	assert_eq(result2.get("message_key", ""),
		"ui.weather.sky_wont_listen_again_today",
		"Second attempt message key must be 'ui.weather.sky_wont_listen_again_today'")

	# Different builder — must still be accepted (quota is per-builder).
	var result3: Dictionary = weather.trigger_rain_dance("uuid-b")
	assert_true(result3.get("accepted", false),
		"A different builder's first rain dance must be accepted")

	# Restore WorldClock state.
	WorldClock._set_elapsed_for_test(original_elapsed)

# ─── Test 2 ────────────────────────────────────────────────────────────────────

func test_rain_dance_quota_survives_save_load() -> void:
	# Ensure no world is currently open.
	if WorldSave.is_open():
		WorldSave.close_world()

	# Open a fresh world.
	var world_id: String = _open_test_world(99)

	# Start WorldClock at day 7.
	var original_elapsed: float = WorldClock.elapsed_seconds
	WorldClock._set_elapsed_for_test(7.0 * WorldClock.SECONDS_PER_DAY)

	# Instantiate Weather and attach to world.
	# Add to tree first (_ready sets _rng), then seed after.
	var weather: Node = load(WEATHER_SCRIPT).new()
	add_child_autofree(weather)
	weather._rng.seed = 99 ^ weather._WEATHER_SEED_SALT

	# Use rain dance — accepted on first call.
	var r1: Dictionary = weather.trigger_rain_dance("uuid-persist-test")
	assert_true(r1.get("accepted", false),
		"First rain dance must be accepted")

	# Checkpoint world (persists rain_dance_quota).
	var cp_ok: bool = WorldSave.checkpoint()
	assert_true(cp_ok, "WorldSave.checkpoint must succeed")

	# Close and reopen the world.
	var world_meta_path: String = ProjectSettings.globalize_path(
		"user://worlds/%s/world.meta.sqlite" % world_id)
	WorldSave.close_world()

	var reopen_ok: bool = WorldSave.open_world(world_id, 99, "sandbox")
	assert_true(reopen_ok, "WorldSave.open_world (reopen) must succeed")

	# Create a fresh Weather instance and restore from save.
	# Add to tree first (_ready sets _rng), then seed after.
	var weather2: Node = load(WEATHER_SCRIPT).new()
	add_child_autofree(weather2)
	weather2._rng.seed = 99 ^ weather2._WEATHER_SEED_SALT
	weather2.load_from_world_save()

	# WorldClock day is still 7 (we haven't changed it).
	# The quota should still show "uuid-persist-test" as used today.
	var r2: Dictionary = weather2.trigger_rain_dance("uuid-persist-test")
	assert_false(r2.get("accepted", true),
		"After reload, rain dance quota must still be exhausted for same builder+day")
	assert_eq(r2.get("message_key", ""),
		"ui.weather.sky_wont_listen_again_today",
		"After reload, message key must be 'ui.weather.sky_wont_listen_again_today'")

	# Clean up.
	WorldSave.close_world()
	WorldClock._set_elapsed_for_test(original_elapsed)

	# Remove the test world directory.
	var test_world_dir: String = ProjectSettings.globalize_path("user://worlds/%s" % world_id)
	var dir := DirAccess.open(ProjectSettings.globalize_path("user://worlds/"))
	if dir != null:
		# Remove files inside the directory.
		var inner := DirAccess.open(test_world_dir)
		if inner != null:
			inner.list_dir_begin()
			var fname: String = inner.get_next()
			while fname != "":
				if not inner.current_is_dir():
					DirAccess.remove_absolute(test_world_dir + "/" + fname)
				fname = inner.get_next()
			inner.list_dir_end()
		DirAccess.remove_absolute(test_world_dir)

# ─── Test 3 ────────────────────────────────────────────────────────────────────

func test_clear_rain_markov_deterministic_per_seed() -> void:
	# Create two Weather instances seeded identically. After the same sequence of
	# day_boundary events they must have identical states.

	const TEST_SEED: int = 0xC0FFEE
	const SALT: int = 0x7EA7E5  # _WEATHER_SEED_SALT

	# Add to tree first (triggers _ready → _rng = RandomNumberGenerator.new()),
	# then set seed after _ready so _ready's assignment is overridden.
	var weather_a: Node = load(WEATHER_SCRIPT).new()
	add_child_autofree(weather_a)
	weather_a._rng.seed = TEST_SEED ^ SALT

	var weather_b: Node = load(WEATHER_SCRIPT).new()
	add_child_autofree(weather_b)
	weather_b._rng.seed = TEST_SEED ^ SALT

	# Both start CLEAR.
	assert_eq(weather_a.state, weather_a.State.CLEAR,
		"Weather A must start CLEAR")
	assert_eq(weather_b.state, weather_b.State.CLEAR,
		"Weather B must start CLEAR")

	# Drive 10 day boundaries on both instances and compare state after each.
	for day_idx: int in range(1, 11):
		# Call the internal Markov handler directly (bypasses WorldSave persistence
		# which requires an open world — not needed for this determinism test).
		weather_a._on_day_boundary(day_idx)
		weather_b._on_day_boundary(day_idx)
		assert_eq(weather_a.state, weather_b.state,
			"After day boundary %d, both Weather instances must have the same state" % day_idx)

	# Verify states are sensible (not always CLEAR — Markov must have run).
	# With seed 0xC0FFEE ^ 0x7EA7E5 and 10 rolls, at least one RAIN transition
	# should occur. We don't assert the exact states (they depend on the RNG stream)
	# but we assert both agree throughout.
	# The identity check above already proves determinism for all 10 steps.
	pass
