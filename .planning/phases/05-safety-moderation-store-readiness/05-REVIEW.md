---
phase: 05-safety-moderation-store-readiness
reviewed: 2026-05-30T00:00:00Z
depth: standard
files_reviewed: 33
files_reviewed_list:
  - supabase/migrations/004_blocks.sql
  - supabase/migrations/005_reports.sql
  - supabase/migrations/006_parental_consents.sql
  - supabase/migrations/007_username_change_log.sql
  - supabase/migrations/008_profiles_safety_columns.sql
  - signaling-server/internal/hub/blocks.go
  - signaling-server/internal/hub/consent.go
  - signaling-server/internal/hub/hub.go
  - signaling-server/internal/hub/hub_test.go
  - src/autoload/friends_client.gd
  - src/autoload/network_manager.gd
  - src/autoload/username_policy.gd
  - src/autoload/world_save.gd
  - src/networking/profanity_filter.gd
  - src/ui/sign_in_panel.gd
  - src/ui/parental_gate_panel.gd
  - src/ui/restricted_account_banner.gd
  - src/ui/block_modal.gd
  - src/ui/report_modal.gd
  - src/ui/context_menu.gd
  - src/ui/legal_viewer.gd
  - src/ui/eula_acknowledge_modal.gd
  - src/ui/settings_menu.gd
  - src/ui/friends_panel.gd
  - src/ui/chat_overlay.gd
  - src/world/remote_builder_nameplate.gd
  - docs/EULA.md
  - docs/PRIVACY.md
  - docs/store-readiness/privacy-nutrition.json
  - tests/unit/test_block_unblock.gd
  - tests/unit/test_report_submission.gd
  - tests/unit/test_dob_parser.gd
  - tests/unit/test_parental_consent_token.gd
  - tests/unit/test_eula_hash_recompute.gd
  - tests/integration/test_blocks_check_on_join.gd
  - tests/integration/test_parental_consent_e2e.gd
findings:
  critical: 7
  warning: 9
  info: 4
  total: 20
status: issues_found
---

# Phase 5: Code Review Report

**Reviewed:** 2026-05-30
**Depth:** standard
**Files Reviewed:** 33 (plus note: `src/ui/restricted_account_banner.gd` did not exist on disk; `src/world/remote_builder_nameplate.gd`, `docs/EULA.md`, `docs/PRIVACY.md`, `docs/store-readiness/privacy-nutrition.json` were not present on disk — listed in scope but absent from repo)
**Status:** issues_found

## Summary

Phase 5 delivers the full safety, moderation, and store-readiness feature set: blocks/reports/parental-consent DB migrations, Go signaling-server enforcement hooks, GDScript client UI (block modal, report modal, parental gate, EULA viewer), and a suite of GUT unit/integration tests.

Overall the architecture is sound: RLS policies correctly use the `(SELECT auth.uid())` wrapper, CSPRNG is used for consent tokens, raw DOB is never serialised to HTTP, and the server-side Go relay is the hard gate for blocks and consent. However, seven correctness/security issues were found that must be fixed before shipping.

---

## Critical Issues

### CR-01: Invalid date accepted as valid DOB — under-13 check bypassed for epoch-0 births

**File:** `src/ui/sign_in_panel.gd:615`
**Issue:** `Time.get_unix_time_from_datetime_dict()` returns `0` (not a negative number) for impossible calendar dates such as February 31 in Godot 4.6 (this is documented in `test_dob_parser.gd:103-108`). The guard `if birth_unix < 0.0` therefore accepts an invalid date as valid and proceeds to compute `is_under_13`. For the concrete attack: entering year=1970, month=1, day=1 returns unix=0, which is also `< 0.0` false, and `today_unix - 0 = today_unix` which is far greater than `THIRTEEN_YEARS_SECONDS`, so the person is classified as an adult. However, entering Feb 31 of any year returns 0; `today_unix - 0` is a large positive number that classifies the submitter as an adult regardless of their actual age. A malicious under-13 user can enter an impossible date to bypass the COPPA age gate.

