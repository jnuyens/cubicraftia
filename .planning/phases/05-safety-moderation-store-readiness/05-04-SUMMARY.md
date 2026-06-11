---
phase: 05-safety-moderation-store-readiness
plan: "04"
subsystem: signaling-server
tags: [safety, blocks, consent, coppa, moderation, smtp, rate-limiting]
dependency_graph:
  requires: [05-02]
  provides: [block-gate, consent-gate, admin-reports, parental-consent-smtp]
  affects: [signaling-server/internal/hub, signaling-server/cmd/signaling]
tech_stack:
  added: []
  patterns:
    - "PostgREST OR filter for bidirectional block query"
    - "Single-use token pattern (consent_token NULLed on confirm)"
    - "net/smtp multipart MIME (HTML + plain text)"
    - "Fail-closed pattern for safety gates (error → reject)"
key_files:
  created:
    - signaling-server/internal/hub/blocks.go
    - signaling-server/internal/hub/consent.go
  modified:
    - signaling-server/internal/hub/hub.go
    - signaling-server/internal/hub/hub_test.go
    - signaling-server/internal/config/config.go
    - signaling-server/cmd/signaling/main.go
decisions:
  - "blocks.go placed in hub package (not a separate package) to keep Hub method receivers and avoid circular imports"
  - "Fail-closed on gate errors: network error on isBlockedBetween or isConsentRequired causes rejection, not pass-through"
  - "checkReportRateLimit defined on Hub for testability without a separate service layer"
  - "consent_token NULLed in PATCH (single-use) rather than using a separate 'used' boolean column"
  - "GoTrue user metadata patched after consent confirm/revoke for JWT claim propagation"
  - "SMTP email sent after INSERT succeeds; failure is logged but not propagated (row is the source of truth)"
metrics:
  duration_seconds: 290
  completed_date: "2026-05-29"
  tasks_completed: 2
  files_changed: 6
---

# Phase 05 Plan 04: Signaling Server Safety Gates Summary

One-liner: Block-check and consent-check hard gates added to signaling server offer relay using Supabase service-role PostgREST queries, with parental consent SMTP lifecycle and operator reports endpoint.

## What Was Built

### Task 1: Block gate + consent gate + admin reports (hub.go, blocks.go)

**blocks.go** (new file, 160 lines):
- `isBlockedBetween(uidA, uidB string) (bool, error)` — queries `/rest/v1/blocks` with bidirectional OR filter using PostgREST syntax `?or=(and(blocker_uid.eq.A,blocked_uid.eq.B),and(...))`. Uses service-role key to bypass RLS. Fail-closed on error.
- `isConsentRequired(uid string) (bool, error)` — queries `/rest/v1/parental_consents` for the child's row; returns true if row exists and `consented_at` is NULL or `revoked_at` is set.
- `checkReportRateLimit(reporterUID string) (bool, error)` — queries `/rest/v1/reports` for count in last 24h (`created_at=gte.{now-24h}`); returns false (rate-limited) if >= 5 rows found.

**hub.go** extended:
- `handleRelay()` now calls `isBlockedBetween(joiner, host)` and `isConsentRequired(joiner)` for every "offer" message before incrementing peer count. Both gates fail-closed (network error → reject).
- `HandleAdminReports()` — GET /admin/reports, requires `Authorization: Bearer {ADMIN_SECRET}`, supports `?page=` and `?limit=` (max 200), proxies Supabase `/rest/v1/reports` with service-role key.
- `RequireAdminSecret()` middleware added for reuse.
- Helper functions: `parseInt()`, `extractTotalFromContentRange()`.

### Task 2: Parental consent lifecycle (consent.go, main.go)

