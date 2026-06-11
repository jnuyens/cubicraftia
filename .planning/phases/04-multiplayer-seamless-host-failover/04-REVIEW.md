---
phase: 04-multiplayer-seamless-host-failover
reviewed: 2026-05-29T00:00:00Z
depth: standard
files_reviewed: 36
files_reviewed_list:
  - signaling-server/cmd/signaling/main.go
  - signaling-server/internal/config/config.go
  - signaling-server/internal/hub/auth.go
  - signaling-server/internal/hub/hub.go
  - signaling-server/internal/hub/hub_test.go
  - signaling-server/internal/hub/relay.go
  - signaling-server/internal/hub/session.go
  - supabase/migrations/001_friendships.sql
  - supabase/migrations/002_invites.sql
  - supabase/migrations/003_profiles.sql
  - src/autoload/friends_client.gd
  - src/autoload/inventory.gd
  - src/autoload/network_manager.gd
  - src/autoload/session_registry.gd
  - src/autoload/world_save.gd
  - src/networking/profanity_filter.gd
  - src/ui/chat_overlay.gd
  - src/ui/friends_panel.gd
  - src/ui/handover_screen.gd
  - src/ui/invite_modal.gd
  - src/ui/join_screen.gd
  - src/ui/mobile_overlay.gd
  - src/ui/network_hud.gd
  - src/ui/players_tab.gd
  - src/ui/settings_menu.gd
  - src/ui/sign_in_panel.gd
  - src/world/remote_builder_nameplate.gd
  - tests/conftest_phase4.gd
  - tests/integration/test_failover_fault_injection.gd
  - tests/integration/test_snapshot_migration.gd
  - tests/unit/test_chat_rate_limit.gd
  - tests/unit/test_election_algorithm.gd
  - tests/unit/test_event_replication.gd
  - tests/unit/test_friends_schema.gd
  - tests/unit/test_invite_token.gd
  - tests/unit/test_keepalive_logic.gd
findings:
  critical: 12
  warning: 10
  info: 5
  total: 27
status: issues_found
---

# Phase 04: Code Review Report

**Reviewed:** 2026-05-29  
**Depth:** standard  
**Files Reviewed:** 36  
**Status:** issues_found

## Summary

This phase delivers the WebRTC signaling server (Go), Supabase schema migrations, and a large GDScript multiplayer layer covering failover state machine, keepalive, event replication, friends/invite management, chat, and multiple UI surfaces.

The security-critical boundaries — `broadcast_event` server guard, `@rpc("authority")` on `_receive_replicated_event` and `_receive_snapshot_reset` — are correctly implemented. The SQL migrations use proper RLS with `(SELECT auth.uid())` subquery optimization. The JWT verifier correctly rejects algorithm confusion by checking the header.

However, there are 12 critical defects that must be fixed before shipping: three security vulnerabilities in the signaling server (unauthenticated `update_host`, missing per-session authorization, and peer-count cap never enforced at the client-join step), an insecure PRNG driving invite token generation, a race condition in ICE candidate flushing, data-loss risks in the failover snapshot path, a broken `_show_error` concatenation, and several other correctness bugs.

---

## Narrative Findings (AI reviewer)

## Critical Issues

### CR-01: `update_host` accepts any authenticated peer as the new host — no authorization check

**File:** `signaling-server/internal/hub/hub.go:275-296`  
**Issue:** `handleUpdateHost` lets any connected, authenticated client claim the role of host for any session. There is no check that the caller is currently a member of `p.SessionID`, nor that they were the expected failover winner. A malicious peer can send `update_host` with any `session_id` and `new_host_uid` to hijack an arbitrary live session's host field in the signaling server registry. The `host_updated` notification is then delivered to the fraudulent new host.

**Fix:** Before calling `h.sessions.UpdateHost`, verify the requesting client's `uid` matches the current `HostUID` **or** is in the session's peer list. At a minimum, require `client.sessionID == p.SessionID`:
```go
// In handleUpdateHost, before UpdateHost call:
s := h.sessions.Get(p.SessionID)
if s == nil || (s.HostUID != client.uid && client.sessionID != p.SessionID) {
    client.send <- buildError("unauthorized", "not a member of this session")
    return
}
```