**Fix:** Change the guard from `< 0.0` to `<= 0.0`:
```gdscript
# sign_in_panel.gd line 615
if birth_unix <= 0.0:
    _show_error(tr("ui.signin.error_dob_invalid"))
    return
```
The test file already documents this as a known deferred issue (`test_dob_parser.gd:103`) — it must be fixed before store submission.

---

### CR-02: Email injection via MIME headers in SMTP consent email

**File:** `signaling-server/internal/hub/consent.go:443-474`
**Issue:** The `sendConsentEmail` function constructs a raw MIME message using `strings.Builder` and injects `body.ParentEmail` directly into the `To:` header at line 444 (`msg.WriteString("To: " + to + "\r\n")`). The `to` parameter is the `parent_email` string taken from the request body. If it contains `\r\n` sequences (CRLF), an attacker can inject additional headers or body parts into the email (header injection / SMTP injection). For example, `parent@example.com\r\nBcc: victim@example.com` would send the consent email silently to a third party.

There is no sanitisation of the email value before it is placed into the MIME header. The `_is_valid_email` check in `parental_gate_panel.gd` only runs client-side (containss `@` and `.`) and is trivially bypassed by a modified client; the Go server has no equivalent check before writing the header.

**Fix:** Validate the email on the server side and reject any value containing CR, LF, or null bytes before using it in a MIME header:
```go
// In HandleRequest, after decoding body:
if strings.ContainsAny(body.ParentEmail, "\r\n\x00") {
    http.Error(w, `{"error":"invalid_parent_email"}`, http.StatusBadRequest)
    return
}
// Also validate basic format:
if !strings.Contains(body.ParentEmail, "@") || len(body.ParentEmail) > 254 {
    http.Error(w, `{"error":"invalid_parent_email"}`, http.StatusBadRequest)
    return
}
```

---

### CR-03: `reporter_uid` and `reported_uid` have ON DELETE SET NULL — referential integrity broken for immutable audit trail

**File:** `supabase/migrations/005_reports.sql:14-15`
**Issue:** Both `reporter_uid` and `reported_uid` use `ON DELETE SET NULL`. This means that deleting the auth.users row for a reporter or a reported user silently NULLs those columns in the reports table. The comment on line 4 states "immutable audit trail" as the design goal, but the foreign key action undermines immutability: a user can arrange to have their account deleted (or an operator can delete it) and their UID disappears from any reports they filed or that were filed against them. Additionally, the RLS INSERT policy `WITH CHECK ((SELECT auth.uid()) = reporter_uid)` will reject INSERTs where reporter_uid is NULL, but the schema allows NULL via the FK action rather than declaring the column NOT NULL when the row is created.

The `reporter_uid` column is declared `NOT NULL` at creation but the FK action can later set it to NULL, creating a NOT NULL violation that Postgres actually does permit when triggered by a FK cascade/set action. Wait — actually `ON DELETE SET NULL` on a `NOT NULL` column is a Postgres error at DDL time. Let me re-examine: the columns are declared `NOT NULL` on lines 13-14. Postgres will reject `ON DELETE SET NULL` on a `NOT NULL` column at migration time. This migration will **fail to apply**.

**Fix:** Decide on the correct semantics. For an immutable audit trail, use `ON DELETE RESTRICT` so that reporter/reported accounts cannot be deleted while reports reference them, or use `ON DELETE SET NULL` and remove `NOT NULL` from the columns (accepting that old reports lose their UIDs). The current combination of `NOT NULL` + `ON DELETE SET NULL` is a migration-time DDL error in Postgres:
```sql
-- Option A: immutable audit trail (preferred)
reporter_uid UUID NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
reported_uid UUID NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
-- Option B: accept nullable UIDs after deletion
reporter_uid UUID REFERENCES auth.users(id) ON DELETE SET NULL,
reported_uid UUID REFERENCES auth.users(id) ON DELETE SET NULL,
```

---

