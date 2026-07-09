---
phase: 13-reliability-version-match-hardening
verified: 2026-07-10T00:00:00Z
status: human_needed
score: 12/12 must-haves verified (5 roadmap success criteria + 7 requirements)
has_blocking_gaps: false
overrides_applied: 0
human_verification:
  - test: "Trigger each of the 7 connection_problem reasons (expired, full, ended, blocked, version_mismatch, relay_failed, timeout) against a running client (e.g. via NetworkManager.report_connection_problem(\"<reason>\") from the Remote inspector, or the real triggers: expired invite, 5th peer joining a full session, mismatched PROTOCOL_VERSION build, killed signaling mid-join)."
    expected: "ConnectionProblemOverlay shows the same heading for all 7, with distinct body copy; relay_failed/timeout show Retry+Back, the other 5 show Back only."
    why_human: "Requires a running game client to observe actual rendered overlay content and button layout in-viewport; headless GUT tests already prove the string/button-set mapping logic, not the rendered result."
  - test: "Confirm the blocked reason's rendered copy never contains the word 'blocked' or implies exclusion, in both EN and NL."
    expected: "Generic 'Couldn't join this session' copy, visually indistinguishable from other failures."
    why_human: "Copy content itself is unit-tested; visual indistinguishability (identical layout/heading) needs an eyeball check."
  - test: "Confirm Escape key and clicking the background scrim do NOT dismiss the overlay; only its own button(s) do."
    expected: "Overlay stays open on Escape/scrim-click; only Primary/Secondary buttons close it."
    why_human: "Requires live input-event dispatch in a running viewport; not exercised by any headless test."
  - test: "Join a session and confirm the Connecting spinner visibly animates (not frozen) and, if the host is unreachable, resolves to timeout/relay_failed within the bounded ~12s window."
    expected: "Spinner animates continuously; Connecting state never hangs past ~12s; ConnectionProblemOverlay appears with the correct reason."
    why_human: "Visual animation playback and end-to-end real-network timing cannot be observed headlessly."
  - test: "Confirm NetworkHud's badge shows 'Direct' (green) or 'Relay' (amber) for every connected peer at all times, with no hover/click affordance, under a real connection."
    expected: "Badge always visible, correct color/text per real ICE candidate type, no interactivity."
    why_human: "Real ICE candidate-pair selection and on-screen color rendering require a live two-client session; the classification heuristic itself is unit-tested, not its real-network accuracy (explicitly deferred to Phase 12 NETVAL-04 per 13-UI-SPEC.md scope boundary)."
  - test: "Run two clients: an unmodified build hosting, and a build with a deliberately bumped BuildInfo.PROTOCOL_VERSION joining. Confirm the mismatched build is cleanly rejected with the version_mismatch reason and never silently connects."
    expected: "Joining peer sees ConnectionProblemOverlay with version_mismatch copy; no gameplay state syncs; host's SessionRegistry never lists the joiner as a failover candidate."
    why_human: "Requires two real running builds with different PROTOCOL_VERSION values; the handshake reject logic and the election-exclusion filter are both unit/integration tested in isolation, but the full real two-process join has not been observed running."
---

# Phase 13: Reliability & Version-Match Hardening Verification Report

