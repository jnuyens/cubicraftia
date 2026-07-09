---
phase: 13-reliability-version-match-hardening
plan: 04
subsystem: networking
tags: [godot, webrtc, gdscript, gut, protocol-version, ice, multiplayer]

# Dependency graph
requires:
  - phase: 13-reliability-version-match-hardening (Plan 13-01)
    provides: connection_problem/report_connection_problem plumbing, CONNECTION_PROBLEM_REASONS,
      the `_on_peer_connected` peer-side anchor comment, STATE_CONNECTING/STATE_CONNECTED_AS_PEER
  - phase: 13-reliability-version-match-hardening (Plan 13-02)
    provides: BuildInfo.PROTOCOL_VERSION, SessionRegistry.set_peer_protocol_version /
      is_protocol_version_compatible, compute_elected_host() version-mismatch filter
provides:
  - PROTOCOL_VERSION P2P join-handshake (_report_protocol_version /
    _handle_reported_protocol_version RPCs)
  - Host-authoritative reject-before-emit gate for version-mismatched joining peers
    (_pending_version_peers, _reject_connecting_peer, _receive_connection_rejected)
  - ICE candidate-type tracking (_track_ice_candidate_type, _ice_candidate_types)
  - get_connection_type(peer_id) Direct/Relay/Unknown heuristic classifier
  - connection_type_changed(peer_id, is_relay) signal
affects: [13-06 (network_hud.gd Direct/Relay badge UI), 13-02 (SessionRegistry election filter, already wired)]

tech-stack:
  added: []
  patterns:
    - "Thin @rpc wrapper + directly-testable private helper (e.g. _report_protocol_version
      -> _handle_reported_protocol_version) so RPC sender-resolution logic stays
      headlessly unit-testable without a live multiplayer peer"
    - "Host-authoritative reject-before-emit gate: defer peer_connected via a pending-set
      Dictionary until an async confirmation RPC resolves, rather than emitting optimistically"

key-files:
  created:
    - tests/integration/test_protocol_version_handshake.gd
    - tests/unit/test_connection_type_badge.gd
  modified:
    - src/autoload/network_manager.gd

key-decisions:
  - "_on_peer_connected's peer-connected.emit(peer_id) is now gated on multiplayer.is_server():
    host role defers to _pending_version_peers (VER-02); peer role (connecting to host,
    peer_id==1) keeps emitting immediately since no explicit accept RPC exists, only reject"
  - "_disconnect_peer() now also erases _pending_version_peers and _ice_candidate_types
    entries so reconnects under the same peer_id don't inherit stale gate/classification state"
  - "get_connection_type() treats both srflx and host candidates as direct, and srflx/host
    presence always overrides a prior relay-only classification (never alarm without evidence)"

requirements-completed: [VER-01, VER-02, RELY-05]

duration: 55min
completed: 2026-07-09
---

# Phase 13 Plan 04: PROTOCOL_VERSION Handshake + Connection-Type Badge Summary

**Host-authoritative PROTOCOL_VERSION join-handshake that rejects mismatched peers before peer_connected ever fires, plus an ICE candidate-type heuristic (host/srflx/relay) backing an honest Direct/Relay connection badge.**

## Performance

- **Duration:** ~55 min
- **Completed:** 2026-07-09T20:58:20Z
- **Tasks:** 2
- **Files modified:** 3 (1 modified, 2 created)

## Accomplishments
- A joining peer reports its `BuildInfo.PROTOCOL_VERSION` to the host immediately on WebRTC connect (`_report_protocol_version.rpc_id(1, ...)`); the host withholds `peer_connected` for that peer_id until the version is confirmed compatible.
- A version-mismatched peer is rejected via `_reject_connecting_peer()` (tells the peer why via `_receive_connection_rejected`, then disconnects it): `peer_connected` is NEVER emitted for it, so no Inventory event or snapshot RPC is ever addressed to it.
- Every peer's `SessionRegistry` learns a reporting peer's version via `_sync_peer_protocol_version.rpc()` broadcast, so `compute_elected_host()`'s existing Plan 13-02 filter works consistently across all peers, not just the host.
- ICE candidate types (host/srflx/relay) are tracked per peer across both locally generated and remotely received candidates; `get_connection_type()` exposes a heuristic "direct"/"relay"/"unknown" classification, and `connection_type_changed` fires at both connection-confirmation points (peer-side host connect, host-side version-confirmed join).