### CR-04: Race condition in `handleRelay` — peer count incremented without session lock; 5th peer can join

**File:** `signaling-server/internal/hub/hub.go:274-310`
**Issue:** `handleRelay` reads `s.PeerCount` and compares it to `s.MaxPeers` without holding the session registry lock. `IncrementPeerCount` is a separate call at line 310. Between the check and the increment, two concurrent goroutines handling two simultaneous "offer" messages from two different peers to the same session can both read `PeerCount = 3` (< 4), both pass the check, and both call `IncrementPeerCount`, resulting in `PeerCount = 5` and a 5-peer session despite the 4-peer enforcement.

The `SessionRegistry` likely has internal locking (not shown in hub.go, but referenced via `h.sessions.Get()`/`h.sessions.IncrementPeerCount()`), however `Get` and `IncrementPeerCount` are two separate lock acquisitions. The check-then-act is non-atomic.

**Fix:** Add a `TryIncrementPeerCount(sessionID string, maxPeers int) bool` method to `SessionRegistry` that performs the check and increment atomically under a single lock:
```go
// In SessionRegistry:
func (r *SessionRegistry) TryIncrementPeerCount(id string, maxPeers int) bool {
    r.mu.Lock()
    defer r.mu.Unlock()
    s, ok := r.sessions[id]
    if !ok || s.PeerCount >= maxPeers {
        return false
    }
    s.PeerCount++
    return true
}
```

---

### CR-05: `isConsentRequired` does not check `consented_at` expiry — revoked consent after re-consent is not detected

**File:** `signaling-server/internal/hub/blocks.go:113`
**Issue:** The consent check logic at line 113 is:
```go
if row.ConsentedAt == nil || (row.RevokedAt != nil && *row.RevokedAt != "") {
    return true, nil
}
```
This correctly handles: (a) never consented, (b) consent revoked. However, it does not handle the case where `consented_at` was set, then `revoked_at` was set, then the parent re-consented (a new `consented_at` was written, but `revoked_at` is still non-null in the DB). The Go server's `HandleConfirm` clears the `consent_token` but does not clear `revoked_at` when re-consenting. Once `revoked_at` is set, `isConsentRequired` will forever return `true` even if the parent later re-confirms, because the `RevokedAt != nil` branch takes precedence over `ConsentedAt != nil`.

**Fix:** In `isConsentRequired`, check that `RevokedAt` is after `ConsentedAt`, not just non-nil:
```go
row := rows[0]
if row.ConsentedAt == nil {
    return true, nil // Never consented
}
if row.RevokedAt != nil && *row.RevokedAt != "" {
    // Only revoked if revoke happened after the last consent
    // (simple approach: clear revoked_at on re-consent in HandleConfirm)
    return true, nil
}
return false, nil
```
And in `HandleConfirm`, clear `revoked_at` when re-consenting:
```go
patchBody := map[string]interface{}{
    "consented_at":  now,
    "consent_token": nil,
    "revoked_at":    nil, // clear revocation on re-consent
}
```

---

### CR-06: `block_modal.gd` emits `user_blocked` signal before server confirms — race with FriendsClient response

**File:** `src/ui/block_modal.gd:193`
**Issue:** `_on_block_pressed` calls `fc.call("block_user", _target_uid)` (which fires an async HTTP POST to Supabase) and then immediately emits `user_blocked.emit(_target_uid)` on line 193 before the HTTP call completes. The modal also closes and re-enables the button at lines 195-196. If the HTTP POST fails (network error, RLS rejection), the signal has already been emitted and subscribers (e.g. `FriendsPanel`) will have updated their local state as if the block succeeded. The server-side block does not actually exist, but the UI shows the user as blocked.

Additionally, since `_block_btn.disabled = false` is set at line 196 (before the async `_on_fc_user_blocked` callback), a fast user can tap Block again, submitting a duplicate request.

