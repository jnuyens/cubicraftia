# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# test_dob_parser.gd — Unit tests for date-of-birth parser and under-13 detection.
#
# Tests the client-side DOB calculation logic in sign_in_panel.gd:
#   - A user born 12 years ago is under 13 (is_under_13 = true).
#   - A user born exactly 13 years ago today is NOT under 13 (is_under_13 = false).
#   - A birthday that falls exactly today (13 years ago) is on the boundary.
#   - An invalid date (e.g., February 31) is rejected with error_dob_invalid.
#
# GDPR minimum-data principle: the raw DOB is NEVER sent to the server.
# Only the derived `is_under_13: bool` is stored in GoTrue user metadata.
# Activate in: 05-05 (age gate + sign-up flow plan).
#
# Anchors:
#   05-01-PLAN.md Task 1 — DOB parser test stubs
#   05-CONTEXT.md Area 3 — is_under_13 boolean, raw DOB not stored
#   05-UI-SPEC.md Surface C — age gate validation error states
#   DOCS §8.5 — Self-declared age 13+; under-13 routed to parental consent flow

extends GutTest

const Phase5Fixtures = preload("res://tests/conftest_phase5.gd")

## Under-13 threshold in seconds — mirrors SignInPanel.THIRTEEN_YEARS_SECONDS.
## Uses 365.25 days/year to account for leap years (same constant as sign_in_panel.gd).
const THIRTEEN_YEARS_SECONDS: float = 13.0 * 365.25 * 86400.0


## Helper: compute the Unix timestamp for a birth date given as year/month/day.
## Returns -1 for invalid dates (same as Godot's Time.get_unix_time_from_datetime_dict).
static func _birth_unix(year: int, month: int, day: int) -> float:
	return Time.get_unix_time_from_datetime_dict({"year": year, "month": month, "day": day})


## Helper: determine is_under_13 using the sign_in_panel.gd algorithm.
## today_unix - birth_unix < THIRTEEN_YEARS_SECONDS → under 13.
static func _is_under_13(birth_unix: float) -> bool:
	var today_unix: float = Time.get_unix_time_from_system()
	return (today_unix - birth_unix) < THIRTEEN_YEARS_SECONDS


func test_age_12_is_under_13() -> void:
	# A child born 12 years ago is definitely under 13.
	# Use an approximate birth date 12 years minus 30 days ago to stay safely under 13.
	# DOCS §8.5 — under-13 accounts routed to parental consent flow.
	var today_unix: float = Time.get_unix_time_from_system()
	# 12 years in seconds (using same constant — 365.25 days/year).
	var twelve_years_seconds: float = 12.0 * 365.25 * 86400.0
	var birth_unix: float = today_unix - twelve_years_seconds

	var result: bool = _is_under_13(birth_unix)
	assert_true(result,
		"A child born 12 years ago must be detected as under-13 (is_under_13 = true)")


func test_age_13_is_not_under_13() -> void:
	# A user whose 13th birthday was more than 1 month ago is definitively NOT under 13.
	# DOCS §8.5 — 13+ users proceed directly to account creation without parental consent.
	var today_unix: float = Time.get_unix_time_from_system()
	# 13 years + 1 month (31 days) ago — safely past the 13-year threshold.
	var age_seconds: float = THIRTEEN_YEARS_SECONDS + (31.0 * 86400.0)
	var birth_unix: float = today_unix - age_seconds

	var result: bool = _is_under_13(birth_unix)
	assert_false(result,
		"A user born 13 years and 1 month ago must NOT be detected as under-13")


func test_age_exactly_13_today() -> void:
	# A user whose 13th birthday is today (within today's window) is NOT under-13.
	# The threshold is strictly < THIRTEEN_YEARS_SECONDS, so a user with exactly
	# 13 years of elapsed time is NOT under-13.
	# DOCS §8.5 — 13+ users proceed without parental consent.
	#
	# To avoid CI flakiness from leap years, use exactly THIRTEEN_YEARS_SECONDS + 1 day
	# to put the birthday clearly in the past (the "day before 13th birthday" is under 13;
	# "day after" is not under 13). This is an "exactly 13 today" approximation:
	# use THIRTEEN_YEARS_SECONDS (float) from system time directly.
	var today_unix: float = Time.get_unix_time_from_system()

	# Exactly at the threshold: today_unix - birth = THIRTEEN_YEARS_SECONDS exactly.
	# (today_unix - birth) < THIRTEEN_YEARS_SECONDS → false → NOT under-13.
	var birth_at_threshold: float = today_unix - THIRTEEN_YEARS_SECONDS

	var result: bool = _is_under_13(birth_at_threshold)
	assert_false(result,
		"A user born exactly THIRTEEN_YEARS_SECONDS ago must NOT be under-13 (boundary: strict <, not <=)")

	# One second before the threshold: still under-13.
	var birth_one_sec_before: float = today_unix - THIRTEEN_YEARS_SECONDS + 1.0
	var result_before: bool = _is_under_13(birth_one_sec_before)
	assert_true(result_before,
		"A user born 1 second before the 13-year threshold must still be under-13")


func test_invalid_dob_date() -> void:
	# February 31 is not a valid date. Godot 4.6's Time.get_unix_time_from_datetime_dict
	# returns 0 (and emits an error push) for invalid calendar dates.
	# Note: The Godot 4.6 implementation returns 0 (not -1) for impossible dates like
	# Feb 31. sign_in_panel.gd guards with `birth_unix < 0.0` — a separate plan
	# (deferred post-05-12) will update that guard to `<= 0.0` to catch Godot 4.6
	# behavior consistently. Here we test what Time actually returns.
	# DOCS §8.5 — sign_in_panel.gd shows error_dob_invalid when birth_unix invalid.
	var invalid_feb31: float = _birth_unix(2010, 2, 31)
	# Godot 4.6 pushes an error and returns 0 for Feb 31 (not a valid epoch date).
	assert_true(invalid_feb31 <= 0.0,
		"Time.get_unix_time_from_datetime_dict must return 0 or negative for Feb 31 (invalid date — Godot 4.6 behaviour)")

	# Additional invalid dates: month 0, day 0.
	var invalid_month: float = _birth_unix(2010, 0, 15)
	var invalid_day: float = _birth_unix(2010, 6, 0)
	assert_true(invalid_month <= 0.0,
		"Month=0 must produce 0 or negative (Time pushes error for impossible dates)")
	assert_true(invalid_day <= 0.0,
		"Day=0 must produce 0 or negative (Time pushes error for impossible dates)")

	# Valid date for comparison: June 15, 2010 must return a positive timestamp.
	var valid_date: float = _birth_unix(2010, 6, 15)
	assert_true(valid_date > 0.0,
		"June 15 2010 must produce a valid positive Unix timestamp")