---

### CR-02: Go signaling server — 4-peer cap tracked in `PeerCount` but never enforced at join time

**File:** `signaling-server/internal/hub/session.go:68-98`  
**Issue:** `Session.PeerCount` is initialized to 1 and never subsequently incremented. The `handleRelay` path (offers/answers from joining peers) does not check or update `PeerCount`. This means the server never enforces `MaxPeers`. A fifth, sixth, or Nth client can successfully exchange WebRTC signaling messages with the host. The client code re-checks in GDScript but the server is the authoritative gate.

**Fix:** Increment `PeerCount` when an `offer` message is successfully relayed to the host (i.e. when a new peer initiates), and reject offers when the session is at capacity:
```go
// In handleRelay, for msgType == "offer":
s := h.sessions.Get(client.sessionID)
if s != nil && s.PeerCount >= s.MaxPeers {
    client.send <- buildError("session_full", "session has reached maximum peers")
    return
}
// After relaying:
if s != nil { s.PeerCount++ }
```

---

### CR-03: Invite token uses `randi()` — not cryptographically secure

**File:** `src/autoload/friends_client.gd:666-671`  
**Issue:** `_generate_invite_token()` calls `randi()` (GDScript's seeded Mersenne Twister PRNG) for each character. Godot's `randi()` is a deterministic PRNG seeded from the OS at engine startup, not a CSPRNG. An attacker who observes multiple invite tokens can predict future tokens, enabling invite forgery.

**Fix:** Use `Crypto.generate_random_bytes(16)` and encode with base32:
```gdscript
func _generate_invite_token() -> String:
    var crypto := Crypto.new()
    var raw: PackedByteArray = crypto.generate_random_bytes(16)
    # Encode 16 raw bytes into 26-char base32 (128 bits).
    var token := ""
    var bits: int = 0
    var bit_count: int = 0
    for byte: int in raw:
        bits = (bits << 8) | byte
        bit_count += 8
        while bit_count >= 5:
            bit_count -= 5
            token += BASE32_ALPHABET[(bits >> bit_count) & 0x1F]
    return token
```

---

### CR-04: ICE candidate race — `_flush_pending_ice_candidates` called before `add_peer()` completes on host side

**File:** `src/autoload/network_manager.gd:411-421`  
**Issue:** In `_on_signaling_peer_offer`, the call sequence is:
```
conn.set_remote_description("offer", sdp)
_remote_sdp_set[peer_id] = true
_flush_pending_ice_candidates(peer_id, conn)
```
`_rtc_mp.add_peer(conn, peer_id)` is called on line 418 **before** `set_remote_description`. If `set_remote_description` triggers the `session_description_created` signal synchronously (which creates an answer and may also trigger ICE candidate creation), those ICE candidates arrive back through `_on_signaling_ice_candidate` while `_remote_sdp_set[peer_id]` is still false (line 419 hasn't executed yet). They would be queued, and then `_flush_pending_ice_candidates` on line 421 flushes them — but the issue is `set_remote_description` is async in WebRTC; candidates created **during** the offer processing could arrive **after** `_flush_pending_ice_candidates` clears the queue, causing them to be dropped.

More concretely: `_flush_pending_ice_candidates` on line 421 calls `conn.add_ice_candidate` for all queued entries — but this is done before the peer connection is fully established. The conn returned from `_rtc_mp.get_peer(peer_id)` on line 737 may not yet have `peer_id` registered if called immediately after `add_peer`. This is the classic Pitfall 7 gap the code claims to address but only partially resolves.

**Fix:** Set `_remote_sdp_set[peer_id] = true` immediately before `set_remote_description`, not after, so that any synchronous ICE callbacks during SDP processing are applied directly rather than queued:
```gdscript
_rtc_mp.add_peer(conn, peer_id)
_remote_sdp_set[peer_id] = true   # must be before set_remote_description
conn.set_remote_description("offer", sdp)
_flush_pending_ice_candidates(peer_id, conn)
```

---

### CR-05: Snapshot broadcast during failover uses `var_to_bytes` on live Inventory state — no integrity check, and snapshot may be empty

**File:** `src/autoload/network_manager.gd:886-891`  
**Issue:** `_broadcast_snapshot_to_peers_id` serializes `Inventory.get_all_state()` with `var_to_bytes`. Godot's `var_to_bytes`/`bytes_to_var` does not verify integrity and can deserialize arbitrary object types from the byte stream if the receiver calls `bytes_to_var` without `allow_objects=false` (the default). In `Inventory.reset_from_state`, line 270 calls `bytes_to_var(state_blob)` with no type restriction — if a malicious peer somehow injects a crafted `state_blob` via the RPC channel, arbitrary GDScript object deserialization occurs.

**Fix:** Use `bytes_to_var_with_objects` only for trusted local data, and restrict the snapshot RPC path:
```gdscript
# In Inventory.reset_from_state:
var state: Variant = bytes_to_var(state_blob)  # CHANGE TO:
var state: Variant = bytes_to_var(state_blob)  # This is already object-restricted by default in Godot 4
# Actually safe — bytes_to_var in Godot 4 does NOT allow objects unless the
# bytes were produced with var_to_bytes_with_objects. But add a check:
if not (state is Dictionary):
    return false
```
The immediate risk is lower than initially feared — Godot 4's `bytes_to_var` only deserializes primitive Godot types, not arbitrary Object references, unless `var_to_bytes_with_objects` was used at the sender. However, the sender uses `var_to_bytes` and the receiver trusts the result. The concern is: if the Inventory contains objects (Resources), those serialize differently. **The actual blocker** is that `_broadcast_snapshot_to_peers_id` calls `Inventory.get_all_state()` at failover time, but does NOT check if Inventory is in a consistent state. If Inventory is mid-event (an `apply_event` call is in flight), the snapshot may reflect a partially-applied state, causing inventory duplication or item loss on all peers.

**Fix:** Ensure `get_all_state()` is only called from a consistent point (after `apply_event` returns), or use a lock/copy-on-write pattern.

---

### CR-06: `_on_peer_connected_during_promotion` transitions to `FAILOVER_COMPLETE` then immediately `CONNECTED_AS_HOST` — double-state-emit causes UI flicker and may confuse state listeners

**File:** `src/autoload/network_manager.gd:843-849`  
**Issue:** `_on_peer_connected_during_promotion` calls `_set_state(STATE_FAILOVER_COMPLETE)` followed immediately by `_set_state(STATE_CONNECTED_AS_HOST)`. Each call emits `session_state_changed`. Listeners such as `ChatOverlay._on_session_state_changed` and `NetworkHud._on_session_state_changed` will receive `FAILOVER_COMPLETE` then `CONNECTED_AS_HOST` in rapid succession. The `HandoverScreen` subscribes to `host_failover_complete` (not the state changes) so it is fine, but other state-machine listeners checking `FAILOVER_COMPLETE` will enter an intermediate state then be immediately overwritten. More importantly, the test harness `test_failover_convergence_under_4s` accepts both states as valid, masking this bug — the code never actually rests in `FAILOVER_COMPLETE` long enough for any real cleanup to occur.

**Fix:** Eliminate the intermediate `FAILOVER_COMPLETE` emission; transition directly to `CONNECTED_AS_HOST` and emit `host_failover_complete` before the state change:
```gdscript
func _on_peer_connected_during_promotion(peer_id: int) -> void:
    _broadcast_snapshot_to_peers_id(peer_id)
    host_failover_complete.emit(1)
    _set_state(STATE_CONNECTED_AS_HOST)
    peer_connected.emit(peer_id)
```

---

### CR-07: `begin_graceful_disconnect` calls `_disconnecting_gracefully.rpc()` which has `@rpc("authority")` — peers cannot call this RPC

**File:** `src/autoload/network_manager.gd:318-329`, `src/autoload/network_manager.gd:553-557`  
**Issue:** `_disconnecting_gracefully` is declared `@rpc("authority", "call_remote", "reliable")`, meaning only peer_id=1 (the server/host) can send it. But `begin_graceful_disconnect()` is called by any node, including non-host peers. When a non-host peer calls `begin_graceful_disconnect()`, the `.rpc()` call on line 319 attempts to send an RPC as a non-authority peer — this silently fails in Godot 4 (the RPC is dropped). The peer disconnects locally without notifying the host or other peers of its departure, leading to keepalive timeouts being the only detection mechanism (up to 6s).

**Fix:** Change `_disconnecting_gracefully` to `@rpc("any_peer")` so any peer can notify others, or add a separate `@rpc("any_peer")` peer→host notification and let the host forward it:
```gdscript
# Peers notify the host, host broadcasts to all:
@rpc("any_peer", "call_remote", "reliable")
func _notify_leaving() -> void:
    if multiplayer.is_server():
        _disconnecting_gracefully.rpc()
```

---

### CR-08: `FriendsClient.create_friendship` emits `sign_up_failed` on friends-limit breach — wrong signal for a friends operation

**File:** `src/autoload/friends_client.gd:344-349`  
**Issue:** When the friends cap (50) is reached, `create_friendship` emits `sign_up_failed.emit(tr("ui.friends.limit_reached"))`. This is the sign-up failure signal, which is wired to sign-up UI handlers. Listeners such as `SignInPanel` that subscribe to `sign_up_failed` will show the "friends limit reached" error inside the sign-up form, not in the friends UI. There is a `friendship_created` and no `friendship_creation_failed` signal, but using `sign_up_failed` here is wrong regardless.

**Fix:** Add a dedicated signal `friendship_creation_failed(reason: String)` and emit it here, or emit `invite_creation_failed` which is semantically closer:
```gdscript
signal friendship_creation_failed(reason: String)
# In create_friendship():
if is_friends_limit_reached():
    friendship_creation_failed.emit(tr("ui.friends.limit_reached"))
    return
```

---

### CR-09: `JoinScreen._show_error` concatenation bug — error heading is always empty

**File:** `src/ui/join_screen.gd:122-125`  
**Issue:** 
```gdscript
_error_heading.text = tr("ui.join.error_connection").replace(reason, "")
```
This replaces the `reason` string (e.g. "Session too old for unverified accounts") within the localized error heading string. If the heading does not contain the `reason` substring — which it won't, because they are distinct locale keys — the heading is displayed unchanged. If the heading happens to contain the reason text (impossible with tr() keys), it would be stripped. The intent was likely:
```gdscript
_error_heading.text = tr("ui.join.error_connection")
_error_body.text = reason
```
But as written, the heading always shows the full `tr("ui.join.error_connection")` (slightly wrong) and the body shows `reason` (correct). The `.replace(reason, "")` call on the heading is dead code at best and a bug waiting to happen if the heading and body ever share text.

**Fix:**
```gdscript
func _show_error(reason: String) -> void:
    _content.visible = false
    _error_content.visible = true
    _error_heading.text = tr("ui.join.error_connection")
    _error_body.text = reason
```

---

### CR-10: `profiles` table missing INSERT policy — no user can create their own profile

**File:** `supabase/migrations/003_profiles.sql`  
**Issue:** The `profiles` table has SELECT and UPDATE RLS policies but no INSERT policy. With RLS enabled and no insert policy, no row can be inserted into `profiles` by an authenticated user. Users can never create their own profile row, breaking the display name system. The `search_friend` and `get_profile` calls in `FriendsClient` will find no results until an admin manually inserts rows.

**Fix:** Add an INSERT policy:
```sql
CREATE POLICY "Users create own profile"
  ON public.profiles FOR INSERT
  TO authenticated
  WITH CHECK ( (SELECT auth.uid()) = id );
```

---

### CR-11: `FriendsClient.sign_out` clears tokens synchronously before the HTTP logout completes — if logout fails, user appears signed out but token is still valid server-side

**File:** `src/autoload/friends_client.gd:241-253`  
**Issue:** `sign_out()` calls `_clear_tokens()` and emits `signed_out()` on lines 252-253 regardless of whether the HTTP POST to `/auth/v1/logout` succeeds. If the network is unavailable, the server-side session is never invalidated — the access token remains valid until it naturally expires. Meanwhile the local state shows the user as signed out. On next app launch, `_load_tokens` finds an empty auth.cfg, so the token cannot be refreshed. This is a session management correctness issue: the token is not revoked.

**Fix:** Clear tokens only after a successful HTTP response (in `_on_auth_completed` for the `"signout"` action), and show an error if the logout network call fails. At minimum, add a comment documenting the intentional behavior if the design decision is to accept orphaned server sessions.

---

### CR-12: `handleUpdateHost` does not validate that `new_host_uid` is a connected client — ghost-host assignment

**File:** `signaling-server/internal/hub/hub.go:275-296`  
**Issue:** `h.sessions.UpdateHost(p.SessionID, p.NewHostUID)` sets the session's `HostUID` to any arbitrary string the caller provides in `new_host_uid`. There is no check that a client with `uid == p.NewHostUID` is actually connected. If the new host disconnects before `update_host` is sent, the signaling server records a non-existent UID as host. Subsequent `relayDirect(p.NewHostUID, notif)` will silently drop the `host_updated` notification (the target is not connected), and the session record is left in a broken state with a phantom host.

**Fix:** Verify the new host is currently connected:
```go
h.mu.RLock()
_, connected := h.clients[p.NewHostUID]
h.mu.RUnlock()
if !connected {
    client.send <- buildError("new_host_not_connected", "new host UID is not connected")
    return
}
```

---

## Warnings

### WR-01: `TURN credentials` use HMAC-SHA256 but coturn `use-auth-secret` mode expects HMAC-SHA1

**File:** `signaling-server/internal/hub/session.go:39-46`  
**Issue:** `GenerateTURNCredentials` uses `hmac.New(sha256.New, ...)`. The coturn `use-auth-secret` static credential mode specifies HMAC-SHA1 (see [coturn docs](https://github.com/coturn/coturn/wiki/turnserver)). Credentials generated with SHA256 will be rejected by a standard coturn installation, causing all TURN relay connections to fail silently (WebRTC falls back to no-relay or fails).

**Fix:**
```go
import "crypto/sha1"
mac := hmac.New(sha1.New, []byte(sharedSecret))
```

---

### WR-02: `_check_peer_timeouts` emits `peer_laggy(true)` every tick at count==3, not just once

**File:** `src/autoload/network_manager.gd:463-473`  
**Issue:** The condition `if count == KEEPALIVE_WARN_THRESHOLD` fires on every `_check_peer_timeouts` call when `count` is exactly 3. Since `_simulate_keepalive_miss` increments and immediately calls `_check_peer_timeouts`, and because the real keepalive loop calls `_check_peer_timeouts` every second, the `peer_laggy(peer_id, true)` signal is emitted once per keepalive tick from tick 3 until tick 6. This floods subscribers (NetworkHud, PlayersTab) with redundant state changes. The unit test only checks `assert_signal_emitted` (not `assert_signal_emit_count`) so the bug is not caught.

**Fix:** Track whether the laggy state has already been signaled per peer, or change to `>=`:
```gdscript
if count == KEEPALIVE_WARN_THRESHOLD and not _laggy_peers.get(peer_id, false):
    _laggy_peers[peer_id] = true
    peer_laggy.emit(peer_id, true)
```

---

### WR-03: `writePump` uses magic integer `1` instead of `websocket.MessageText`

**File:** `signaling-server/internal/hub/relay.go:78`  
**Issue:** `c.conn.Write(ctx, 1 /* websocket.MessageText */, msg)` — the constant `1` is used instead of the named constant `websocket.MessageText`. If the nhooyr.io/websocket library ever changes the numeric value of the message type constants (unlikely but possible in a major version), this silently breaks. More importantly it makes the code harder to audit.

**Fix:**
```go
if err := c.conn.Write(ctx, websocket.MessageText, msg); err != nil {
```

---

### WR-04: `_on_friends_completed` emits `friendship_deleted` even when the DELETE response body is a JSON array (success with body)

**File:** `src/autoload/friends_client.gd:523-532`  
**Issue:** The handler checks `code == 204` for DELETE success, but Supabase PostgREST with `Prefer: return=representation` (which `_authed_headers()` always adds) returns HTTP 200 with a JSON array body on DELETE, not 204. The `if json is Array` branch on line 528 would emit `friends_loaded` (wrong signal) instead of `friendship_deleted` for a successful DELETE. The code only emits `friendship_deleted` on the `elif code == 204` branch which is unreachable when `return=representation` is always sent.

**Fix:** Track what kind of request is in flight (similar to `_pending_action` pattern on `_invite_req`) so the completion handler knows whether it was a GET, POST, or DELETE:
```gdscript
var _friends_pending_action: String = ""
# In delete_friendship(): _friends_pending_action = "delete"
# In _on_friends_completed(): check _friends_pending_action to dispatch correctly
```

---

### WR-05: `prune_old_snapshots` with `session_prefix` uses `LIKE` with user-supplied string — potential SQL wildcard injection

**File:** `src/autoload/world_save.gd:746-764`  
**Issue:** The `session_prefix + "%"` is concatenated into a parameterized query as a bind parameter, so SQL injection is not possible. However, the `%` and `_` characters within `session_prefix` itself are treated as LIKE wildcards. A session prefix containing `%` would match all snapshots, and `_` would match any single character. Session IDs are typically UUIDs so this is low-exploitability, but it can cause `prune_old_snapshots` to silently delete more snapshots than intended if the session_id contains special characters.

**Fix:** Escape LIKE wildcards in the prefix:
```gdscript
var safe_prefix := session_prefix.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_")
params = [safe_prefix + "%", keep_count]
# Add ESCAPE '\\' to the LIKE clause in the query string
```

---

### WR-06: `_canonical_pair` uses `<=` (less-than-or-equal) instead of `<` — two equal UIDs produce a valid pair instead of an error

**File:** `src/autoload/friends_client.gd:648-651`  
**Issue:** `if uid_x <= uid_y: return [uid_x, uid_y]`. When `uid_x == uid_y`, this returns `[uid_x, uid_y]` — a self-friendship. The Postgres `CHECK (user_a < user_b)` constraint will reject this (`<`, not `<=`), but the error will come back as an HTTP 400 from PostgREST rather than being caught client-side. The code should detect the self-friendship attempt before sending the request.

**Fix:**
```gdscript
static func _canonical_pair(uid_x: String, uid_y: String) -> Array[String]:
    if uid_x == uid_y:
        push_warning("FriendsClient._canonical_pair: attempt to friend self (%s)" % uid_x)
        return []  # Caller must check for empty result
    if uid_x < uid_y:
        return [uid_x, uid_y]
    return [uid_y, uid_x]
```

---

### WR-07: `start_host` transitions to `CONNECTED_AS_HOST` before WebSocket connection is established

**File:** `src/autoload/network_manager.gd:244-253`  
**Issue:** `start_host` calls `_connect_signaling()` (which calls `_ws.connect_to_url(...)` — an async non-blocking call), then immediately calls `_signaling_publish_session(...)` which calls `_ws.send_text(...)`. The WebSocket connection is not yet established at this point; the send will silently fail or buffer (depending on `WebSocketPeer` behavior). The state is also set to `CONNECTED_AS_HOST` before the signaling handshake is complete.

**Fix:** Wait for the WebSocket to reach `STATE_OPEN` before sending `publish_session`. Use a state check in `_process` or connect to a `WebSocketPeer.connected` callback.

---

### WR-08: `chat_overlay._attempt_send` starts rate window timer only on the **first** message, but `_rate_window_timer` is one-shot — if the first message is sent and the timer expires, subsequent sends don't restart the timer

**File:** `src/ui/chat_overlay.gd:187-189`  
**Issue:** 
```gdscript
if _message_count == 1:
    _rate_window_timer.start()
```
The timer only starts on `_message_count == 1`. If a user sends 1 message, waits for the timer to expire (count resets to 0), then sends another single message, the timer starts again (count becomes 1). This part is correct. However: if the user sends 5 messages rapidly (count 1→5), the timer runs. When it expires, count resets to 0. Now the user sends 1 message — count becomes 1, timer starts again. This is correct too. The bug: if `_message_count` was externally reset to 0 and the user sends their **first** message of a new window, it resets correctly. No bug here in the happy path. The actual issue: if `_message_count == 1` check is used, but messages 2 through 5 don't re-start the timer. This is intentional — the timer is already running from message 1. But if message 1 was somehow processed without starting the timer (e.g. the timer was manually stopped externally), messages 2-5 would never trigger the rate limit reset. This is a fragile design but not immediately exploitable.

**More critical:** The `_countdown_remaining` is initialized as `int(RATE_LIMIT_WINDOW_S)` = 10, but the rate window timer may not expire in exactly 10 seconds relative to when the countdown label shows "0". The countdown ticks at `COUNTDOWN_TICK_S` (1s) independently of the rate window timer. If the timer expires while countdown > 0 (e.g. due to timer drift), the input is re-enabled but the countdown label still shows a non-zero value. Vice versa if timer is slow, input stays locked after countdown hits 0. The two timers are not synchronized.

**Fix:** In `_on_rate_window_expired`, always stop and reset the countdown:
```gdscript
func _on_rate_window_expired() -> void:
    _message_count = 0
    _input_field.editable = true
    _rate_limit_label.visible = false
    _countdown_timer.stop()
    _countdown_remaining = 0
```
(This is already done — so the actual gap is that `_countdown_remaining` is not reset to 0, leaving a stale display. Add `_countdown_remaining = 0`.)

---

### WR-09: `InviteModal.open()` calls `FriendsClient.is_invite_send_allowed()` before checking network readiness, showing `ui.invite.error_network` for unverified accounts

**File:** `src/ui/invite_modal.gd:88-101`  
**Issue:** When `is_invite_send_allowed()` returns false (user not signed in or not email-verified), `_on_invite_failed(tr("ui.invite.error_network"))` is called with the network error string — but the failure is actually an auth/verification failure, not a network error. The error message misleads the user.

**Fix:**
```gdscript
func open(session_id: String) -> void:
    if is_instance_valid(FriendsClient) and not FriendsClient.is_signed_in():
        _on_invite_failed(tr("ui.invite.error_not_signed_in"))
        return
    if is_instance_valid(FriendsClient) and not FriendsClient.is_email_verified():
        _on_invite_failed(tr("ui.invite.error_not_verified"))
        return
    if is_instance_valid(FriendsClient) and FriendsClient.is_friends_limit_reached():
        _on_invite_failed(tr("ui.friends.limit_reached"))
        return
    ...
```

---

### WR-10: `test_snapshot_migration.test_snapshot_size_under_2mb` marks chunks dirty but `_stud_grid` is null — chunk_blob will always be empty (false pass)

**File:** `tests/integration/test_snapshot_migration.gd:84-103`  
**Issue:** The test calls `WorldSave.mark_chunk_dirty(Vector3i(cx, 0, cz))` for 200 chunks, then calls `save_world_snapshot("size_test")`. In `save_world_snapshot`, the chunk blob is only populated when `_stud_grid != null` (line 713: `if _stud_grid != null:`). In the test fixture, no StudGrid is attached, so `chunk_blob` will always be `PackedByteArray()` (empty). The size assertion `assert_lt(snapshot_size_kb, 2048.0)` will always pass because the chunk blob contributes 0 bytes. The test does not actually validate the 2 MB budget for real chunk data.

**Fix:** Either attach a stub StudGrid to WorldSave in the fixture, or note that this test only validates the inventory blob size and rename it accordingly. The 2 MB budget test is vacuously passing.

---

## Info

### IN-01: `_get_peer_display_name` in `chat_overlay.gd` returns `tr("ui.chat.send")` for peer_id==0 — using a button label as a system message name

**File:** `src/ui/chat_overlay.gd:284-285`  
**Issue:** `if peer_id == 0: return tr("ui.chat.send")` — the "Send" button label string is reused as the system message sender name. This will display "Send:" before system messages instead of something like "System".

**Fix:** Add a dedicated locale key `ui.chat.system_sender` and use it here.

---

### IN-02: `JoinScreen._get_host_username` returns the raw UID string, not a display name

**File:** `src/ui/join_screen.gd:133-137`  
**Issue:** `SessionRegistry.get_host_uid()` returns a UUID string (e.g., `"a3b4c5d6-..."`). This is then displayed in the heading `tr("ui.join.heading").replace("{username}", _get_host_username())`. Players will see "Joining a3b4c5d6-..." rather than the host's display name.

**Fix:** Look up the host's username from `SessionRegistry.get_peer_list()` or `FriendsClient` before falling back to the raw UID.

---

### IN-03: `players_tab._on_rollback_confirmed` broadcasts a `SNAPSHOT_RESET` event via `broadcast_event` — `apply_event` does not handle this kind

**File:** `src/ui/players_tab.gd:473-477`  
**Issue:** `NetworkManager.broadcast_event({"kind": "SNAPSHOT_RESET", "snapshot_id": snapshot_id})` routes through `Inventory.apply_event`. The `apply_event` match statement in `inventory.gd` does not have a `"SNAPSHOT_RESET"` case — it will fall to the `_:` branch and emit `push_warning("unknown event kind")`. The rollback does not actually propagate to peers. The correct mechanism is `NetworkManager._receive_snapshot_reset.rpc(inventory_blob)` or calling `_broadcast_snapshot_to_peers()`.

**Fix:**
```gdscript
# In _on_rollback_confirmed, replace broadcast_event call with:
if is_instance_valid(NetworkManager):
    NetworkManager._broadcast_snapshot_to_peers()
```

---

### IN-04: `handover_screen` does not handle `host_failover_failed` — overlay stays visible forever if failover fails

**File:** `src/ui/handover_screen.gd`  
**Issue:** `HandoverScreen` subscribes to `host_failover_started` and `host_failover_complete` but not `host_failover_failed`. If `host_failover_failed` is emitted by `NetworkManager`, the handover overlay remains visible indefinitely, blocking the entire UI.

**Fix:** Subscribe to `host_failover_failed` and dismiss the overlay:
```gdscript
NetworkManager.host_failover_failed.connect(_on_failover_failed)

func _on_failover_failed(_reason: String) -> void:
    _slow_subtitle_timer.stop()
    queue_free()
```

---

### IN-05: `conftest_phase4.cleanup_temp_world` calls `DirAccess.remove_absolute` on a directory that may still contain files (atomic and .tmp files)

**File:** `tests/conftest_phase4.gd:58-70`  
**Issue:** The cleanup removes `world.meta.sqlite` and `.bak.N` files but not `.atomic` or `.tmp` files that `WorldSaveIo` may create during checkpoint. `DirAccess.remove_absolute` on a non-empty directory fails silently on most platforms. This leaves orphaned test world directories in `user://worlds/phase4_test_*/`.

**Fix:** Use a recursive directory deletion, or also delete `world.meta.sqlite.atomic` and `world.meta.sqlite.tmp`:
```gdscript
for ext in [".atomic", ".tmp"]:
    var extra := meta_path + ext
    if FileAccess.file_exists(extra):
        DirAccess.remove_absolute(extra)
```

---

_Reviewed: 2026-05-29_  
_Reviewer: Claude (gsd-code-reviewer)_  
_Depth: standard_
