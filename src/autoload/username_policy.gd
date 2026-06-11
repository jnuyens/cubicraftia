# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# username_policy.gd — Static username validation helpers.
#
# Accessed by class_name UsernamePol from any script that needs it.
# No HTTP calls, no signals, no autoload infrastructure.
#
# Responsibilities:
#   1. Format validation: 3–20 chars, alphanumeric + underscore only.
#   2. Reserved-prefix enforcement: admin, mod, moderator, etc.
#   3. Profanity check delegation to ProfanityFilter.filter_reject().
#   4. Aggregate validate() returning {valid: bool, error_key: String}.
#   5. Username-change cooldown: days_until_change_allowed() from a Unix timestamp.
#
# Security:
#   T-05-T1: Reserved-prefix check uses begins_with() to catch "admin123", "moderator_helper".
#   T-05-SC: No network calls; all validation is local.
#
# References:
#   05-CONTEXT.md Area 6 — username policy, 30-day cooldown, reserved prefixes
#   05-RESEARCH.md — USERNAME_REGEX, RESERVED_PREFIXES, days_until_change_allowed()

class_name UsernamePol
extends RefCounted

# Preload-based reference to ProfanityFilter — avoids class_name registry
# dependency at parse time (see friends_client.gd for rationale).
const _ProfanityFilter = preload("res://src/networking/profanity_filter.gd")

# ─── Constants ────────────────────────────────────────────────────────────────

## Minimum username length (inclusive).
const MIN_LEN: int = 3

## Maximum username length (inclusive).
const MAX_LEN: int = 20

## Cooldown period in days before a username can be changed again.
const CHANGE_COOLDOWN_DAYS: int = 30

## Regex pattern: 3–20 chars, alphanumeric + underscore only.
## The length constraint is encoded in the regex to avoid a separate length check.
const USERNAME_REGEX: String = "^[a-zA-Z0-9_]{3,20}$"

## Reserved username prefixes (case-insensitive). Matches exact username or any username
## that begins_with() one of these values, catching "admin123", "moderator_helper", etc.
const RESERVED_PREFIXES: Array[String] = [
	"admin",
	"mod",
	"moderator",
	"cubicraftia",
	"support",
	"staff",
	"system",
	"official",
]

# ─── Compiled regex cache ─────────────────────────────────────────────────────

## Lazily compiled username format regex.
static var _format_regex: RegEx = null

# ─── Public API ───────────────────────────────────────────────────────────────

## Validate a username format: 3–20 chars, alphanumeric + underscore only.
## Returns false for empty strings or strings outside the allowed pattern.
static func is_valid_format(username: String) -> bool:
	if username.is_empty():
		return false
	if _format_regex == null:
		_format_regex = RegEx.new()
		_format_regex.compile(USERNAME_REGEX)
	return _format_regex.search(username) != null


## Check if a username matches a reserved prefix (exact or begins_with, case-insensitive).
## Examples: "admin" → true, "admin123" → true, "moderator_help" → true, "player" → false.
static func is_reserved(username: String) -> bool:
	var lower := username.to_lower()
	for prefix: String in RESERVED_PREFIXES:
		if lower == prefix or lower.begins_with(prefix):
			return true
	return false


## Check if a username contains profanity using ProfanityFilter.filter_reject().
## Returns false (clean) when ProfanityFilter is not available (graceful degradation).
static func is_clean(username: String) -> bool:
	# Access via preload-bound _ProfanityFilter to avoid class_name registry race.
	return not _ProfanityFilter.filter_reject(username)


## Validate a username and return a Dictionary with keys:
##   valid     : bool   — true if the username passes all checks.
##   error_key : String — "" if valid, otherwise an i18n key for the error message.
##
## Validation order: format → reserved → profanity.
## UI code does one call and gets both validity and the error i18n key.
static func validate(username: String) -> Dictionary:
	if not is_valid_format(username):
		return {"valid": false, "error_key": "ui.username.error_format"}
	if is_reserved(username):
		return {"valid": false, "error_key": "ui.username.error_reserved"}
	if not is_clean(username):
		return {"valid": false, "error_key": "ui.username.error_profanity"}
	return {"valid": true, "error_key": ""}


## Calculate days remaining before a username change is allowed.
## last_changed_at_unix: Unix timestamp (float) of the last username change.
## Returns 0 if the cooldown has elapsed, or the number of whole days remaining.
static func days_until_change_allowed(last_changed_at_unix: float) -> int:
	var now: float = Time.get_unix_time_from_system()
	var elapsed_seconds: float = now - last_changed_at_unix
	var elapsed_days: float = elapsed_seconds / 86400.0
	var remaining: int = CHANGE_COOLDOWN_DAYS - int(elapsed_days)
	return max(0, remaining)
