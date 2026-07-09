# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# network_manager.gd — NetworkManager autoload: WebRTC host/peer lifecycle,
#   10-state failover state machine, keepalive RPC loop, and event-replication
#   RPC bridge.
#
# Registered as autoload "NetworkManager" in project.godot (after Inventory and
# WorldSave, before FriendsClient — Pitfall 8 load-order contract).
#
# Responsibilities:
#   1. Manage a WebRTCMultiplayerPeer (or ENetMultiplayerPeer for LAN/dev).
#   2. Connect to the Go signaling server via WebSocket for offer/answer/ICE relay.
#   3. Send keepalive pings at 1 Hz; detect laggy / timed-out peers.
#   4. Run a 10-state failover state machine on host disconnection.
#   5. Bridge Inventory.apply_event() mutations to all peers via RPC.
#   6. Parse session_list messages and emit session_metadata_received per entry.
#
# Phase 5 (Plan 05-10): Added safety hooks:
#   7. Block-aware peer display: _is_blocked_locally() checked before peer_joined emission.
#      Blocked peers are still connected at WebRTC level but suppressed from UI/peer lists.
#      _blocks_cache updated from FriendsClient.blocks_loaded signal.
#   8. Under-13 chat suppression: send_chat() drops outbound packets for accounts where
#      FriendsClient.is_under_13 is true and not yet consented. Shows "Chat requires parent
#      approval." toast. The server-side Go relay is the hard gate; this is UX-only.
#   9. Session join gate: start_peer() returns early for unconsented under-13 accounts and
#      emits join_blocked so the parental gate panel can be shown.
#  10. Auto-mute of reported users: report_submitted → sender added to _session_muted;
#      incoming chat from muted senders is dropped before reaching ChatOverlay.
#
# Security:
#   T-04-05-T  (fake event injection): broadcast_event() guards `if not multiplayer.is_server()`.
#   T-04-05-T2 (peer impersonates host): @rpc("authority") on _receive_replicated_event.
#   T-04-05-D  (chat DoS): chat does NOT go through broadcast_event/journal.
#   T-04-05-T3 (snapshot from non-host): @rpc("authority") on _receive_snapshot_reset.
#   T-04-05-SC (signaling injection): signaling only relays offer/answer/ICE with JWT.
#   T-04-08-T  (chat injection): ProfanityFilter applied client-side + host re-checks.
#   T-04-08-D  (chat flood): host-side rate limit tracked in _chat_rate_counts.
#   T-05-bypass (client skips block check): server-side Go checks are the hard gates;
#               client-side checks are UX-only (display suppression).
#
# References:
#   04-CONTEXT.md Area 1 — failover policy
#   04-CONTEXT.md Area 4 — replication model
#   04-RESEARCH.md Patterns 1-4 — host/peer setup, keepalive, RPC bridge
#   04-RESEARCH.md Pitfalls 7, 8 — ICE candidate queue, autoload load-order
#   04-PATTERNS.md lines 135-142 — inventory broadcast hook position
#   04-RESEARCH.md lines 615-662 — failover state machine
#   04-08-PLAN.md — chat + profanity filter extension
#   05-10-PLAN.md — block-aware peer display + under-13 chat suppression

extends Node

const _ProfanityFilter = preload("res://src/networking/profanity_filter.gd")

# ─── State machine ────────────────────────────────────────────────────────────

## All valid session/failover states.
const STATE_IDLE               := "IDLE"
const STATE_CONNECTING         := "CONNECTING"
const STATE_CONNECTED_AS_HOST  := "CONNECTED_AS_HOST"
const STATE_CONNECTED_AS_PEER  := "CONNECTED_AS_PEER"
const STATE_FAILOVER_DETECTING := "FAILOVER_DETECTING"
const STATE_FAILOVER_ELECTED   := "FAILOVER_ELECTED"
const STATE_FAILOVER_PROMOTING := "FAILOVER_PROMOTING"
const STATE_FAILOVER_COMPLETE  := "FAILOVER_COMPLETE"
const STATE_FAILOVER_WAITING   := "FAILOVER_WAITING"
const STATE_RECONNECTING       := "RECONNECTING"
const STATE_DISCONNECTED       := "DISCONNECTED"

## Canonical set of reasons the shared connection-problem screen understands
## (13-CONTEXT.md D-01). Anything outside this list is still surfaced (never
## silently dropped) but push_warning()s first as a defensive signal.
const CONNECTION_PROBLEM_REASONS: Array[String] = [
	"expired", "full", "ended", "blocked", "version_mismatch", "relay_failed", "timeout",
]

## Current state. Use _set_state() to transition (emits session_state_changed).
var _state: String = STATE_IDLE

## Most recent reason passed to report_connection_problem(), one of
## CONNECTION_PROBLEM_REASONS. Empty string means no connection problem has
## been reported yet this run.
var last_failure_reason: String = ""

# ─── Private state ────────────────────────────────────────────────────────────

## Active WebRTC (or ENet) multiplayer peer.
var _rtc_mp: MultiplayerPeer = null

## WebSocket peer connected to the Go signaling server.
var _ws: WebSocketPeer = WebSocketPeer.new()

## WR-07: Messages queued while the WebSocket is still connecting.
## Flushed on the first _process tick that sees STATE_OPEN.
var _ws_send_queue: Array[String] = []

## True once the signaling WebSocket has reached STATE_OPEN and the pending
## queue has been flushed for the first time.
var _ws_open: bool = false

## URL of the Go signaling WebSocket. Read from ProjectSettings or env.
var _signaling_url: String = ""

## Active session identifier.
var _session_id: String = ""

## STUN/TURN credentials (loaded in _ready).
var _turn_user: String = ""
var _turn_credential: String = ""
var _stun_url: String = "stun:cubicraftia.com:3478"
var _turn_url: String = "turn:cubicraftia.com:3478"

## Keepalive accumulator (seconds since last keepalive tick).
var _keepalive_accum: float = 0.0

## Missed keepalive count per peer: { peer_id → count }.
## Incremented each tick; reset to 0 on pong receipt.
var _keepalive_miss_count: Dictionary = {}

## WR-02: Track which peers have already been flagged as laggy so peer_laggy(true)
## is emitted exactly once per laggy episode, not once per keepalive tick.
## { peer_id (int) → bool }
var _laggy_peers: Dictionary = {}

## ICE candidate queue (Pitfall 7): candidates received before set_remote_description().
## { peer_id → Array[{mid, index, candidate}] }
var _pending_ice_candidates: Dictionary = {}

## Track whether remote SDP has been set for each peer (Pitfall 7).
## { peer_id → bool }
var _remote_sdp_set: Dictionary = {}

