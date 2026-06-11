---
phase: 04-multiplayer-seamless-host-failover
plan: "05"
subsystem: networking
tags: [webrtc, failover, keepalive, rpc, multiplayer, inventory-replication]
dependency_graph:
  requires:
    - 04-01  # SessionRegistry wave-0 scaffolding
    - 04-03  # WorldSave v3 + SessionRegistry peer tracking
    - 04-04  # FriendsClient (get_user_id, get_access_token)
  provides:
    - NetworkManager autoload — WebRTC lifecycle + failover state machine + keepalive + RPC bridge
    - Inventory.broadcast_event hook — host-authoritative event replication
    - Inventory.get_all_state / reset_from_state — snapshot API for failover
  affects:
    - 04-06  # Keepalive integration tests (depend on NetworkManager being live)
    - 04-08  # Chat RPC (send_chat stub already present)
    - 04-10  # Inventory snapshot deserialisation (reset_from_state stub)
tech_stack:
  added:
    - WebRTCMultiplayerPeer (Godot built-in — host/peer WebRTC lifecycle)
    - WebSocketPeer (Godot built-in — Go signaling server connection)
  patterns:
    - 10-state string constant machine with _set_state() emitting session_state_changed
    - ICE candidate queue (Pitfall 7): _pending_ice_candidates dict, flushed after set_remote_description
    - Keepalive EWMA RTT via SessionRegistry.update_peer_rtt; miss count in NetworkManager
    - RPC bridge: @rpc("authority") on _receive_replicated_event blocks non-host senders
    - is_instance_valid() guard on every cross-autoload call (Pitfall 8)
key_files:
  created:
    - src/autoload/network_manager.gd
  modified:
    - src/autoload/inventory.gd
    - project.godot
    - tests/unit/test_keepalive_logic.gd
    - tests/unit/test_event_replication.gd
    - tests/unit/test_election_algorithm.gd
decisions:
  - "NetworkManager registered after Inventory+WorldSave (Pitfall 8 load-order); FriendsClient comes after NetworkManager"
  - "Failover detection uses 200ms one-shot Timer (not a full second) for fast election after host drop"
  - "broadcast_event guards if not multiplayer.is_server(): return — non-host peers never broadcast (T-04-05-T)"
  - "_receive_replicated_event is @rpc(authority) so only peer_id=1 can send it (T-04-05-T2)"
  - "state strings (not enum) keep GDScript debugger output human-readable without a separate name table"
  - "reset_from_state is a stub returning true for non-empty blob; full deserialisation deferred to Plan 04-10"
metrics:
  duration_seconds: ~90
  tasks_completed: 3
  files_created: 1
  files_modified: 5
  completed_date: "2026-05-29"
---

# Phase 04 Plan 05: NetworkManager Autoload — WebRTC + Failover State Machine + Inventory RPC Bridge

**One-liner:** WebRTCMultiplayerPeer host/peer lifecycle with 10-state failover machine, 1 Hz keepalive loop with RTT tracking, and host-authoritative Inventory event replication over @rpc("authority").

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1a | NetworkManager WebRTC + keepalive + RPC bridge + signaling | 53a6093 | src/autoload/network_manager.gd, project.godot, tests/unit/test_keepalive_logic.gd, tests/unit/test_event_replication.gd |
| 1b | Failover state machine — 6 transition handlers | 816efea | tests/unit/test_election_algorithm.gd |
| 2 | Inventory broadcast hook + get_all_state + reset_from_state | 0291fef | src/autoload/inventory.gd |

## What Was Built

### Task 1a: NetworkManager — WebRTC + Keepalive + RPC Bridge

`src/autoload/network_manager.gd` (718 lines) implements:

- **11 state constants** (IDLE, CONNECTING, CONNECTED_AS_HOST, CONNECTED_AS_PEER, FAILOVER_DETECTING, FAILOVER_ELECTED, FAILOVER_PROMOTING, FAILOVER_COMPLETE, FAILOVER_WAITING, RECONNECTING, DISCONNECTED) with `_set_state()` emitting `session_state_changed`.
- **Public API**: `start_host()`, `start_peer()`, `is_multiplayer_active()`, `is_session_host()`, `get_session_id()`, `broadcast_event()`, `send_chat()`, `begin_graceful_disconnect()`, `set_update_rate_hz()`.
- **WebRTC setup**: `_start_as_host_rtc()` calls `create_server()`; `_start_as_peer_rtc()` calls `create_client()` and creates offer.
- **ICE candidate queue** (Pitfall 7): `_pending_ice_candidates` dict; `_on_signaling_ice_candidate` queues if SDP not set, `_flush_pending_ice_candidates` applies them after `set_remote_description()`.
- **Keepalive loop**: `_keepalive_accum` in `_process(delta)`; `_send_keepalive_to_all_peers()` increments miss count; `_keepalive_ping` @rpc(authority,unreliable); `_keepalive_pong` @rpc(any_peer) updates SessionRegistry RTT and resets miss count; `peer_laggy` emitted at 3 misses, `keepalive_timeout` at 6 misses.
- **RPC bridge**: `broadcast_event()` guards `if not multiplayer.is_server(): return`; `_receive_replicated_event` @rpc("authority","call_remote","reliable") calls `Inventory.apply_event()`.
- **Signaling WebSocket**: `_on_signaling_message` dispatches on type; `session_list` handler emits `session_metadata_received(session_id, published_at_unix)` for each entry and populates `SessionRegistry.set_session_published_at()`.
- **project.godot**: `NetworkManager="*res://src/autoload/network_manager.gd"` inserted after SessionRegistry, before FriendsClient.