## Task Commits

Both tasks landed in a single commit because Task 2's `connection_type_changed` emission points are literally inserted at Task 1's exact confirmation points inside the same function (`_on_peer_connected` and `_handle_reported_protocol_version`): the plan itself specifies this coupling, so a clean per-task line-level split was not practical without risking an incorrect partial commit.

1. **Task 1 + Task 2: PROTOCOL_VERSION handshake + ICE candidate-type tracking** - `99198be` (feat)

**Plan metadata commit:** pending (this summary + STATE.md/ROADMAP.md update, committed separately per protocol)

## Files Created/Modified
- `src/autoload/network_manager.gd` - Added `_pending_version_peers` / `_ice_candidate_types` state, `connection_type_changed` signal, `_report_protocol_version` / `_handle_reported_protocol_version` / `_sync_peer_protocol_version` / `_receive_connection_rejected` RPCs, `_reject_connecting_peer()` helper, `_track_ice_candidate_type()` / `get_connection_type()`, and wired the reject-before-emit gate + ICE tracking hooks into `_on_peer_connected`, `_on_signaling_peer_offer`, `_start_as_peer_rtc`, `_on_signaling_ice_candidate`, and `_disconnect_peer`.
- `tests/integration/test_protocol_version_handshake.gd` - Proves matching versions confirm the pending peer and emit `peer_connected` exactly once; mismatched versions never emit `peer_connected` and leave `SessionRegistry.is_protocol_version_compatible()` false; the rejected peer's own `_receive_connection_rejected` handler reports `version_mismatch` and transitions to `DISCONNECTED`.
- `tests/unit/test_connection_type_badge.gd` - Proves the host/srflx/relay/unknown classification logic, including that an srflx candidate seen after a relay candidate upgrades the classification from relay to direct.

## Decisions Made
- Gated `peer_connected.emit(peer_id)` with `if multiplayer.is_server():` rather than deferring unconditionally in both branches of `_on_peer_connected`, because the peer's own local emission (connecting to host, peer_id==1) has no corresponding "accept" RPC to wait for, only a reject RPC exists. Deferring the peer's own emission unconditionally would have broken the existing "silence == success" model that `title_scene.gd` relies on for its `peer_connected`-driven join-completion flow.
- Extracted `_handle_reported_protocol_version(sender_id, their_version)` as the plan's own `<done>` fallback specifies, since `multiplayer.get_remote_sender_id()` cannot be reliably driven in a headless off-tree/pending-peer test; the `@rpc` wrapper (`_report_protocol_version`) is a one-line pass-through.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing Critical] `_disconnect_peer()` now also cleans up `_pending_version_peers` and `_ice_candidate_types`**
- **Found during:** Task 1/2 implementation review
- **Issue:** The plan's action text for `_disconnect_peer()` cleanup wasn't updated for the two new per-peer Dictionaries this plan introduces. Without cleanup, a peer_id that reconnects after a prior disconnect would inherit a stale pending-version gate state or a stale (possibly wrong) ICE candidate-type classification from its previous connection.
- **Fix:** Added `_pending_version_peers.erase(peer_id)` and `_ice_candidate_types.erase(peer_id)` alongside the existing `_keepalive_miss_count` / `_laggy_peers` / `_pending_ice_candidates` / `_remote_sdp_set` cleanup in `_disconnect_peer()`.
- **Files modified:** src/autoload/network_manager.gd
- **Verification:** Full unit + integration GUT suites pass (381/406 unit, 61/65 integration; all non-passing are pre-existing pending/manual tests, 0 failures).
- **Committed in:** 99198be (Task 1+2 commit)