**Phase Goal:** Connection failures (including version mismatches) are always clearly explained and recoverable, never silent, frozen, or desynced.
**Verified:** 2026-07-10T00:00:00Z
**Status:** human_needed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths (5 ROADMAP Success Criteria)

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Every connection failure surfaces on one shared "connection problem" screen with a specific, correct reason (expired/full/ended/blocked/version_mismatch/relay_failed/timeout) | VERIFIED (code layer) | `NetworkManager.CONNECTION_PROBLEM_REASONS` (network_manager.gd:74-75) lists exactly these 7 reasons; `report_connection_problem()` funnels every failure path (signaling errors, connecting timeout, reconnect-grace timeout, invite-redeem failure, version-mismatch reject) into `connection_problem(reason)`. `ConnectionProblemOverlay.show_reason()` maps all 7 to distinct i18n body copy (`_BODY_KEYS` dict) sharing one heading. Overlay is instanced in both `main_scene.tscn` and `title_scene.tscn` (self-subscribing to the signal in its own `_ready()`). 8/8 GUT tests in `test_connection_problem_overlay_reasons.gd` pass, including a no-digit and non-revealing-`blocked`-copy assertion. In-viewport rendering of the overlay itself is the human-verify item below. |
| 2 | A brief network blip triggers a silent auto-reconnect within a grace window before any failure is shown | VERIFIED (code layer) | `_do_failover_waiting()` starts a silent one-shot 5s `_reconnect_grace_timer` (network_manager.gd:1285-1293); no UI signal fires during the window; only `_on_reconnect_grace_timeout()` (on elapse) calls `report_connection_problem("ended")`. Stopped on success in `_do_failover_waiting_reconnect()`. 4/4 `test_reconnect_grace_timeout.gd` tests pass, including a "no-op after successful reconnect" case. The "genuinely zero visible UI change for the full window" claim is a rendering/timing observation deferred to human-verify. |
| 3 | "Connecting…" never appears frozen (bounded timeout); stale/invalid invite resolves to actionable error, not a hang | VERIFIED (code layer) | Bounded 12s `_connecting_timeout_timer` (`CONNECTING_TIMEOUT_S = 12.0`, network_manager.gd:218) started in `start_peer()`, resolves to `timeout`/`relay_failed` via `_on_connecting_timeout()`. `JoinScreen` now has a real looping `AnimatedSprite2D` spinner (`src/ui/join_screen.tscn:72`), confirmed present via `test_join_screen_migration.gd` (7/7 pass). Invite-redeem: `FriendsClient._on_invite_completed()` fails closed on a zero-row PATCH result AND on a non-empty row with an empty `host_uid` (WR-01 fix applied, `friends_client.gd:1053-1075`), emitting `invite_redeem_failed("expired")` instead of a phantom `friendship_created("")`; `title_scene.gd` has a matching defense-in-depth guard. `test_invite_redeem_expired.gd` (2/2) passes. Spinner *animating on screen* and the invite flow's real-app dismissal is human-verify. |
| 4 | Connection-quality badge honestly reflects relay vs. direct at all times | VERIFIED (code layer) | `NetworkHud.set_connection_badge(peer_id, is_relay)` replaces the old hidden-by-default `show_relay_badge`; badge defaults visible/Direct/green on row build (`network_hud.gd:247`), wired to `NetworkManager.connection_type_changed` (`_on_connection_type_changed`, line 130-133), which fires from ICE candidate-type classification (`get_connection_type()` in network_manager.gd, host/srflx=direct, relay=relay, srflx/host always overrides a prior relay classification). `NetworkHud` is instanced under `main_scene.tscn`'s UI CanvasLayer (confirmed by grep + headless boot). 6/6 `test_network_hud_badge.gd` + 4/4 `test_connection_type_badge.gd` pass. Real-network ICE candidate-pair accuracy is explicitly scoped to Phase 12 (NETVAL-04) per 13-UI-SPEC.md — not re-verified here; on-screen color/text rendering is human-verify. |
| 5 | Coarse `protocol_version` exchanged in join handshake; mismatched build cleanly rejected (incl. as failover candidate), never connect-and-silently-desync | VERIFIED (code layer) | `BuildInfo.PROTOCOL_VERSION` constant (build_info.gd:36) exchanged via `_report_protocol_version`/`_handle_reported_protocol_version` RPCs on WebRTC connect; host withholds `peer_connected` for a pending peer via `_pending_version_peers` until confirmed; mismatched peers are rejected via `_reject_connecting_peer()` (`_receive_connection_rejected` reports `version_mismatch` peer-side) and `peer_connected` is NEVER emitted for them. `SessionRegistry.compute_elected_host()` filters out version-mismatched peers from failover-election candidates (with a deadlock-avoidance fallback if 100% are mismatched), and `clear_all_peers()` now also clears `_peer_protocol_version` (WR-02 fix) so a promoted host's peer-ID reuse can't inherit a stale verdict. 5/5 `test_protocol_version_handshake.gd` (integration) + 5/5 `test_session_registry_version_filter.gd` pass. **Critical seam confirmed fixed:** `_start_as_peer_rtc()` now wires `multiplayer.peer_connected`/`peer_disconnected` to `_on_peer_connected`/`_on_peer_disconnected` (CR-01 fix, network_manager.gd:636-639) — without this, no joining peer could ever complete a handshake at all, breaking criteria 1-5 for every real join. A dedicated regression test (`test_start_peer_wires_peer_connected_signal`) drives the real public `start_peer()` entry point and passes. Real two-build (different PROTOCOL_VERSION) live-process rejection is human-verify. |

**Score:** 5/5 roadmap success criteria verified at the code/behavioral layer.

### Requirements Coverage (RELY-01..05, VER-01..02)