**Fix:** Emit `user_blocked` only in `_on_fc_user_blocked` (the success callback), not before:
```gdscript
func _on_block_pressed() -> void:
    _block_btn.disabled = true
    var fc: Node = get_node_or_null("/root/FriendsClient")
    if fc != null and fc.has_method("block_user"):
        fc.call("block_user", _target_uid)
        if fc.has_signal("user_blocked"):
            if not fc.user_blocked.is_connected(_on_fc_user_blocked):
                fc.user_blocked.connect(_on_fc_user_blocked, CONNECT_ONE_SHOT)
    visible = false
    # Do NOT emit user_blocked or re-enable button here — wait for server confirmation.

func _on_fc_user_blocked(uid: String) -> void:
    user_blocked.emit(uid)
    _block_btn.disabled = false
    if is_instance_valid(Toasts):
        Toasts.show("ui.block.toast_blocked", "error")
```

---

### CR-07: `fetchConsentRow` passes token directly into URL without URL encoding

**File:** `signaling-server/internal/hub/consent.go:330`
**Issue:** In `fetchConsentRow`, the token is placed directly into the endpoint URL without encoding:
```go
endpoint := fmt.Sprintf(
    "%s/rest/v1/parental_consents?%s=eq.%s&select=...",
    ch.hub.cfg.SupabaseURL,
    tokenField,  // injected without validation
    token,       // injected without url.QueryEscape
)
```
The comment on line 330 says "token is base32 — no special URL chars" which is true for the standard base32 alphabet `A-Z2-7`. However, the `consent.go` server uses the `base32.StdEncoding` which produces uppercase A-Z and 2-7, which are URL-safe. The client-side GDScript uses a lowercase alphabet (`abcdefghijklmnopqrstuvwxyz234567`). If tokens from the GDScript client are passed through an intermediary or stored differently (e.g., case-normalisation by the email client), a case-variant token could be presented to the confirm endpoint. More critically, the `tokenField` parameter is caller-controlled (passed as either `"consent_token"` or `"revoke_token"`). While the two callers only ever pass those two known strings, this is a latent injection surface. If a bug introduced a third caller with attacker-influenced `tokenField`, this becomes a URL injection.

Additionally, passing `token` without `url.QueryEscape` is technically incorrect even if base32 is safe, because URL semantics say query values should be percent-encoded. If the Supabase URL or proxy ever normalises the query string, unexpected behaviour could result.

**Fix:**
```go
endpoint := fmt.Sprintf(
    "%s/rest/v1/parental_consents?%s=eq.%s&select=child_uid,requested_at,consented_at,revoked_at&limit=1",
    ch.hub.cfg.SupabaseURL,
    url.QueryEscape(tokenField),
    url.QueryEscape(token),
)
```

---

## Warnings

### WR-01: `parseInt` in `hub.go` overflows silently on large `page` or `limit` values

**File:** `signaling-server/internal/hub/hub.go:411-419`
**Issue:** The custom `parseInt` function accumulates digits with `n = n*10 + int(c-'0')` without any overflow check. A query parameter of `page=99999999999999999999` will silently overflow `int` (which is 64-bit on amd64 but 32-bit on 32-bit ARM), producing a garbage negative offset sent to Supabase. On 32-bit builds the overflow happens much sooner (11 digits). Use `strconv.Atoi` which returns an error on overflow.

**Fix:**
```go
import "strconv"

func parseInt(s string) (int, error) {
    return strconv.Atoi(s)
}
```

---

### WR-02: `check_username_reserved` trigger echoes the matched reserved prefix in the exception message

**File:** `supabase/migrations/008_profiles_safety_columns.sql:33`
**Issue:** The trigger raises `RAISE EXCEPTION 'Username matches reserved pattern: %', r` which includes the matched reserved word in the exception message. PostgREST forwards this message to the HTTP response body (as the `message` field in a 422 response). The client-side `_on_username_completed` in `friends_client.gd` inspects this message for `"reserved"` substring to choose the `username_change_failed("reserved")` signal. However, surfacing the specific matched prefix ("admin", "mod", etc.) leaks the exact reserved word list to any client that can read HTTP responses. Per the anti-pattern noted in 05-UI-SPEC.md Surface G: callers should show a generic rejection without echoing what was matched.