**consent.go** (new file, 430 lines):
- `ConsentHandler` struct with `Hub *Hub` field.
- `HandleRequest(w, r)` — POST /consent/request; JWT-authenticates child; generates two 128-bit base32 tokens (consent + revoke) via `crypto/rand`; INSERTs `parental_consents` via service-role; sends SMTP multipart email via `net/smtp` with HTML+plain-text body and COPPA 2025 confirmation statement.
- `HandleConfirm(w, r)` — GET /consent/confirm?token=; looks up `consent_token`; validates 7-day expiry from `requested_at`; PATCHes `consented_at=NOW()` and clears `consent_token` to NULL (single-use); PATCHes GoTrue user metadata; returns HTML success page.
- `HandleRevoke(w, r)` — GET /consent/revoke?token=; looks up `revoke_token`; sets `revoked_at`; clears GoTrue `consented_at`; returns HTML success page.
- Internal helpers: `generateToken()`, `fetchConsentRow()`, `patchConsentRow()`, `patchGoTrueUserMeta()`, `sendConsentEmail()`.

**config.go** extended: Added `SupabaseServiceKey`, `AdminSecret`, `SMTPHost`, `SMTPPort`, `SMTPUser`, `SMTPPassword`, `SMTPFrom`, `ConsentBaseURL`, `TURNSharedSecret` fields with corresponding env var loading.

**main.go** extended: Route registration for `/consent/request`, `/consent/confirm`, `/consent/revoke`, `/admin/reports`.

### Tests Added (3 new)

- `TestBlockedSessionJoinRejected` — stubs Supabase to return a block row; verifies `handleMessage` sends `{"type":"error","payload":{"code":"blocked"}}` and does not relay the offer.
- `TestReportRateLimitFiveIn24h` — stubs Supabase to return 5 report rows; verifies `checkReportRateLimit` returns false.
- `TestConsentTokenSingleUse` — stubs Supabase SELECT/PATCH; verifies HandleConfirm returns 200 on first use and 404 on second use of the same token.

## Verification

```
cd signaling-server && go build ./... && go test ./...
```

Output: `ok github.com/cubicraftia/signaling-server/internal/hub 0.487s` — all 14 tests pass.

## Commits

- `368a312` — `test(05-04): add failing tests for blocked join, report rate limit, consent single-use` (RED phase)
- `cc9cb68` — `feat(05-04): block-aware join gate, consent lifecycle, admin reports endpoint` (GREEN phase)

## Deviations from Plan

### Auto-added: Fail-closed on gate errors

**Found during:** Task 1 implementation

**Issue:** Plan specified "reject if blocked" but didn't explicitly state what to do if `isBlockedBetween` or `isConsentRequired` returns an error (network failure, Supabase down).

**Fix:** Both gates fail-closed — any error causes the join to be rejected with the appropriate error code. This is the correct security posture (T-05-E2, T-05-E3): a modified client cannot bypass a gate by causing a network error.

**Files:** `signaling-server/internal/hub/hub.go`

### Implementation note: blocks.go as separate file

Plan described adding functions to hub.go, but `isBlockedBetween`, `isConsentRequired`, and `checkReportRateLimit` were placed in `blocks.go` for better code organization while remaining in the `hub` package.

### No structural deviations

All other implementation matches the plan exactly. No new dependencies introduced — only `crypto/rand`, `encoding/base32`, `net/smtp`, `net/http`, `encoding/json` from stdlib used.

## Threat Coverage

| Threat ID | Mitigation | Status |
|-----------|-----------|--------|
| T-05-E2 | `isBlockedBetween()` called on every offer relay (server-side hard gate) | Implemented |
| T-05-E3 | `isConsentRequired()` called on every offer relay (server-side hard gate) | Implemented |
| T-05-S1 | 128-bit `crypto/rand` tokens, single-use (consent_token NULLed), 7-day TTL | Implemented |
| T-05-D1 | `checkReportRateLimit()` enforces 5/24h before INSERT | Implemented |
| T-05-SC | No new packages — stdlib only | Verified |

## Self-Check: PASSED

Files verified present:
- signaling-server/internal/hub/blocks.go — FOUND
- signaling-server/internal/hub/consent.go — FOUND
- signaling-server/internal/hub/hub.go (contains isBlockedBetween call) — FOUND

Commits verified:
- 368a312 — FOUND (test RED phase)
- cc9cb68 — FOUND (feat GREEN phase)

`go test ./...` — PASSED (14 tests)
