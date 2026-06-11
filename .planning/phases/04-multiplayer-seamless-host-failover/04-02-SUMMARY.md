---
phase: 04-multiplayer-seamless-host-failover
plan: "02"
subsystem: server-infrastructure
tags: [supabase, go, signaling-server, websocket, jwt, rls, friends-graph, webrtc]
dependency_graph:
  requires: [04-01]
  provides: [supabase-schema, go-signaling-server]
  affects: [04-03, 04-04, 04-05, 04-06, 04-07, 04-08, 04-09, 04-10, 04-11]
tech_stack:
  added:
    - nhooyr.io/websocket v1.8.11 (Go WebSocket library — pure Go, no CGO)
  patterns:
    - HS256 JWT verification using stdlib only (no third-party JWT lib)
    - HMAC time-limited TURN credentials (coturn use-auth-secret mode)
    - sync.RWMutex session registry with soft-cap operator alert
    - JSON v1 envelope on every WebSocket message {"v":1,"type":"...","payload":{}}
key_files:
  created:
    - supabase/migrations/001_friendships.sql
    - supabase/migrations/002_invites.sql
    - supabase/migrations/003_profiles.sql
    - supabase/README.md
    - signaling-server/go.mod
    - signaling-server/go.sum
    - signaling-server/cmd/signaling/main.go
    - signaling-server/internal/config/config.go
    - signaling-server/internal/hub/auth.go
    - signaling-server/internal/hub/session.go
    - signaling-server/internal/hub/hub.go
    - signaling-server/internal/hub/relay.go
    - signaling-server/internal/hub/hub_test.go
    - signaling-server/deploy/signaling.service
  modified:
    - .gitignore (added signaling binary to ignored paths)
decisions:
  - key: "stdlib-only-jwt"
    description: "VerifyJWT uses encoding/base64 + crypto/hmac + encoding/json only — no third-party JWT library. Reduces dependency surface for a security-critical path and satisfies go mod verify (T-04-02-SC)."
  - key: "nhooyr-websocket-over-gorilla"
    description: "Used nhooyr.io/websocket (pure Go, no CGO) per RESEARCH.md discretion. gorilla/websocket requires CGO on some targets; nhooyr builds cleanly with CGO_ENABLED=0 for the single-binary Linux deployment recipe."
  - key: "soft-cap-not-hard-block"
    description: "200-session cap is a soft cap: Register succeeds for the 201st session but logs an OPERATOR ALERT. Matches CONTEXT Area 2 intent — manual horizontal-scale checklist, not an automatic rejection that would break user sessions."
  - key: "published-at-unix-in-session-list"
    description: "Session.PublishedAt (time.Time) exposed as published_at_unix (int64 Unix timestamp) in session_list payload. Required for the CONTEXT Area 3 unverified-account join gate: clients block joining sessions >24h old."
metrics:
  duration_minutes: 5
  completed_date: "2026-05-29"
  tasks_completed: 2
  tasks_total: 2
  files_created: 14
  files_modified: 1
  test_pass_count: 10
---

# Phase 04 Plan 02: Supabase Migrations + Go Signaling Server Skeleton Summary

**One-liner:** Supabase friends-graph schema with RLS + Go WebSocket signaling server (JWT auth, 200-session cap, 4-peer max, 15-min idle prune, offer/answer/ICE relay).

## What Was Built

### Task 1 — Supabase SQL Migrations

Three SQL migration files establishing the friends-graph schema for Cubicraftia:

- **`001_friendships.sql`** — `friendships(user_a, user_b, status, created_at)` table with `CHECK (user_a < user_b)` canonical-order constraint and three RLS policies (SELECT/INSERT/DELETE scoped to members).
- **`002_invites.sql`** — `invites(token, host_uid, session_id, expires_at, redeemed_by, created_at)` table. The UPDATE RLS policy's `USING (redeemed_by IS NULL)` clause is the atomic single-use enforcement — Postgres row-level locking prevents concurrent double-redemption.
- **`003_profiles.sql`** — `profiles(id, username, created_at)` with `username TEXT NOT NULL UNIQUE`. SELECT policy `USING (TRUE)` for friend-search; UPDATE scoped to owner only.
- **`supabase/README.md`** — migration apply instructions (supabase CLI + psql paths), coturn restricted-mode requirement.