## One-shot failover detection timer (200 ms).
var _failover_timer: Timer = null

## Periodic snapshot timer (30 s while host).
var _snapshot_timer: Timer = null

## Adaptive broadcast rate limit (seconds between event broadcasts).
## Controlled by set_update_rate_hz(). Default 20 Hz.
var _broadcast_rate_limit: float = 1.0 / 20.0

## Freeze-build flags per peer. Host sets; peers read via is_peer_frozen().
## { peer_id (int) -> frozen (bool) }
var _frozen_peers: Dictionary = {}

## Host-side chat rate tracking: message count per peer in current window.
## { peer_id (int) → count (int) }
## Reset per-peer after CHAT_RATE_WINDOW_S seconds (rolling via timer).
var _chat_rate_counts: Dictionary = {}

## Timestamps of last chat reset per peer (Unix time float).
var _chat_rate_reset_time: Dictionary = {}

## Local cache of blocked UIDs loaded from FriendsClient.get_blocks().
## Updated when FriendsClient.blocks_loaded fires. Each entry is a Dictionary
## with key "blocked_uid" (String).
## Used by _is_blocked_locally() before peer_joined emission (Phase 5 Plan 05-10).
var _blocks_cache: Array = []

## Session-scoped auto-mute list: peer UIDs reported by the local user this session.
## Incoming chat from muted senders is dropped before reaching ChatOverlay.
## Cleared on session end (IDLE state transition via begin_graceful_disconnect).
## Populated via _on_report_submitted() connected to FriendsClient.report_submitted.
## { uid (String) → true }
var _session_muted: Dictionary = {}

# ─── Chat rate limit constants ────────────────────────────────────────────────

## Host-side rate limit: max messages per peer per window (mirrors client-side limit).
const CHAT_RATE_LIMIT: int = 5

## Host-side rate window in seconds.
const CHAT_RATE_WINDOW_S: float = 10.0

# ─── Keepalive constants ───────────────────────────────────────────────────────

## Keepalive RPC sent at this interval (seconds).
const KEEPALIVE_INTERVAL_S   := 1.0

## After this many consecutive missed keepalives (6 s), disconnect the peer.
const KEEPALIVE_TIMEOUT_S    := 6.0

## Emit peer_laggy(true) at this miss count (3 s).
const KEEPALIVE_WARN_THRESHOLD := 3

# ─── Signals ──────────────────────────────────────────────────────────────────

## A peer has fully connected (either direction).
signal peer_connected(peer_id: int)

## A peer has disconnected (either direction).
signal peer_disconnected(peer_id: int)

## Emitted when a peer misses KEEPALIVE_WARN_THRESHOLD keepalives (is_laggy=true)
## or recovers (is_laggy=false).
signal peer_laggy(peer_id: int, is_laggy: bool)

## Emitted each time a keepalive pong is received from a peer.
signal keepalive_received(peer_id: int)

## Emitted when a peer misses KEEPALIVE_TIMEOUT_S keepalives — peer is dropped.
signal keepalive_timeout(peer_id: int)

## Failover has started (host gone; election in progress).
signal host_failover_started()

## Failover is complete. new_host_peer_id is 1 (the new multiplayer server).
signal host_failover_complete(new_host_peer_id: int)

## Failover could not be completed.
signal host_failover_failed(reason: String)

## Emitted whenever _state changes.
signal session_state_changed(new_state: String)

## Emitted for each session entry in a "session_list" message from the Go server.
signal session_metadata_received(session_id: String, published_at_unix: int)

## A chat message has been received. sender_id=0 means the local host.
signal chat_message_received(sender_id: int, message: String)

## Emitted after a SNAPSHOT_RESET RPC has been applied to local Inventory state.
## Peers listen for this to know their inventory is up-to-date from the new host.
signal snapshot_reset_applied()

## Emitted when the host changes the build-freeze state for a peer.
signal freeze_build_changed(peer_id: int, frozen: bool)

## Emitted when a session join attempt is blocked because the local account is
## under-13 and has not yet received parental consent.
## Listeners should show ParentalGatePanel (Surface D) or a "Chat requires parent
## approval." error so the user knows what to do.
## Server-side Go relay is the hard gate; this client signal is UX-only.
signal join_blocked(reason: String)

## Emitted for every connection failure that should surface the shared
## connection-problem screen (13-CONTEXT.md D-01/D-02): server-side reject,
## connecting timeout, or failover-reconnect timeout. reason is one of
## CONNECTION_PROBLEM_REASONS. See report_connection_problem().
signal connection_problem(reason: String)

# ─── Lifecycle ────────────────────────────────────────────────────────────────

func _ready() -> void:
	# Read STUN/TURN config from ProjectSettings (fallback to env vars).
	_turn_user       = ProjectSettings.get_setting("network/turn_user",       OS.get_environment("TURN_USER"))
	_turn_credential = ProjectSettings.get_setting("network/turn_credential",  OS.get_environment("TURN_CREDENTIAL"))
	_stun_url        = ProjectSettings.get_setting("network/stun_url",         "stun:cubicraftia.com:3478")
	_turn_url        = ProjectSettings.get_setting("network/turn_url",         "turn:cubicraftia.com:3478")
	_signaling_url   = ProjectSettings.get_setting("network/signaling_url",
		OS.get_environment("SIGNALING_URL") if OS.has_environment("SIGNALING_URL") else "ws://localhost:8080/ws")

	# Failover detection timer (200 ms one-shot; only started on host disconnect).
	_failover_timer = Timer.new()
	_failover_timer.one_shot = true
	_failover_timer.wait_time = 0.2
	_failover_timer.timeout.connect(_on_failover_timer_timeout)
	add_child(_failover_timer)

	# Periodic snapshot timer (30 s; only running while CONNECTED_AS_HOST).
	_snapshot_timer = Timer.new()
	_snapshot_timer.one_shot = false
	_snapshot_timer.wait_time = 30.0
	_snapshot_timer.timeout.connect(_on_snapshot_timer_timeout)
	add_child(_snapshot_timer)

	# iOS / desktop background focus hook: save a snapshot when the app loses focus
	# so the world is safe if iOS suspends the process (Pitfall 1 mobile safety net).
	get_tree().root.focus_exited.connect(_on_app_focus_lost)
	get_tree().root.focus_entered.connect(_on_app_focus_entered)

	# Phase 5 (Plan 05-10): Connect FriendsClient safety signals.
	# Guard with is_instance_valid: FriendsClient may not be present in test environments.
	var fc: Node = get_node_or_null("/root/FriendsClient")
	if fc != null:
		# blocks_loaded: update the local blocks cache used by _is_blocked_locally().
		if fc.has_signal("blocks_loaded"):
			fc.blocks_loaded.connect(_on_blocks_loaded)
		# report_submitted: add the reported UID to the session auto-mute list.
		# FriendsClient.report_submitted carries no arguments; we rely on the last
		# reported UID being stored externally. Since the report modal provides the UID
		# through the context menu call chain, we hook into the _last_reported_uid
		# property if it exists, or track via the block flow. For now we connect the
		# signal — actual UID capture is done when report_submitted fires via
		# _on_report_submitted_with_uid() called directly from the report UI.
		if fc.has_signal("report_submitted"):
			fc.report_submitted.connect(_on_report_submitted)


