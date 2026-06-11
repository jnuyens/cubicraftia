# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# test_spawning_rules.gd — Unit tests for hostile mob spawning rules.
#
# Anchors:
#   DOCS.md §5.1 — sandbox suppresses hostile spawns
#   DOCS.md §5.3 — light-level gate; ~10/chunk cap; bed-bubble blocks spawn
#   03-CONTEXT.md D-01 — sandbox mode suppresses all survival mechanics
#   03-CONTEXT.md D-10 — bed-bubble 8m radius blocks spawns AND repels ghost
#
# Note: Engine.has_singleton() returns false for GDScript autoloads registered via
# project.godot (per STATE.md `inventory-engine-has-singleton` decision). Tests use
# has_method() checks on the Spawning autoload directly, per the established pattern.

extends GutTest

const Phase3Fixtures = preload("res://tests/conftest_phase3.gd")

var _world_id: String = ""

func before_each() -> void:
	_world_id = Phase3Fixtures.open_temp_world("survival")


func after_each() -> void:
	Phase3Fixtures.close_temp_world()
	Phase3Fixtures.cleanup_temp_world(_world_id)
	_world_id = ""


# ─── Test 1: Sandbox suppresses all hostile spawns ────────────────────────────

func test_sandbox_suppresses_all_hostile_spawns() -> void:
	# DOCS §5.1 + D-01: in sandbox mode, Spawning.try_spawn_tick() emits no mobs.
	if not Spawning.has_method("try_spawn_tick"):
		pending("Spawning.try_spawn_tick not available — pending until Plan 03-03")
		return
	Phase3Fixtures.fake_survival_mode(false)  # Set world to sandbox.
	# Count hostile spawn attempts across 10 ticks.
	watch_signals(Spawning)
	for _i: int in range(10):
		Spawning.try_spawn_tick()
	assert_signal_not_emitted(Spawning, "hostile_spawned",
		"Spawning.hostile_spawned must not fire in sandbox mode (DOCS §5.1 + D-01)")


# ─── Test 2: Survival spawns only below light threshold ───────────────────────

func test_survival_spawns_only_below_light_threshold() -> void:
	# DOCS §5.3: hostile spawns require ambient_light < 0.1 AND nighttime.
	if not Spawning.has_method("is_eligible_spawn_position"):
		pending("Spawning.is_eligible_spawn_position not available — pending until Plan 03-03")
		return
	Phase3Fixtures.fake_survival_mode(true)  # Set world to survival.
	# With daytime (high ambient light), no spawn should occur.
	if WorldClock.has_method("_set_elapsed_for_test"):
		WorldClock._set_elapsed_for_test(WorldClock.SECONDS_PER_DAY * 0.5)  # Noon.
	var spawn_pos := Vector3(0, 64, 0)
	var ambient_light_day: float = 1.0  # Daytime = high light.
	var eligible_day: bool = Spawning.is_eligible_spawn_position(spawn_pos, ambient_light_day)
	assert_false(eligible_day,
		"Spawn must be suppressed during daytime / high ambient light (DOCS §5.3)")
	# With low ambient light (dark cave), spawn should be eligible.
	var ambient_light_dark: float = 0.05  # Below 0.1 threshold.
	var eligible_dark: bool = Spawning.is_eligible_spawn_position(spawn_pos, ambient_light_dark)
	assert_true(eligible_dark,
		"Spawn must be eligible in dark conditions (ambient_light < 0.1 per DOCS §5.3)")


# ─── Test 3: Per-chunk hostile cap is enforced ────────────────────────────────

func test_per_chunk_cap_enforced() -> void:
	# DOCS §5.3: hostile mob cap is ~10 per chunk (main_scene.hostile_mob_active_cap).
	if not Spawning.has_method("can_spawn_in_chunk"):
		pending("Spawning.can_spawn_in_chunk not available — pending until Plan 03-03")
		return
	Phase3Fixtures.fake_survival_mode(true)
	# Simulate filling a chunk to the cap.
	var test_chunk := Vector3i(0, 0, 0)
	Spawning.reset_chunk_count(test_chunk)  # Clear any existing count.
	# Fill to cap (10 hostiles).
	for _i: int in range(10):
		Spawning._register_hostile_in_chunk(test_chunk, "laser_penguin_%d" % _i)
	# 11th spawn attempt in the same chunk must fail.
	var can_spawn: bool = Spawning.can_spawn_in_chunk(test_chunk)
	assert_false(can_spawn,
		"Spawning must be blocked at the per-chunk cap (~10 per DOCS §5.3)")
	# Clean up for other tests.
	Spawning.reset_chunk_count(test_chunk)


# ─── Test 4: Bed bubble blocks spawns ─────────────────────────────────────────

func test_bed_bubble_blocks_spawn() -> void:
	# D-10: within 8 m of any placed builder-bed, no hostile spawns.
	if not Spawning.has_method("register_bed"):
		pending("Spawning.register_bed not available — pending until Plan 03-03")
		return
	Phase3Fixtures.fake_survival_mode(true)
	# Register a bed at world origin.
	var bed_pos := Vector3(0.0, 0.0, 0.0)
	Spawning.register_bed(bed_pos)
	# Candidate at 4 m from bed → inside 8 m bubble → should be blocked.
	var inside_bubble := Vector3(4.0, 0.0, 0.0)
	assert_true(Spawning.is_inside_any_bed_bubble(inside_bubble),
		"Position 4 m from bed should be inside the 8 m bed bubble (D-10)")
	# Candidate at 10 m from bed → outside bubble → should be eligible.
	var outside_bubble := Vector3(10.0, 0.0, 0.0)
	assert_false(Spawning.is_inside_any_bed_bubble(outside_bubble),
		"Position 10 m from bed should be outside the 8 m bed bubble (D-10)")
	# Clean up bed.
	Spawning.unregister_bed(bed_pos)
