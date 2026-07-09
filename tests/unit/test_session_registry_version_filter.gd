# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# test_session_registry_version_filter.gd — Unit tests for the host-failover-election
# version-mismatch exclusion filter (D-09, VER-02).
#
# Proves that compute_elected_host() can never select a peer whose reported
# PROTOCOL_VERSION differs from the local build's, even when that peer has the best
# (lowest) RTT of the surviving candidates. Also proves the two safety nets:
#   - defensive default: a peer with no recorded version is treated as compatible
#     (its handshake simply hasn't completed in this local view yet)
#   - deadlock avoidance: if filtering would leave zero candidates, election falls
#     back to the unfiltered set rather than crash / return an invalid peer_id
#
# Anchors:
#   13-CONTEXT.md D-09 — version-mismatched peer excluded from failover election
#   13-02-PLAN.md Task 2 — behavior spec
#   tests/integration/test_failover_fault_injection.gd — RTT pre-seeding pattern mirrored here

extends GutTest

const SessionRegistryScript := preload("res://src/autoload/session_registry.gd")

var _sr: Node = null


func before_each() -> void:
	_sr = SessionRegistryScript.new()
	add_child_autoqfree(_sr)


func after_each() -> void:
	pass  # add_child_autoqfree handles cleanup


# ─── Version-mismatch election-exclusion tests ────────────────────────────────

## test_version_mismatched_peer_excluded_despite_best_rtt: peer 2 has the best RTT of
## the survivors {2, 3} but reports a mismatched PROTOCOL_VERSION (2 vs local 1) — it
## must be excluded from election, so peer 3 (matched version) wins instead.
func test_version_mismatched_peer_excluded_despite_best_rtt() -> void:
	_sr.register_peer(1, "uid-1", "host")
	_sr.register_peer(2, "uid-2", "peer2")
	_sr.register_peer(3, "uid-3", "peer3")
	_sr._rtt_rolling_avg[1] = 40.0
	_sr._rtt_rolling_avg[2] = 60.0   # best RTT among survivors {2, 3}
	_sr._rtt_rolling_avg[3] = 80.0

	_sr.set_local_protocol_version_override(1)
	_sr.set_peer_protocol_version(2, 2)  # mismatched
	_sr.set_peer_protocol_version(3, 1)  # matched

	# Simulate host (peer 1) failing.
	_sr.set_surviving_peers(1)

	var elected: int = _sr.compute_elected_host()
	assert_eq(elected, 3, "Peer 2 has the best RTT but a mismatched PROTOCOL_VERSION and must be excluded")


## test_no_recorded_versions_behaves_unaffected: when no peer has a recorded protocol
## version, compute_elected_host() must behave exactly as before the filter was added
## (defensive default: unknown version == compatible).
func test_no_recorded_versions_behaves_unaffected() -> void:
	_sr.register_peer(1, "uid-1", "host")
	_sr.register_peer(2, "uid-2", "peer2")
	_sr.register_peer(3, "uid-3", "peer3")
	_sr._rtt_rolling_avg[1] = 40.0
	_sr._rtt_rolling_avg[2] = 60.0
	_sr._rtt_rolling_avg[3] = 80.0
	_sr.set_surviving_peers(1)

	var elected: int = _sr.compute_elected_host()
	assert_eq(elected, 2, "With no recorded versions, election is unaffected by the version filter")


## test_all_survivors_mismatched_falls_back_to_unfiltered: extreme edge case where every
## surviving peer is recorded as version-mismatched. Filtering must not leave election
## with zero candidates (would crash / return an invalid peer_id) — it must fall back
## to the unfiltered candidate set and still return a valid peer_id.
func test_all_survivors_mismatched_falls_back_to_unfiltered() -> void:
	_sr.register_peer(1, "uid-1", "host")
	_sr.register_peer(2, "uid-2", "peer2")
	_sr.register_peer(3, "uid-3", "peer3")
	_sr._rtt_rolling_avg[1] = 40.0
	_sr._rtt_rolling_avg[2] = 60.0
	_sr._rtt_rolling_avg[3] = 80.0

	_sr.set_local_protocol_version_override(1)
	_sr.set_peer_protocol_version(2, 2)  # mismatched
	_sr.set_peer_protocol_version(3, 3)  # mismatched

	_sr.set_surviving_peers(1)

	var elected: int = _sr.compute_elected_host()
	assert_true(elected == 2 or elected == 3, "Election must fall back to the unfiltered set and return a valid peer_id, not crash or return -1")


## test_is_protocol_version_compatible_unknown_peer_defaults_true: a peer with no
## recorded version is treated as compatible (defensive default).
func test_is_protocol_version_compatible_unknown_peer_defaults_true() -> void:
	_sr.register_peer(5, "uid-5", "unknownversion")
	assert_true(_sr.is_protocol_version_compatible(5), "A peer with no recorded PROTOCOL_VERSION must default to compatible")


## test_is_protocol_version_compatible_matched_and_mismatched: exercise both branches
## of is_protocol_version_compatible directly against the local override.
func test_is_protocol_version_compatible_matched_and_mismatched() -> void:
	_sr.register_peer(1, "uid-1", "alice")
	_sr.register_peer(2, "uid-2", "bob")
	_sr.set_local_protocol_version_override(1)
	_sr.set_peer_protocol_version(1, 1)
	_sr.set_peer_protocol_version(2, 2)
	assert_true(_sr.is_protocol_version_compatible(1), "Matched version must be compatible")
	assert_false(_sr.is_protocol_version_compatible(2), "Mismatched version must be incompatible")