func _exit_tree() -> void:
	# Disconnect root-node focus signals so that freeing this node (e.g. in unit
	# tests via autoqfree) does not leave dangling callables on the scene root and
	# cause ObjectDB "instances leaked" errors.
	if is_instance_valid(get_tree()) and is_instance_valid(get_tree().root):
		if get_tree().root.focus_exited.is_connected(_on_app_focus_lost):
			get_tree().root.focus_exited.disconnect(_on_app_focus_lost)
		if get_tree().root.focus_entered.is_connected(_on_app_focus_entered):
			get_tree().root.focus_entered.disconnect(_on_app_focus_entered)


func _process(delta: float) -> void:
	# ── Poll the signaling WebSocket ──
	_ws.poll()
	# WR-07: Detect the first STATE_OPEN tick and flush any messages that were
	# queued before the WebSocket handshake completed (e.g. publish_session sent
	# synchronously in start_host() right after connect_to_url()).
	if not _ws_open and _ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_ws_open = true
		for queued_msg: String in _ws_send_queue:
			_ws.send_text(queued_msg)
		_ws_send_queue.clear()
	while _ws.get_available_packet_count() > 0:
		var raw := _ws.get_packet()
		var text := raw.get_string_from_utf8()
		var msg: Variant = JSON.parse_string(text)
		if msg is Dictionary:
			_on_signaling_message(msg as Dictionary)

	# ── Keepalive tick ──
	if _state in [STATE_CONNECTED_AS_HOST, STATE_CONNECTED_AS_PEER]:
		_keepalive_accum += delta
		if _keepalive_accum >= KEEPALIVE_INTERVAL_S:
			_keepalive_accum = 0.0
			if multiplayer.is_server():
				_send_keepalive_to_all_peers()
			_check_peer_timeouts()

# ─── Public API ───────────────────────────────────────────────────────────────

## Start this node as the session host.
## @param session_id   Unique session identifier (UUID or fallback timestamp string).
## @param world_name   Human-readable world name published to the signaling server.
func start_host(session_id: String, world_name: String) -> void:
	_session_id = session_id
	_set_state(STATE_CONNECTING)
	_start_as_host_rtc()
	_connect_signaling()
	_signaling_publish_session(session_id, world_name)
	_set_state(STATE_CONNECTED_AS_HOST)
	if is_instance_valid(SessionRegistry):
		SessionRegistry.set_session_id(session_id)
	_snapshot_timer.start()


## Start this node as a session peer.
## @param session_id   Session to join (must be published by host first).
## @param my_peer_id   Peer ID assigned by the signaling server.
##
## Phase 5 (Plan 05-10): Under-13 join gate — if the local account is under-13
## and has not yet received parental consent, emit join_blocked and abort.
## The Go signaling server enforces the hard gate; this is an immediate UX signal
## so the UI can show the parental gate panel without waiting for a server rejection.
func start_peer(session_id: String, my_peer_id: int) -> void:
	# Client-side under-13 consent gate (T-05-bypass: server is the hard gate).
	if _is_under_13_unconsented():
		join_blocked.emit("parental_consent_required")
		return

	_session_id = session_id
	_set_state(STATE_CONNECTING)
	_start_as_peer_rtc(my_peer_id)
	_connect_signaling()
	if is_instance_valid(SessionRegistry):
		SessionRegistry.set_session_id(session_id)
	_set_state(STATE_CONNECTED_AS_PEER)


## Returns true if a session is active (not idle or disconnected).
func is_multiplayer_active() -> bool:
	return _state not in [STATE_IDLE, STATE_DISCONNECTED]


## Returns true if this node is the session host (authoritative server).
func is_session_host() -> bool:
	return _state == STATE_CONNECTED_AS_HOST


## Returns the current session identifier.
func get_session_id() -> String:
	return _session_id


## Returns the current state machine state string (one of the STATE_* constants).
## Used by unit and integration tests to assert state transitions.
func get_state() -> String:
	return _state


## Report a connection problem to the shared connection-problem screen
## (13-CONTEXT.md D-01/D-02). Sets last_failure_reason and emits
## connection_problem(reason). Callers include the signaling "error" mapping,
## the Connecting timeout, and the failover-reconnect grace timeout.
## Defensive: an unrecognised reason is still set/emitted (never silently
## dropped) but push_warning()s first so the mismatch is visible in logs.
func report_connection_problem(reason: String) -> void:
	if not CONNECTION_PROBLEM_REASONS.has(reason):
		push_warning("NetworkManager.report_connection_problem: reason '%s' is not in CONNECTION_PROBLEM_REASONS" % reason)
	last_failure_reason = reason
	connection_problem.emit(reason)


## Broadcast an accepted Inventory event to all connected peers.
## SECURITY CRITICAL: no-op for non-host peers — only the host broadcasts.
func broadcast_event(event: Dictionary) -> void:
	if not multiplayer.is_server():
		return  # no-op for peers — only the host broadcasts
	_receive_replicated_event.rpc(event)


## Send a chat message. Applies ProfanityFilter client-side before submission.
## Host routes filtered message to all peers; peer forwards to host for relay.
## The caller (ChatOverlay) already shows the original unfiltered message to the
## local sender — peers receive the host-filtered version.
##
## Phase 5 (Plan 05-10): Under-13 chat suppression — if the local account is
## under-13 and not yet consented, drop the packet silently and show a toast.
## No error code is shown to the user to avoid confusing UI states.
func send_chat(message: String) -> void:
	if message.is_empty():
		return

	# Under-13 outbound chat suppression (T-05-bypass: Go relay is the hard gate;
	# this is UX-only — drop silently and show a helpful toast).
	if _is_under_13_unconsented():
		# Show a toast so the user knows what's happening, but don't surface an error.
		var toasts: Node = get_node_or_null("/root/Toasts")
		if toasts != null and toasts.has_method("show"):
			toasts.show(tr("ui.chat.under13_blocked"))
		return  # Packet dropped — no RPC sent.

	# Client-side filter (defense in depth; host re-filters on receive).
	var filtered: String = _ProfanityFilter.filter(message)
	if multiplayer.is_server():
		# Host: relay to all peers and emit locally.
		var ts: int = int(Time.get_unix_time_from_system())
		_deliver_chat.rpc(1, filtered, ts)
		chat_message_received.emit(1, filtered)
	else:
		_send_chat_to_host.rpc_id(1, filtered)


