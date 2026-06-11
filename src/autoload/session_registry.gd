# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# session_registry.gd — SessionRegistry autoload: peer tracking + host election.
#
# Registered as autoload "SessionRegistry" in project.godot (after Inventory,
# before NetworkManager which ships in Plan 04-05).
#
# Responsibilities:
#   1. Maintain the live peer list (peer_id → uid, join_order, username).
#   2. Track per-peer RTT via an Exponential Weighted Moving Average (EWMA).
#   3. Compute the deterministic host election winner (lowest RTT, join-order tiebreak).
#   4. Track missed keepalive counts for disconnect detection (Plan 04-06).
#   5. Maintain a survivors set during failover (excludes failed host).
#
# Election algorithm (04-RESEARCH.md §"Election Algorithm"):
#   - Sort surviving peers by EWMA RTT ascending.
#   - Tiebreak: lowest join_order wins (earliest joiner becomes host).
#   - Result is local + deterministic: every surviving peer computes the same winner
#     from the same shared data; no coordination round-trip needed (T-04-03-T2).
#
# RTT EWMA (alpha=0.1 ≈ 30s rolling average at 1 Hz keepalive):
#   new_avg = old_avg * 0.9 + new_rtt * 0.1
#
# Autoload note: NetworkManager (Plan 04-05) calls register_peer / unregister_peer
#   and update_peer_rtt. SessionRegistry is pure data; it does NOT open sockets.
#
# References:
#   04-CONTEXT.md Area 2 — host election + failover
#   04-RESEARCH.md §"Election Algorithm" — RTT + join-order tiebreak
#   04-PATTERNS.md lines 172-183 — compute_elected_host verbatim
#   04-PATTERNS.md lines 286-308 — save_world_snapshot pattern
#   STATE.md — strawberry-session-id-fallback (03-09)

extends Node

# ─── Constants ────────────────────────────────────────────────────────────────

## EWMA decay coefficient for RTT rolling average.
## alpha=0.1 approximates a 30-second window at a 1 Hz keepalive rate.
const RTT_EWMA_ALPHA := 0.1

## Maximum peers per session (DOCS §6 — 2-4 players per world).
const MAX_PEERS_PER_SESSION := 4

# ─── Signals ──────────────────────────────────────────────────────────────────

## Emitted when a peer's RTT rolling average is updated.
signal peer_rtt_updated(peer_id: int, rtt_ms: float)

## Emitted when the elected host changes (peer list or RTT update caused re-election).
signal election_result_changed(elected_peer_id: int)

# ─── Private state ────────────────────────────────────────────────────────────

## Full peer list: { peer_id (int) → { uid: String, join_order: int, username: String } }
var _peer_list: Dictionary = {}

## EWMA RTT per peer: { peer_id (int) → rtt_ms (float) }
var _rtt_rolling_avg: Dictionary = {}

## Join order per peer: { peer_id (int) → join_order (int) }
var _join_order: Dictionary = {}

## Surviving peers during failover — populated by set_surviving_peers().
## Excludes the failed host; election is run on this subset.
var _surviving_peers: Dictionary = {}

## Active session ID (set by NetworkManager in Plan 04-05).
var _session_id: String = ""

## UID of the current session host (set by NetworkManager in Plan 04-05).
var _host_uid: String = ""

## Monotonically increasing join-order counter.
var _join_counter: int = 0

## Missed keepalive count per peer: { peer_id (int) → count (int) }
## Incremented by Plan 04-06 keepalive ticker; reset to 0 on each RTT update.
var _missed_keepalive_count: Dictionary = {}

## Per-session published_at cache: { session_id (String) → published_at_unix (int) }
## Populated by NetworkManager (Plan 04-05) via set_session_published_at().
## Used by client gate: unverified accounts cannot join sessions published >24h ago.
var _session_published_at: Dictionary = {}

# ─── Lifecycle ────────────────────────────────────────────────────────────────

func _ready() -> void:
	pass

# ─── Peer management ──────────────────────────────────────────────────────────

## Register a new peer in the session.
## Assigns the next join_order and initialises RTT to INF (no measurement yet).
##
## @param peer_id   Godot multiplayer peer ID.
## @param uid       Supabase user UID string.
## @param username  Display name for HUD.
func register_peer(peer_id: int, uid: String, username: String) -> void:
	_peer_list[peer_id] = {
		"uid":        uid,
		"join_order": _join_counter,
		"username":   username,
	}
	_join_order[peer_id]             = _join_counter
	_rtt_rolling_avg[peer_id]        = INF
	_missed_keepalive_count[peer_id] = 0
	_join_counter += 1


## Unregister a peer (clean disconnect or failover removal).
func unregister_peer(peer_id: int) -> void:
	_peer_list.erase(peer_id)
	_rtt_rolling_avg.erase(peer_id)
	_join_order.erase(peer_id)
	_surviving_peers.erase(peer_id)
	_missed_keepalive_count.erase(peer_id)


## Return a shallow copy of the full peer list.
func get_peer_list() -> Dictionary:
	return _peer_list.duplicate()


## Return all peer IDs in the full peer list.
func get_all_peer_ids() -> Array:
	return _peer_list.keys()


## Return the Supabase UID for a given peer ID.
## Returns "" if the peer is not registered or has no UID set.
## Added in Phase 5 Plan 05-10 for block-aware peer display and auto-mute lookups.
##
## @param peer_id  Godot multiplayer peer ID.
## @return         Supabase UID string, or "" if unknown.
func get_peer_uid(peer_id: int) -> String:
	var entry: Variant = _peer_list.get(peer_id, null)
	if entry is Dictionary:
		return str((entry as Dictionary).get("uid", ""))
	return ""

