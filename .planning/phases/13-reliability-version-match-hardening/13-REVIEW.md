---
phase: 13-reliability-version-match-hardening
reviewed: 2026-07-10T00:00:00Z
depth: deep
files_reviewed: 15
files_reviewed_list:
  - src/autoload/network_manager.gd
  - src/autoload/session_registry.gd
  - src/autoload/friends_client.gd
  - src/autoload/build_info.gd
  - src/ui/connection_problem_overlay.gd
  - src/ui/connection_problem_overlay.tscn
  - src/ui/join_screen.gd
  - src/ui/join_screen.tscn
  - src/ui/network_hud.gd
  - src/ui/title_scene.gd
  - src/ui/title_scene.tscn
  - src/world/main_scene.gd
  - src/world/main_scene.tscn
  - locale/en.po
  - locale/nl.po
findings:
  critical: 1
  warning: 4
  info: 2
  total: 7
status: issues_found
---

# Phase 13: Code Review Report

**Reviewed:** 2026-07-10T00:00:00Z
**Depth:** deep
**Files Reviewed:** 15
**Status:** issues_found

## Summary

Phase 13 adds a connection-problem reason/overlay pipeline, a PROTOCOL_VERSION P2P
join-handshake reject gate, a failover-election version-exclusion filter, ICE
candidate-type tracking, bounded Connecting/reconnect timers, and an invite-redeem
fail-closed fix, plus the UI wiring to surface all of it.

The isolated pieces are each carefully built and individually well-tested (the
version-mismatch reject path, the election-exclusion filter, the bounded timeout
timers, and the zero-row invite-redeem guard all have direct unit/integration
coverage and behave correctly in isolation). However, tracing the join flow
end-to-end across `network_manager.gd` surfaced a single wiring gap that breaks
the entire "join a session as a non-hosting peer" flow for any fresh app launch:
`_start_as_peer_rtc()` never connects Godot's `multiplayer.peer_connected` signal
to `_on_peer_connected()`, so the RELY-03 state transition, the PROTOCOL_VERSION
handshake, and the whole downstream connected-peer bookkeeping this phase now
depends on can never fire for a joining peer. Every test added by this phase
drives `_handle_reported_protocol_version` / `_on_connecting_timeout` /
`_on_reconnect_grace_timeout` directly rather than through the real signal path,
so none of them observe this gap. This is classified Critical — it is a
regression in shipped, reachable code, not a hypothetical edge case.

Three second-tier correctness gaps were found in the invite-redeem fail-closed
fix and the failover version-exclusion dict lifecycle (host/failover cleanup),
plus a repo-convention violation (new em/en-dashes in comments, against
project CLAUDE.md) introduced by this phase's new files.

## Critical Issues

### CR-01: `_start_as_peer_rtc()` never wires `multiplayer.peer_connected` — peer join can never complete (RELY-03/VER-01 regression)

**File:** `src/autoload/network_manager.gd:626-641` (`_start_as_peer_rtc`)

**Issue:**

`_start_as_host_rtc()` (line 599-600) and `_do_failover_elected()` (line
1263-1264) both connect the low-level multiplayer signal:

```gdscript
if not multiplayer.peer_connected.is_connected(_on_peer_connected):
    multiplayer.peer_connected.connect(_on_peer_connected)
```