## Gracefully disconnect from the session.
## Notifies peers, saves a snapshot, then closes the WebRTC peer.
func begin_graceful_disconnect() -> void:
	_disconnecting_gracefully.rpc()
	if is_session_host() and is_instance_valid(WorldSave):
		WorldSave.save_world_snapshot("disconnect_" + str(int(Time.get_unix_time_from_system())))
	if is_instance_valid(_rtc_mp):
		_rtc_mp.close()
	_ws.close()
	_set_state(STATE_DISCONNECTED)
	_snapshot_timer.stop()
	_keepalive_accum = 0.0
	_keepalive_miss_count.clear()
	_session_id = ""
	# Phase 5 (Plan 05-10): Clear session-scoped auto-mute list on disconnect.
	_session_muted.clear()


## Adjust the event broadcast rate (called by ThermalProbe for adaptive quality).
## @param hz  Target events-per-second. Clamped to minimum 1 Hz.
func set_update_rate_hz(hz: int) -> void:
	_broadcast_rate_limit = 1.0 / max(hz, 1)


## Returns true if a session is currently active (host or peer connected).
## Alias for is_multiplayer_active() — used by PlayersTab for visibility gating.
func is_in_session() -> bool:
	return is_multiplayer_active()


## Kick a peer from the session. Host-only; no-op for non-host callers.
## Broadcasts a "kicked" event to the kicked peer before removing them.
func kick_peer(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	# Notify the kicked peer before disconnecting.
	_receive_kicked_notice.rpc_id(peer_id)
	# Give a frame for the RPC to be queued, then disconnect.
	await get_tree().process_frame
	_disconnect_peer(peer_id)


## Set the build-freeze flag for a peer. Host-only; no-op for non-host callers.
## Broadcasts a FREEZE_BUILD event to all peers so their UI updates.
func set_freeze_build(peer_id: int, frozen: bool) -> void:
	if not multiplayer.is_server():
		return
	_frozen_peers[peer_id] = frozen
	freeze_build_changed.emit(peer_id, frozen)
	broadcast_event({"kind": "FREEZE_BUILD", "peer_id": peer_id, "frozen": frozen})


## Returns true if the given peer has the build-freeze flag set by the host.
func is_peer_frozen(peer_id: int) -> bool:
	return _frozen_peers.get(peer_id, false)


## Test-only helper: increment the keepalive miss count for a peer by 1 and run the
## timeout check. Emits peer_laggy or peer_disconnected at the relevant thresholds.
## Equivalent to one keepalive tick where the peer did not respond.
##
## @param peer_id  The peer whose miss counter to increment.
func _simulate_keepalive_miss(peer_id: int) -> void:
	_keepalive_miss_count[peer_id] = _keepalive_miss_count.get(peer_id, 0) + 1
	_check_peer_timeouts()


## Test-only helper: simulate receipt of a keepalive pong from a peer,
## resetting their miss counter and emitting keepalive_received.
##
## @param peer_id  The peer whose miss counter to reset.
func _simulate_keepalive_pong(peer_id: int) -> void:
	_keepalive_miss_count[peer_id] = 0
	keepalive_received.emit(peer_id)


## Test-only helper: simulate a peer disconnection without a real WebRTC drop.
## If peer_id == 1 (the host), triggers the failover state machine.
func _simulate_peer_disconnect(peer_id: int) -> void:
	if peer_id == 1:
		_on_host_disconnected()
	else:
		_disconnect_peer(peer_id)

# ─── WebRTC host setup ────────────────────────────────────────────────────────

func _start_as_host_rtc() -> void:
	_rtc_mp = WebRTCMultiplayerPeer.new()
	_rtc_mp.create_server()
	multiplayer.multiplayer_peer = _rtc_mp
	if not multiplayer.peer_connected.is_connected(_on_peer_connected):
		multiplayer.peer_connected.connect(_on_peer_connected)
	if not multiplayer.peer_disconnected.is_connected(_on_peer_disconnected):
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)


## Called by the signaling message handler when an offer arrives (host side).
func _on_signaling_peer_offer(peer_id: int, sdp: String) -> void:
	var conn := WebRTCPeerConnection.new()
	conn.initialize(_build_ice_config())
	conn.session_description_created.connect(
		func(type: String, s: String) -> void: _signaling_send_answer(peer_id, type, s))
	conn.ice_candidate_created.connect(
		func(m: String, i: int, c: String) -> void: _signaling_send_ice(peer_id, m, i, c))
	_rtc_mp.add_peer(conn, peer_id)
	# CR-04: Set _remote_sdp_set BEFORE set_remote_description so that any ICE
	# candidates arriving synchronously during SDP processing (via the signaling
	# message handler) are applied immediately rather than queued and potentially
	# dropped after _flush_pending_ice_candidates clears the queue.
	_remote_sdp_set[peer_id] = true
	conn.set_remote_description("offer", sdp)
	_flush_pending_ice_candidates(peer_id, conn)

# ─── WebRTC peer setup ────────────────────────────────────────────────────────

func _start_as_peer_rtc(my_peer_id: int) -> void:
	_rtc_mp = WebRTCMultiplayerPeer.new()
	_rtc_mp.create_client(my_peer_id)
	multiplayer.multiplayer_peer = _rtc_mp
	if not multiplayer.server_disconnected.is_connected(_on_host_disconnected):
		multiplayer.server_disconnected.connect(_on_host_disconnected)
	var conn := WebRTCPeerConnection.new()
	conn.initialize(_build_ice_config())
	conn.session_description_created.connect(
		func(type: String, s: String) -> void: _signaling_send_offer(1, type, s))
	conn.ice_candidate_created.connect(
		func(m: String, i: int, c: String) -> void: _signaling_send_ice(1, m, i, c))
	_rtc_mp.add_peer(conn, 1)
	conn.create_offer()


## Build the ICE server config dictionary (STUN + TURN).
func _build_ice_config() -> Dictionary:
	return {
		"iceServers": [
			{"urls": [_stun_url]},
			{"urls": [_turn_url], "username": _turn_user, "credential": _turn_credential},
		]
	}

# ─── Keepalive ────────────────────────────────────────────────────────────────

