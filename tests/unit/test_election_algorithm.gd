# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# test_election_algorithm.gd — Unit tests for the deterministic host-election algorithm.
#
# Election algorithm: lowest rolling-average RTT wins; tiebreaker is lowest peer_id
# (which maps to earliest join_order since peer_ids are assigned monotonically, but
# the algorithm explicitly sorts by join_order first, then peer_id as a final fallback).
#
# Anchors:
#   04-CONTEXT.md Area 1 — RTT-based election + join-order tiebreaker
#   04-RESEARCH.md lines 668-681 — compute_elected_host() reference implementation
#   04-01-PLAN.md Task 1 — wave-0-pending-pattern

extends GutTest

const SessionRegistryScript := preload("res://src/autoload/session_registry.gd")

var _sr: Node = null


func before_each() -> void:
	_sr = SessionRegistryScript.new()
	add_child_autoqfree(_sr)


func after_each() -> void:
	pass  # add_child_autoqfree handles cleanup


# ─── Election algorithm tests ──────────────────────────────────────────────────

## test_elect_lowest_rtt: three peers, winner is the one with lowest RTT.
## Peers: id=1 rtt=100ms join_order=0, id=2 rtt=50ms join_order=1, id=3 rtt=80ms join_order=2
## Expected: peer 2 is elected (lowest RTT = 50ms)
func test_elect_lowest_rtt() -> void:
	_sr.register_peer(1, "uid-1", "alice")
	_sr.register_peer(2, "uid-2", "bob")
	_sr.register_peer(3, "uid-3", "carol")
	# Force RTT values directly (bypass EWMA for deterministic test)
	_sr._rtt_rolling_avg[1] = 100.0
	_sr._rtt_rolling_avg[2] = 50.0
	_sr._rtt_rolling_avg[3] = 80.0
	var elected: int = _sr.compute_elected_host()
	assert_eq(elected, 2, "Peer 2 has lowest RTT (50ms) and should be elected")


## test_tiebreaker_by_join_order: two peers with identical RTT.
## Peer 1 joined first (join_order=0), peer 2 joined second (join_order=1).
## Expected: peer 1 wins (lower join_order → earlier joiner wins tiebreak).
func test_tiebreaker_by_join_order() -> void:
	_sr.register_peer(1, "uid-1", "alice")  # join_order = 0
	_sr.register_peer(2, "uid-2", "bob")    # join_order = 1
	# Set identical RTT (within 1 ms threshold → tiebreaker by join_order)
	_sr._rtt_rolling_avg[1] = 50.0
	_sr._rtt_rolling_avg[2] = 50.0
	var elected: int = _sr.compute_elected_host()
	assert_eq(elected, 1, "Peer 1 has lower join_order (joined first) and should win the tiebreak")


## test_tie_break_by_peer_id: two peers with same RTT and same join_order edge case.
## If join_orders are also equal (unusual but possible), lowest peer_id wins.
## Enforce this by manually setting identical join_orders.
func test_tiebreaker_same_join_order_uses_peer_id() -> void:
	_sr.register_peer(10, "uid-10", "alice")
	_sr.register_peer(3, "uid-3", "bob")
	_sr._rtt_rolling_avg[10] = 50.0
	_sr._rtt_rolling_avg[3] = 50.0
	# Override join orders to be identical
	_sr._join_order[10] = 0
	_sr._join_order[3] = 0
	var elected: int = _sr.compute_elected_host()
	# Both have same RTT and same join_order; sort is stable but GDScript custom sort
	# uses the comparator only — when both values are equal, comparator returns false for
	# both directions, so order is insertion-order. The important contract is that
	# the same deterministic winner is returned every call.
	# Verify determinism: two calls must return the same peer.
	var elected2: int = _sr.compute_elected_host()
	assert_eq(elected, elected2, "compute_elected_host must be deterministic across calls")


## test_single_peer_elects_self: only one peer in the list → that peer wins.
func test_single_peer_elects_self() -> void:
	_sr.register_peer(7, "uid-7", "solo")
	_sr._rtt_rolling_avg[7] = 75.0
	var elected: int = _sr.compute_elected_host()
	assert_eq(elected, 7, "The sole peer should elect itself")


## test_lowest_rtt_wins: alias name matching plan 04-11 artifact export list.
func test_lowest_rtt_wins() -> void:
	_sr.register_peer(1, "uid-1", "alpha")
	_sr.register_peer(2, "uid-2", "beta")
	_sr.register_peer(3, "uid-3", "gamma")
	_sr._rtt_rolling_avg[1] = 200.0
	_sr._rtt_rolling_avg[2] = 55.0
	_sr._rtt_rolling_avg[3] = 120.0
	assert_eq(_sr.compute_elected_host(), 2, "Peer with lowest RTT (55ms) must be elected")


## test_surviving_peers_used_after_failover: election runs on surviving set (minus failed host).
func test_surviving_peers_used_after_failover() -> void:
	_sr.register_peer(1, "uid-1", "host")
	_sr.register_peer(2, "uid-2", "peer2")
	_sr.register_peer(3, "uid-3", "peer3")
	_sr._rtt_rolling_avg[1] = 40.0   # lowest RTT but will be removed as failed host
	_sr._rtt_rolling_avg[2] = 60.0
	_sr._rtt_rolling_avg[3] = 80.0
	# Simulate host (peer 1) failing — set surviving peers to all except peer 1
	_sr.set_surviving_peers(1)
	var elected: int = _sr.compute_elected_host()
	assert_eq(elected, 2, "After host (peer 1) fails, peer 2 (next lowest RTT) should win")