All policies use `(SELECT auth.uid())` instead of bare `auth.uid()` per RESEARCH.md guidance to avoid per-row function call overhead.

### Task 2 — Go Signaling Server Skeleton

Complete 6-file Go skeleton with tests:

- **`internal/config/config.go`** — env-var loader (PORT, SUPABASE_URL, SUPABASE_JWT_SECRET, MAX_SESSIONS with defaults 8080/200).
- **`internal/hub/auth.go`** — `VerifyJWT(tokenString, secret string) (uid string, err error)` using stdlib only. Validates HS256 signature, expiry, and `sub` claim.
- **`internal/hub/session.go`** — `SessionRegistry` with `sync.RWMutex`. `Register` enforces max_peers ≤ 4. Soft-cap operator alert at 200+ sessions. `PruneIdle(timeout)` for 15-min idle enforcement. `Session.PublishedAt` exposed as `published_at_unix` in `sessionListEntry`. `GenerateTURNCredentials` produces HMAC-SHA1 coturn use-auth-secret credentials per session.
- **`internal/hub/hub.go`** — `Hub` struct with `HandleConn` (JWT verification on WebSocket upgrade → 401 on failure), `handleMessage` dispatcher (register/publish_session/unpublish_session/offer/answer/ice/update_host), background idle-session pruner via `Run(ctx)`.
- **`internal/hub/relay.go`** — `relay(fromUID, toUID, raw)` with `peer_not_found` error response. `writePump` drains `client.send` channel to WebSocket.
- **`cmd/signaling/main.go`** — CLI flags override env vars, graceful shutdown on SIGINT/SIGTERM with 10s deadline.
- **`deploy/signaling.service`** — systemd unit with `EnvironmentFile=/etc/cubicraftia/signaling.env`, `Restart=on-failure`, security hardening (`NoNewPrivileges`, `PrivateTmp`, `ProtectSystem`).
- **`internal/hub/hub_test.go`** — 10 tests:
  - `TestSessionRegisterAndGet`, `TestSessionCapacityWarning`, `TestUpdateHost`, `TestUpdateHostNotFound`, `TestPruneIdle`, `TestPruneIdleKeepsActive`, `TestSessionListEntry`
  - `TestJWTRejectionOnConnect` — 4 sub-cases (no token, invalid token, wrong secret, expired token) → all return HTTP 401
  - `TestFourPeerMaxEnforced` — Registry rejects max_peers=5; handleMessage returns `peer_limit_exceeded` error
  - `TestTURNCredentials` — TURN credential structure validation

## Verification Results

```
go build ./cmd/signaling   → exit 0 (BUILD OK)
go test ./...              → ok github.com/cubicraftia/signaling-server/internal/hub  0.299s (10/10 pass)
go mod verify              → all modules verified (T-04-02-SC satisfied)
```

## CONTEXT-Locked Constraints Enforced

| Constraint | Where Enforced | Status |
|-----------|----------------|--------|
| 200-session soft cap | SessionRegistry.Register — operator ALERT log | Soft cap (log + continue) |
| 4-peer max per session | SessionRegistry.Register returns error if maxPeers>4; Hub.handlePublishSession returns peer_limit_exceeded | Hard block |
| 15-min idle timeout | SessionRegistry.PruneIdle(15*time.Minute) called every 60s by Hub.Run | Implemented |
| JSON v1 envelope | Every message encodes {"v":1,"type":"...","payload":{...}} | Implemented |
| JWT auth on WS upgrade | Hub.HandleConn calls VerifyJWT; returns 401 on failure | Implemented |
| HMAC TURN credentials | GenerateTURNCredentials(sessionID, sharedSecret, ttlSeconds) | Implemented |
| published_at_unix in session_list | sessionListEntry.PublishedAtUnix set from Session.PublishedAt.Unix() | Implemented |

## Decisions Made

