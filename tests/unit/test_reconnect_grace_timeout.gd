# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# test_reconnect_grace_timeout.gd — Unit tests for the silent failover-reconnect
# grace window (RELY-02, 13-CONTEXT.md D-03).
#
# Drives _on_reconnect_grace_timeout() directly (bypassing the real 5 s wait)
# to assert that a peer which lost the election and never hears from the
# newly-elected host surfaces connection_problem("ended") within the bounded
# window, and that the handler is a defensive no-op once the state has already
# moved past FAILOVER_WAITING/RECONNECTING (success already stopped the timer).
#
# Anchors:
#   13-01-PLAN.md Task 2
#   13-CONTEXT.md D-03

extends GutTest

const NetworkManagerScript := preload("res://src/autoload/network_manager.gd")

var _nm: Node = null


func before_each() -> void:
	# Off-tree: no add_child, mirroring test_keepalive_logic.gd /
	# test_connection_problem_reasons.gd conventions.
	_nm = NetworkManagerScript.new()


func after_each() -> void:
	if is_instance_valid(_nm):
		_nm.free()
	_nm = null


func test_grace_timeout_during_failover_waiting_emits_ended() -> void:
	_nm._state = _nm.STATE_FAILOVER_WAITING
	watch_signals(_nm)
	_nm._on_reconnect_grace_timeout()
	assert_signal_emitted_with_parameters(_nm, "connection_problem", ["ended"])
	assert_eq(_nm.get_state(), "DISCONNECTED",
		"A grace-window timeout during FAILOVER_WAITING must resolve to DISCONNECTED")


func test_grace_timeout_during_reconnecting_emits_ended() -> void:
	_nm._state = _nm.STATE_RECONNECTING
	watch_signals(_nm)
	_nm._on_reconnect_grace_timeout()
	assert_signal_emitted_with_parameters(_nm, "connection_problem", ["ended"])
	assert_eq(_nm.get_state(), "DISCONNECTED",
		"A grace-window timeout during RECONNECTING must resolve to DISCONNECTED")


func test_grace_timeout_is_noop_after_successful_reconnect() -> void:
	# Simulates the timer firing after _on_snapshot_received_during_failover()
	# already stopped it and moved the state on — a defensive double-guard,
	# not a real race (the timer.stop() call prevents the signal from firing
	# in practice, but the handler itself must still be safe if called).
	_nm._state = _nm.STATE_CONNECTED_AS_PEER
	watch_signals(_nm)
	_nm._on_reconnect_grace_timeout()
	assert_signal_not_emitted(_nm, "connection_problem",
		"_on_reconnect_grace_timeout must no-op outside FAILOVER_WAITING/RECONNECTING")
	assert_eq(_nm.get_state(), "CONNECTED_AS_PEER",
		"State must be left untouched when the timeout fires after a successful reconnect")


func test_grace_window_const_matches_d03_tunable() -> void:
	assert_eq(_nm.FAILOVER_RECONNECT_TIMEOUT_S, 5.0,
		"FAILOVER_RECONNECT_TIMEOUT_S must be the D-03 ~5s tunable const")
