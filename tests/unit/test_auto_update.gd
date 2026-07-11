# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# test_auto_update.gd: Unit tests for AutoUpdate.is_update_available (DIST-05).
# The notify-and-link update check must only prompt when both versions are present
# and genuinely differ, and never for unstamped dev builds.

extends GutTest

const AutoUpdateScript := preload("res://src/autoload/auto_update.gd")

func test_no_update_when_versions_equal() -> void:
	assert_false(AutoUpdateScript.is_update_available("abc123 2026-07-10", "abc123 2026-07-10"))

func test_update_when_versions_differ() -> void:
	assert_true(AutoUpdateScript.is_update_available("abc123 2026-07-10", "def456 2026-07-11"))

func test_no_update_when_local_empty() -> void:
	assert_false(AutoUpdateScript.is_update_available("", "def456"))

func test_no_update_when_manifest_empty() -> void:
	assert_false(AutoUpdateScript.is_update_available("abc123", ""))

func test_no_update_for_unstamped_dev() -> void:
	assert_false(AutoUpdateScript.is_update_available("unstamped-dev-build", "def456"))

func test_whitespace_tolerant_equal() -> void:
	assert_false(AutoUpdateScript.is_update_available("  abc123  ", "abc123"))