### Task 1b: Failover State Machine

All 6 transition handlers fully implemented (no push_warning stubs):

1. `_on_host_disconnected()`: CONNECTED_AS_PEER → FAILOVER_DETECTING; starts 200ms `_failover_timer`.
2. `_on_failover_timer_timeout()`: calls `SessionRegistry.set_surviving_peers(1)` then `am_i_elected()` to branch to elected or waiting.
3. `_do_failover_elected()`: DETECTING → ELECTED → PROMOTING; closes old peer, `create_server()`, `clear_all_peers()`, `_notify_signaling_update_host()`.
4. `_on_peer_connected_during_promotion()`: pushes inventory snapshot blob via `_receive_snapshot_reset.rpc_id()`; transitions to CONNECTED_AS_HOST; emits `host_failover_complete(1)`.
5. `_do_failover_waiting()`: DETECTING → WAITING; listens for `update_host` signaling message.
6. `_on_snapshot_received_during_failover()`: transitions RECONNECTING → CONNECTED_AS_PEER; emits `host_failover_complete(1)`.

### Task 2: Inventory Broadcast Hook + Snapshot API

`src/autoload/inventory.gd` additions:

- **Broadcast hook** (after `_journal.append(event)` in `apply_event()`): triple-guarded with `is_instance_valid(NetworkManager) and NetworkManager.is_multiplayer_active() and multiplayer.is_server()`. The `is_instance_valid()` guard ensures headless GUT runs are unaffected.
- **`get_all_state()`**: returns deep-copy `{inventories, journal, next_seq}` for snapshot serialisation.
- **`reset_from_state(blob: PackedByteArray)`**: stub returns `false` on empty blob, `true` otherwise; full implementation deferred to Plan 04-10.

## Security Verification

| Threat ID | Mitigation | Status |
|-----------|-----------|--------|
| T-04-05-T | `if not multiplayer.is_server(): return` in broadcast_event() | Implemented |
| T-04-05-T2 | `@rpc("authority")` on `_receive_replicated_event` | Implemented |
| T-04-05-D | Chat goes through `send_chat` RPC, not broadcast_event/journal | Implemented |
| T-04-05-T3 | `@rpc("authority")` on `_receive_snapshot_reset` | Implemented |
| T-04-05-SC | Signaling only relays offer/answer/ICE; session_list is read-only parse | Implemented |

## Deviations from Plan

**1. [Rule 2 - Missing Critical Functionality] State count 11 not 10**
- The plan behavior spec lists 11 states (including DISCONNECTED) though the objective says "10-state". All 11 are implemented as const strings. No functional deviation — DISCONNECTED is necessary for `begin_graceful_disconnect()`.

**2. Task 1a and 1b implemented atomically**
- The plan expected 1a to have stub failover handlers replaced in 1b. Since GDScript has no separate compilation, the full 6 handler implementations were written at file creation time (1a) and the 1b commit captures the test update. Both commits exist and the done criteria for both tasks are met.

No other deviations — plan executed as specified.

## Known Stubs

| File | Stub | Reason |
|------|------|--------|
| src/autoload/inventory.gd | `reset_from_state(blob)` — TODO Plan 04-10 | Full snapshot deserialisation requires Plan 04-10's bytes_to_var replay logic |
| src/autoload/network_manager.gd | `_do_failover_waiting_reconnect` reconnects with `your_peer_id` from payload | Peer ID re-assignment protocol depends on Go signaling server v2 spec (Plan 04-09) |

## Threat Flags

None — all surface changes were within the plan's threat model boundary.

## Self-Check: PASSED

- `src/autoload/network_manager.gd` — FOUND
- `src/autoload/inventory.gd` broadcast hook — FOUND (1 non-comment occurrence)
- `get_all_state()` in inventory.gd — FOUND
- `reset_from_state()` in inventory.gd — FOUND
- `NetworkManager` in project.godot — FOUND
- Commit 53a6093 (Task 1a) — FOUND
- Commit 816efea (Task 1b) — FOUND
- Commit 0291fef (Task 2) — FOUND