## Ping all registered peers and increment their miss count.
func _send_keepalive_to_all_peers() -> void:
	if not is_instance_valid(SessionRegistry):
		return
	var peer_ids: Array = SessionRegistry.get_all_peer_ids()
	for peer_id: int in peer_ids:
		_keepalive_miss_count[peer_id] = _keepalive_miss_count.get(peer_id, 0) + 1
		_keepalive_ping.rpc_id(peer_id, Time.get_ticks_usec())


## Check all peers for laggy / timeout conditions.
func _check_peer_timeouts() -> void:
	var to_disconnect: Array = []
	for peer_id: int in _keepalive_miss_count:
		var count: int = _keepalive_miss_count[peer_id]
		# WR-02: Guard with _laggy_peers so peer_laggy(true) fires exactly once per
		# laggy episode, not on every tick that count == KEEPALIVE_WARN_THRESHOLD.
		if count == KEEPALIVE_WARN_THRESHOLD and not _laggy_peers.get(peer_id, false):
			_laggy_peers[peer_id] = true
			peer_laggy.emit(peer_id, true)
		elif count >= int(KEEPALIVE_TIMEOUT_S / KEEPALIVE_INTERVAL_S):
			keepalive_timeout.emit(peer_id)
			to_disconnect.append(peer_id)
	for peer_id: int in to_disconnect:
		_disconnect_peer(peer_id)


## Remove a peer from the session cleanly (keepalive timeout or manual).
func _disconnect_peer(peer_id: int) -> void:
	if is_instance_valid(multiplayer) and multiplayer.is_server() and is_instance_valid(_rtc_mp):
		_rtc_mp.remove_peer(peer_id)
	if is_instance_valid(SessionRegistry):
		SessionRegistry.unregister_peer(peer_id)
	_keepalive_miss_count.erase(peer_id)
	_laggy_peers.erase(peer_id)
	_pending_ice_candidates.erase(peer_id)
	_remote_sdp_set.erase(peer_id)
	peer_disconnected.emit(peer_id)


## Host → all peers: keepalive ping with server timestamp.
@rpc("authority", "call_remote", "unreliable")
func _keepalive_ping(server_time_us: int) -> void:
	# Peers respond directly to the host (peer_id 1).
	_keepalive_pong.rpc_id(1, server_time_us, Time.get_ticks_usec())


## Peer → host: keepalive pong with original timestamp for RTT computation.
@rpc("any_peer", "call_remote", "unreliable")
func _keepalive_pong(sent_us: int, _peer_received_us: int) -> void:
	var peer_id: int = multiplayer.get_remote_sender_id()
	var rtt_ms: float = float(Time.get_ticks_usec() - sent_us) / 1000.0
	if is_instance_valid(SessionRegistry):
		SessionRegistry.update_peer_rtt(peer_id, rtt_ms)
	_keepalive_miss_count[peer_id] = 0
	# WR-02: If the peer was laggy and has now recovered, clear the flag and emit
	# peer_laggy(false) exactly once so the UI can remove the laggy indicator.
	if _laggy_peers.get(peer_id, false):
		_laggy_peers[peer_id] = false
		peer_laggy.emit(peer_id, false)
	keepalive_received.emit(peer_id)

# ─── RPC bridge ───────────────────────────────────────────────────────────────

## Receive a replicated Inventory event (peers only; host never calls this on itself).
## @rpc("authority") ensures only peer_id=1 (the server/host) can send this RPC.
@rpc("authority", "call_remote", "reliable")
func _receive_replicated_event(event: Dictionary) -> void:
	if is_instance_valid(Inventory):
		Inventory.apply_event(event)


## Host → all peers: deliver a filtered chat message from a sender.
## @param sender_id  Original sender peer_id (1 = host itself).
## @param message    Profanity-filtered message text.
## @param ts         Unix timestamp (seconds) for ordering.
##
## Phase 5 (Plan 05-10): Auto-mute filter — if the sender UID is in _session_muted,
## drop the message before emitting to ChatOverlay (display-layer filter only;
## the sender is still connected and can communicate with other peers).
@rpc("authority", "call_remote", "reliable")
func _deliver_chat(sender_id: int, message: String, _ts: int) -> void:
	# Resolve the sender's UID from SessionRegistry if available.
	var sender_uid: String = ""
	if is_instance_valid(SessionRegistry):
		sender_uid = SessionRegistry.get_peer_uid(sender_id)
	# Drop messages from session-muted senders (reported this session).
	if not sender_uid.is_empty() and _session_muted.has(sender_uid):
		return  # Silently drop — the sender is still connected.
	chat_message_received.emit(sender_id, message)


## Peer → host: forward a pre-filtered chat message for host relay.
## Host applies a second filter pass (defense in depth) and enforces rate limit.
@rpc("any_peer", "call_remote", "reliable")
func _send_chat_to_host(message: String) -> void:
	if not multiplayer.is_server():
		return
	var sender_id: int = multiplayer.get_remote_sender_id()

	# Host-side rate limit (T-04-08-D): drop silently if peer exceeds 5/10s.
	var now: float = Time.get_unix_time_from_system()
	var last_reset: float = _chat_rate_reset_time.get(sender_id, 0.0)
	if now - last_reset >= CHAT_RATE_WINDOW_S:
		_chat_rate_counts[sender_id] = 0
		_chat_rate_reset_time[sender_id] = now
	var count: int = _chat_rate_counts.get(sender_id, 0)
	if count >= CHAT_RATE_LIMIT:
		return  # Drop silently — sender already sees countdown on their client.
	_chat_rate_counts[sender_id] = count + 1

	# Host re-applies filter (T-04-08-T defense in depth).
	var filtered: String = _ProfanityFilter.filter(message)
	var ts: int = int(now)

	# Broadcast to all peers (excluding host — host emits locally below).
	_deliver_chat.rpc(sender_id, filtered, ts)
	# Emit locally on the host so host's chat overlay also shows the message.
	chat_message_received.emit(sender_id, filtered)


## Host → all: notification of graceful disconnect.
## CR-07: Changed from @rpc("authority") to @rpc("any_peer") so that non-host peers
## can also broadcast their departure. The host re-broadcasts on receipt so every peer
## is informed; previously non-host peers would silently disconnect with only a 6 s
## keepalive timeout detecting the departure.
@rpc("any_peer", "call_remote", "reliable")
func _disconnecting_gracefully() -> void:
	# If the host receives a peer departure notice, relay it to all other peers so
	# every peer knows the sender is leaving gracefully.
	if multiplayer.is_server():
		var sender_id: int = multiplayer.get_remote_sender_id()
		_disconnect_peer(sender_id)


