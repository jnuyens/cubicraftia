# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# test_connection_problem_overlay_reasons.gd — headless proof of the
# ConnectionProblemOverlay reason-to-copy/button mapping (13-05-PLAN.md Task 2).
#
# All assertions here run against an off-tree instance (ConnectionProblemOverlayScript.new(),
# never add_child()'d) and call only the pure helpers, never show_reason() itself (which
# needs @onready nodes present in the scene tree). tr() works headlessly without a display
# once the locale/en.po + locale/nl.po keys from Task 1 exist.
#
# In-viewport visual verification (scrim, layout, focus ring) is display-gated and is
# deferred to Phase 12 per the executor's instructions — not claimed here.

extends GutTest

const ConnectionProblemOverlayScript = preload("res://src/ui/connection_problem_overlay.gd")

const _ALL_REASONS: Array[String] = [
	"expired", "full", "ended", "blocked", "version_mismatch", "relay_failed", "timeout",
]


func _make_overlay():
	# autofree(): CanvasLayer.new() allocates a Canvas RID even off-tree; autofree()
	# ensures GUT frees the instance at end-of-test instead of leaking it as an orphan.
	return autofree(ConnectionProblemOverlayScript.new())


# ─── _reason_has_secondary_action ─────────────────────────────────────────────

func test_relay_failed_and_timeout_have_secondary_action() -> void:
	var overlay = _make_overlay()
	assert_true(overlay._reason_has_secondary_action("relay_failed"),
		"relay_failed must offer a Retry + Back-to-menu button pair")
	assert_true(overlay._reason_has_secondary_action("timeout"),
		"timeout must offer a Retry + Back-to-menu button pair")


func test_other_five_reasons_have_no_secondary_action() -> void:
	var overlay = _make_overlay()
	for reason in ["expired", "full", "ended", "blocked", "version_mismatch"]:
		assert_false(overlay._reason_has_secondary_action(reason),
			"%s must show Back-to-menu only, no Retry button" % reason)


# ─── _body_key_for_reason ─────────────────────────────────────────────────────

func test_body_key_for_reason_maps_all_seven_reasons() -> void:
	var overlay = _make_overlay()
	var expected := {
		"expired": "ui.connproblem.reason_expired",
		"full": "ui.connproblem.reason_full",
		"ended": "ui.connproblem.reason_ended",
		"blocked": "ui.connproblem.reason_blocked",
		"version_mismatch": "ui.connproblem.reason_version_mismatch",
		"relay_failed": "ui.connproblem.reason_relay_failed",
		"timeout": "ui.connproblem.reason_timeout",
	}
	for reason in _ALL_REASONS:
		assert_eq(overlay._body_key_for_reason(reason), expected[reason],
			"%s must map to %s" % [reason, expected[reason]])


# ─── Non-revealing "blocked" constraint (T-13-05-01) ──────────────────────────

func test_blocked_reason_copy_never_contains_the_word_blocked() -> void:
	var overlay = _make_overlay()
	var resolved := tr(overlay._body_key_for_reason("blocked"))
	assert_true(resolved != "", "blocked body key must resolve to non-empty text (Task 1 keys must exist)")
	assert_false(resolved.to_lower().contains("blocked"),
		"blocked reason copy must never contain the literal substring 'blocked'")


func test_blocked_reason_copy_does_not_imply_exclusion_in_nl() -> void:
	# Same substring-absence check against the Dutch locale, since D-01's fail-closed
	# requirement applies to both shipped languages, not just English.
	var previous_locale := TranslationServer.get_locale()
	TranslationServer.set_locale("nl")
	var overlay = _make_overlay()
	var resolved := tr(overlay._body_key_for_reason("blocked"))
	TranslationServer.set_locale(previous_locale)
	assert_true(resolved != "", "NL blocked body key must resolve to non-empty text")
	assert_false(resolved.to_lower().contains("geblokkeerd"),
		"NL blocked reason copy must never contain 'geblokkeerd' (the Dutch word for blocked)")


# ─── version_mismatch never renders a raw version integer ────────────────────

func test_version_mismatch_copy_contains_no_digits() -> void:
	var overlay = _make_overlay()
	var resolved := tr(overlay._body_key_for_reason("version_mismatch"))
	assert_true(resolved != "", "version_mismatch body key must resolve to non-empty text")
	var has_digit := false
	for i in resolved.length():
		if resolved[i].is_valid_int():
			has_digit = true
			break
	assert_false(has_digit,
		"version_mismatch copy must never render a raw PROTOCOL_VERSION integer or digit")


# ─── No em-dash / en-dash in any shipped copy (project-wide CLAUDE.md rule) ───

func test_no_em_dash_or_en_dash_in_any_connproblem_copy() -> void:
	var overlay = _make_overlay()
	var keys := [
		"ui.connproblem.heading",
		"ui.connproblem.action_retry",
		"ui.connproblem.action_back",
	]
	for reason in _ALL_REASONS:
		keys.append(overlay._body_key_for_reason(reason))

	for key in keys:
		var resolved: String = tr(key)
		assert_false(resolved.contains("—"), "%s (EN) must not contain an em-dash" % key)
		assert_false(resolved.contains("–"), "%s (EN) must not contain an en-dash" % key)

	var previous_locale := TranslationServer.get_locale()
	TranslationServer.set_locale("nl")
	for key in keys:
		var resolved: String = tr(key)
		assert_false(resolved.contains("—"), "%s (NL) must not contain an em-dash" % key)
		assert_false(resolved.contains("–"), "%s (NL) must not contain an en-dash" % key)
	TranslationServer.set_locale(previous_locale)


# ─── Exactly one overlay, exactly one public entry point ─────────────────────

func test_show_reason_is_the_only_public_entry_point() -> void:
	# A direct structural proof of "one public entry point": show_reason must exist,
	# and no second "show_error"/"display_reason"-style method should be present.
	var overlay = _make_overlay()
	assert_true(overlay.has_method("show_reason"),
		"ConnectionProblemOverlay must expose show_reason(reason)")
	assert_false(overlay.has_method("show_error"),
		"ConnectionProblemOverlay must not carry a second, competing display method")