**2. [Rule 3 - Blocking] Removed a defensive `is_instance_valid(get_tree())` guard I initially added to `_reject_connecting_peer()`**
- **Found during:** Task 1 test authoring
- **Issue:** I first added a guard to make `_reject_connecting_peer()` safe to call from an off-tree test node (since `get_tree()` returns null off-tree and the engine prints a C++-level error). This guard changed timing semantics: it made `_disconnect_peer()` (which erases the peer's `SessionRegistry` protocol-version entry) run synchronously instead of after the intended `await get_tree().process_frame` suspension, which broke the plan's own `<done>` assertion that `SessionRegistry.is_protocol_version_compatible(peer_id)` reads `false` immediately after the rejection call returns.
- **Fix:** Reverted `_reject_connecting_peer()` to the plan's literal, unguarded pattern (identical to the existing `kick_peer()` precedent) and instead added the test's `NetworkManager` instance to the scene tree (`add_child_autoqfree`) so `get_tree()` resolves and the `await` genuinely suspends until the next frame, preserving the synchronous "not yet disconnected" window the assertion depends on.
- **Files modified:** src/autoload/network_manager.gd (net no-op vs. the literal plan text), tests/integration/test_protocol_version_handshake.gd
- **Verification:** `test_mismatched_version_rejects_and_withholds_peer_connected` passes; the engine still prints a non-fatal `ERROR: Attempt to call RPC with unknown peer ID` (no live multiplayer peer configured in the test), which is expected console noise, not a test failure.
- **Committed in:** 99198be (Task 1+2 commit)

**3. [Rule 1 - Bug] Fixed a GUT `assert_signal_emitted_with_parameters` misuse I introduced while drafting the test**
- **Found during:** Task 1 test authoring
- **Issue:** I initially passed a free-text assertion message as the 4th positional argument to `assert_signal_emitted_with_parameters()`, which GUT 9.4.0 interprets as an integer signal-emission index, causing a `SCRIPT ERROR: Invalid operands 'String' and 'int'`. This exact gotcha is already documented in `tests/unit/test_connection_problem_reasons.gd`'s header comment, which I initially missed.
- **Fix:** Removed the 4th positional argument from both call sites in the new test file.
- **Files modified:** tests/integration/test_protocol_version_handshake.gd
- **Verification:** All 8 new tests pass with 0 script errors.
- **Committed in:** 99198be (Task 1+2 commit)

---

**Total deviations:** 3 auto-fixed (1 missing critical, 1 blocking self-correction, 1 bug in my own test draft)
**Impact on plan:** All auto-fixes were necessary for correctness (state hygiene) or to satisfy the plan's own test/timing contract. No scope creep beyond the plan's stated tasks.

## Issues Encountered
None beyond the deviations above. The plan's guidance on the `Engine.register_singleton` limitation (STATE.md `engine-register-singleton-limit`) and the `_handle_reported_protocol_version` extraction fallback both applied directly and avoided further trial-and-error.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- `get_connection_type()` / `connection_type_changed` are ready for Plan 13-06 to wire into `network_hud.gd`'s Direct/Relay badge.
- VER-01/VER-02 are fully wired end-to-end; the accepted residual (T-13-04-02: bounded RPC-broadcast window before the version handshake resolves) is documented in the plan's threat model and requires no further action in this plan.
- No blockers for downstream plans (13-05, 13-06, 13-07).

---
*Phase: 13-reliability-version-match-hardening*
*Completed: 2026-07-09*

## Self-Check: PASSED

- FOUND: src/autoload/network_manager.gd
- FOUND: tests/integration/test_protocol_version_handshake.gd
- FOUND: tests/unit/test_connection_type_badge.gd
- FOUND: .planning/phases/13-reliability-version-match-hardening/13-04-SUMMARY.md
- FOUND commit: 99198be