**Fix:** Remove the matched word from the exception message:
```sql
RAISE EXCEPTION 'Username is reserved'
    USING ERRCODE = 'check_violation';
```

---

### WR-03: `consent.go` SMTP `sendConsentEmail` sends with static MIME boundary — predictable boundary allows MIME injection via child username

**File:** `signaling-server/internal/hub/consent.go:441`
**Issue:** The MIME boundary `boundary := "cubicraftia-consent-20260101"` is hardcoded and static. The `child_username` from the request body is injected into both the plain-text and HTML email parts via `strings.NewReplacer`. If an attacker can register a username that contains the exact boundary string (`cubicraftia-consent-20260101`), they can inject a premature boundary into the email body, effectively terminating one MIME part early and injecting arbitrary MIME content. The `check_username_reserved` trigger and `UsernamePol.validate()` do not block this string because it starts with `cubicraftia` which is a reserved prefix — so this specific payload is actually blocked. However, a generic username containing arbitrary MIME-structure text could still confuse email clients.

A truly safe approach uses a randomly generated boundary per message.

**Fix:**
```go
import (
    "fmt"
    "math/rand"
)

boundary := fmt.Sprintf("cubicraftia-%x", rand.Int63())
```

---

### WR-04: `_on_invite_completed` uses `_pending_action` (shared with auth requests) for invite actions — clobber risk

**File:** `src/autoload/friends_client.gd:966-990`
**Issue:** `_on_invite_completed` reads `_pending_action` on line 967, which is the same variable used by `_on_auth_completed` (signin, signup, refresh, get_user, signout). The `create_invite` method sets `_pending_action = "create_invite:" + token` (line 527) and `redeem_invite` sets `_pending_action = "redeem_invite"` (line 541). If an auth request and an invite request overlap in flight (e.g., the token refresh timer fires while an invite creation is pending), the `_pending_action` set by the auth request will overwrite the invite action string, and `_on_invite_completed` will see the wrong action.

The separate `_invite_req` HTTPRequest node prevents concurrent HTTP calls on the same node, but `_pending_action` is shared across both. `_on_auth_completed` clears `_pending_action` at line 878 regardless of which action it was.

**Fix:** Use a dedicated `_invite_pending_action` variable (similar to `_friends_pending_action`, `_block_pending_action`), setting it in `create_invite` and `redeem_invite`, reading it in `_on_invite_completed`.

---

### WR-05: `report_modal.gd` does not call `NetworkManager.mute_session_uid()` — auto-mute path broken

**File:** `src/ui/report_modal.gd:411, 433-444`
**Issue:** `_auto_mute_reported_user()` attempts to mute via `ChatOverlay.mute_by_uid()` only. It does not call `NetworkManager.mute_session_uid(_target_uid)`. The comment in `network_manager.gd:1128-1130` explicitly states: "the UI layer calls `mute_session_uid()` with the UID." `NetworkManager._deliver_chat()` checks `_session_muted` (which is populated only via `mute_session_uid()`). Without that call, incoming chat from the reported user is filtered in `chat_overlay.gd`'s `_muted_uids` dict but NOT in `NetworkManager._deliver_chat()`. Since `_deliver_chat` is called before the signal reaches `ChatOverlay`, relying solely on `ChatOverlay.mute_by_uid` is fragile — it only works if `ChatOverlay` is in the scene tree and `mute_by_uid` is called before the next message arrives.

**Fix:** Add `NetworkManager.mute_session_uid()` call in `_auto_mute_reported_user()`:
```gdscript
func _auto_mute_reported_user() -> void:
    if _target_uid.is_empty():
        return
    # Mute in NetworkManager (filters at RPC delivery layer).
    var nm: Node = get_node_or_null("/root/NetworkManager")
    if nm != null and nm.has_method("mute_session_uid"):
        nm.call("mute_session_uid", _target_uid)
    # Also mute in ChatOverlay for the display layer.
    ...
```