| Requirement | Description | Status | Evidence |
|---|---|---|---|
| RELY-01 | Single shared connection-problem screen, specific reason | SATISFIED | `ConnectionProblemOverlay` + `CONNECTION_PROBLEM_REASONS`, wired into both `main_scene.tscn` and `title_scene.tscn` |
| RELY-02 | Silent auto-reconnect grace window | SATISFIED | `_reconnect_grace_timer` (5s), silent by design, `test_reconnect_grace_timeout.gd` |
| RELY-03 | Non-frozen Connecting, sane timeout, clear failure path | SATISFIED | `_connecting_timeout_timer` (12s), real spinner in `join_screen.tscn`, `test_connecting_timeout.gd` |
| RELY-04 | Stale/invalid invite resolves to actionable error | SATISFIED | Fail-closed `FriendsClient`/`title_scene.gd` guards (both zero-row and empty-`host_uid` cases), `test_invite_redeem_expired.gd` |
| RELY-05 | Honest relay-vs-direct badge | SATISFIED | `NetworkHud.set_connection_badge`, always-visible two-state, ICE-driven |
| VER-01 | Coarse `protocol_version` exchanged in join handshake | SATISFIED | `BuildInfo.PROTOCOL_VERSION` + `_report_protocol_version`/`_handle_reported_protocol_version` RPCs |
| VER-02 | Mismatched build cleanly rejected, incl. failover candidate exclusion | SATISFIED | Host-authoritative reject-before-emit gate + `SessionRegistry.compute_elected_host()` exclusion filter, both fixed for the `clear_all_peers()` leak (WR-02) |

No orphaned requirements: REQUIREMENTS.md maps exactly these 7 IDs to Phase 13, all present in plan frontmatter (`requirements-completed` across 13-01..13-06).

### Required Artifacts

| Artifact | Expected | Status | Details |
|---|---|---|---|
| `src/autoload/network_manager.gd` | connection_problem funnel, bounded timers, VER handshake, ICE tracking | VERIFIED | All constructs present and wired; CR-01 fix confirmed in place at lines 636-639 |
| `src/autoload/session_registry.gd` | per-peer version tracking + election exclusion filter | VERIFIED | `compute_elected_host()` filter + `clear_all_peers()` WR-02 fix present |
| `src/autoload/friends_client.gd` | fail-closed invite redeem | VERIFIED | Both zero-row and empty-`host_uid` guards present (WR-01 fix) |
| `src/autoload/build_info.gd` | `PROTOCOL_VERSION` const | VERIFIED | Present, documented bump policy |
| `src/ui/connection_problem_overlay.gd`/`.tscn` | single reusable overlay, 7 reasons | VERIFIED, WIRED | Instanced as scene-root sibling in `main_scene.tscn` and `title_scene.tscn`; self-subscribes to `NetworkManager.connection_problem` |
| `src/ui/join_screen.gd`/`.tscn` | spinner, delegation to overlay, Reconnecting copy | VERIFIED, WIRED | `ErrorContent`/`_show_error()` removed; `Spinner` node present; `_on_connection_problem()` frees screen on any reason |
| `src/ui/network_hud.gd` | always-visible Direct/Relay badge | VERIFIED, WIRED | Instanced under `main_scene.tscn` UI CanvasLayer; `set_connection_badge`/`_on_connection_type_changed` present |
| `src/world/main_scene.gd`/`.tscn` | scene-tree wiring for all 3 UI surfaces + JoinScreen conditional instantiation | VERIFIED, WIRED | `_install_network_ui_wiring()` present and called from `_ready()`; grep + headless boot confirm ext-resources/node instances exist |
| `src/ui/title_scene.gd`/`.tscn` | ConnectionProblemOverlay pre-join coverage | VERIFIED, WIRED | Node instance confirmed present |

### Key Link Verification

| From | To | Via | Status | Details |
|---|---|---|---|---|
| `NetworkManager.connection_problem` | `ConnectionProblemOverlay.show_reason` | signal `.connect()` in overlay's own `_ready()` | WIRED | `connection_problem_overlay.gd:76` |
| `start_peer()` → `_start_as_peer_rtc()` | `multiplayer.peer_connected` → `_on_peer_connected()` | direct signal connect (CR-01 fix) | WIRED | `network_manager.gd:636-637`; regression test `test_start_peer_wires_peer_connected_signal` passes |
| `_on_peer_connected()` (peer side) | `_report_protocol_version.rpc_id(1, ...)` | RPC call inside handler | WIRED | `network_manager.gd:1177-1179` |
| Host `_handle_reported_protocol_version` | `SessionRegistry.set_peer_protocol_version` + `compute_elected_host()` exclusion | direct call + broadcast RPC | WIRED | Confirmed via `test_protocol_version_handshake.gd` + `test_session_registry_version_filter.gd` |
| `NetworkManager.connection_type_changed` | `NetworkHud._on_connection_type_changed` → `set_connection_badge` | signal `.connect()` in `network_hud.gd:_ready()` | WIRED | `network_hud.gd:86-87, 130-133` |
| `main_scene._ready()` | `_install_network_ui_wiring()` (JoinScreen conditional instantiation) | direct call | WIRED | `main_scene.gd:917` calling into `main_scene.gd:1084` |
| `FriendsClient.invite_redeem_failed` | `title_scene._on_invite_redeem_failed` | signal `.connect()` | WIRED | Confirmed present in title_scene.gd (per 13-03-SUMMARY, unchanged since) |

