# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# test_connecting_timeout.gd — Unit tests for the bounded initial-join
# "Connecting..." timeout (RELY-03, 13-CONTEXT.md D-04).
#
# Drives _on_connecting_timeout() directly (bypassing the real 12 s wait) to
# assert that a join attempt that never resolves (no peer_connected, no
# server-side rejection) surfaces connection_problem within the bounded
# window instead of hanging indefinitely.
#
# Anchors:
#   13-01-PLAN.md Task 2
#   13-CONTEXT.md D-04

extends GutTest

const NetworkManagerScript := preload("res://src/autoload/network_manager.gd")

var _nm: Node = null


func before_each() -> void:
	# Off-tree: no add_child, mirroring test_keepalive_logic.gd /
	# test_connection_problem_reasons.gd conventions. _rtc_mp stays null in
	# this test, so the get_connection_state()-based relay_failed detection
	# naturally falls through to the "timeout" default (per plan <done>).
	_nm = NetworkManagerScript.new()


func after_each() -> void:
	if is_instance_valid(_nm):
		_nm.free()
	_nm = null


func test_connecting_timeout_emits_timeout_reason_and_disconnects() -> void:
	_nm._state = _nm.STATE_CONNECTING
	watch_signals(_nm)
	_nm._on_connecting_timeout()
	assert_signal_emitted_with_parameters(_nm, "connection_problem", ["timeout"])
	assert_eq(_nm.get_state(), "DISCONNECTED",
		"A Connecting timeout with no live peer connection must resolve to DISCONNECTED")


func test_connecting_timeout_is_noop_outside_connecting_state() -> void:
	# Defensive double-guard: if the state already moved on (e.g. peer_connected
	# fired and stopped the timer, but a queued timeout signal still arrives),
	# the handler must not fire a spurious connection_problem.
	_nm._state = _nm.STATE_CONNECTED_AS_PEER
	watch_signals(_nm)
	_nm._on_connecting_timeout()
	assert_signal_not_emitted(_nm, "connection_problem",
		"_on_connecting_timeout must no-op when _state is not STATE_CONNECTING")
	assert_eq(_nm.get_state(), "CONNECTED_AS_PEER",
		"State must be left untouched when the timeout fires outside CONNECTING")


func test_connecting_const_within_d04_range() -> void:
	assert_between(_nm.CONNECTING_TIMEOUT_S, 10.0, 15.0,
		"CONNECTING_TIMEOUT_S must be within the D-04 10-15s range")