`_start_as_peer_rtc()` — called from `start_peer()` (the ordinary "join a
session as a client" path) and from `_do_failover_waiting_reconnect()` — does
**not**. It only connects `multiplayer.server_disconnected`:

```gdscript
func _start_as_peer_rtc(my_peer_id: int) -> void:
    _rtc_mp = WebRTCMultiplayerPeer.new()
    _rtc_mp.create_client(my_peer_id)
    multiplayer.multiplayer_peer = _rtc_mp
    if not multiplayer.server_disconnected.is_connected(_on_host_disconnected):
        multiplayer.server_disconnected.connect(_on_host_disconnected)
    ...
```

Before Phase 13, this didn't matter: `start_peer()` transitioned to
`STATE_CONNECTED_AS_PEER` **optimistically**, immediately after calling
`_start_as_peer_rtc()`, regardless of whether the real WebRTC data channel to
peer 1 ever opened. Plan 13-01 (RELY-03) deliberately removed that
optimistic transition:

```gdscript
func start_peer(session_id: String, my_peer_id: int) -> void:
    ...
    _start_as_peer_rtc(my_peer_id)
    _connect_signaling()
    ...
    # RELY-03: do not optimistically transition to CONNECTED_AS_PEER here — the
    # real WebRTC handshake has not completed yet. Start the bounded Connecting
    # timeout instead; the transition happens only when _on_peer_connected(1)
    # genuinely fires.
    if is_instance_valid(_connecting_timeout_timer):
        _connecting_timeout_timer.wait_time = CONNECTING_TIMEOUT_S
        _connecting_timeout_timer.start()
```

The transition to `CONNECTED_AS_PEER` now depends entirely on
`_on_peer_connected(1)` firing (network_manager.gd:1149-1192), which in turn
depends on `multiplayer.peer_connected` being connected on the peer side. It
never is, for a process that has not previously acted as host (i.e. every
ordinary "join a friend's session" launch). Consequences, all reachable in a
real playtest:

1. The joining peer's WebRTC data channel to the host may open perfectly, but
   `_on_peer_connected(1)` is never invoked, so `_connecting_timeout_timer` is
   never stopped, `_state` never becomes `CONNECTED_AS_PEER`, and
   `_report_protocol_version.rpc_id(1, ...)` (only sent from inside
   `_on_peer_connected`, line 1171) is never sent.
2. Because the host never receives `_report_protocol_version`, its own
   `_pending_version_peers[peer_id]` gate (set in `_on_peer_connected` on the
   host side, line 1190) never resolves — the host also never emits its own
   `peer_connected` for this peer. The join is broken from both sides, not
   just the client's.
3. After `CONNECTING_TIMEOUT_S` (12 s), `_on_connecting_timeout()` fires (state
   is still `STATE_CONNECTING`), and the peer reports `connection_problem`
   ("timeout" or "relay_failed") and disconnects — even though the underlying
   P2P connection may be completely healthy.
4. Downstream UI wired in this same phase observes exactly this failure:
   `JoinScreen._on_connection_problem()` (join_screen.gd:103-104) tears itself
   down, `ConnectionProblemOverlay` pops the "taking longer than expected"
   modal, and `title_scene.gd`'s one-shot `peer_connected` listener
   (`_on_self_joined`, bound at line 694) never fires, so `INVITE_JOINED`
   telemetry and the `joined_via_invite` marker are also silently never
   written.

No test in the suite exercises this path: `grep -rl "_start_as_peer_rtc\|start_peer("` under `tests/` returns nothing. `test_connecting_timeout.gd` drives `_on_connecting_timeout()` directly; `test_protocol_version_handshake.gd` drives `_handle_reported_protocol_version()` directly (its own header explicitly says it bypasses `multiplayer.get_remote_sender_id()` "which cannot be reliably driven in a headless off-tree test"). Both are valid unit-test choices in isolation, but together they mean the actual signal-wiring regression at the seam between `start_peer()` and the rest of the new state machine has zero coverage.

**Fix:**

```gdscript
func _start_as_peer_rtc(my_peer_id: int) -> void:
    _rtc_mp = WebRTCMultiplayerPeer.new()
    _rtc_mp.create_client(my_peer_id)
    multiplayer.multiplayer_peer = _rtc_mp
    if not multiplayer.server_disconnected.is_connected(_on_host_disconnected):
        multiplayer.server_disconnected.connect(_on_host_disconnected)
    if not multiplayer.peer_connected.is_connected(_on_peer_connected):
        multiplayer.peer_connected.connect(_on_peer_connected)
    if not multiplayer.peer_disconnected.is_connected(_on_peer_disconnected):
        multiplayer.peer_disconnected.connect(_on_peer_disconnected)
    var conn := WebRTCPeerConnection.new()
    ...
```

Then add a regression test that exercises the real signal path (e.g. an
integration test that calls `start_peer()`, manually emits
`multiplayer.peer_connected.emit(1)` — or drives two real in-process
`WebRTCMultiplayerPeer` instances through signaling — and asserts
`get_state() == "CONNECTED_AS_PEER"`), since this is precisely the seam the
existing unit tests were designed to bypass.

## Warnings

### WR-01: Invite-redeem success path can still emit `friendship_created` with an empty `host_uid`

**File:** `src/autoload/friends_client.gd:1053-1070` (`_on_invite_completed`, `redeem_invite` branch)

**Issue:** The Plan 13-03 fix (commit `62b7582`/`5b0afe8`) correctly guards the
zero-row case documented in RELY-04/D-05:

```gdscript
if not (json is Array and (json as Array).size() > 0):
    invite_redeem_failed.emit("expired")
    return
var host_uid := ""
var row: Variant = (json as Array)[0]
if row is Dictionary:
    host_uid = str((row as Dictionary).get("host_uid", ""))
if host_uid != "" and host_uid != _user_id:
    create_friendship(host_uid)
friendship_created.emit(host_uid)
```

but it does not guard the case where the array is non-empty and `row` is a
`Dictionary` (or not) whose `host_uid` field is missing or an empty string —
`friendship_created.emit(host_uid)` runs unconditionally on the last line,
so `friendship_created("")` can still fire. This is exactly the invariant the
signal's own doc comment (line 96-100) says must never happen
("friendship_created must never fire with an empty host_uid"), and the only
test added (`test_invite_redeem_expired.gd`) covers the `"[]"` case and the
fully-populated `'[{"host_uid":"uid-x"}]'` case, not a `'[{}]'` /
`'[{"host_uid":""}]'` row.

`title_scene.gd:671-673` does add its own defense-in-depth guard
(`if host_uid.is_empty(): _on_invite_redeem_failed("expired"); return`) for
this exact scenario, which limits the blast radius for that one call site,
but `friends_panel.gd:277-278` connects `friendship_created` with no such
guard, and any future caller inherits the same gap.

**Fix:**

```gdscript
if host_uid.is_empty():
    invite_redeem_failed.emit("expired")
    return
if host_uid != _user_id:
    create_friendship(host_uid)
friendship_created.emit(host_uid)
```

### WR-02: `SessionRegistry.clear_all_peers()` does not clear `_peer_protocol_version` — stale version data can leak across a failover promotion

**File:** `src/autoload/session_registry.gd:118-126` vs `292-298`

**Issue:** `unregister_peer()` (the per-peer cleanup path) correctly erases
`_peer_protocol_version[peer_id]` (line 125). `clear_all_peers()` (the
bulk-reset path invoked by `NetworkManager._do_failover_elected()` when a
promoted peer becomes the new host) clears `_peer_list`,
`_rtt_rolling_avg`, `_join_order`, `_surviving_peers`,
`_missed_keepalive_count`, and resets `_join_counter` — but not
`_peer_protocol_version`. Any peer_id that was recorded as version-mismatched
(or matched) before the failover remains in that dictionary after
`clear_all_peers()`. If a subsequently-reconnecting peer is assigned the same
numeric peer_id (plausible: peer IDs are small integers handed out by the
signaling server / WebRTCMultiplayerPeer, and are not guaranteed unique across
a session's lifetime once the old holder has left), `is_protocol_version_compatible()`
and `compute_elected_host()` will silently apply the *old* peer's
compatibility verdict to the *new* peer until the new peer's own
`_report_protocol_version` RPC round-trip overwrites the entry — a window in
which an incompatible new peer could be treated as compatible, or vice versa.

**Fix:**

```gdscript
func clear_all_peers() -> void:
    _peer_list.clear()
    _rtt_rolling_avg.clear()
    _join_order.clear()
    _surviving_peers.clear()
    _missed_keepalive_count.clear()
    _peer_protocol_version.clear()
    _join_counter = 0
```

### WR-03: New Phase 13 comments introduce em-dashes/en-dashes, violating CLAUDE.md

**Files:** `src/autoload/network_manager.gd:426, 1069, 1159, 1206, 1315`;
`src/ui/connection_problem_overlay.gd` (11 occurrences, e.g. lines 4, 14, 22,
28-33); `src/ui/connection_problem_overlay.tscn` (12 occurrences in header/
inline `;` comments, e.g. lines 4, 12-20)

**Issue:** CLAUDE.md (project root) states: "Never use em-dashes or en-dashes
(— –) in any output: prose, code, comments, commit messages, or generated
content ... Regular hyphens in compound words are fine." All of the instances
above are newly-added lines in this phase's diff (verified against
`git diff b77a9ae~1 HEAD`), not pre-existing text. Examples:

```gdscript
# RELY-03: do not optimistically transition to CONNECTED_AS_PEER here — the
## (13-UI-SPEC.md Copywriting Contract — only these 3 reasons reference the host).
```
```
; Icon        — TextureRect: 32×32, icon_error.png, brick-white tint.
```

None of these are player-facing i18n strings (all `msgid`/`msgstr` additions
in `locale/en.po`/`locale/nl.po` were checked and are clean), so there is no
user-facing localization impact, but it is a direct, repeated violation of an
explicit, non-negotiable project rule across the new/modified files in this
phase.

**Fix:** Replace each em/en-dash with a comma, colon, parenthetical, or a
period + new sentence, e.g. `"...CONNECTED_AS_PEER here: the real WebRTC
handshake has not completed yet."` A quick repo-scoped sweep:
`git diff <base>..HEAD -- src/ | grep -P '^\+.*[—–]'` to catch the rest before
merging.

### WR-04: No test drives the real signal-wiring path that CR-01 broke

**Files:** `tests/unit/test_connecting_timeout.gd`, `tests/integration/test_protocol_version_handshake.gd`

**Issue:** Both new test files are explicit, well-reasoned choices to bypass
Godot's live multiplayer signal plumbing (documented in their own header
comments), which is reasonable for unit-testing the pure logic in isolation.
But the net effect, combined across both files, is that the actual
`start_peer()` → `_start_as_peer_rtc()` → (real `multiplayer.peer_connected`
signal) → `_on_peer_connected()` → `_report_protocol_version` chain this phase
newly depends on has zero test coverage anywhere in the suite (see CR-01).

