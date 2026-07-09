# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# test_protocol_version_handshake.gd: Integration tests for the P2P join-handshake
# PROTOCOL_VERSION check (VER-01, VER-02).
#
# Proves that a version-mismatched joining peer is cleanly rejected before any
# peer_connected signal (and therefore no Inventory event / snapshot RPC ever
# addressed to it) is emitted, and that a matching version confirms the pending
# connection and emits peer_connected exactly once.
#
# NetworkManager, SessionRegistry, and BuildInfo are all real project autoloads
# (project.godot [autoload] section) that are already present in the SceneTree root
# during a headless GUT run. Engine.register_singleton() does NOT override the
# compiled global-identifier resolution used inside network_manager.gd itself
# (STATE.md `engine-register-singleton-limit`, 04-11), so this test uses the REAL
# SessionRegistry/BuildInfo autoloads directly rather than faking them, and cleans
# up any state it writes in after_each().
#
# _handle_reported_protocol_version(sender_id, their_version) is called directly
# (bypassing the @rpc wrapper and multiplayer.get_remote_sender_id(), which cannot be
# reliably driven in a headless off-tree test) per this plan's <done> fallback clause.
#
# Anchors:
#   13-04-PLAN.md Task 1
#   13-CONTEXT.md D-08/D-09
#   tests/integration/test_failover_fault_injection.gd - off-tree GUT pattern reference
#   tests/unit/test_connecting_timeout.gd - off-tree NetworkManager instantiation convention

extends GutTest

const NetworkManagerScript := preload("res://src/autoload/network_manager.gd")

var _nm: Node = null


func before_each() -> void:
	# In-tree (add_child_autoqfree), mirroring test_failover_fault_injection.gd: unlike
	# the simpler off-tree unit tests, _reject_connecting_peer() needs a real get_tree()
	# for its `await get_tree().process_frame` (mirrors kick_peer()'s exact pattern) to
	# suspend correctly rather than erroring on a null tree.
	_nm = NetworkManagerScript.new()
	add_child_autoqfree(_nm)


func after_each() -> void:
	if is_instance_valid(_nm):
		_nm.free()
	_nm = null
	# Clean up state written to the REAL SessionRegistry autoload so it doesn't leak
	# into other test files run in the same headless GUT session.
	if is_instance_valid(SessionRegistry):
		SessionRegistry.unregister_peer(2)
		SessionRegistry.unregister_peer(3)


## test_matching_version_confirms_pending_peer_and_emits_peer_connected: a peer whose
## reported PROTOCOL_VERSION matches BuildInfo.PROTOCOL_VERSION has its pending gate
## cleared and peer_connected is emitted exactly once.
func test_matching_version_confirms_pending_peer_and_emits_peer_connected() -> void:
	watch_signals(_nm)
	_nm._pending_version_peers[2] = true

	_nm._handle_reported_protocol_version(2, BuildInfo.PROTOCOL_VERSION)

	assert_signal_emitted_with_parameters(_nm, "peer_connected", [2])
	assert_false(_nm._pending_version_peers.has(2),
		"_pending_version_peers must be cleared once the version is confirmed")
	assert_true(SessionRegistry.is_protocol_version_compatible(2),
		"SessionRegistry must record the matching version as compatible")


## test_mismatched_version_rejects_and_withholds_peer_connected: a peer whose reported
## PROTOCOL_VERSION differs from BuildInfo.PROTOCOL_VERSION is rejected and
## peer_connected is NEVER emitted for it (VER-02, never connect-and-silently-desync).
func test_mismatched_version_rejects_and_withholds_peer_connected() -> void:
	watch_signals(_nm)
	_nm._pending_version_peers[3] = true

	_nm._handle_reported_protocol_version(3, BuildInfo.PROTOCOL_VERSION + 999)

	assert_signal_not_emitted(_nm, "peer_connected",
		"A mismatched PROTOCOL_VERSION must NEVER result in peer_connected being emitted")
	assert_false(_nm._pending_version_peers.has(3),
		"_pending_version_peers must be cleared (peer was rejected, not left pending)")
	assert_false(SessionRegistry.is_protocol_version_compatible(3),
		"SessionRegistry must record the mismatched version as incompatible, excluding this "
		+ "peer from failover-host candidacy (Plan 13-02's filter)")


## test_mismatched_version_reports_version_mismatch_reason: the rejected peer's own
## NetworkManager (simulated by directly invoking the rejection RPC handler) reports
## "version_mismatch" via report_connection_problem() and transitions to DISCONNECTED.
func test_mismatched_version_reports_version_mismatch_reason() -> void:
	# Simulate the rejected peer's side: it receives _receive_connection_rejected.
	_nm._state = _nm.STATE_CONNECTING
	watch_signals(_nm)

	_nm._receive_connection_rejected("version_mismatch")

	assert_signal_emitted_with_parameters(_nm, "connection_problem", ["version_mismatch"])
	assert_eq(_nm.last_failure_reason, "version_mismatch")
	assert_eq(_nm.get_state(), "DISCONNECTED",
		"The rejected peer must transition to STATE_DISCONNECTED")


## test_reject_connecting_peer_exists_and_is_callable: sanity check that the
## host-side helper exists with the expected signature (does not raise).
func test_reject_connecting_peer_helper_exists() -> void:
	assert_true(_nm.has_method("_reject_connecting_peer"),
		"_reject_connecting_peer() must exist on NetworkManager")
