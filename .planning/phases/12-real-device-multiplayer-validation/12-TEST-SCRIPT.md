# Phase 12: Real-Device Multiplayer Validation — Test Script

Hands-on two-device procedure against the **live** backend (m1). Discharges the 6 deferred v1.0
WebRTC tests (NETVAL-01..05), the Phase 13 in-viewport human-verify checkpoint, and the DEPLOY-07
smoke. Requires real hardware; cannot be run headless.

## ⚠ Known gap to resolve first (or expect NETVAL-02 to fail)

**Ephemeral TURN credentials are not wired end-to-end.** The signaling server has
`GenerateTURNCredentials()` (session.go, HMAC-SHA1, matches coturn `use-auth-secret`) but **never
calls it or sends creds to the client**, and the client handles no `turn_credentials` message — it
uses empty static `_turn_user`/`_turn_credential`. So coturn will reject relay allocations and
**TURN fallback (NETVAL-02, symmetric-NAT/CGNAT peers) will not work** until this is closed.

Direct P2P, sign-in, friends, Supabase, and the STUN path are unaffected.

Fix options (pick one before NETVAL-02):
- **(recommended) Wire ephemeral creds:** server calls `GenerateTURNCredentials(sessionID, TURN_SHARED_SECRET, 3600)` on join and sends `{"type":"turn_credentials","username":..,"credential":..}`; client handles it in `_on_signaling_message` -> sets `_turn_user`/`_turn_credential` and refreshes the ICE config. Small, testable; re-issue on failover/reconnect.
- **(stopgap) Static long-term cred:** switch coturn to `lt-cred-mech` + a fixed `user=cubi:<pw>`, set `network/turn_user.release`/`network/turn_credential.release` to match. Simpler, less secure (shared fixed cred embedded in client). Fine at 2-4-friend scale.

## Prerequisites

- **2 real devices** (e.g. a laptop + a phone, or two laptops), each a **release** build so the
  `.release` ProjectSettings apply (dev/editor still points at localhost). Export release:
  `Project > Export > <platform> > Export Project` (NOT "Export with Debug").
- **2 physically distinct networks.** The important combination for NETVAL-02 is **both peers on
  cellular / behind CGNAT** (same-LAN hides the symmetric-NAT bugs that matter). Home broadband +
  phone-on-cellular is the minimum honest test.
- Two accounts (or sign up two fresh ones). For frictionless testing, confirm Supabase auth
  autoconfirms email (`ENABLE_EMAIL_AUTOCONFIRM=true` in `/opt/cubicraftia/supabase/docker/.env`)
  or have SMTP wired; otherwise the confirmation email must be handled.

## Backend observation (run on m1 in a side terminal during tests)

```
# signaling
sudo journalctl -u cubicraftia-signaling -f
# coturn (allocations / auth)
sudo journalctl -u coturn -f
# supabase auth / rest
cd /opt/cubicraftia/supabase/docker && docker compose logs -f auth rest kong
```

## DEPLOY-07 smoke (do first)

1. Launch a release build. In its log/console confirm it connects to **`wss://signal.cubicraftia.com/ws`**
   and **`https://supabase.cubicraftia.com`** (not localhost). If it still shows localhost, the
   `.release` overrides didn't apply -> you built a debug export, not release.
2. Sign up / sign in succeeds -> Supabase auth reachable over TLS. Watch the m1 `auth` log for the token request.

## Tests

### NETVAL-01 — join over the internet (table stakes)
- Device A signs in, hosts a session. Device B signs in, befriends A, joins A's session.
- PASS: B lands in A's world over the internet; both see each other's nameplate.
- Watch: signaling log shows both peers register + exchange offer/answer/candidate.

### NETVAL-02 — direct P2P + TURN relay fallback  (gated on the TURN fix above)
- Same-network first: expect **direct** (badge shows Direct). 
- Then both peers on **cellular/CGNAT**: expect fallback to **relay** (badge shows Relay), session still works.
- PASS: connects in both; coturn log shows an allocation for the relay case.
- If the TURN gap is unfixed: relay case FAILS (coturn rejects; badge never reaches Relay).

### NETVAL-03 — host failover <= 4s, no world loss
- 2-4 peers in a session. Kill the host (force-quit device A).
- PASS: a new host is elected and the session continues within ~4s; placed bricks / world state intact; no manual reconnect.

### NETVAL-04 — relay badge, nameplates, freeze UI under real conditions (also Phase 13 in-viewport)
- Relay badge honestly shows Direct vs Relay matching the actual path (cross-check coturn log).
- Nameplates update live as peers join/reconnect.
- Freeze UI (host build-freeze on a peer) renders correctly.

### NETVAL-05 — desktop <-> mobile crossplay
- Host on desktop, join from mobile (or vice-versa). One live cross-platform session.
- PASS: both platforms interact in the same world.

## Phase 13 in-viewport checkpoint (13-07 human-verify)

Confirm on a real running build (these can't be checked headless):
1. **Connection-problem overlay** shows the correct reason for each: kill the session (`ended`),
   fill it to 4 then join (`full`), use a stale invite (`expired`), join while blocked (`blocked`),
   two builds with different `PROTOCOL_VERSION` (`version_mismatch`), force a relay failure
   (`relay_failed`), pull the network mid-connect (`timeout`).
2. **Connecting spinner** animates (not frozen) and resolves to success or a clear failure within the timeout.
3. **Direct/Relay badge** renders in the HUD and is honest.
4. **Version-mismatch reject:** build two clients with different `BuildInfo.PROTOCOL_VERSION`; the
   mismatched peer is cleanly rejected (overlay `version_mismatch`), never connect-and-desync, and
   is excluded as a failover candidate.
5. Escape / clicking the scrim does NOT dismiss the modal (it is blocking).

## On pass

Record results in `.planning/phases/12-real-device-multiplayer-validation/12-UAT.md`, mark
NETVAL-01..05 complete in REQUIREMENTS.md, flip Phase 13's VERIFICATION `human_needed` -> `passed`
(the in-viewport checkpoint is discharged here), and DEPLOY-07 complete. That closes the entire
"go-live multiplayer" track (Phases 11 + 12 + 13).
