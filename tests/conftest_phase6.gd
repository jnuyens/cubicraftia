# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# conftest_phase6.gd — Shared GUT fixtures for the Phase 6 first-five-minutes test suite.
#
# NOT extends GutTest — this is a helper class used by test files via preload().
# NOT registered as an autoload (test-only code).
#
# Usage in test files:
#   const Phase6Fixtures = preload("res://tests/conftest_phase6.gd")
#   var cfg := Phase6Fixtures.make_avatar_cfg()
#   var path := Phase6Fixtures.make_telemetry_cfg_path()
#
# Provides:
#   - make_avatar_cfg()              — valid default avatar config Dictionary
#   - make_telemetry_cfg_path()      — unique user:// path for telemetry test isolation
#   - make_world_index_path()        — unique user:// path for world index test isolation
#
# Anchors:
#   06-01-PLAN.md Task 2 — conftest_phase6 fixture spec
#   06-UI-SPEC.md Surface 2 — avatar config keys and valid value ranges

class_name Phase6Fixtures
extends RefCounted


# ─── Avatar config ─────────────────────────────────────────────────────────────

## Return a valid default avatar configuration Dictionary.
##
## Keys:
##   skin_colour_index   int   0-4 (light to deep)
##   head_shape          String "square" | "round" | "tall"
##   face_expression     String "neutral" | "happy" | "cool" | "surprised" | "sleepy"
##   body_colour_index   int   0-9 (10-colour palette subset)
##   body_accessory      String "none" | "backpack" | "cape"
##   leg_colour_index    int   0-9
##   leg_shoes           String "none" | "boots" | "sneakers"
##   hand_accessory      String "none" | "pickaxe" | "lantern" | "flower" | "blank"
##
## All values are the first/default option so the result is always valid.
static func make_avatar_cfg() -> Dictionary:
	return {
		"skin_colour_index": 0,
		"head_shape":        "square",
		"face_expression":   "neutral",
		"body_colour_index": 0,
		"body_accessory":    "none",
		"leg_colour_index":  0,
		"leg_shoes":         "none",
		"hand_accessory":    "none",
	}


# ─── Telemetry isolation ───────────────────────────────────────────────────────

## Return a unique user:// path for a telemetry config so parallel tests
## do not clobber each other's data.
##
## Pattern: "user://test_telemetry_%d.cfg" % randi()
## Call cleanup after each test: DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
static func make_telemetry_cfg_path() -> String:
	return "user://test_telemetry_%d.cfg" % randi()


# ─── World index isolation ─────────────────────────────────────────────────────

## Return a unique user:// path for a world index so parallel tests
## do not clobber each other's data.
##
## Pattern: "user://test_world_index_%d.json" % randi()
## Call cleanup after each test.
static func make_world_index_path() -> String:
	return "user://test_world_index_%d.json" % randi()
