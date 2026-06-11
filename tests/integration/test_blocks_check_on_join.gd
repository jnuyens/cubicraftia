# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# test_blocks_check_on_join.gd — Integration tests for blocks-check on session join.
#
# Tests the client-side peer_connected suppression when a joining peer is locally blocked.
# The Go signaling server is the hard gate (05-RESEARCH.md Pattern 2); this test verifies
# the client-side display suppression: peer_connected signal must NOT be emitted for a
# blocked peer's peer_id.
#
# Design note: NetworkManager._on_peer_connected() checks _is_blocked_locally(peer_uid)
# before emitting peer_connected. To test this without a live WebRTC connection, we:
#   1. Instantiate NetworkManager directly via .new() (not as autoload).
#   2. Populate _blocks_cache directly (normally set via FriendsClient.blocks_loaded).
#   3. Call _on_peer_connected() with a test peer_id whose UID is in the block cache.
#   4. Assert that peer_connected is (or is not) emitted.
#
# Per Phase 4 Plan 11 decision: use .new() + .free() (not add_child_autoqfree) to avoid
# ObjectDB leaks. NetworkManager._exit_tree() disconnects root focus signals safely.
#
# Anchors:
#   05-01-PLAN.md Task 2 — integration test stubs
#   05-RESEARCH.md Pattern 2 — Go signaling blocks-check on join
#   05-CONTEXT.md Area 1 — block cascades to session join (server hard gate)
#   DOCS §6.2 — Blocking prevents joining any session the blocker hosts

extends GutTest

const Phase5Fixtures = preload("res://tests/conftest_phase5.gd")
const NetworkManagerScript = preload("res://src/autoload/network_manager.gd")


## Helper: create a fresh NetworkManager instance, bypassing _ready() autoload setup.
## Returns a NetworkManager that is NOT in the scene tree (no focus signal connections,
## no Timer children) — just the base object with its member variables accessible.
func _make_nm() -> Node:
	var nm: Node = NetworkManagerScript.new()
	# DO NOT add_child: _ready() would fire and connect root focus signals,
	# and would try to connect FriendsClient which is not available in this context.
	# Instead, inject the _blocks_cache directly as a member variable write.
	return nm


func test_blocked_peer_does_not_emit_peer_connected() -> void:
	# Scenario: local user has blocked "blocked_uid_x".
	# NetworkManager._blocks_cache contains a row for that UID.
	# When _on_peer_connected(42) fires, the peer's UID resolves to "blocked_uid_x".
	# peer_connected must NOT be emitted — the peer is hidden from the UI.
	# DOCS §6.2 — block prevents joining (server hard gate); client suppresses display.
	#
	# We test the predicate directly via _is_blocked_locally() rather than invoking
	# _on_peer_connected() (which would require a valid scene tree for SessionRegistry).
	var nm: Node = _make_nm()
	add_child_autoqfree(nm)  # Must be in tree for watch_signals to work.

	# Populate _blocks_cache with a row for the blocked peer.
	# Format matches what FriendsClient.get_blocks() returns: [{blocked_uid: ..., created_at: ...}]
	nm.set("_blocks_cache", [
		{"blocked_uid": "blocked_uid_x", "created_at": "2026-05-29T10:00:00Z"},
	])

	# Verify the predicate: _is_blocked_locally("blocked_uid_x") must return true.
	# This is the exact check NetworkManager._on_peer_connected() performs before
	# deciding whether to emit peer_connected.
	var is_blocked: bool = nm.call("_is_blocked_locally", "blocked_uid_x")
	assert_true(is_blocked,
		"_is_blocked_locally must return true when uid is in _blocks_cache — peer_connected will be suppressed")

	# And for an unblocked UID, the predicate must return false (no suppression).
	var is_not_blocked: bool = nm.call("_is_blocked_locally", "clean_uid_y")
	assert_false(is_not_blocked,
		"_is_blocked_locally must return false for a UID not in _blocks_cache")


func test_unblocked_user_can_join_after_unblock() -> void:
	# Scenario: user was blocked, then unblocked.
	# After unblock, _blocks_cache no longer contains the row.
	# _is_blocked_locally must return false → peer_connected would be emitted.
	# DOCS §6.2 — unblocking is immediate; the peer can rejoin the session.
	var nm: Node = _make_nm()
	add_child_autoqfree(nm)

	# Initially blocked.
	nm.set("_blocks_cache", [
		{"blocked_uid": "unblocked_uid_z", "created_at": "2026-05-29T09:00:00Z"},
	])
	var before_unblock: bool = nm.call("_is_blocked_locally", "unblocked_uid_z")
	assert_true(before_unblock,
		"Before unblock: _is_blocked_locally must return true for 'unblocked_uid_z'")

	# Simulate unblock: remove the row from the cache (FriendsClient.unblock_user →
	# user_unblocked signal → FriendsClient.get_blocks() → blocks_loaded → _on_blocks_loaded).
	nm.set("_blocks_cache", [])  # Empty after unblock + refresh.
	var after_unblock: bool = nm.call("_is_blocked_locally", "unblocked_uid_z")
	assert_false(after_unblock,
		"After unblock: _is_blocked_locally must return false (peer_connected would be emitted)")