**Fix:** Add at minimum one integration test that calls the public
`start_peer()` entry point and asserts the resulting wiring
(`multiplayer.peer_connected.is_connected(_nm._on_peer_connected)`) rather
than only ever testing the private handlers it's supposed to invoke.

## Info

### IN-01: `compute_elected_host()` doc comment overstates its own guarantee

**File:** `src/autoload/session_registry.gd:203-210`

**Issue:** The inline comment states a peer with a mismatched
PROTOCOL_VERSION "can never be elected host, even if it has the best RTT."
This is true except in the deliberate (and tested — see
`test_all_survivors_mismatched_falls_back_to_unfiltered`) deadlock-avoidance
fallback: if every surviving candidate is recorded as mismatched, election
falls back to the unfiltered set and a mismatched peer *can* be elected. This
is a reasonable design tradeoff (there's no correct choice when 100% of
survivors are incompatible), but the comment's absolute wording doesn't match
the implemented and tested behavior.

**Fix:** Reword to: "...can never be elected host, even with the best RTT,
unless every surviving candidate is recorded as mismatched (deadlock
avoidance fallback below)."

### IN-02: `JoinScreen._get_host_username()` fallback is a hardcoded English literal, inconsistent with the new overlay's own stated standard

**File:** `src/ui/join_screen.gd:127-132`

**Issue:** Not new to this phase's diff (line unchanged), but Phase 13's own
new code calls this out explicitly:
`connection_problem_overlay.gd:157-163`'s comment says JoinScreen's
`_get_host_username()` fallback "is a hardcoded English literal; this
overlay must never show English text under the Dutch locale, so its
fallback uses the newly-added `ui.common.generic_host` key instead." Since
`join_screen.gd` was actively migrated in this same phase (13-06) and the
gap is directly acknowledged in a sibling file added by this phase, it's
worth closing now rather than carrying the inconsistency forward.

**Fix:** In `join_screen.gd`, replace `return "your host"` with
`return tr("ui.common.generic_host")` (the key already exists, added by this
same phase for the overlay).

---

_Reviewed: 2026-07-10T00:00:00Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: deep_
