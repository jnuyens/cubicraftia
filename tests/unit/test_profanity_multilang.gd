# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# test_profanity_multilang.gd — Unit tests for multilingual profanity filter.
#
# Tests ProfanityFilter with EN and NL word lists (LDNOOBW CC-BY-4.0):
#   - filter() replaces an EN word match with "[filtered]".
#   - filter_reject() returns true when text contains an EN profanity word.
#   - filter_reject() returns false for clean text with no profanity.
#   - filter() correctly matches an NL word via set_word_list() extension point.
#   - set_word_list() extension point replaces the active EN word list.
#   - filter_reject() returns false for an empty string (no regex check).
#
# ProfanityFilter location: src/networking/profanity_filter.gd
# Phase 5 interface (05-03):
#   class_name ProfanityFilter
#   static func filter(text: String) -> String
#   static func filter_reject(text: String) -> bool  ← NEW in Phase 5
#   static func set_word_list(words: Array[String]) -> void
#   static func load_word_lists() -> void
#
# Word list files: assets/profanity/wordlist_en.txt, wordlist_nl.txt
#
# Anchors:
#   05-01-PLAN.md Task 1 — profanity multilang test stubs
#   05-03-PLAN.md Task 2 — activate assertions
#   05-CONTEXT.md Area 2 — filter_reject() new method, EN+NL word lists

extends GutTest

const Phase5Fixtures = preload("res://tests/conftest_phase5.gd")
const ProfanityFilter = preload("res://src/networking/profanity_filter.gd")


func before_each() -> void:
	# Reset static regex state before each test so tests are independent.
	ProfanityFilter._regex_en = null
	ProfanityFilter._regex_nl = null
	ProfanityFilter._regex_custom = null


func test_filter_replaces_en_word_with_filtered() -> void:
	# "ass" is in wordlist_en.txt; load_word_lists() is triggered by _ensure_regex().
	var result: String = ProfanityFilter.filter("You are an ass hat.")
	assert_eq(result, "You are an [filtered] hat.", "filter() must replace EN profanity with [filtered]")


func test_filter_reject_returns_true_for_en_word() -> void:
	# filter_reject() must return true when any EN word appears in the candidate string.
	var rejected: bool = ProfanityFilter.filter_reject("asshole")
	assert_true(rejected, "filter_reject() must return true for a known EN profanity word")


func test_filter_reject_returns_false_for_clean_text() -> void:
	# filter_reject() must return false for text with no profanity.
	var rejected: bool = ProfanityFilter.filter_reject("my awesome world")
	assert_false(rejected, "filter_reject() must return false for clean text")


func test_filter_nl_word_after_wordlist_load() -> void:
	# "kut" is in wordlist_nl.txt; both regexes loaded by load_word_lists().
	ProfanityFilter.load_word_lists()
	var result: String = ProfanityFilter.filter("Wat een kut niveau.")
	assert_eq(result, "Wat een [filtered] niveau.", "filter() must replace NL profanity with [filtered]")


func test_filter_reject_returns_true_for_nl_word() -> void:
	# filter_reject() must also match NL word list entries.
	var rejected: bool = ProfanityFilter.filter_reject("lul")
	assert_true(rejected, "filter_reject() must return true for a known NL profanity word")


func test_filter_reject_empty_string_returns_false() -> void:
	# Empty string must short-circuit without calling regex.
	var rejected: bool = ProfanityFilter.filter_reject("")
	assert_false(rejected, "filter_reject() must return false for empty string")


func test_set_word_list_extension_point() -> void:
	# set_word_list() overrides the EN word list with a custom list.
	ProfanityFilter.set_word_list(["customblock"])
	# Custom word should now be rejected.
	assert_true(ProfanityFilter.filter_reject("this has customblock in it"),
		"filter_reject() must return true for a word added via set_word_list()")
	# filter() must also replace the custom word.
	var result: String = ProfanityFilter.filter("testing customblock here")
	assert_eq(result, "testing [filtered] here",
		"filter() must replace custom word added via set_word_list()")


func test_filter_clean_through_after_set_word_list() -> void:
	# Text without any blocked words must pass through unchanged after set_word_list().
	ProfanityFilter.set_word_list(["onlyblock"])
	var result: String = ProfanityFilter.filter("this is clean text")
	assert_eq(result, "this is clean text", "filter() must not alter clean text")