### Behavioral Spot-Checks / Test Suite

Full workspace GUT suite run once (`godot --headless --path . -s addons/gut/gut_cmdln.gd -gconfig=res://tests/gut_config.cfg`):

- **493 tests total, 464 passing, 0 failing, 29 pending/risky** (all pre-existing, documented as pending future plans e.g. Plan 03-02/03-04/03-09, or requiring a real display/GPU — none touch Phase 13 scope).
- All Phase 13 test files pass 100%: `test_connecting_timeout.gd` (3/3), `test_connection_problem_overlay_reasons.gd` (8/8), `test_connection_problem_reasons.gd` (7/7), `test_connection_type_badge.gd` (4/4), `test_invite_redeem_expired.gd` (2/2), `test_join_screen_migration.gd` (7/7), `test_network_hud_badge.gd` (6/6), `test_reconnect_grace_timeout.gd` (4/4), `test_session_registry_version_filter.gd` (5/5), `test_protocol_version_handshake.gd` (5/5 — including the CR-01 regression test).
- No new failures were introduced by this phase; the previously reported 17 world-save/SQLite failures from 13-REVIEW-FIX.md are **not reproduced** in this run (0 failing overall) — regardless, they are out of Phase 13 scope per the verification task's own instruction (Phase 13 touched no world-save code).
- Anti-pattern scan of all Phase 13 touched files: zero `TBD`/`FIXME`/`XXX`/`TODO`/`HACK`/`PLACEHOLDER` markers, zero em-dash/en-dash characters (confirms 13-REVIEW-FIX's WR-03 fix holds).

### Code Review Findings (13-REVIEW.md / 13-REVIEW-FIX.md)

The phase's own deep code review found 1 Critical + 4 Warning + 2 Info issues. All 6 in-scope findings (CR-01, WR-01, WR-02, WR-03, WR-04, IN-02) were fixed and independently re-verified against the current codebase in this pass:

| Finding | Fix confirmed in code? |
|---|---|
| CR-01 (join-hang: `_start_as_peer_rtc()` missing `peer_connected` wiring) | YES — `network_manager.gd:636-639` |
| WR-01 (invite-redeem could still emit `friendship_created("")`) | YES — `friends_client.gd:1069-1072` |
| WR-02 (`clear_all_peers()` leaks stale protocol-version data) | YES — `session_registry.gd:299-300` |
| WR-03 (em/en-dashes in new comments) | YES — zero dashes found in this pass's scan |
| WR-04 (no test drives the real peer-join signal path) | YES — `test_start_peer_wires_peer_connected_signal` added and passing |
| IN-02 (hardcoded English host-name fallback) | YES — `join_screen.gd:135` now uses `tr("ui.common.generic_host")` |
| IN-01 (doc-comment wording, skipped by instruction) | Not applicable — explicitly out of scope, cosmetic only |

### Human Verification Required

The phase's own plan (13-07) reached an explicit `checkpoint:human-verify` (Task 3, gate=blocking) that has not yet been approved. This is the correct, expected remaining gap: every behavioral/logic-layer truth above is verified via code + headless GUT tests, but rendering (spinner animation, overlay layout/colors, badge colors, real Escape/scrim-click non-dismissal, and a genuine two-build PROTOCOL_VERSION mismatch across two live processes) cannot be observed by a headless test run. See the `human_verification` list in this report's frontmatter for the 6 specific checks a human must perform in-app (mirrors 13-UI-SPEC.md's Acceptance Checkpoints and 13-07-SUMMARY.md's Task 3 checkpoint text verbatim).

### Gaps Summary

No code-level gaps. All 5 ROADMAP success criteria and all 7 requirements (RELY-01..05, VER-01..02) are implemented, wired, and covered by passing automated tests, including a dedicated regression test for the single Critical defect (CR-01) the phase's own code review found and fixed. The sole remaining item is the phase's own deliberately-deferred, blocking human-verify checkpoint for in-viewport confirmation — this is not a gap in delivered code, it is the expected next step per the phase's own plan structure. Recommend a human runs the 6 checks listed above, then marks 13-07 Task 3 approved and closes out STATE.md/ROADMAP.md/REQUIREMENTS.md bookkeeping (which currently show RELY/VER rows as "Complete" in REQUIREMENTS.md but 13-07 unchecked in ROADMAP.md — a minor documentation inconsistency, not a functional one, since the code-level work behind those rows is genuinely complete as verified here).

---

_Verified: 2026-07-10T00:00:00Z_
_Verifier: Claude (gsd-verifier)_
