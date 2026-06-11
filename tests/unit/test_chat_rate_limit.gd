# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# test_chat_rate_limit.gd — Unit tests for chat rate limiting and profanity filter.
#
# Chat contract (04-CONTEXT.md Area 4):
#   - Rate limit: 5 messages per 10 seconds (RATE_LIMIT_MESSAGES = 5)
#   - Over-limit messages are dropped silently (_attempt_send returns early)
#   - Profanity filter: matching text replaced with "[filtered]"
#
# Rate limit logic in ChatOverlay._attempt_send():
#   if _message_count >= RATE_LIMIT_MESSAGES: return  # drop
#   _message_count += 1
#   ...
#   if _message_count >= RATE_LIMIT_MESSAGES: _input_field.editable = false
#
# Since ChatOverlay extends CanvasLayer with @onready node refs, we cannot
# instantiate it in headless mode without a scene. Instead we test:
#   1. The rate limit constant (5 messages / 10s) is correct.
#   2. The _message_count gate logic (directly, by reading the constant + field logic).
#   3. ProfanityFilter.filter() replaces stub words correctly.
#
# For the rate limit behaviour tests we create a minimal GDScript object that
# mirrors the ChatOverlay rate gate logic without requiring the full scene tree.
#
# Anchors:
#   04-CONTEXT.md Area 4 — rate limit (5/10s) + profanity filter
#   04-UI-SPEC.md Surface 7 — chat overlay and rate limit feedback
#   04-08-PLAN.md Task 1 — chat system implementation
#   04-11-PLAN.md — integration test activation

extends GutTest

const ChatOverlayScript := preload("res://src/ui/chat_overlay.gd")
const ProfanityFilter   := preload("res://src/networking/profanity_filter.gd")

# Inline helper class that mirrors the rate-limit portion of ChatOverlay without
# depending on scene-tree @onready refs.
class RateLimiter:
	var message_count: int = 0
	const LIMIT: int = 5

	## Returns true if the next send should be blocked.
	func is_rate_limited() -> bool:
		return message_count >= LIMIT

	## Simulate a send attempt: returns true if the message was accepted, false if dropped.
	func attempt_send() -> bool:
		if is_rate_limited():
			return false
		message_count += 1
		return true


func before_each() -> void:
	# Inject deterministic stub words so the profanity tests neither depend on nor print
	# the real wordlist. set_word_list() overrides the file-loaded EN regex via
	# _regex_custom (which filter() prefers). The filter moved to file-based word lists, so
	# the old "_WORD_LIST with badword/spamword" the tests assumed no longer exists — we
	# recreate that contract explicitly here.
	ProfanityFilter.set_word_list(["badword", "spamword"])


func after_each() -> void:
	# Clear the custom list so the stub words don't leak into other test files (static var).
	ProfanityFilter.set_word_list([])


# ─── Rate limit constant tests ─────────────────────────────────────────────────

## test_rate_limit_constant: RATE_LIMIT_MESSAGES must be 5, RATE_LIMIT_WINDOW_S must be 10.
func test_rate_limit_constant() -> void:
	assert_eq(ChatOverlayScript.RATE_LIMIT_MESSAGES, 5,
		"Rate limit must be 5 messages per window")
	assert_eq(ChatOverlayScript.RATE_LIMIT_WINDOW_S, 10.0,
		"Rate limit window must be 10 seconds")


# ─── Rate limit logic tests ────────────────────────────────────────────────────

## test_rate_limit_allows_5: first 5 messages in a window must be accepted.
func test_rate_limit_allows_5() -> void:
	var limiter := RateLimiter.new()
	for i: int in 5:
		var accepted: bool = limiter.attempt_send()
		assert_true(accepted, "Message %d of 5 should be accepted" % (i + 1))
	assert_eq(limiter.message_count, 5,
		"After 5 accepted messages, count must be 5")


## test_rate_limit_blocks_6th: the 6th message in the same window must be dropped.
func test_rate_limit_blocks_6th() -> void:
	var limiter := RateLimiter.new()
	# Accept 5
	for _i: int in 5:
		limiter.attempt_send()
	# 6th must be blocked
	var accepted := limiter.attempt_send()
	assert_false(accepted,
		"The 6th message within a 10s window must be dropped (rate limited)")


## test_rate_limit_resets: after window expires (count reset to 0), messages accepted again.
func test_rate_limit_resets() -> void:
	var limiter := RateLimiter.new()
	for _i: int in 5:
		limiter.attempt_send()
	assert_true(limiter.is_rate_limited(), "Should be rate limited at count 5")
	# Simulate window expiry: reset count (mirrors _on_rate_window_expired)
	limiter.message_count = 0
	assert_false(limiter.is_rate_limited(), "After reset, should no longer be rate limited")
	var accepted := limiter.attempt_send()
	assert_true(accepted, "Message after window reset must be accepted")


# ─── Profanity filter tests ────────────────────────────────────────────────────

## test_profanity_filter_redacts: known stub word is replaced with "[filtered]".
func test_profanity_filter_redacts() -> void:
	# "badword" is the first entry in ProfanityFilter._WORD_LIST
	var result: String = ProfanityFilter.filter("hello badword world")
	assert_false(result.contains("badword"),
		"The stub word 'badword' must not appear in the filtered output")
	assert_true(result.contains("[filtered]"),
		"Filtered words must be replaced with '[filtered]'")
	assert_true(result.contains("hello"),
		"Non-filtered words ('hello') must pass through unchanged")
	assert_true(result.contains("world"),
		"Non-filtered words ('world') must pass through unchanged")


## test_profanity_filter_empty: empty string is returned unchanged.
func test_profanity_filter_empty_input() -> void:
	var result: String = ProfanityFilter.filter("")
	assert_eq(result, "",
		"Empty string input must return empty string")


## test_profanity_filter_clean_text: clean text passes through unchanged.
func test_profanity_filter_clean_text() -> void:
	var clean := "hello world this is fine"
	var result: String = ProfanityFilter.filter(clean)
	assert_eq(result, clean,
		"Clean text must pass through the profanity filter unchanged")


## test_profanity_filter_replaces_all: all stub words in one message are replaced.
func test_profanity_filter_replaces_all() -> void:
	# "badword" and "spamword" are both in _WORD_LIST
	var result: String = ProfanityFilter.filter("badword and spamword")
	assert_false(result.contains("badword"),
		"First stub word must be filtered")
	assert_false(result.contains("spamword"),
		"Second stub word must be filtered")
