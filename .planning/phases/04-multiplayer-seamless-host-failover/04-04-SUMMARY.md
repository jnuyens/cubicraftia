---
phase: 04-multiplayer-seamless-host-failover
plan: "04"
subsystem: auth-friends
tags:
  - autoload
  - supabase
  - gotrue
  - friends
  - invites
  - auth

dependency-graph:
  requires:
    - 04-01  # Supabase schema (friendships, invites, profiles tables)
    - 04-03  # SessionRegistry autoload (session_published_at pattern)
  provides:
    - FriendsClient autoload (sign_in, sign_up, sign_out, get_friends, create_invite,
      redeem_invite, create_friendship, delete_friendship, get_profile)
  affects:
    - 04-05  # NetworkManager will connect FriendsClient.session_metadata_received
    - 04-08  # Integration tests for friends schema + invite token contract
    - Wave 3 UI  # SignInPanel, FriendsPanel, InviteModal wire into FriendsClient

tech-stack:
  added:
    - "ConfigFile persistence pattern for auth tokens (user://auth.cfg)"
    - "HTTPRequest child nodes per concern (concurrent-safe)"
    - "GoTrue REST: POST /auth/v1/token (signin + refresh), POST /auth/v1/signup, POST /auth/v1/logout"
    - "Supabase PostgREST: GET /rest/v1/friendships, POST /rest/v1/friendships, DELETE, PATCH /rest/v1/invites"
    - "26-char base32 invite token generation (128-bit entropy, lowercase base32 alphabet)"
  patterns:
    - "Multiple HTTPRequest child nodes for concurrent calls without GDScript await"
    - "Canonical UUID ordering (string comparison) mirrors Postgres CHECK (user_a < user_b)"
    - "_pending_action string dispatches correct signal in shared _on_auth_completed handler"
    - "NetworkManager signal connection with is_instance_valid guard (Pitfall 8 load-order)"

key-files:
  created:
    - src/autoload/friends_client.gd
  modified:
    - project.godot
    - locale/en.po
    - tests/unit/test_friends_schema.gd
    - tests/unit/test_invite_token.gd

decisions:
  - "Multiple HTTPRequest child nodes (one per concern) chosen over single node + queue to allow concurrent sign-in + friends fetch without await deadlock"
  - "ProjectSettings > OS.get_environment() > localhost fallback for Supabase URL — consistent with 04-RESEARCH.md Pitfall 8 and mobile sandbox constraints"
  - "sign_in_with_provider('apple'/'google') emits sign_in_failed('not_implemented_phase_5') stub — OAuth credentials are a Phase 5 dependency"
  - "Token debug log omitted — T-04-04-I mitigation; only first 8 chars would be logged if debug mode added later"
  - "redeem_invite PATCH target is /rest/v1/invites?token=eq.<token> — single-use semantics enforced by Supabase RLS UPDATE policy (redeemed_by IS NULL)"

metrics:
  duration: "~20 minutes"
  completed: "2026-05-29"
  tasks_completed: 1
  tasks_total: 1
  files_created: 1
  files_modified: 4
---

# Phase 04 Plan 04: FriendsClient Autoload Summary

**One-liner:** GoTrue email/password auth with token refresh + Supabase REST friends graph, 26-char base32 invite tokens, and session-age context via NetworkManager signal.

## Tasks Completed

| Task | Name | Commit | Key Files |
|------|------|--------|-----------|
| 1 | FriendsClient autoload — full implementation | c0f5fa9 | src/autoload/friends_client.gd, project.godot |

## What Was Built

`src/autoload/friends_client.gd` is a complete Godot 4 autoload (extends Node) providing:

**Auth layer (GoTrue):**
- `sign_in(email, password)` — POST `/auth/v1/token?grant_type=password`; emits `signed_in(user_id)` or `sign_in_failed(reason)`
- `sign_up(email, password, username)` — POST `/auth/v1/signup`; emits `sign_up_ok(user_id)` or `sign_up_failed(reason)`
- `sign_out()` — POST `/auth/v1/logout` + clear `user://auth.cfg`; emits `signed_out()`
- `refresh_token()` — POST `/auth/v1/token?grant_type=refresh_token`; called by 60s Timer when within 5 minutes of expiry
- `get_user()` — GET `/auth/v1/user`; reads `email_confirmed_at` into `_email_confirmed`
- `sign_in_with_provider(provider)` — Phase 5 stub; emits `sign_in_failed("not_implemented_phase_5")`

**Friends graph (Supabase PostgREST):**
- `get_friends()` — GET `/rest/v1/friendships` with `or=(user_a.eq.,user_b.eq.)` filter; emits `friends_loaded(friends)`
- `search_friend(query)` — GET `/rest/v1/profiles?username=ilike.*`; emits `profiles_found(profiles)`
- `get_profile(uid)` — GET `/rest/v1/profiles?id=eq.uid`; emits `profiles_found(profiles)`
- `create_friendship(other_uid)` — POST `/rest/v1/friendships` with canonical UUID ordering; gates on 50-friend cap
- `delete_friendship(other_uid)` — DELETE with canonical filter; emits `friendship_deleted()`

**Invite lifecycle:**
- `create_invite(session_id)` — generates 26-char base32 token; POST `/rest/v1/invites`; emits `invite_created(token, link)`. Gates on `is_invite_send_allowed()` and `not is_friends_limit_reached()`
- `redeem_invite(token)` — PATCH `/rest/v1/invites?token=eq.<token>` with `{redeemed_by}`; then calls `create_friendship(host_uid)`; emits `friendship_created(host_uid)`

**Session age context:**
- `get_session_published_at(session_id)` — returns cached Unix timestamp or 0 (unknown = do not block)
- `_on_session_metadata_received(session_id, published_at_unix)` — connected to `NetworkManager.session_metadata_received` in `_ready()` with `is_instance_valid` guard

**Token persistence:** ConfigFile at `user://auth.cfg` [auth] section; loaded in `_ready()` to restore session across restarts.

**Autoload registration:** `FriendsClient="*res://src/autoload/friends_client.gd"` added to project.godot after SessionRegistry (before NetworkManager per Plan 04-05 load-order contract).

## Deviations from Plan

None — plan executed exactly as written.

The plan specified `sign_in_with_email` but the action block confirmed `sign_in()` as the method name matching the exports list in `must_haves.artifacts`. Implementation uses `sign_in()` consistent with the artifacts exports list.

## Known Stubs

- `sign_in_with_provider("apple")` and `sign_in_with_provider("google")` emit `sign_in_failed("not_implemented_phase_5")`. These are intentional stubs — OAuth credentials are a Phase 5 dependency. The stub is documented in the method docstring.
- Integration round-trip tests in `test_friends_schema.gd` and `test_invite_token.gd` remain `pending()` — they require live Supabase and are deferred to Plan 04-08.

## Threat Surface Scan

All threat mitigations from the plan's `<threat_model>` are implemented:

| Threat ID | Mitigation Implemented |
|-----------|----------------------|
| T-04-04-S | Tokens stored in `user://auth.cfg` (app sandbox); refresh on timer |
| T-04-04-T | Canonical UUID ordering in `create_friendship()` before POST |
| T-04-04-D | 26-char base32 = 128-bit entropy; `expires_at = now + 86400s` |
| T-04-04-I | No token logging in any handler (docstring notes first-8-chars limit for future debug) |
| T-04-04-E | `is_invite_send_allowed()` gates `create_invite()`; emits `invite_creation_failed` if not verified |

No new security-relevant surface introduced beyond the plan's scope.

## Self-Check: PASSED

- `src/autoload/friends_client.gd` exists: FOUND
- `signed_in` signal declaration: FOUND (14 occurrences in grep)
- `create_invite` function: FOUND
- `redeem_invite` function: FOUND
- `FriendsClient` in project.godot: FOUND
- Commit c0f5fa9 exists: FOUND
- `ui.friends.limit_reached` in locale/en.po: FOUND