# ─── RTT tracking ─────────────────────────────────────────────────────────────

## Apply one RTT measurement to the EWMA rolling average.
## Resets the missed-keepalive counter (proof-of-life).
## Emits peer_rtt_updated and, if the election winner changed, election_result_changed.
##
## @param peer_id  Godot multiplayer peer ID.
## @param rtt_ms   Round-trip time in milliseconds.
func update_peer_rtt(peer_id: int, rtt_ms: float) -> void:
	var current: float = _rtt_rolling_avg.get(peer_id, rtt_ms)
	_rtt_rolling_avg[peer_id] = current * (1.0 - RTT_EWMA_ALPHA) + rtt_ms * RTT_EWMA_ALPHA
	_missed_keepalive_count[peer_id] = 0
	emit_signal("peer_rtt_updated", peer_id, _rtt_rolling_avg[peer_id])
	# Re-check election result and emit if changed.
	var elected := compute_elected_host()
	emit_signal("election_result_changed", elected)


## Return the current EWMA RTT for a peer (INF if not measured yet).
func get_peer_rtt(peer_id: int) -> float:
	return _rtt_rolling_avg.get(peer_id, INF)


## Reset a peer's missed-keepalive counter to 0 (explicit proof-of-life).
func reset_keepalive_counter(peer_id: int) -> void:
	_missed_keepalive_count[peer_id] = 0


## Increment a peer's missed-keepalive counter and return the new count.
## Called by Plan 04-06 keepalive ticker each time a response is NOT received.
##
## @return  New missed count (caller compares against threshold to declare peer dead).
func increment_missed_keepalive(peer_id: int) -> int:
	var prev: int = _missed_keepalive_count.get(peer_id, 0)
	_missed_keepalive_count[peer_id] = prev + 1
	return _missed_keepalive_count[peer_id]

# ─── Election algorithm ────────────────────────────────────────────────────────

## Compute the elected host from the surviving peers.
##
## Algorithm (04-RESEARCH.md §"Election Algorithm"):
##   1. Sort surviving peers by EWMA RTT ascending.
##   2. Tiebreak (RTT delta < 1 ms): lowest join_order wins.
##   3. Fallback: if no survivors, return own multiplayer ID.
##
## Pure function — no side effects, no RPC. Every surviving peer runs this locally
## on shared data and converges to the same answer (T-04-03-T2).
func compute_elected_host() -> int:
	var candidates: Array = _surviving_peers.keys()
	# If no failover has been initiated, fall back to full peer list.
	if candidates.is_empty():
		candidates = _peer_list.keys()
	candidates.sort_custom(func(a: int, b: int) -> bool:
		var rtt_a: float = _rtt_rolling_avg.get(a, INF)
		var rtt_b: float = _rtt_rolling_avg.get(b, INF)
		if absf(rtt_a - rtt_b) < 1.0:
			return _join_order.get(a, INF) < _join_order.get(b, INF)
		return rtt_a < rtt_b
	)
	return candidates[0] if candidates.size() > 0 else multiplayer.get_unique_id()


## Override the local peer ID used for election comparisons in tests.
## In production, am_i_elected() compares against multiplayer.get_unique_id().
## In headless unit tests (no real multiplayer peer), call set_local_peer_id() in before_each
## so am_i_elected() returns the expected result without a live WebRTC connection.
var _local_peer_id_override: int = 0


func set_local_peer_id(peer_id: int) -> void:
	_local_peer_id_override = peer_id


## Return true if this local peer is the elected host.
## Uses _local_peer_id_override when set (non-zero), otherwise multiplayer.get_unique_id().
func am_i_elected() -> bool:
	var my_id: int = _local_peer_id_override if _local_peer_id_override != 0 else multiplayer.get_unique_id()
	return compute_elected_host() == my_id


## Populate the surviving-peers set by copying the full peer list minus the failed host.
## Called during failover when the current host's connection is lost.
##
## @param failed_peer_id  The peer_id of the failed host to exclude.
func set_surviving_peers(failed_peer_id: int) -> void:
	_surviving_peers = _peer_list.duplicate()
	_surviving_peers.erase(failed_peer_id)


## Clear all peer state and reset the join counter (for session teardown / reconnect).
func clear_all_peers() -> void:
	_peer_list.clear()
	_rtt_rolling_avg.clear()
	_join_order.clear()
	_surviving_peers.clear()
	_missed_keepalive_count.clear()
	_join_counter = 0

# ─── Session metadata ──────────────────────────────────────────────────────────

## Set the active session ID (called by NetworkManager on session join).
func set_session_id(sid: String) -> void:
	_session_id = sid


## Return the active session ID.
func get_session_id() -> String:
	return _session_id


## Set the host UID (called by NetworkManager on session join).
func set_host_uid(uid: String) -> void:
	_host_uid = uid


## Return the host UID.
func get_host_uid() -> String:
	return _host_uid


## Cache the published_at Unix timestamp for a session.
## Called by NetworkManager (Plan 04-05) when parsing the session list response.
## Used to enforce the unverified-account >24h session join gate (published-at-unix-in-session-list).
##
## @param session_id        Session identifier string.
## @param published_at_unix Unix timestamp (int) when the session was published.
func set_session_published_at(session_id: String, published_at_unix: int) -> void:
	_session_published_at[session_id] = published_at_unix


## Return the cached published_at Unix timestamp for a session, or 0 if unknown.
##
## @param session_id  Session identifier string.
## @return            Unix timestamp (int) or 0 if not yet populated.
func get_session_published_at(session_id: String) -> int:
	return _session_published_at.get(session_id, 0)