## Host → kicked peer: notify that they have been kicked from the session.
## @rpc("authority") ensures only peer_id=1 (host) can send this.
@rpc("authority", "call_remote", "reliable")
func _receive_kicked_notice() -> void:
	# The peer receiving this knows it was kicked; gracefully disconnect.
	if is_instance_valid(_rtc_mp):
		_rtc_mp.close()
	_set_state(STATE_DISCONNECTED)


## Host → new peer: push the world snapshot during failover promotion.
## @rpc("authority") ensures only peer_id=1 can call this on peers.
## Security: T-04-05-T3 — non-host peers cannot forge snapshot resets.
@rpc("authority", "call_remote", "reliable")
func _receive_snapshot_reset(state_blob: PackedByteArray) -> void:
	if is_instance_valid(Inventory):
		Inventory.reset_from_state(state_blob)
	snapshot_reset_applied.emit()
	_on_snapshot_received_during_failover()

# ─── Signaling WebSocket ──────────────────────────────────────────────────────

## Open the WebSocket connection to the Go signaling server.
func _connect_signaling() -> void:
	# In Godot 4.6, WebSocketPeer.connect_to_url(url, tls_options) does not accept
	# custom headers as a second parameter. Custom headers must be set via
	# WebSocketPeer.handshake_headers before calling connect_to_url().
	if is_instance_valid(FriendsClient) and FriendsClient.has_method("get_access_token"):
		var token: String = FriendsClient.get_access_token()
		if not token.is_empty():
			_ws.handshake_headers = PackedStringArray(["Authorization: Bearer " + token])
	# WR-07: Reset the open flag and queue so that the _process loop can flush
	# any messages queued synchronously between _connect_signaling() and STATE_OPEN.
	_ws_open = false
	_ws_send_queue.clear()
	_ws.connect_to_url(_signaling_url)


## WR-07: Send a text message to the signaling server, queuing it if the
## WebSocket is not yet open (STATE_OPEN not reached on this frame).
## The queue is flushed in _process on the first STATE_OPEN tick.
func _ws_send(text: String) -> void:
	if _ws_open:
		_ws.send_text(text)
	else:
		_ws_send_queue.append(text)


## Publish a new session to the Go signaling server.
func _signaling_publish_session(session_id: String, world_name: String) -> void:
	var uid: String = ""
	if is_instance_valid(FriendsClient) and FriendsClient.has_method("get_user_id"):
		uid = FriendsClient.get_user_id()
	var msg: Dictionary = {
		"v": 1,
		"type": "session.publish",
		"payload": {
			"session_id": session_id,
			"world_name": world_name,
			"host_uid":   uid,
		}
	}
	_ws_send(JSON.stringify(msg))


## Send an SDP offer to the signaling server for a target peer.
func _signaling_send_offer(peer_id: int, type: String, sdp: String) -> void:
	var msg: Dictionary = {
		"v": 1,
		"type": "offer",
		"payload": {"target_peer_id": peer_id, "sdp_type": type, "sdp": sdp}
	}
	_ws_send(JSON.stringify(msg))


## Send an SDP answer to the signaling server for a target peer.
func _signaling_send_answer(peer_id: int, type: String, sdp: String) -> void:
	var msg: Dictionary = {
		"v": 1,
		"type": "answer",
		"payload": {"target_peer_id": peer_id, "sdp_type": type, "sdp": sdp}
	}
	_ws_send(JSON.stringify(msg))


## Send an ICE candidate to the signaling server for a target peer.
func _signaling_send_ice(peer_id: int, mid: String, index: int, candidate: String) -> void:
	var msg: Dictionary = {
		"v": 1,
		"type": "candidate",
		"payload": {
			"target_peer_id": peer_id,
			"mid":            mid,
			"index":          index,
			"candidate":      candidate,
		}
	}
	_ws_send(JSON.stringify(msg))


## Notify the signaling server that this peer is now the host (used during failover).
func _notify_signaling_update_host() -> void:
	var uid: String = ""
	if is_instance_valid(FriendsClient) and FriendsClient.has_method("get_user_id"):
		uid = FriendsClient.get_user_id()
	var msg: Dictionary = {
		"v": 1,
		"type": "update_host",
		"payload": {"session_id": _session_id, "new_host_uid": uid}
	}
	_ws_send(JSON.stringify(msg))


## Dispatch incoming signaling server messages.
func _on_signaling_message(msg: Dictionary) -> void:
	var msg_type: String = msg.get("type", "")
	var payload: Dictionary = msg.get("payload", {})

	match msg_type:
		"session_list":
			# Parse session list and emit metadata for each entry.
			# FriendsClient connects to session_metadata_received to cache published_at.
			var sessions: Variant = msg.get("sessions", msg.get("data", {}).get("sessions", []))
			if sessions is Array:
				for session: Variant in (sessions as Array):
					if session is Dictionary:
						var sd := session as Dictionary
						var sid: String  = sd.get("session_id", "")
						var pat: int     = int(sd.get("published_at_unix", 0))
						if not sid.is_empty():
							session_metadata_received.emit(sid, pat)
							# Also update SessionRegistry cache directly.
							if is_instance_valid(SessionRegistry):
								SessionRegistry.set_session_published_at(sid, pat)

		"offer":
			# A peer sent us an offer (host receives this).
			var peer_id: int = int(payload.get("source_peer_id", 0))
			var sdp: String  = payload.get("sdp", "")
			if peer_id > 0 and not sdp.is_empty():
				_on_signaling_peer_offer(peer_id, sdp)

		"answer":
			# The host sent us an answer (peer receives this).
			var peer_id: int = int(payload.get("source_peer_id", 1))
			var sdp: String  = payload.get("sdp", "")
			if not sdp.is_empty() and is_instance_valid(_rtc_mp):
				var conn: WebRTCPeerConnection = _rtc_mp.get_peer(peer_id).get("connection")
				if is_instance_valid(conn):
					conn.set_remote_description("answer", sdp)
					_remote_sdp_set[peer_id] = true
					_flush_pending_ice_candidates(peer_id, conn)

		"candidate":
			# ICE candidate from a remote peer (Pitfall 7: may arrive before SDP).
			var peer_id: int    = int(payload.get("source_peer_id", 0))
			var mid: String     = payload.get("mid", "")
			var index: int      = int(payload.get("index", 0))
			var candidate: String = payload.get("candidate", "")
			_on_signaling_ice_candidate(peer_id, mid, index, candidate)

		"peer.joined":
			var peer_id: int = int(payload.get("peer_id", 0))
			if peer_id > 0:
				peer_connected.emit(peer_id)

		"peer.left":
			var peer_id: int = int(payload.get("peer_id", 0))
			if peer_id > 0:
				_disconnect_peer(peer_id)

		"update_host":
			# A new host has taken over; reconnect as peer to new host.
			if _state == STATE_FAILOVER_WAITING:
				_do_failover_waiting_reconnect(payload)

		"error":
			# Go signaling server rejected a request or reported a wire-protocol
			# problem. Map whitelisted codes to the shared connection_problem
			# reason enum (13-CONTEXT.md D-01/D-02); everything else is logged
			# server-side only via push_warning (T-13-01-01: no raw error text
			# ever reaches the player-facing overlay).
			var code: String = payload.get("code", "")
			var message: String = payload.get("message", "")
			match code:
				"blocked":
					report_connection_problem("blocked")
				"session_full":
					report_connection_problem("full")
				"peer_not_found":
					report_connection_problem("ended")
				"version_mismatch":
					report_connection_problem("version_mismatch")
				"consent_required":
					# Existing under-13 parental-gate flow — has its own UI,
					# not one of the 7 canonical connection_problem reasons.
					join_blocked.emit("parental_consent_required")
				_:
					push_warning("NetworkManager: unhandled signaling error code=%s message=%s" % [code, message])

		_:
			pass  # Unknown message type — ignore silently (forward compat).


