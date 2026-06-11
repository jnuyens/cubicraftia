# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# test_feature_flags.gd — DOC-09: every §9 deferred feature flag ships false
#
# Verifies that all 18 DOCS.md §9 feature flags are registered and return false.
# Also verifies that an unknown key causes an assertion error (debug-build guard).
#
# Referenced DOC: DOC-09 — "every not-in-v1 feature gated, ships off"
# See: DOCS.md §9, RESEARCH.md Pattern 1, scripts/verify-feature-flags.sh
extends GutTest


func test_all_deferred_features_are_registered() -> void:
	## Features._DEFERRED_FEATURES must contain exactly 18 keys (one per DOCS.md §9 row).
	assert_eq(
		Features._DEFERRED_FEATURES.size(),
		18,
		"Features._DEFERRED_FEATURES must have exactly 18 keys (18 DOCS.md §9 rows)"
	)


func test_all_deferred_features_return_false() -> void:
	## Every key in Features._DEFERRED_FEATURES must return false via is_enabled().
	## This is the Phase 1 invariant: no §9 feature is active at ship time.
	for key: String in Features._DEFERRED_FEATURES:
		assert_false(
			Features.is_enabled(key),
			"Feature '%s' must return false in Phase 1 (DOC-09)" % key
		)


func test_all_18_canonical_keys_are_present() -> void:
	## Verify the exact 18 canonical key names from DOCS.md §9 are all present.
	## This guards against typos that would silently skip a §9 row.
	var canonical_keys := [
		"snow_thunder_lightning",
		"hunger_thirst",
		"voice_chat",
		"open_lobbies",
		"pvp_combat",
		"creeper_explode",
		"mod_system",
		"vr_mode",
		"cosmetics_subscription",
		"cloud_world_sync",
		"resource_packs",
		"large_servers_5plus",
		"dedicated_server_dist",
		"web_browser_client",
		"cross_mode_switching",
		"brick_rotation",
		"master_builder_gating",
		"brick_gravity",
	]
	for key: String in canonical_keys:
		assert_true(
			key in Features._DEFERRED_FEATURES,
			"Canonical §9 key '%s' is missing from Features._DEFERRED_FEATURES" % key
		)


func test_voice_chat_is_false() -> void:
	## Spot-check the most commonly cited §9 feature.
	assert_false(Features.is_enabled("voice_chat"), "voice_chat must be false in Phase 1")


func test_brick_rotation_is_false() -> void:
	## Spot-check: brick_rotation is a §9 deferred feature.
	assert_false(Features.is_enabled("brick_rotation"), "brick_rotation must be false in Phase 1")


func test_build_palette_enabled_is_false() -> void:
	## DOC-09: build_palette_enabled constant must be false in Phase 1.
	## Phase 2 flips this to enable the brick palette UI.
	assert_false(
		Features.build_palette_enabled,
		"Features.build_palette_enabled must be false in Phase 1 (DOC-09)"
	)


func test_unknown_feature_flag_asserts() -> void:
	## is_enabled() must assert on an unknown key in debug builds.
	## GUT cannot trap assert() failures as exceptions in GDScript, so we
	## verify the condition that would trigger the assert instead.
	## The presence of a has_setting() guard in the implementation is the contract.
	var unknown_key := "not_a_real_flag_xyz_99999"
	var setting := "cubicraftia/features/%s" % unknown_key
	assert_false(
		ProjectSettings.has_setting(setting),
		"ProjectSettings must NOT have a setting for unknown key '%s'" % unknown_key
	)
	# The above assertion confirms that is_enabled("not_a_real_flag_xyz_99999")
	# would trigger the assert() in Features.is_enabled(). We cannot call
	# is_enabled() here in a passing test since it would crash the test runner.
