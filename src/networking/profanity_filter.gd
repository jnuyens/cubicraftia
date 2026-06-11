# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# profanity_filter.gd — Static utility for filtering profanity in chat messages,
# usernames, world names, and avatar names.
#
# Phase 4 shipped a minimal ~20-word stub. Phase 5 replaces it with two compiled
# regexes loaded from curated LDNOOBW CC-BY-4.0 word lists at startup.
#
# Security: T-05-P2 — Two separate compiled regexes (_regex_en, _regex_nl) each under
# 500 words, avoiding regex engine timeout on Tier-3 Android (Pitfall 2).
# T-05-P-bypass — filter_reject() returns bool only; callers show
# "Please choose another name." and NEVER echo the rejected input.
#
# Usage:
#   var clean := ProfanityFilter.filter("some fuck text")      # → "some [filtered] text"
#   var bad := ProfanityFilter.filter_reject("badusername")   # → true
#   ProfanityFilter.set_word_list(my_list)  # runtime override (v1.x extension point)
#
# References:
#   05-03-PLAN.md — dual-regex load_word_lists(), filter_reject()
#   05-CONTEXT.md Area 2 — filter_reject() contract
#   05-RESEARCH.md Section C — LDNOOBW CC-BY-4.0, dual-regex pattern

class_name ProfanityFilter
extends RefCounted

# ─── Phase 5 dual compiled regexes ───────────────────────────────────────────
## English profanity regex compiled from wordlist_en.txt.
## Never merged with _regex_nl (Pitfall 2: 500-word alternation limit on mobile).
static var _regex_en: RegEx = null

## Dutch profanity regex compiled from wordlist_nl.txt.
static var _regex_nl: RegEx = null

# ─── Phase 4 backward-compat: single _regex for set_word_list() callers ──────
## Set by set_word_list() to override _regex_en with a custom list.
## When non-null, takes precedence over the file-loaded _regex_en.
static var _regex_custom: RegEx = null

# ─── Public API ───────────────────────────────────────────────────────────────

## Filter profanity from a chat message.
## Whole-word matches (case-insensitive, \b anchors) are replaced with "[filtered]".
## The sender always sees their original message locally — this is applied to the
## copy sent via the host to all peers.
## @param text  Raw message text.
## @return      Filtered text safe for broadcast.
static func filter(text: String) -> String:
	if text.is_empty():
		return text
	_ensure_regex()
	var result: String = text
	# Apply custom/EN regex first, then NL as a second pass.
	var active_en: RegEx = _regex_custom if _regex_custom != null else _regex_en
	if active_en != null:
		result = active_en.sub(result, "[filtered]", true)
	if _regex_nl != null:
		result = _regex_nl.sub(result, "[filtered]", true)
	return result


## Reject a user-authored string (username, world name, avatar name).
## Returns true if any profanity word appears in text (any language).
## Callers MUST NOT echo the rejected text in their error message.
## Show "Please choose another name." instead.
## @param text  String to check.
## @return      true if text contains a blocked word, false otherwise.
static func filter_reject(text: String) -> bool:
	if text.is_empty():
		return false
	_ensure_regex()
	var active_en: RegEx = _regex_custom if _regex_custom != null else _regex_en
	if active_en != null and active_en.search(text) != null:
		return true
	if _regex_nl != null and _regex_nl.search(text) != null:
		return true
	return false


## Extension point for v1.x: replace the runtime EN word list with a custom one.
## Calling this resets the compiled custom regex so the next filter() call recompiles.
## NL regex (_regex_nl) is unaffected and continues to use the file-loaded list.
## @param words  Array of lowercase words to block (replaces file-loaded EN list).
static func set_word_list(words: Array[String]) -> void:
	_regex_custom = null
	if words.is_empty():
		return
	_regex_custom = _compile_regex(words)


## Load EN and NL word lists from assets/profanity/wordlist_en.txt and nl.txt.
## Called once at startup (lazy-init via _ensure_regex). Skips lines beginning
## with '#' (comments) and blank lines. Lowercases and deduplicates entries.
## On file-not-found: push_warning and continue (graceful degradation).
static func load_word_lists() -> void:
	_regex_en = _load_list("res://assets/profanity/wordlist_en.txt")
	_regex_nl = _load_list("res://assets/profanity/wordlist_nl.txt")


# ─── Private ──────────────────────────────────────────────────────────────────

## Lazy-init: load word lists if neither regex has been compiled yet.
## Idempotent — calling multiple times after init is a no-op.
static func _ensure_regex() -> void:
	if _regex_en != null or _regex_nl != null or _regex_custom != null:
		return
	load_word_lists()


## Load a word list file and return a compiled RegEx, or null on failure.
static func _load_list(path: String) -> RegEx:
	if not FileAccess.file_exists(path):
		push_warning("ProfanityFilter: word list not found at '%s' — filter degraded" % path)
		return null
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("ProfanityFilter: could not open '%s' (error %d)" % [path, FileAccess.get_open_error()])
		return null
	var words: Array[String] = []
	while not file.eof_reached():
		var line: String = file.get_line().strip_edges()
		if line.is_empty() or line.begins_with("#"):
			continue
		var word: String = line.to_lower()
		if not words.has(word):
			words.append(word)
	file.close()
	if words.is_empty():
		return null
	return _compile_regex(words)


## Compile a case-insensitive word-boundary regex from a list of words.
## Pattern: (?i)\b(word1|word2|...)\b
## Escapes basic regex metacharacters in words.
static func _compile_regex(words: Array[String]) -> RegEx:
	var escaped: Array[String] = []
	for w: String in words:
		var e: String = w
		e = e.replace("\\", "\\\\")
		e = e.replace(".", "\\.")
		e = e.replace("*", "\\*")
		e = e.replace("+", "\\+")
		e = e.replace("?", "\\?")
		e = e.replace("(", "\\(")
		e = e.replace(")", "\\)")
		e = e.replace("[", "\\[")
		e = e.replace("]", "\\]")
		e = e.replace("{", "\\{")
		e = e.replace("}", "\\}")
		e = e.replace("^", "\\^")
		e = e.replace("$", "\\$")
		e = e.replace("|", "\\|")
		escaped.append(e)
	var pattern: String = "(?i)\\b(%s)\\b" % "|".join(escaped)
	var rx: RegEx = RegEx.new()
	var err: int = rx.compile(pattern)
	if err != OK:
		push_warning("ProfanityFilter: regex compile failed (error %d)" % err)
		return null
	return rx