## Queue an ICE candidate if remote SDP is not yet set; otherwise apply immediately.
## Implements Pitfall 7 guard.
func _on_signaling_ice_candidate(peer_id: int, mid: String, index: int, candidate: String) -> void:
	if not _remote_sdp_set.get(peer_id, false):
		# Queue until after set_remote_description().
		if not _pending_ice_candidates.has(peer_id):
			_pending_ice_candidates[peer_id] = []
		_pending_ice_candidates[peer_id].append({"mid": mid, "index": index, "candidate": candidate})
		return
	# SDP already set — apply immediately.
	if is_instance_valid(_rtc_mp):
		var peer_data: Dictionary = _rtc_mp.get_peer(peer_id)
		var conn: WebRTCPeerConnection = peer_data.get("connection")
		if is_instance_valid(conn):
			conn.add_ice_candidate(mid, index, candidate)


## Flush queued ICE candidates after remote SDP has been set.
func _flush_pending_ice_candidates(peer_id: int, conn: WebRTCPeerConnection) -> void:
	var queued: Variant = _pending_ice_candidates.get(peer_id, null)
	if queued == null:
		return
	for entry: Dictionary in (queued as Array):
		conn.add_ice_candidate(entry["mid"], entry["index"], entry["candidate"])
	_pending_ice_candidates.erase(peer_id)

# ─── Multiplayer signal handlers ──────────────────────────────────────────────

func _on_peer_connected(peer_id: int) -> void:
	if is_instance_valid(SessionRegistry):
		SessionRegistry.register_peer(peer_id, "", "")
	_keepalive_miss_count[peer_id] = 0

	if _state in [STATE_FAILOVER_PROMOTING, STATE_FAILOVER_COMPLETE]:
		_on_peer_connected_during_promotion(peer_id)
	else:
		# Phase 5 (Plan 05-10): Block-aware peer display suppression.
		# Resolve the peer's UID from SessionRegistry and check if blocked locally.
		# If blocked: peer is still connected at the WebRTC level (server-side hard gate
		# already prevented a blocked peer from joining), but suppress from peer list/UI.
		# T-05-bypass: server-side Go relay is the hard gate; this is display-only.
		var peer_uid: String = ""
		if is_instance_valid(SessionRegistry):
			peer_uid = SessionRegistry.get_peer_uid(peer_id)
		if not peer_uid.is_empty() and _is_blocked_locally(peer_uid):
			# Peer is blocked — do NOT emit peer_connected. Hide from peer list.
			return
		peer_connected.emit(peer_id)


func _on_peer_disconnected(peer_id: int) -> void:
	if peer_id == 1 and _state == STATE_CONNECTED_AS_PEER:
		_on_host_disconnected()
	else:
		_disconnect_peer(peer_id)

# ─── Failover state machine ───────────────────────────────────────────────────

## Transition 1: Host gone — start the election delay.
## CONNECTED_AS_PEER → FAILOVER_DETECTING
func _on_host_disconnected() -> void:
	if _state != STATE_CONNECTED_AS_PEER:
		return
	host_failover_started.emit()
	_set_state(STATE_FAILOVER_DETECTING)
	_failover_timer.start()


## Transition 2: Election delay expired — pick a winner.
## FAILOVER_DETECTING → FAILOVER_ELECTED or FAILOVER_WAITING
func _on_failover_timer_timeout() -> void:
	if _state != STATE_FAILOVER_DETECTING:
		return
	if is_instance_valid(SessionRegistry):
		SessionRegistry.set_surviving_peers(1)  # 1 = old host peer_id
	if is_instance_valid(SessionRegistry) and SessionRegistry.am_i_elected():
		_do_failover_elected()
	else:
		_do_failover_waiting()


## Transition 3a: This peer won the election.
## FAILOVER_DETECTING → FAILOVER_ELECTED → FAILOVER_PROMOTING
func _do_failover_elected() -> void:
	_set_state(STATE_FAILOVER_ELECTED)

	# Save a local snapshot for recovery (best-effort; may fail if WorldSave not ready).
	if is_instance_valid(WorldSave):
		WorldSave.save_world_snapshot("failover_" + str(int(Time.get_unix_time_from_system())))

	_set_state(STATE_FAILOVER_PROMOTING)

	# Rebuild the WebRTC server (Pitfall 3: old host was peer_id=1; after create_server()
	# we ARE peer_id=1; clear stale peer table before reconnecting).
	if is_instance_valid(_rtc_mp):
		_rtc_mp.close()
	_rtc_mp = WebRTCMultiplayerPeer.new()
	_rtc_mp.create_server()
	multiplayer.multiplayer_peer = _rtc_mp
	if not multiplayer.peer_connected.is_connected(_on_peer_connected):
		multiplayer.peer_connected.connect(_on_peer_connected)
	if not multiplayer.peer_disconnected.is_connected(_on_peer_disconnected):
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)

	if is_instance_valid(SessionRegistry):
		SessionRegistry.clear_all_peers()

	# Announce to the signaling server that we are the new host.
	_notify_signaling_update_host()


## Transition 3b: Another peer won — wait for them to become host and reconnect.
## FAILOVER_DETECTING → FAILOVER_WAITING
func _do_failover_waiting() -> void:
	_set_state(STATE_FAILOVER_WAITING)
	# The new host will send update_host via the signaling server; handled in
	# _on_signaling_message → "update_host" → _do_failover_waiting_reconnect().


