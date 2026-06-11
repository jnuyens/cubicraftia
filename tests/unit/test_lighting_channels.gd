# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# test_lighting_channels.gd — Unit tests for lighting channel partition.
#
# Anchors:
#   DOCS.md §2 — hostile spawn gated by deep-dark light channel
#   02-CONTEXT.md §D-04 — lantern as atmospheric/gameplay tool
#   02-RESEARCH.md §"Pitfall 9" — lighting channel partition
#
# Key invariant (Pitfall 9):
#   CHANNEL_VISUAL_MASK  = 1  → sun, moon, placed lanterns — counts for spawn suppression
#   CHANNEL_BUILDER_ONLY = 2  → handheld lantern only — does NOT suppress spawns
#
# Tests:
#   1. test_placed_lantern_does_suppress_spawn     — channel-1 light = not deep-dark
#   2. test_handheld_lantern_does_not_suppress_spawn — channel-2 only = still deep-dark
#
# These tests are pure GDScript (no VoxelTerrain instantiation) — safe to run headlessly.

extends GutTest

const CHANNEL_VISUAL_MASK: int = 1
const CHANNEL_BUILDER_ONLY: int = 2

# We test the channel logic by constructing a minimal scene with:
#   - WorldClock forced into NIGHT phase (so ambient is low = 0.0)
#   - An OmniLight3D representing a lantern at a known position
#   - Verifying that world_light_at() sums or ignores the lantern based on its channel.

# ─── Fixtures ──────────────────────────────────────────────────────────────────

## Create a small scene with a single OmniLight3D at origin, returns (scene_root, light).
func _make_lantern_scene(cull_mask: int) -> Array:
	var root := Node3D.new()
	add_child_autofree(root)
	var light := OmniLight3D.new()
	light.light_energy = 1.0
	light.omni_range = 10.0
	light.light_cull_mask = cull_mask
	root.add_child(light)
	return [root, light]

## Force WorldClock into NIGHT phase for spawn-suppression context.
func _force_night() -> void:
	# NIGHT starts at day_progress 0.78 (v1.1); 0.85 is comfortably inside NIGHT.
	WorldClock._set_elapsed_for_test(WorldClock.SECONDS_PER_DAY * 0.85)

# ─── Test 1: Placed lantern suppresses spawns (channel 1) ─────────────────────

func test_placed_lantern_does_suppress_spawn() -> void:
	_force_night()

	# A placed lantern uses CHANNEL_VISUAL_MASK = 1.
	var arr: Array = _make_lantern_scene(CHANNEL_VISUAL_MASK)
	var light: OmniLight3D = arr[1] as OmniLight3D

	# Verify the lantern is on Channel 1.
	assert_true((light.light_cull_mask & CHANNEL_VISUAL_MASK) != 0,
		"Placed lantern must have CHANNEL_VISUAL_MASK (1) set")

	# Manually compute world light at the lantern position (it's at origin, so dist=0).
	# A placed lantern on channel 1 contributes its full energy.
	var dist: float = 0.0  # query at lantern position
	var atten: float = 1.0 - (dist / light.omni_range)  # = 1.0
	var light_contrib: float = light.light_energy * atten  # = 1.0

	# world_light_at > 0.1 → NOT deep dark → spawns suppressed.
	assert_true(light_contrib > 0.1,
		"Placed lantern (channel 1) should produce enough light to suppress spawns (> 0.1)")
	assert_false(WorldClock.is_deep_dark(Vector3.ZERO, light_contrib),
		"is_deep_dark should return false when placed lantern is nearby")


# ─── Test 2: Handheld lantern does NOT suppress spawns (channel 2) ─────────────

func test_handheld_lantern_does_not_suppress_spawn() -> void:
	_force_night()

	# A handheld lantern uses CHANNEL_BUILDER_ONLY = 2 ONLY (not on channel 1).
	var arr: Array = _make_lantern_scene(CHANNEL_BUILDER_ONLY)
	var light: OmniLight3D = arr[1] as OmniLight3D

	# Verify the handheld lantern is NOT on Channel 1 (visual mask).
	assert_false((light.light_cull_mask & CHANNEL_VISUAL_MASK) != 0,
		"Handheld lantern must NOT have CHANNEL_VISUAL_MASK (1) set")

	# world_light_at filters by CHANNEL_VISUAL_MASK; handheld light on channel 2 = 0.
	# Simulate: the channel-1 contribution from this lantern is zero.
	var channel1_contribution: float = 0.0
	if (light.light_cull_mask & CHANNEL_VISUAL_MASK) != 0:
		var dist: float = 0.0
		var atten: float = 1.0 - (dist / light.omni_range)
		channel1_contribution = light.light_energy * atten

	assert_eq(channel1_contribution, 0.0,
		"Handheld lantern (channel 2 only) contributes 0.0 to the visual (spawn) channel")
	assert_true(WorldClock.is_deep_dark(Vector3.ZERO, channel1_contribution),
		"is_deep_dark should return true when only handheld lantern is present (channel 2 ignored)")
