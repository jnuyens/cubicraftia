# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# test_connection_problem_reasons.gd — Unit tests for NetworkManager's shared
# "connection problem" reason plumbing (13-CONTEXT.md D-01/D-02, RELY-01).
#
# Covers:
#   - report_connection_problem() sets last_failure_reason and emits connection_problem.
#   - _on_signaling_message() maps the Go signaling server's "error" message codes
#     (blocked / session_full / peer_not_found / version_mismatch) to the canonical
#     connection_problem reason, previously silently dropped.
#   - "consent_required" is routed to the pre-existing join_blocked flow instead,
#     NOT connection_problem.
#
# Note: assert_signal_emitted_with_parameters(object, signal_name, params) takes
# an optional 4th "index" int argument (not a message string) — do not pass a
# free-text message as the 4th positional arg, it silently corrupts the
# signal_watcher lookup (GUT 9.4.0).
#
# Anchors:
#   13-01-PLAN.md Task 1
#   13-CONTEXT.md D-01/D-02
#   tests/integration/test_failover_fault_injection.gd — off-tree GUT pattern reference

extends GutTest

const NetworkManagerScript := preload("res://src/autoload/network_manager.gd")

var _nm: Node = null


func before_each() -> void:
	# Off-tree instance: no add_child. _ready() connects to get_tree().root focus
	# signals and would leak on free() between tests (mirrors test_keepalive_logic.gd
	# and test_blocks_check_on_join.gd conventions). None of these tests need _ready()
	# to have run.
	_nm = NetworkManagerScript.new()


func after_each() -> void:
	if is_instance_valid(_nm):
		_nm.free()
	_nm = null


# ─── report_connection_problem() ──────────────────────────────────────────────

func test_report_connection_problem_emits_signal_and_sets_last_failure_reason() -> void:
	watch_signals(_nm)
	_nm.report_connection_problem("timeout")
	assert_signal_emitted_with_parameters(_nm, "connection_problem", ["timeout"])
	assert_eq(_nm.last_failure_reason, "timeout",
		"last_failure_reason must be updated after report_connection_problem()")


# ─── Signaling "error" message → connection_problem mapping ───────────────────

func test_error_blocked_maps_to_blocked_reason() -> void:
	watch_signals(_nm)
	_nm._on_signaling_message({"type": "error", "payload": {"code": "blocked", "message": "x"}})
	assert_signal_emitted_with_parameters(_nm, "connection_problem", ["blocked"])
	assert_eq(_nm.last_failure_reason, "blocked")


func test_error_session_full_maps_to_full_reason() -> void:
	watch_signals(_nm)
	_nm._on_signaling_message({"type": "error", "payload": {"code": "session_full", "message": "x"}})
	assert_signal_emitted_with_parameters(_nm, "connection_problem", ["full"])
	assert_eq(_nm.last_failure_reason, "full")


func test_error_peer_not_found_maps_to_ended_reason() -> void:
	watch_signals(_nm)
	_nm._on_signaling_message({"type": "error", "payload": {"code": "peer_not_found", "message": "x"}})
	assert_signal_emitted_with_parameters(_nm, "connection_problem", ["ended"])
	assert_eq(_nm.last_failure_reason, "ended")


func test_error_version_mismatch_maps_to_version_mismatch_reason() -> void:
	watch_signals(_nm)
	_nm._on_signaling_message({"type": "error", "payload": {"code": "version_mismatch", "message": "x"}})
	assert_signal_emitted_with_parameters(_nm, "connection_problem", ["version_mismatch"])
	assert_eq(_nm.last_failure_reason, "version_mismatch")


func test_error_consent_required_emits_join_blocked_not_connection_problem() -> void:
	watch_signals(_nm)
	_nm._on_signaling_message({"type": "error", "payload": {"code": "consent_required", "message": "x"}})
	assert_signal_emitted_with_parameters(_nm, "join_blocked", ["parental_consent_required"])
	assert_signal_not_emitted(_nm, "connection_problem",
		"'consent_required' must NOT be routed through connection_problem — it has its own UI")


func test_error_unknown_code_does_not_emit_connection_problem() -> void:
	watch_signals(_nm)
	_nm._on_signaling_message({"type": "error", "payload": {"code": "bad_payload", "message": "x"}})
	assert_signal_not_emitted(_nm, "connection_problem",
		"Unhandled/unknown error codes must not surface a player-facing connection_problem overlay")
	assert_signal_not_emitted(_nm, "join_blocked")