## Called when the signaling server delivers "update_host" while FAILOVER_WAITING.
func _do_failover_waiting_reconnect(payload: Dictionary) -> void:
	var new_my_peer_id: int = int(payload.get("your_peer_id", multiplayer.get_unique_id()))
	_set_state(STATE_RECONNECTING)
	_start_as_peer_rtc(new_my_peer_id)
	# Wait for _receive_snapshot_reset RPC; _on_snapshot_received_during_failover handles COMPLETE.


## Transition 4a: A peer reconnected while we are the new host (FAILOVER_PROMOTING).
## CR-06: Emit host_failover_complete before transitioning to CONNECTED_AS_HOST to
## avoid the intermediate FAILOVER_COMPLETE state that caused UI flicker and confused
## state-machine listeners (they received two rapid state changes with no stable
## resting point in between).
func _on_peer_connected_during_promotion(peer_id: int) -> void:
	# Push the current inventory snapshot to the reconnecting peer.
	_broadcast_snapshot_to_peers_id(peer_id)
	# Emit the failover-complete signal BEFORE the state transition so listeners
	# receive the signal while we are still in FAILOVER_PROMOTING (a well-defined
	# intermediate state), not after two back-to-back _set_state() calls.
	host_failover_complete.emit(1)
	_set_state(STATE_CONNECTED_AS_HOST)
	peer_connected.emit(peer_id)


## Transition 4b: Peer received a snapshot from the new host.
## AWAITING → CONNECTED_AS_PEER
func _on_snapshot_received_during_failover() -> void:
	_set_state(STATE_CONNECTED_AS_PEER)
	host_failover_complete.emit(1)

# ─── Snapshot timer ───────────────────────────────────────────────────────────

func _on_snapshot_timer_timeout() -> void:
	if not is_session_host():
		return
	if is_instance_valid(WorldSave) and WorldSave.is_open():
		WorldSave.save_world_snapshot("autosave_" + str(int(Time.get_unix_time_from_system())))


## Broadcast the current inventory snapshot to all connected peers.
## Host-only guard: no-op for non-host callers.
## Used after failover promotion to synchronise incoming peers with the new host's state.
func _broadcast_snapshot_to_peers() -> void:
	if not multiplayer.is_server():
		return
	if not is_instance_valid(WorldSave):
		return
	var snap := WorldSave.load_latest_snapshot()
	if snap.is_empty():
		push_warning("NetworkManager._broadcast_snapshot_to_peers: no snapshot available for broadcast")
		return
	var inventory_blob: PackedByteArray = snap.get("inventory_blob", PackedByteArray())
	_receive_snapshot_reset.rpc(inventory_blob)


## Send the current snapshot to a single specific peer (used during FAILOVER_PROMOTING).
## @param peer_id  The peer ID to target.
func _broadcast_snapshot_to_peers_id(peer_id: int) -> void:
	if not is_instance_valid(Inventory):
		return
	var state_dict: Dictionary = Inventory.get_all_state()
	var blob: PackedByteArray = var_to_bytes(state_dict)
	_receive_snapshot_reset.rpc_id(peer_id, blob)


## Called when the application window loses focus (background / app switch).
## Saves a snapshot so world state is preserved if iOS suspends the process.
func _on_app_focus_lost() -> void:
	if is_multiplayer_active() and is_instance_valid(WorldSave) and WorldSave.is_open():
		WorldSave.save_world_snapshot("bg_" + str(int(Time.get_unix_time_from_system())))
		# On iOS, background time is limited; begin graceful disconnect so peers
		# get a clean failover before the OS suspends us.
		if OS.get_name() == "iOS":
			begin_graceful_disconnect()


## Called when the application window regains focus.
## Reconnect logic is handled by begin_graceful_disconnect's reconnect window; this is a no-op.
func _on_app_focus_entered() -> void:
	pass

# ─── Private helpers ──────────────────────────────────────────────────────────

## Transition to a new state and emit session_state_changed.
func _set_state(new_state: String) -> void:
	_state = new_state
	session_state_changed.emit(new_state)


# ─── Phase 5 safety hooks (Plan 05-10) ───────────────────────────────────────

## Check whether a UID is in the local blocks cache.
## Returns true if the UID appears as a "blocked_uid" entry in _blocks_cache.
## @param uid  The UID to check (String).
func _is_blocked_locally(uid: String) -> bool:
	return _blocks_cache.any(func(b: Variant) -> bool:
		return b is Dictionary and (b as Dictionary).get("blocked_uid", "") == uid
	)


## Return true when outbound chat must be suppressed for the local account.
## This wraps _is_under_13_unconsented() as a public, unit-testable surface so
## integration tests can call it directly without triggering the RPC dispatch path.
## Plan 05-12: added as a testable extraction of the chat suppression predicate.
## DOCS §8.5 — under-13 unconsented accounts cannot use chat.
func should_suppress_chat() -> bool:
	return _is_under_13_unconsented()


## Return true if the local FriendsClient account is under-13 AND has not yet
## received parental consent. Used to gate outbound chat and join attempts.
## Returns false (non-blocking) if FriendsClient is not available, so test
## environments and offline play are not accidentally blocked.
func _is_under_13_unconsented() -> bool:
	var fc: Node = get_node_or_null("/root/FriendsClient")
	if not is_instance_valid(fc):
		return false  # Graceful degradation — no FC, no block.
	# FriendsClient exposes is_under_13 and is_consented as properties (set via
	# consent_status_received signal in Plan 05-05/05-06).
	var under_13: bool = false
	var consented: bool = true  # Default to true so non-under-13 accounts are never blocked.
	if "is_under_13" in fc:
		under_13 = bool(fc.get("is_under_13"))
	if "is_consented" in fc:
		consented = bool(fc.get("is_consented"))
	return under_13 and not consented


## Called when FriendsClient.blocks_loaded fires.
## Updates the local blocks cache used by _is_blocked_locally().
func _on_blocks_loaded(blocks: Array) -> void:
	_blocks_cache = blocks


## Called when FriendsClient.report_submitted fires.
## The report modal passes the reported UID via mute_session_uid() so we can
## add it to _session_muted without needing to store it in FriendsClient.
## Note: report_submitted carries no arguments — the UID must be passed separately
## by the UI layer calling mute_session_uid() before or after the report is submitted.
func _on_report_submitted() -> void:
	# No-op without a UID — the UI layer calls mute_session_uid() with the UID.
	# This handler exists so the connection is established and the signal is handled.
	pass


## Add a UID to the session auto-mute list so their incoming chat messages are
## dropped for the remainder of this session. Called by the report UI immediately
## after submit_report() to provide instant local feedback.
##
## @param uid  The UID of the player to auto-mute for this session.
func mute_session_uid(uid: String) -> void:
	if uid.is_empty():
		return
	_session_muted[uid] = true