---

### WR-06: `HandleAdminReports` re-implements admin authentication instead of using `RequireAdminSecret` middleware

**File:** `signaling-server/internal/hub/hub.go:332-338` and `396-408`
**Issue:** `HandleAdminReports` manually checks `h.cfg.AdminSecret` at lines 332-338. The `RequireAdminSecret` middleware at lines 396-408 implements the same logic. Having two copies of the same auth check means a future change to the admin auth logic must be made in two places. If `HandleAdminReports` is ever updated without updating `RequireAdminSecret` (or vice versa), the auth semantics diverge silently.

**Fix:** Wrap the handler registration with the middleware instead of duplicating the check:
```go
// In main/router setup:
mux.HandleFunc("/admin/reports", hub.RequireAdminSecret(hub.HandleAdminReports))

// Remove the duplicate auth check from HandleAdminReports.
```

---

### WR-07: `EULA hash uses only first 16 hex characters — collision space is 64 bits, not 256 bits

**File:** `src/autoload/friends_client.gd:697-703` and `src/ui/legal_viewer.gd:377-379`
**Issue:** Both `check_eula_acknowledgement()` and `_compute_hash()` truncate the SHA-256 hash to its first 16 hex characters (64 bits). The EULA hash is stored in `user://settings.cfg` and compared to detect version changes. At 64 bits the truncated hash still has a theoretical collision probability of ~1/2^64 between any two different EULA versions, which is acceptable for version detection. However, the code's comment says "sufficient for version detection" without acknowledging a concrete risk: a malicious EULA file whose first 64 bits of SHA-256 match the previous EULA could be deployed without triggering re-acknowledgement. While this threat is low for an in-app document, the store review teams (Apple, Google) may flag the truncation as insufficient. Using the full hash has no performance cost.

**Fix:** Compare the full 256-bit hash:
```gdscript
# Replace 0, 16 with 0, 64 (full SHA-256 = 64 hex chars)
var bundled_short: String = hex_hash  # no .substr()
```

---

### WR-08: `sign_in_panel.gd` — username validation bypassed on "Sign in" tab via tab-switch race

**File:** `src/ui/sign_in_panel.gd:416-432`
**Issue:** When the user switches from "Create account" tab back to "Sign in" tab, `_on_tab_pressed("signin")` sets `_username_valid = false` and `_submit_button.disabled = false`. If the user had previously typed a valid username (setting `_username_valid = true`) and then switches to "Sign in" tab, the button is re-enabled. That alone is correct. However, if the user switches tab with a pending debounce timer still running, the timer fires after the tab switch and calls `_validate_username_inline()`, which checks `if _active_tab == "create" and _submit_button != null: _submit_button.disabled = true/false`. The `_active_tab == "create"` guard is correct. But if the timer fires before `_active_tab` is updated (unlikely but possible within a single frame), it could re-disable the submit button for the signin tab.

The more concrete issue: `_username_validation_timer.start()` is not stopped in `_on_tab_pressed("signin")`. The timer should be stopped when switching to the signin tab to avoid any late-firing validation that toggles button state on the wrong tab.

**Fix:**
```gdscript
# In _on_tab_pressed when tab == "signin":
if _username_validation_timer != null:
    _username_validation_timer.stop()
```

---

### WR-09: `consent.go` SMTP sends without TLS if `cfg.SMTPUser` is empty — credentials still sent in plaintext if a relay requires auth

**File:** `signaling-server/internal/hub/consent.go:469-474`
**Issue:** `smtp.SendMail(addr, auth, ...)` uses `net/smtp` which upgrades to TLS via STARTTLS only if the server advertises it. If `cfg.SMTPUser == ""`, `auth` is set to `nil`, and `smtp.SendMail` will connect over plaintext if STARTTLS is not advertised. The parent's email address and the consent links are transmitted in the clear. For a COPPA-sensitive flow (parental email and child consent URL), this is a data-handling concern.

