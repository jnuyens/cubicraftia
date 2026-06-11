# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# test_username_validator.gd — Unit tests for username policy validation.
#
# Tests the static validation logic in src/autoload/username_policy.gd:
#   - Reserved prefix "admin" (and variants) is rejected.
#   - Valid username format (3–20 chars, ^[a-zA-Z0-9_]{3,20}$) is accepted.
#   - Username with special characters (e.g., hyphens, spaces) is rejected.
#   - Username shorter than 3 characters is rejected.
#   - A second username change within 30 days is blocked by the cooldown.
#
# Reserved prefixes: admin, mod, moderator, cubicraftia, support, staff, system, official.
# Format regex: ^[a-zA-Z0-9_]{3,20}$ (case-insensitive uniqueness enforced server-side).
# Cooldown: 30-day window enforced via Postgres function can_change_username() + username_change_log.
# Client-side check via username_policy.gd is for UX speed only — Postgres is the hard gate.
#
# Activated in Plan 05-10 (was stubbed in 05-01 pending 05-12 activation; promoted early per
# plan 05-10 "test activation" task).
#
# Anchors:
#   05-01-PLAN.md Task 1 — username validator test stubs
#   05-10-PLAN.md Task 1 — test activation
#   05-CONTEXT.md Area 6 — username format, reserved prefixes, 30-day cooldown
#   05-RESEARCH.md Migration 007 — can_change_username() + username_change_log

extends GutTest

const Phase5Fixtures = preload("res://tests/conftest_phase5.gd")
const UsernamePolicy = preload("res://src/autoload/username_policy.gd")


## test_reserved_prefix_admin_rejected: "admin", "admin123", "adminhelper" must all be rejected.
func test_reserved_prefix_admin_rejected() -> void:
	# Exact match.
	var r1: Dictionary = UsernamePolicy.validate("admin")
	assert_false(r1.get("valid", true),
		"'admin' must be rejected (reserved prefix)")
	assert_eq(r1.get("error_key", ""), "ui.username.error_reserved",
		"'admin' must return the reserved error key")

	# begins_with prefix (T-05-T1 mitigation).
	var r2: Dictionary = UsernamePolicy.validate("admin123")
	assert_false(r2.get("valid", true),
		"'admin123' must be rejected (begins_with admin)")

	var r3: Dictionary = UsernamePolicy.validate("moderator_help")
	assert_false(r3.get("valid", true),
		"'moderator_help' must be rejected (begins_with moderator)")

	# Non-reserved name must pass (control).
	var r4: Dictionary = UsernamePolicy.validate("player_one")
	assert_true(r4.get("valid", false),
		"'player_one' must not be rejected as reserved")


## test_format_regex_accepts_valid: standard alphanumeric + underscore names in 3–20 chars.
func test_format_regex_accepts_valid() -> void:
	var valid_names: Array[String] = [
		"abc",
		"ABC",
		"player1",
		"Player_One",
		"user_name_123",
		"a" + "b".repeat(19),  # exactly 20 chars
	]
	for name: String in valid_names:
		var result: Dictionary = UsernamePolicy.validate(name)
		assert_true(result.get("valid", false),
			"'%s' (len=%d) should pass format validation" % [name, name.length()])


## test_format_regex_rejects_special_chars: hyphens, spaces, dots must be rejected.
func test_format_regex_rejects_special_chars() -> void:
	var bad_names: Array[String] = [
		"hello-world",
		"hello world",
		"hello.world",
		"hello@world",
		"hello!",
		"<script>",
	]
	for name: String in bad_names:
		var result: Dictionary = UsernamePolicy.validate(name)
		assert_false(result.get("valid", true),
			"'%s' must fail format validation (contains disallowed char)" % name)
		assert_eq(result.get("error_key", ""), "ui.username.error_format",
			"'%s' must return the format error key" % name)


## test_format_rejects_too_short: names under 3 chars must be rejected.
func test_format_rejects_too_short() -> void:
	for short_name: String in ["a", "ab", ""]:
		var result: Dictionary = UsernamePolicy.validate(short_name)
		assert_false(result.get("valid", true),
			"'%s' (len=%d) must fail format validation (too short)" % [short_name, short_name.length()])


## test_format_rejects_too_long: names over 20 chars must be rejected.
func test_format_rejects_too_long() -> void:
	var long_name: String = "a".repeat(21)
	var result: Dictionary = UsernamePolicy.validate(long_name)
	assert_false(result.get("valid", true),
		"21-char name must fail format validation (too long)")


## test_cooldown_blocks_second_change_within_30_days:
## days_until_change_allowed() returns > 0 when called with a recent Unix timestamp.
func test_cooldown_blocks_second_change_within_30_days() -> void:
	# Simulate a username change 5 days ago.
	var five_days_ago: float = Time.get_unix_time_from_system() - 5.0 * 86400.0
	var days_left: int = UsernamePolicy.days_until_change_allowed(five_days_ago)
	assert_true(days_left > 0,
		"5 days after a change, cooldown should still have days remaining (expected ~25, got %d)" % days_left)
	# Rough bound: should be around 24–25 days (allow ±2 for clock drift in CI).
	assert_true(days_left >= 23 and days_left <= 27,
		"Cooldown days remaining should be ~25 after 5 days (got %d)" % days_left)


## test_cooldown_allows_after_30_days:
## days_until_change_allowed() returns 0 when 30+ days have passed.
func test_cooldown_allows_after_30_days() -> void:
	var thirty_one_days_ago: float = Time.get_unix_time_from_system() - 31.0 * 86400.0
	var days_left: int = UsernamePolicy.days_until_change_allowed(thirty_one_days_ago)
	assert_eq(days_left, 0,
		"31 days after a change, cooldown must be 0 (change allowed)")