1. **stdlib-only-jwt** — `VerifyJWT` uses only `encoding/base64`, `crypto/hmac`, `encoding/json` — no third-party JWT library. Reduces dependency surface for the security-critical authentication path. `go mod verify` passes (T-04-02-SC mitigation).

2. **nhooyr-websocket-over-gorilla** — `nhooyr.io/websocket` chosen per RESEARCH.md discretion. Pure Go (no CGO), compatible with `CGO_ENABLED=0` single-binary Linux cross-compile. gorilla/websocket requires CGO on some targets.

3. **soft-cap-not-hard-block** — The 200-session cap is a soft cap (log OPERATOR ALERT on breach, do not fail Register). This matches CONTEXT Area 2 intent: operator alert + manual horizontal-scale checklist. Hard-rejecting the 201st session would break live user sessions unexpectedly.

4. **published-at-unix-in-session-list** — `Session.PublishedAt` (set in `Register` to `time.Now()`) is exposed in the `session_list` server→client payload as `published_at_unix` (int64 Unix timestamp). Required for CONTEXT Area 3: unverified accounts cannot join sessions older than 24 hours.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed json.RawMessage type mismatch in relay.go buildError**
- **Found during:** Task 2 — `go build ./cmd/signaling`
- **Issue:** `envelope.Payload` is `json.RawMessage` but `buildError` initially passed a raw struct literal value
- **Fix:** Marshal errPayload to `[]byte` first, then cast to `json.RawMessage`
- **Files modified:** `signaling-server/internal/hub/relay.go`
- **Commit:** ec07a4d (included in Task 2 commit after fix)

No other deviations — plan executed as written.

## Threat Surface Scan

All security surfaces were in the plan's `<threat_model>`:

| Threat ID | Mitigation | Where |
|-----------|-----------|-------|
| T-04-02-S | `VerifyJWT()` on every WebSocket upgrade; 401 on failure; `TestJWTRejectionOnConnect` covers all failure cases | `hub.go:HandleConn`, `auth.go:VerifyJWT` |
| T-04-02-T | RLS `USING (redeemed_by IS NULL)` in `002_invites.sql` | `supabase/migrations/002_invites.sql` |
| T-04-02-D | 200-session soft cap logged; 4-peer hard block in `Register` and `handlePublishSession` | `session.go`, `hub.go` |
| T-04-02-D2 | coturn restricted-mode deployment documented in `supabase/README.md` | `supabase/README.md` |
| T-04-02-SC | `go mod verify` passes; `nhooyr.io/websocket v1.8.11` hash verified | `go.sum` |

No new threat surface introduced beyond the plan's threat model.

## Known Stubs

None — all functionality in this plan is fully implemented. The signaling server is a skeleton in the architectural sense (no game-state logic) but all the wired-up components are complete and tested.

## Self-Check: PASSED

- [x] `supabase/migrations/001_friendships.sql` exists, contains `CHECK (user_a < user_b)`
- [x] `supabase/migrations/002_invites.sql` exists, contains `redeemed_by IS NULL`
- [x] `supabase/migrations/003_profiles.sql` exists, contains `username TEXT NOT NULL UNIQUE`
- [x] `supabase/README.md` exists
- [x] `signaling-server/go.mod` exists
- [x] `signaling-server/go.sum` exists
- [x] `signaling-server/cmd/signaling/main.go` exists
- [x] `signaling-server/internal/hub/hub.go` exists
- [x] `signaling-server/internal/hub/session.go` exists
- [x] `signaling-server/internal/hub/relay.go` exists
- [x] `signaling-server/internal/hub/auth.go` exists
- [x] `signaling-server/internal/hub/hub_test.go` exists (10 tests, all pass)
- [x] `signaling-server/deploy/signaling.service` exists with `Restart=on-failure` and `EnvironmentFile`
- [x] Commit `a733e4a` exists (Task 1)
- [x] Commit `ec07a4d` exists (Task 2)
- [x] `go build ./cmd/signaling` exits 0
- [x] `go test ./...` reports `ok github.com/cubicraftia/signaling-server/internal/hub`