**Fix:** Require TLS by using `smtp.Dial` + `client.StartTLS` explicitly, or use a well-typed SMTP library (`gopkg.in/gomail.v2` or similar) that enforces TLS. At minimum, document in the deployment guide that the SMTP server must support STARTTLS, and add a config validation that rejects a plain-TCP SMTP host.

---

## Info

### IN-01: `delete_friendship` sets `_friends_pending_action = "delete"` but `create_friendship` does not set it

**File:** `src/autoload/friends_client.gd:484, 453-476`
**Issue:** `delete_friendship` sets `_friends_pending_action = "delete"` before the request. `create_friendship` does not set `_friends_pending_action` at all (it remains at its previous value). If `_friends_pending_action` happens to be `"delete"` from a previous delete call when a create response arrives, `_on_friends_completed` will fire `friendship_deleted.emit()` instead of handling the create response. In normal usage these are sequential, but it is a fragile implicit assumption.

**Fix:** Set `_friends_pending_action = "create"` in `create_friendship` and handle it in `_on_friends_completed`.

---

### IN-02: `can_change_username` function lacks `SEARCH_PATH` protection (SECURITY DEFINER without fixed search_path)

**File:** `supabase/migrations/007_username_change_log.sql:28-47`
**Issue:** The `SECURITY DEFINER` function `can_change_username` does not set `SET search_path = public, pg_temp`. A superuser or attacker who can create objects in a schema earlier in the search path could shadow the `username_change_log` table. This is a standard Postgres security hardening recommendation for `SECURITY DEFINER` functions.

**Fix:**
```sql
CREATE OR REPLACE FUNCTION public.can_change_username(user_uid UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$ ...
```
Same fix applies to `enforce_username_change_cooldown` in migration 008.

---

### IN-03: `_generate_invite_token` in `friends_client.gd` produces 25 characters, not 26 — constant `INVITE_TOKEN_LENGTH = 26` is wrong

**File:** `src/autoload/friends_client.gd:1199-1211` and line 48
**Issue:** The base32 encoding algorithm in `_generate_invite_token` processes 16 bytes (128 bits) into 5-bit groups. 128 / 5 = 25.6, which means 25 complete 5-bit groups and 3 leftover bits (not output because `while bit_count >= 5`). The result is a 25-character token. The constant `INVITE_TOKEN_LENGTH = 26` and the comment "128-bit entropy in base32" are both inaccurate. The test file `test_parental_consent_token.gd:64` documents this discrepancy explicitly.

This does not cause a runtime error but is misleading. The Go server's `generateToken` also produces 25 or 26 characters depending on encoding (standard base32 of 16 bytes with no padding is 26 characters when using the Go implementation, because `base32.StdEncoding.WithPadding(base32.NoPadding).EncodeToString` produces `ceil(128/5) = 26` characters). The two implementations are inconsistent: Go produces 26 chars, GDScript produces 25.

**Fix:** For invite tokens generated client-side, use 17 bytes to get exactly 27 characters (or 20 bytes to get exactly 32), or simply align the constant to match actual output (25). For the Go consent tokens, the mismatch with client is irrelevant (they are never compared), but document it.

---

### IN-04: `report_modal.gd` placeholder text not using `tr()` — i18n violation

**File:** `src/ui/report_modal.gd:244`
**Issue:** `_reason_edit.placeholder_text = "Describe what happened…"` is a hardcoded English string, not wrapped in `tr()`. All other UI strings in this file use `tr()`. This string will not be localised for non-English locales.

**Fix:**
```gdscript
_reason_edit.placeholder_text = tr("ui.report.reason_placeholder")
```
Note: the heading label on line 205 reuses the same `tr("ui.report.reason_placeholder")` key for a heading, which is semantically wrong — the heading and the placeholder should be different keys. Add `ui.report.reason_placeholder_hint` or similar for the TextEdit placeholder.

---

_Reviewed: 2026-05-30_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
