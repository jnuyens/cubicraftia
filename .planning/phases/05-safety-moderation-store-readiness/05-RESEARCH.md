---
phase: 5
slug: safety-moderation-store-readiness
created: 2026-05-29
domain: Safety systems, Supabase schema, Go signaling extensions, store compliance, COPPA/GDPR-K, Godot in-app legal renderer
confidence: HIGH
---

# Phase 5: Safety, Moderation & Store Readiness — Research

**Researched:** 2026-05-29
**Domain:** UGC safety (block/report), profanity filtering, parental consent (COPPA/GDPR-K), EULA/privacy rendering in Godot, App Store/Play Store compliance, Supabase schema extensions, Go signaling hardening
**Confidence:** HIGH

---

## Summary

Phase 5 is the safety and store-clearance phase. The core technical work is entirely additive — four new Supabase tables, three new Go signaling endpoints, profanity filter hardening from a stub to production word lists, an in-app legal document renderer, a parental consent email flow, and a batch of store metadata documents. No Phase 4 autoloads are substantially rewritten; all are extended at defined extension points already built into Phase 4.

The biggest risk in this phase is not technical — it is policy compliance. COPPA was amended in June 2025 (first FTC rulemaking since 2013). The email-plus consent method remains valid under the updated rule for low-risk services without third-party data disclosure (which Cubicraftia matches). App Store guideline 1.2 on UGC requires automated content filtering, a user block mechanism, and rapid content removal — all of which the Phase 5 plan delivers. A human legal review of the parental consent implementation is explicitly flagged as a `checkpoint:human-verify` item (see Open Questions Q2).

The LDNOOBW word list's license is **Creative Commons Attribution 4.0** (CC-BY-4.0), not MIT as originally noted in the CONTEXT.md. CC-BY-4.0 is compatible with Cubicraftia's GPL-3.0-or-later distribution when the attribution requirement is satisfied (credit in `assets/profanity/README.md` and in-app About screen). No restriction on bundling in a GPL binary.

**Primary recommendation:** Implement in this wave order: (1) Supabase migrations + Go signaling extensions, (2) profanity filter hardening + `filter_reject()`, (3) parental consent flow, (4) EULA/privacy renderer, (5) store metadata docs + iOS CI. This order ensures the server-side safety gates are live before any client UI that depends on them.

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Area 1 — Block + Report Architecture**
- `blocks(blocker_uid UUID, blocked_uid UUID, created_at TIMESTAMPTZ)` — direction matters; PK on `(blocker_uid, blocked_uid)`. No `reason` column in v1 (the CONTEXT.md tables the `reason TEXT` column from the original task spec — do not add it).
- Mutual enforcement is logical, not stored: Go signaling queries both directions before admitting a join.
- RLS: blocker can SELECT/INSERT/DELETE their own rows; blocked_uid cannot see rows where they are the target.
- Block cascades to: friend-search, session join, invite redemption, nameplate visibility.
- `friendships` row NOT deleted on block — block overrides it logically.
- `reports(id UUID PK, reporter_uid UUID, reported_uid UUID, surface TEXT, category TEXT, reason TEXT, evidence JSONB, session_id TEXT, created_at TIMESTAMPTZ)` — reporter INSERT/SELECT own; `reported_uid` cannot see; no UPDATE or DELETE (immutable).
- `surface`: `'player' | 'build' | 'chat_message'`; `category`: `'harassment' | 'spam' | 'cheating' | 'csam' | 'other'`
- Go signaling: `GET /admin/reports` (operator-authenticated). No auto-action in v1.
- Three report surfaces: player nameplate/friends list, long-press build, long-press chat message.

**Area 2 — Profanity Filter Hardening**
- Phase 4 stub `profanity_filter.gd` already has `set_word_list()` extension point.
- Replace stub with curated lists from `assets/profanity/wordlist_en.txt` and `assets/profanity/wordlist_nl.txt`.
- Source: LDNOOBW (CC-BY-4.0) — curated, false-positives trimmed for gaming context.
- Target: 300–500 words per language.
- Chat → `[filtered]`; username/world name/avatar name → reject with "Please choose another name."
- New `ProfanityFilter.filter_reject(text) -> bool` static method.
- Coverage: chat (Phase 4), username at sign-up (new), world name at creation (new), avatar name at save (new — API delivered Phase 5, surface Phase 6).
- Remote update deferred to v1.x.

**Area 3 — Parental Consent Flow**
- Sign-up adds mandatory date-of-birth (day/month/year dropdowns). `is_under_13` boolean stored in GoTrue user metadata; raw DOB NOT stored.
- Under-13 restrictions before consent: cannot create invites, cannot join sessions, cannot use chat, cannot send/receive friend requests. Solo play unlimited.
- `parental_consents(child_uid UUID PK, parent_email TEXT NOT NULL, requested_at TIMESTAMPTZ DEFAULT NOW(), consented_at TIMESTAMPTZ, revoked_at TIMESTAMPTZ, consent_token TEXT UNIQUE NOT NULL, revoke_token TEXT UNIQUE NOT NULL)`.
- Token: random 128-bit base32, single-use, 7-day TTL.
- Go signaling: `POST /consent/request`, `GET /consent/confirm?token=`, `GET /consent/revoke?token=`.
- Revocation via `revoke_token` (no parent login required).
- RLS: child can SELECT own row; only Go server (service role) can write.

**Area 4 — EULA + Privacy Policy**
- Bundled markdown: `docs/EULA.md` and `docs/PRIVACY.md`.
- In-app viewer: Markdown subset (H1-H3, bold, italic, lists, inline links) rendered via GDScript → BBCode → RichTextLabel.
- SHA-256 hash of file content. Stored in `user://settings.cfg`. Modal on hash mismatch at next launch.
- Linked from title screen (small text links) and `Settings → About`.
- Decline = sign out, return to title; account intact.
- English only in v1, localised header: "The following legal text is provided in English only."

**Area 5 — Store Submission Checklist**
- `docs/store-readiness/` directory: app-store-metadata.md, play-store-metadata.md, privacy-nutrition.json, age-rating.md, accessibility-statement.md, screenshot-checklist.md, code-signing-runbook.md.
- iOS CI (Phase 1 D-04 deviation closure): iOS row added to `.github/workflows/ci.yml` in this phase.
- Age rating target: 12+ (App Store) / Everyone 10+ (Play Store) via IARC questionnaire.

**Area 6 — Username Gating**
- Username: 3–20 chars, `^[a-zA-Z0-9_]{3,20}$`, case-insensitive uniqueness.
- Reserved prefixes: `admin`, `mod`, `moderator`, `cubicraftia`, `support`, `staff`, `system`, `official`.
- New `src/autoload/username_policy.gd` — static methods only, no HTTP.
- `username_change_log(uid UUID, old_username TEXT, new_username TEXT, changed_at TIMESTAMPTZ)` — INSERT-only.
- Postgres function `can_change_username(uid)` checks 30-day cooldown; trigger on `profiles.username` update.
- Profiles table extended: add `is_under_13 BOOLEAN DEFAULT FALSE`, `eula_acknowledged_hash TEXT`, `eula_acknowledged_at TIMESTAMPTZ`.

### Claude's Discretion

- Exact Postgres trigger function body (plpgsql implementation details)
- Go signaling server: consent endpoint path naming, JSON payload field names, error code strings
- GDScript markdown-to-BBCode parser implementation detail (headings, bold, list conversion logic)
- FriendsClient HTTPRequest child node naming for new block/report endpoints
- GUT test fixture class name and method signatures in `tests/conftest_phase5.gd`
- `docs/store-readiness/` file formatting (Markdown structure, heading levels)

### Deferred (OUT OF SCOPE)
- Real-time moderation pipeline / auto-suspend after N reports
- ML / AI profanity detection (Aho-Corasick, transformer-based)
- Third-party identity providers (SIWA, Google, Discord) — stubs remain stubs
- Advertising IDs / analytics SDKs
- GDPR Right-to-Portability data export endpoint
- Username display name separation (single `username` field locked)
- Voice chat moderation (voice chat not in v1)
- Open-lobby content moderation (no open lobbies)
- Community moderation dashboard UI (raw JSON endpoint only)
- Multi-language profanity lists FR/ES/DE (contributable pattern exists, not required for v1)
- TOTP / hardware-key MFA
- Breach-check on sign-up passwords (HaveIBeenPwned)
- Dedicated server software packaging
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| DOC-08 | Full §8 implementation: block/report from three surfaces, profanity filter on all user-authored strings, parental consent flow for under-13, EULA + privacy policy linked and version-hashed, data-collection inventory published in privacy policy | Supabase schema, Go signaling extensions, profanity filter hardening, Godot EULA renderer, store metadata docs — all researched below |
</phase_requirements>

---

## Project Constraints (from CLAUDE.md)

- Engine: Godot 4.6, MIT license — locked
- Auth + friends backend: Supabase self-hosted (GoTrue + Postgres + RLS) — locked
- Signaling server: Go service (WebSocket, single binary) — locked
- Scripting: GDScript for gameplay; Rust GDExtension for hot paths — locked
- License: GPL-3.0-or-later — locked (CC-BY-4.0 word lists require attribution, which is compatible with GPL distribution)
- Autoloads: `extends Node`, single-file, registered in `project.godot`
- Tests: GUT in `tests/unit/` and `tests/integration/`; fixture class in `tests/conftest_phase5.gd`
- i18n: every UI string via `tr("ui.<surface>.<key>")` added to `locale/en.po`
- Player-facing terminology: brick / stud / builder — never "Lego"
- Renderer: `mobile` renderer enforced in `project.godot` (not Forward+)
- No Co-Authored-By lines in commits (global CLAUDE.md)

---

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Block enforcement (friend search, session join) | Go signaling server (hard gate) | Client `FriendsClient` (UI fast-hide) | Server must be the hard gate; client-side block is UI convenience only — a compromised client must not bypass block |
| Block data persistence | Supabase Postgres `blocks` table (RLS) | `FriendsClient` local cache | Relational persistence with row-level isolation; client caches for offline display |
| Report submission + storage | Supabase Postgres `reports` table (RLS) | Go signaling `/admin/reports` read endpoint | Reports are immutable audit trail — Postgres is the correct store; Go server exposes operator read access |
| Profanity filtering | Client `ProfanityFilter` (fast path) + Host re-check (defense in depth) | `WorldSave.create_world()` + username validation | Matches Phase 4 chat pattern; server-side Postgres trigger is the hard gate for username |
| Parental consent lifecycle | Go signaling server (unauthenticated consent endpoints, service-role Supabase writes) | `FriendsClient.request_parental_consent()` (initiates flow) | Parent has no Supabase account — Go server is the only non-authenticated actor that can write consent state via service role |
| Parental consent enforcement (session join, chat, invites) | Go signaling server (join check) + `NetworkManager` + `FriendsClient` (client gates) | — | Two layers: client prevents action before server even sees it; server rejects anyway for compromised clients |
| EULA hash storage and acknowledgement | Client `user://settings.cfg` (local) | Supabase `profiles.eula_acknowledged_hash` (server-side optional sync) | Hash is a local gate; Supabase column enables multi-device enforcement in future |
| Username reserved-prefix enforcement | Postgres trigger on `profiles.username` (hard gate) | `username_policy.gd` client-side (fast rejection) | Postgres is the hard gate; client validates for UX feedback speed |
| Username change cooldown | Postgres function `can_change_username(uid)` + `username_change_log` (hard gate) | `FriendsClient` client-side check before form display | Same two-layer pattern; Postgres is authoritative |
| Store metadata and code signing | Documentation only (`docs/store-readiness/`) | GitHub Actions CI (iOS row) | Store metadata is operator work, not runtime code; CI is automation for the iOS export |
| Age-gate / DOB check | Client sign-up form (fast path, `is_under_13` computed) | GoTrue user metadata (`is_under_13` stored) | DOB never persisted; `is_under_13` boolean in JWT claims used by Go signaling for enforcement |

---

## Standard Stack

### Core (all locked from Phase 4 / CLAUDE.md — no new packages)

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Godot 4.6 `RichTextLabel` + BBCode | Built-in | EULA/Privacy in-app renderer | No extra dependency; BBCode supports headings, bold, lists, URLs natively |
| Godot 4.6 `HashingContext` | Built-in | SHA-256 hash of EULA/Privacy files for versioning | `HashingContext.HASH_SHA256` in Godot 4.x core — no external lib needed |
| Godot 4.6 `Crypto.generate_random_bytes()` | Built-in | Consent token generation (same pattern as Phase 4 invite tokens) | CSPRNG already proven in `FriendsClient._generate_invite_token()` |
| Supabase GoTrue SMTP | Self-hosted | Parental consent email delivery | Single SMTP server for all transactional email; custom templates via `GOTRUE_MAILER_TEMPLATES_*` env vars |
| LDNOOBW word list | CC-BY-4.0 | Profanity word lists (EN + NL curated) | De-facto open-source profanity list used by Shutterstock; covers 28 languages; Dutch available |
| GUT test framework | Already installed | Phase 5 unit + integration tests | Existing infrastructure; `gut_config.cfg` present |

### No New Package Installs

Phase 5 introduces **zero new GDExtension packages, npm packages, or Go module dependencies**. All client-side functionality uses Godot built-ins. The Go signaling server extends the existing `cmd/signaling` binary without new `go.mod` imports. Supabase schema additions are pure SQL migrations.

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| BBCode via GDScript markdown parser | `MarkdownLabel` asset (daenvil, Godot Asset Library) | MarkdownLabel is a ready-made Godot 4.2+ addon that converts Markdown to BBCode at runtime. Tradeoff: adds a third-party asset dependency for a small parsing problem. Recommendation: write a 60-line GDScript parser — headings, bold, unordered lists, and links are the only required elements; the parser is trivial and eliminates the dependency. |
| CC-BY-4.0 LDNOOBW word list | Other lists (Profanity Check, bad-words, manual curation) | LDNOOBW is the most widely cited open-source option and includes Dutch (required). CC-BY-4.0 requires attribution but is compatible with GPL-3.0 distribution. Manual curation from scratch would take weeks. |
| GoTrue SMTP for consent email | Separate transactional email service (SendGrid, Postmark) | External services add billing complexity, privacy surface, and vendor lock-in. Self-hosted GoTrue SMTP already handles password reset and verification emails — extending the same infrastructure for parental consent is zero additional ops burden. |

---

## Package Legitimacy Audit

> Phase 5 introduces no new external packages. This section confirms that finding.

**No new npm, PyPI, Godot GDExtension, or Go module packages are introduced in Phase 5.** All functionality is built from:
- Godot 4.6 built-in classes (`RichTextLabel`, `HashingContext`, `Crypto`, `ConfigFile`, `FileAccess`)
- Existing Supabase self-hosted stack (GoTrue + Postgres)
- Existing Go signaling server binary (new HTTP handlers added, no new `go.mod` imports)
- LDNOOBW word list files (plain text, no package installation)

**Packages removed due to slopcheck [SLOP] verdict:** none  
**Packages flagged as suspicious [SUS]:** none  
*Not applicable — no packages installed.*

---

## Architecture Patterns

### System Architecture Diagram

```
[Godot client — any player]
  FriendsClient
  |-- block_user(uid)          → POST /rest/v1/blocks
  |-- submit_report(...)       → POST /rest/v1/reports
  |-- request_parental_consent(email) → POST /consent/request (Go signaling)
  |-- check_consent_status()   → GET /rest/v1/parental_consents?child_uid=...
  |-- [EULA hash check at launch] → read user://settings.cfg, compare bundled hash
  |
  NetworkManager
  |-- [on peer_joined] check blocks table locally (fast UI hide)
  |-- [suppress outbound chat] for unconsented under-13 accounts
  |-- [local auto-mute] of reported user for session duration
  |
  ProfanityFilter (static, loaded at _ready from assets/profanity/wordlist_*.txt)
  |-- filter(text) → "[filtered]" for chat
  |-- filter_reject(text) → true/false for usernames, world names, avatar names

[Go signaling server — Linux VPS]
  Existing: WebSocket hub, session registry, relay, auth
  New endpoints:
  |-- session.join handler → SELECT 1 FROM blocks WHERE (A,B) OR (B,A) → reject if found
  |                        → check parental_consents.consented_at for under-13 accounts
  |-- POST /consent/request → generate consent_token + revoke_token, insert parental_consents, send email via GoTrue admin API
  |-- GET /consent/confirm?token= → validate token, set consented_at, clear consent_token (single-use), update GoTrue metadata
  |-- GET /consent/revoke?token=  → validate revoke_token, set revoked_at, force offline at next session check
  |-- GET /admin/reports          → operator-authenticated (ADMIN_SECRET env var), paginated reports JSON

[Supabase (GoTrue + Postgres)]
  New tables (this phase):
  |-- blocks(blocker_uid, blocked_uid, created_at)
  |-- reports(id, reporter_uid, reported_uid, surface, category, reason, evidence, session_id, created_at)
  |-- parental_consents(child_uid, parent_email, requested_at, consented_at, revoked_at, consent_token, revoke_token)
  |-- username_change_log(uid, old_username, new_username, changed_at)
  Existing tables extended:
  |-- profiles += is_under_13, eula_acknowledged_hash, eula_acknowledged_at
  New functions/triggers:
  |-- can_change_username(uid) → BOOLEAN
  |-- trigger on profiles.username UPDATE → enforce 30-day cooldown + reserved-prefix check
  |-- trigger on profiles INSERT/UPDATE → enforce reserved-prefix list

[GoTrue SMTP]
  Template: parental consent email (HTML + plain text)
  Content: consent link (https://cubicraftia.com/consent?token=<consent_token>)
           revoke link  (https://cubicraftia.com/consent/revoke?token=<revoke_token>)
```

**Entry points:**
- Player blocks another → `FriendsClient.block_user()` → POST to Supabase → Go signaling enforces on next join
- Player reports another → `FriendsClient.submit_report()` → POST to Supabase → operator sees via `/admin/reports`
- Under-13 signs up → DOB form → `is_under_13` stored in GoTrue metadata → `request_parental_consent()` → Go server sends email
- Parent clicks link → Go server validates token → `consented_at` set → account unlocks
- Player launches app → EULA hash check → re-acknowledge modal if hash changed

### Recommended Project Structure (Phase 5 additions)

```
src/
├── autoload/
│   ├── friends_client.gd       # Extended: block_user, unblock_user, get_blocks,
│   │                           #   submit_report, request_parental_consent,
│   │                           #   check_consent_status (new HTTPRequest nodes added)
│   └── username_policy.gd      # New: static reserved-prefix + format validation
├── networking/
│   └── profanity_filter.gd     # Hardened: filter_reject() added, wordlist loaded
│                               #   from assets/profanity/wordlist_en.txt + nl.txt
├── ui/
│   ├── legal_viewer.gd/.tscn   # New: in-app EULA/Privacy renderer (Markdown→BBCode)
│   ├── report_modal.gd/.tscn   # New: 3-surface report form
│   ├── eula_acknowledge_modal.gd/.tscn # New: hash-mismatch re-acknowledge gate
│   └── parental_gate_panel.gd/.tscn   # New: "Waiting for parent" state UI
assets/
└── profanity/
    ├── wordlist_en.txt         # ~300-500 curated EN words (LDNOOBW CC-BY-4.0 + curation)
    ├── wordlist_nl.txt         # ~300-500 curated NL words (LDNOOBW CC-BY-4.0 + curation)
    └── README.md               # CC-BY-4.0 attribution (required by license)
docs/
├── EULA.md                     # Plain-language summary + full legal text (English)
├── PRIVACY.md                  # Plain-language summary + full legal text (English)
└── store-readiness/
    ├── app-store-metadata.md
    ├── play-store-metadata.md
    ├── privacy-nutrition.json
    ├── age-rating.md
    ├── accessibility-statement.md
    ├── screenshot-checklist.md
    └── code-signing-runbook.md
signaling-server/
├── cmd/signaling/main.go       # Adds /consent/* + /admin/reports routes
└── internal/hub/
    ├── hub.go                  # handleJoin extended with blocks-check + consent-check
    ├── session.go              # (unchanged)
    ├── relay.go                # (unchanged)
    ├── auth.go                 # (unchanged)
    └── consent.go              # New: consent lifecycle handlers (confirm, revoke, request)
supabase/migrations/
    ├── 004_blocks.sql
    ├── 005_reports.sql
    ├── 006_parental_consents.sql
    ├── 007_username_change_log.sql
    └── 008_profiles_safety_columns.sql
tests/
├── conftest_phase5.gd          # New: mock blocks, reports, consent table fixtures
└── unit/
    ├── test_block_rls.gd       # Covers: blocker cannot see blocked_uid rows
    ├── test_report_submission.gd # Covers: immutable audit trail, surface enum validation
    ├── test_profanity_filter_extended.gd # Covers: filter(), filter_reject(), EN+NL words
    ├── test_username_policy.gd  # Covers: reserved prefixes, format regex, 30-day cooldown
    ├── test_consent_token.gd   # Covers: 7-day TTL, single-use, revoke token
    └── test_eula_hash.gd       # Covers: SHA-256 hash computation, mismatch detection
```

### Pattern 1: Supabase `blocks` Table with Asymmetric RLS

[CITED: 04-RESEARCH.md — RLS policy pattern from `friendships` table; blocks follows same structure]

```sql
-- Migration 004_blocks.sql
CREATE TABLE public.blocks (
  blocker_uid  UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  blocked_uid  UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (blocker_uid, blocked_uid),
  CONSTRAINT no_self_block CHECK (blocker_uid != blocked_uid)
);

CREATE INDEX blocks_blocker_idx ON public.blocks (blocker_uid);
CREATE INDEX blocks_blocked_idx ON public.blocks (blocked_uid);

ALTER TABLE public.blocks ENABLE ROW LEVEL SECURITY;

-- Blocker can see who they have blocked (their own rows as initiator)
CREATE POLICY "Blockers view own blocks"
  ON public.blocks FOR SELECT
  TO authenticated
  USING ( (SELECT auth.uid()) = blocker_uid );

-- Users can INSERT blocks where they are the initiator
CREATE POLICY "Users create blocks"
  ON public.blocks FOR INSERT
  TO authenticated
  WITH CHECK ( (SELECT auth.uid()) = blocker_uid );

-- Users can remove blocks they created (unblock)
CREATE POLICY "Users remove own blocks"
  ON public.blocks FOR DELETE
  TO authenticated
  USING ( (SELECT auth.uid()) = blocker_uid );
-- Note: blocked_uid has NO SELECT policy — they cannot discover they are blocked.
```

### Pattern 2: Go Signaling — Blocks-Check on Session Join

[ASSUMED based on established Phase 4 Go hub pattern; no authoritative external source]

The join check must run before a peer's `offer` is relayed to the host. The existing `handleRelay` in `hub.go` is the injection point (it already guards the peer-count cap for `offer` messages).

```go
// In internal/hub/hub.go — extend handleRelay for "offer" type
// New field on Hub: db *sql.DB (or supabase HTTP client for consistency)
// For v1: use a single HTTP call to Supabase PostgREST /rest/v1/blocks
// rather than a raw SQL connection — keeps the signaling server stateless
// with respect to DB connections.
func (h *Hub) isBlockedBetween(uidA, uidB string) (bool, error) {
    // GET /rest/v1/blocks?or=(and(blocker_uid.eq.A,blocked_uid.eq.B),and(blocker_uid.eq.B,blocked_uid.eq.A))&select=blocker_uid&limit=1
    // Returns: [] (not blocked) or [{blocker_uid: "..."}] (blocked)
    url := h.cfg.SupabaseURL + "/rest/v1/blocks?or=(and(blocker_uid.eq." + uidA +
        ",blocked_uid.eq." + uidB + "),and(blocker_uid.eq." + uidB +
        ",blocked_uid.eq." + uidA + "))&select=blocker_uid&limit=1"
    req, _ := http.NewRequest("GET", url, nil)
    req.Header.Set("apikey", h.cfg.SupabaseServiceKey)
    req.Header.Set("Authorization", "Bearer "+h.cfg.SupabaseServiceKey)
    resp, err := http.DefaultClient.Do(req)
    if err != nil {
        return false, err
    }
    defer resp.Body.Close()
    var rows []struct{}
    json.NewDecoder(resp.Body).Decode(&rows)
    return len(rows) > 0, nil
}
```

**Key design note:** The Go signaling server uses `SupabaseServiceKey` (not the anon key) for this check because the `blocks` RLS policies do not allow cross-user visibility — the service role bypasses RLS for this server-side enforcement query. This is the correct pattern and mirrors how GoTrue admin operations work.

### Pattern 3: Parental Consent Token Flow (Go signaling + GoTrue SMTP)

[CITED: supabase.com/docs/guides/self-hosting/custom-email-templates — GoTrue SMTP template system]

```go
// internal/hub/consent.go — POST /consent/request
// Called by FriendsClient when an under-13 account provides parent_email at sign-up.
// This endpoint is unauthenticated by token — it is authenticated by the JWT of the
// child user (verified in the standard Hub.HandleConn middleware).
func (h *Hub) handleConsentRequest(w http.ResponseWriter, r *http.Request) {
    // 1. Decode: {child_uid, parent_email}
    // 2. Generate consent_token: crypto/rand → 16 bytes → base32 (same as invite token pattern)
    // 3. Generate revoke_token: separate 16 random bytes → base32
    // 4. INSERT INTO parental_consents (child_uid, parent_email, consent_token, revoke_token)
    //    via Supabase service-role REST call
    // 5. Send email via GoTrue admin API: POST /auth/v1/admin/users/<child_uid>/... 
    //    OR: use Supabase's built-in custom email + GOTRUE_MAILER_TEMPLATES_INVITE env
    //    OR (simpler for v1): send directly via net/smtp using the SMTP credentials
    //    from environment (same SMTP server GoTrue uses for verification emails)
    // 6. Return 200 OK
}

// GET /consent/confirm?token=<consent_token>
func (h *Hub) handleConsentConfirm(w http.ResponseWriter, r *http.Request) {
    token := r.URL.Query().Get("token")
    // 1. SELECT * FROM parental_consents WHERE consent_token = token AND consented_at IS NULL
    // 2. Verify token not expired (requested_at + 7 days > now)
    // 3. UPDATE SET consented_at = NOW(), consent_token = NULL (single-use: clear token)
    // 4. Update GoTrue user metadata: PATCH /auth/v1/admin/users/<child_uid>
    //    {"user_metadata": {"is_under_13": true, "consented_at": "<iso8601>"}}
    // 5. Return HTML "Parental consent confirmed. Your child can now play Cubicraftia."
}

// GET /consent/revoke?token=<revoke_token>
func (h *Hub) handleConsentRevoke(w http.ResponseWriter, r *http.Request) {
    token := r.URL.Query().Get("token")
    // 1. SELECT * FROM parental_consents WHERE revoke_token = token AND revoked_at IS NULL
    // 2. UPDATE SET revoked_at = NOW()
    // 3. Update GoTrue user metadata: {"user_metadata": {"consented_at": null}}
    // 4. Return HTML "Parental consent revoked."
    // Client is forced offline at next session-check (NetworkManager polls consent_status)
}
```

**Email via net/smtp (simpler than GoTrue template):** For v1, send the parental consent email directly via Go's `net/smtp` package using the same SMTP credentials that GoTrue uses (sourced from `signaling.env`). This avoids needing to configure a new GoTrue email template type — GoTrue's custom template system supports `Invite User`, `Confirm Signup`, `Reset Password`, `Magic Link`, and `Change Email`; it does not have a built-in "parental consent" template type. [CITED: supabase.com/docs/guides/auth/auth-email-templates]

### Pattern 4: EULA Hash Check and Re-acknowledge Gate

[CITED: docs.godotengine.org/en/stable/classes/class_hashingcontext.html]

```gdscript
# src/autoload/friends_client.gd or a new EulaManager autoload
# Called at app startup, before title screen

func check_eula_acknowledgement() -> bool:
    # Compute SHA-256 of bundled docs/EULA.md
    var ctx := HashingContext.new()
    ctx.start(HashingContext.HASH_SHA256)
    var f := FileAccess.open("res://docs/EULA.md", FileAccess.READ)
    if f == null:
        push_warning("EULA file not found")
        return true  # Fail open — don't block play if file is missing
    while not f.eof_reached():
        ctx.update(f.get_buffer(4096))
    f.close()
    var hash_bytes := ctx.finish()
    var current_hash: String = hash_bytes.hex_encode().substr(0, 16)  # First 16 hex chars

    # Load stored hash from settings
    var cfg := ConfigFile.new()
    cfg.load("user://settings.cfg")
    var stored_hash: String = cfg.get_value("legal", "eula_hash", "")

    if stored_hash == current_hash:
        return true  # Up to date — no re-acknowledge needed

    # Hash mismatch — force re-acknowledge modal
    _show_eula_modal(current_hash)
    return false


func _store_eula_hash(hash: String) -> void:
    var cfg := ConfigFile.new()
    cfg.load("user://settings.cfg")  # Preserve existing values
    cfg.set_value("legal", "eula_hash", hash)
    cfg.save("user://settings.cfg")
```

### Pattern 5: Markdown-to-BBCode Parser (GDScript)

[ASSUMED: based on Godot RichTextLabel BBCode documentation; no authoritative Godot source for a built-in Markdown parser]

```gdscript
# Minimal inline Markdown → BBCode converter for EULA/Privacy renderer
# Supports: H1-H3 (#/##/###), **bold**, *italic*, - lists, [text](url)
static func md_to_bbcode(md: String) -> String:
    var lines := md.split("\n")
    var out := PackedStringArray()
    for line in lines:
        # Headings
        if line.begins_with("### "):
            line = "[b][i]" + line.substr(4) + "[/i][/b]"
        elif line.begins_with("## "):
            line = "[b]" + line.substr(3) + "[/b]"
        elif line.begins_with("# "):
            line = "[font_size=20][b]" + line.substr(2) + "[/b][/font_size]"
        # Unordered list
        elif line.begins_with("- ") or line.begins_with("* "):
            line = "  • " + line.substr(2)
        # Inline: **bold**, *italic*, [text](url)
        line = line.replace("**", "[b]") if line.count("**") % 2 == 0 else line  # simplified
        # (full parser handles open/close pairs properly)
        out.append(line)
    return "\n".join(out)
```

**Note:** The full implementation needs proper open/close pair tracking for `**bold**` and `*italic*`. The pattern above is a sketch; the implementation plan should include a proper state-machine parser. Alternatively, `MarkdownLabel` (Godot Asset Library, daenvil, MIT-compatible) is a ready-made addon that handles full GFM-subset Markdown. Since Phase 5 adds no new GDExtension dependencies, using MarkdownLabel requires evaluating it as a GDScript addon (not a GDExtension). It is MIT licensed and has no runtime dependencies — acceptable to include if the manual parser proves error-prone.

### Anti-Patterns to Avoid

- **Do NOT query the `blocks` table from the Godot client using the anon key to enforce join gating.** The client-side block check is UI-only. Server-side enforcement via the Go signaling server + service role is the only hard gate. A client can be modified to skip client-side checks.
- **Do NOT store the raw date-of-birth** anywhere in Supabase or GoTrue metadata. GDPR minimum-data principle (and CONTEXT.md Area 3) requires only the derived `is_under_13` boolean.
- **Do NOT echo the attempted profanity in the rejection error message.** Rejecting a username with "The word 'X' is not allowed" teaches the user which words are blocked. Use "Please choose another name." only.
- **Do NOT use GoTrue's existing email template types for parental consent.** GoTrue's template system covers `confirm_signup`, `invite_user`, `magic_link`, `change_email_address`, `reset_password` — it has no `parental_consent` type. Use `net/smtp` directly from the Go signaling server.
- **Do NOT compile a single regex from all words across all languages.** Split into per-language regexes (`_regex_en`, `_regex_nl`). Apply only the relevant language's regex plus the `en` baseline for NL users. This is the mitigation for Tier-3 regex engine limits with 500+ words.
- **Do NOT use `auth.uid()` directly in RLS policies without the `(SELECT auth.uid())` wrapper.** The `friendships` table in 001_friendships.sql already uses the wrapper pattern to avoid per-row function calls. All Phase 5 RLS policies must follow this pattern.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Cryptographic token generation | `randi()`-based tokens | `Crypto.generate_random_bytes()` (GDScript) or `crypto/rand` (Go) | Mersenne Twister is not a CSPRNG; tokens derived from it can be predicted if the seed leaks |
| JWT verification in Go | Custom parser | Standard library `encoding/base64` + `crypto/hmac` (already implemented in `auth.go`) | Already correctly implemented in Phase 4; do not add a third-party JWT library |
| SMTP email in Go | Custom SMTP from scratch | `net/smtp` standard library | Stdlib covers TLS, authentication, MIME; no additional deps needed for the consent email use case |
| Postgres RLS privilege escalation | Client-side SELECT to verify blocks | Go signaling server with service-role key | Service role bypasses RLS for the server-side enforcement check; client anon key cannot see cross-user blocks |
| Parental consent age verification | Third-party age verification API | Self-declared DOB + email-plus consent | FTC email-plus method is accepted for low-risk services under the 2025 COPPA amendments; third-party APIs add cost, privacy surface, and complexity |
| File hashing | MD5 or SHA-1 for EULA versioning | `HashingContext.HASH_SHA256` | SHA-256 is collision-resistant; MD5/SHA-1 have known weaknesses; built-in, zero cost |

**Key insight:** The safety domain is full of footguns in token generation and access control. Trust the established patterns from Phase 4 (`Crypto.generate_random_bytes`, `hmac.Equal`, `(SELECT auth.uid())` in RLS) rather than inventing new ones.

---

## Supabase Schema — Complete Migration Set

### Migration 004: `blocks` Table

[CITED: 04-RESEARCH.md RLS pattern; asymmetric visibility confirmed by CONTEXT.md Area 1]

```sql
-- 004_blocks.sql
CREATE TABLE public.blocks (
  blocker_uid  UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  blocked_uid  UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (blocker_uid, blocked_uid),
  CONSTRAINT no_self_block CHECK (blocker_uid != blocked_uid)
);

CREATE INDEX blocks_blocker_idx ON public.blocks (blocker_uid);
CREATE INDEX blocks_blocked_idx ON public.blocks (blocked_uid);

ALTER TABLE public.blocks ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Blockers view own blocks"
  ON public.blocks FOR SELECT TO authenticated
  USING ( (SELECT auth.uid()) = blocker_uid );

CREATE POLICY "Users create blocks"
  ON public.blocks FOR INSERT TO authenticated
  WITH CHECK ( (SELECT auth.uid()) = blocker_uid );

CREATE POLICY "Users remove own blocks"
  ON public.blocks FOR DELETE TO authenticated
  USING ( (SELECT auth.uid()) = blocker_uid );
```

### Migration 005: `reports` Table

```sql
-- 005_reports.sql
CREATE TYPE report_surface AS ENUM ('player', 'build', 'chat_message');
CREATE TYPE report_category AS ENUM ('harassment', 'spam', 'cheating', 'csam', 'other');

CREATE TABLE public.reports (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  reporter_uid UUID NOT NULL REFERENCES auth.users(id) ON DELETE SET NULL,
  reported_uid UUID NOT NULL REFERENCES auth.users(id) ON DELETE SET NULL,
  surface      report_surface NOT NULL,
  category     report_category NOT NULL,
  reason       TEXT CHECK (char_length(reason) <= 500),
  evidence     JSONB,
  session_id   TEXT,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
  -- No resolved_at / resolved_by in v1 — operator triages manually via /admin/reports
);

CREATE INDEX reports_reporter_idx   ON public.reports (reporter_uid);
CREATE INDEX reports_reported_idx   ON public.reports (reported_uid);
CREATE INDEX reports_created_at_idx ON public.reports (created_at DESC);

ALTER TABLE public.reports ENABLE ROW LEVEL SECURITY;

-- Reporter can insert
CREATE POLICY "Reporters submit reports"
  ON public.reports FOR INSERT TO authenticated
  WITH CHECK ( (SELECT auth.uid()) = reporter_uid );

-- Reporter can view their own submissions (for UI confirmation)
CREATE POLICY "Reporters view own reports"
  ON public.reports FOR SELECT TO authenticated
  USING ( (SELECT auth.uid()) = reporter_uid );

-- No UPDATE or DELETE policies — immutable audit trail
-- Service role (Go signaling /admin/reports) bypasses RLS to read all rows
```

### Migration 006: `parental_consents` Table

```sql
-- 006_parental_consents.sql
CREATE TABLE public.parental_consents (
  child_uid     UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  parent_email  TEXT NOT NULL,
  requested_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  consented_at  TIMESTAMPTZ,
  revoked_at    TIMESTAMPTZ,
  consent_token TEXT UNIQUE NOT NULL,
  revoke_token  TEXT UNIQUE NOT NULL
);

-- No index on tokens needed — UNIQUE constraint creates implicit index.

ALTER TABLE public.parental_consents ENABLE ROW LEVEL SECURITY;

-- Child can read their own consent row (to show "Waiting for parent" UI)
CREATE POLICY "Child views own consent"
  ON public.parental_consents FOR SELECT TO authenticated
  USING ( (SELECT auth.uid()) = child_uid );

-- No INSERT or UPDATE policies for users — only Go service role can write.
-- Go server uses SupabaseServiceKey which bypasses RLS.
```

### Migration 007: `username_change_log` Table

```sql
-- 007_username_change_log.sql
CREATE TABLE public.username_change_log (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  uid          UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  old_username TEXT NOT NULL,
  new_username TEXT NOT NULL,
  changed_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX username_change_log_uid_idx ON public.username_change_log (uid, changed_at DESC);

ALTER TABLE public.username_change_log ENABLE ROW LEVEL SECURITY;

-- INSERT-only for authenticated users (to log their own change)
-- The trigger on profiles.username calls this via SECURITY DEFINER function
-- so RLS on this table is bypassed by the trigger itself.
-- No SELECT for users — moderation team only via service role.

-- Function: can the user change their username?
CREATE OR REPLACE FUNCTION public.can_change_username(user_uid UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER  -- Run as the function owner, not the caller, to bypass RLS
AS $$
DECLARE
  last_change TIMESTAMPTZ;
BEGIN
  SELECT changed_at INTO last_change
  FROM public.username_change_log
  WHERE uid = user_uid
  ORDER BY changed_at DESC
  LIMIT 1;

  IF last_change IS NULL THEN
    RETURN TRUE;  -- No previous change
  END IF;
  RETURN last_change < NOW() - INTERVAL '30 days';
END;
$$;
```

### Migration 008: `profiles` Table — Safety Columns

```sql
-- 008_profiles_safety_columns.sql
-- Extends the existing profiles table (from migration 003) with safety columns.

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS is_under_13 BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS eula_acknowledged_hash TEXT,
  ADD COLUMN IF NOT EXISTS eula_acknowledged_at TIMESTAMPTZ;

-- Trigger: enforce reserved username prefixes on INSERT and UPDATE
CREATE OR REPLACE FUNCTION public.check_username_reserved()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  reserved TEXT[] := ARRAY['admin', 'mod', 'moderator', 'cubicraftia',
                             'support', 'staff', 'system', 'official'];
  r TEXT;
BEGIN
  FOREACH r IN ARRAY reserved LOOP
    IF lower(NEW.username) = r OR lower(NEW.username) LIKE r || '%' THEN
      RAISE EXCEPTION 'Username matches reserved pattern: %', r
        USING ERRCODE = 'check_violation';
    END IF;
  END LOOP;
  RETURN NEW;
END;
$$;

CREATE TRIGGER username_reserved_check
  BEFORE INSERT OR UPDATE OF username ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.check_username_reserved();

-- Trigger: enforce 30-day username change cooldown and log changes
CREATE OR REPLACE FUNCTION public.enforce_username_change_cooldown()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  IF OLD.username IS DISTINCT FROM NEW.username THEN
    IF NOT public.can_change_username(NEW.id) THEN
      RAISE EXCEPTION 'Username can only be changed once every 30 days'
        USING ERRCODE = 'check_violation';
    END IF;
    INSERT INTO public.username_change_log (uid, old_username, new_username)
    VALUES (NEW.id, OLD.username, NEW.username);
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER username_change_cooldown
  BEFORE UPDATE OF username ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.enforce_username_change_cooldown();
```

---

## Common Pitfalls

### Pitfall 1: LDNOOBW License — CC-BY-4.0 Requires Attribution

**What goes wrong:** The CONTEXT.md states LDNOOBW is "MIT licensed." It is actually **Creative Commons Attribution 4.0 International** (CC-BY-4.0). [CITED: github.com/LDNOOBW/List-of-Dirty-Naughty-Obscene-and-Otherwise-Bad-Words/blob/master/README.md]

**Why it happens:** The MIT misconception is widespread in secondary sources. The README footer is clear: "This work is licensed under a Creative Commons Attribution 4.0 International License."

**How to avoid:**
- CC-BY-4.0 is compatible with GPL-3.0 distribution (CC-BY-4.0 does not restrict sublicensing; it only requires attribution).
- Add `assets/profanity/README.md` with the required attribution: "Word lists derived from LDNOOBW/List-of-Dirty-Naughty-Obscene-and-Otherwise-Bad-Words, licensed under CC-BY-4.0. Copyright Shutterstock, Inc."
- Include this attribution in the About screen under `Settings → About → Open Source Licenses`.
- Document the license in the project's `REUSE` infrastructure.

**Warning signs:** Legal review flags a license violation at store submission if attribution is absent.

### Pitfall 2: Regex Engine Limits with 500-Word Alternation on Android

**What goes wrong:** The Phase 4 profanity filter compiles a single `(?i)\b(word1|word2|...)` regex. At 500 words per language, GDScript's `RegEx` (built on PCRE2 under the hood in Godot 4) may take >2 ms per call on Tier-3 Android, causing frame drops during heavy chat activity.

**Why it happens:** PCRE2 alternation with large word counts builds a backtracking automaton that degrades linearly.

**How to avoid:** Split into two separate compiled regexes: `_regex_en` and `_regex_nl`. Apply `_regex_en` always (English is universal); apply `_regex_nl` only when the account's locale is Dutch (or as a second pass for all users since NL slurs differ significantly from EN). At 300-word EN + 300-word NL, each regex is under the problematic threshold. If benchmarks show >2 ms on Tier-3, escalate to an Aho-Corasick Rust GDExtension (same toolchain as the meshing extension).

**Warning signs:** `ProfanityFilter.filter()` takes >2 ms in profiling during the Phase 5 Tier-3 acceptance test.

### Pitfall 3: GoTrue SMTP Template System Does Not Have a Parental Consent Type

**What goes wrong:** Developer tries to use `GOTRUE_MAILER_TEMPLATES_PARENTAL_CONSENT` environment variable — it does not exist. GoTrue's template system supports: `confirmation`, `invite`, `recovery`, `email_change`, `magic_link`, `reauthentication`. There is no parental consent template type.

**Why it happens:** Assuming GoTrue's email template system is extensible to arbitrary email types.

**How to avoid:** Send the parental consent email directly from the Go signaling server using `net/smtp` with the same SMTP credentials GoTrue uses (from `signaling.env` / environment variables). This keeps the email infrastructure in one place (same SMTP server) without adding a new service. [CITED: supabase.com/docs/guides/auth/auth-email-templates — lists all supported template types]

**Warning signs:** Go server returns 500 on consent request because the SMTP call is never reached.

### Pitfall 4: `(SELECT auth.uid())` Wrapper Required in RLS Policies

**What goes wrong:** Writing `auth.uid()` directly in a `USING` clause causes Postgres to call the function once per row instead of once per query, causing a 10-100x performance regression on large tables.

**Why it happens:** `auth.uid()` without the `(SELECT ...)` wrapper is not memoized per query.

**How to avoid:** Always write `(SELECT auth.uid())` in RLS `USING` and `WITH CHECK` clauses. This pattern is established in Phase 4's `001_friendships.sql` and must be followed in all Phase 5 migrations. [CITED: 04-RESEARCH.md — RLS pattern documentation]

**Warning signs:** Slow `SELECT` on `blocks` or `reports` as table grows; Postgres EXPLAIN shows `auth.uid()` calls in per-row filter.

### Pitfall 5: Under-13 Bypass via Direct WebRTC Join (Client Skips Consent Check)

**What goes wrong:** A modified client skips `FriendsClient.check_consent_status()` and sends an `offer` directly to the Go signaling server's session join flow.

**Why it happens:** Client-side validation is never a hard security gate.

**How to avoid:** The Go signaling server's `handleRelay` (for `offer` messages) must verify consent status before relaying to the host. This requires a Supabase PostgREST call: `SELECT consented_at, is_under_13 FROM parental_consents WHERE child_uid = <peer_uid>`. If `is_under_13 = true` in GoTrue metadata AND `consented_at IS NULL`, reject the offer with `{"type":"error","payload":{"code":"consent_required"}}`. The peer's GoTrue metadata (`is_under_13`) is retrieved from the JWT claims (Phase 4 already extracts the `sub` claim from the JWT; `is_under_13` can be embedded as a custom claim in GoTrue user metadata and reflected in the JWT).

**Warning signs:** An under-13 account with no parent consent can join sessions.

### Pitfall 6: COPPA 2025 Amendments — Email-Plus Method Requirements

**What goes wrong:** The email-plus mechanism is assumed to be sufficient without additional safeguards, but the 2025 FTC COPPA amendments introduced stricter requirements around parental identity verification for some use cases.

**Why it happens:** COPPA was last substantially amended in 2013; the 2025 amendments (in effect June 23, 2025) introduced new VPC methods and tightened existing ones.

**How to avoid:**
- Email-plus remains accepted for low-risk services without third-party data disclosure (Cubicraftia matches: no third-party advertising, no data sold to third parties).
- The consent page should include a statement confirming the parent's authority to consent on behalf of the child (e.g., "By clicking Confirm, I confirm that I am the parent or legal guardian of [child username]").
- Include the parent's email address in the `parental_consents` table only as long as consent is active; delete it when the account is deleted (CASCADE handles this).
- Flag for human legal review in `05-HUMAN-UAT.md`. [CITED: FTC COPPA FAQ — ftc.gov/business-guidance/resources/complying-coppa-frequently-asked-questions]

**Warning signs:** FTC enforcement action or App Store rejection citing inadequate parental consent implementation.

### Pitfall 7: Apple App Store Guideline 1.2 — UGC Requirements

**What goes wrong:** App Store review rejects the app for missing a required UGC safety mechanism.

**Why it happens:** Apple App Store Guideline 1.2 requires apps with user-generated content to implement: (1) a mechanism to filter objectionable content, (2) a way for users to block other users, (3) reporting tools for abuse, and (4) rapid response capability to remove reported content. [CITED: developer.apple.com/app-store/review/guidelines/]

**How to avoid:**
- Profanity filter (implemented Phase 5) = (1) content filtering.
- Block system (implemented Phase 5) = (2) block mechanism.
- Report from all three surfaces (implemented Phase 5) = (3) reporting tools.
- Operator `/admin/reports` endpoint with commitment in the privacy policy = (4) rapid response. Document the response SLA in the App Store metadata.
- Friends-only sessions (§9 locked, no open lobbies) = significantly reduces UGC exposure, which reviewers view favorably.

**Warning signs:** App Store rejection with "Guideline 1.2 - Safety - User Generated Content" reason code.

### Pitfall 8: iOS CI — `macos-15` Runner Required for Xcode 16

**What goes wrong:** Using `macos-14` or `macos-13` GitHub-hosted runner fails Godot 4.6 iOS export because Xcode 16 is required for the latest Godot iOS export templates.

**Why it happens:** Godot 4.6 iOS export templates target iOS 17+ SDK, which ships in Xcode 16. Xcode 16 is only pre-installed on `macos-15` GitHub-hosted runners. [ASSUMED: based on GitHub Actions runner image documentation pattern; verified against Godot iOS export requirements indirectly via godot-ios-upload Action docs]

**How to avoid:** Specify `runs-on: macos-15` in the iOS CI job. The `dulvui/godot-ios-upload` GitHub Action (verified at github.com/marketplace/actions/godot-ios-upload) supports Godot 4.x and handles the export template + TestFlight upload flow.

**Warning signs:** CI runner fails with "Xcode version not found" or "SDK not found."

---

## STRIDE Threat Register (Phase 5 additions)

| Threat ID | Description | STRIDE Category | Mitigation |
|-----------|-------------|-----------------|------------|
| T-05-T1 | Reporter impersonation — attacker submits a report as another user | Tampering | JWT auth on all REST calls; `reporter_uid` set from `auth.uid()` in RLS WITH CHECK; server cannot be lied to about who is submitting |
| T-05-S1 | Spoofed consent click — attacker guesses or replays consent token | Spoofing | 128-bit random token (16 bytes via CSPRNG); single-use (token cleared on confirm); 7-day TTL enforced |
| T-05-S2 | Age gate bypass via lying about DOB | Spoofing | Self-declared DOB is accepted residual risk per COPPA "good faith" standard; no technical mitigation (no biometric, no CC check in v1); documented in privacy policy |
| T-05-I1 | Reported user discovers they were reported | Information Disclosure | No notification to reported user; RLS blocks `reported_uid` from seeing their own reports row; auto-mute is local-only (display filter, not a block) |
| T-05-D1 | Mass-report DoS — attacker spam-submits reports to flood the moderation queue | Denial of Service | Reporter rate limit: 5 reports per 24 hours per reporter (enforced via `reports` table count check in Go signaling before INSERT, or client-side guard). Accepted residual risk for v1: operator can filter by reporter_uid in the raw JSON to identify abusers |
| T-05-E1 | Username squatting — player registers `admin` or `cubicraftia` to impersonate staff | Elevation of Privilege | Reserved-prefix list enforced via Postgres trigger on `profiles.username`; client-side `username_policy.gd` for fast UX feedback; both gates required |
| T-05-E2 | Block bypass via invite deep-link — blocked user sends invite link directly to victim | Elevation of Privilege | Go signaling rejects offer messages from blocked users; invite redemption checks blocks before creating friendship; client also hides invite UI for blocked users |
| T-05-E3 | Unconsented under-13 joins session via modified client (skips `check_consent_status`) | Elevation of Privilege | Go signaling server re-checks consent status from Supabase on every `offer` message — client-side check is UX only |

---

## Code Examples

### Loading Profanity Word Lists at Startup

```gdscript
# In profanity_filter.gd — Phase 5 replaces the stub with this
# Called from the autoload that owns ProfanityFilter (e.g., a new EulaManager
# or from FriendsClient._ready() before the filter is needed)
static func load_word_lists() -> void:
    var words: Array[String] = []
    for lang in ["en", "nl"]:
        var path := "res://assets/profanity/wordlist_%s.txt" % lang
        var f := FileAccess.open(path, FileAccess.READ)
        if f == null:
            push_warning("ProfanityFilter: missing word list at %s" % path)
            continue
        while not f.eof_reached():
            var word := f.get_line().strip_edges().to_lower()
            if word != "" and not words.has(word):
                words.append(word)
        f.close()
    ProfanityFilter.set_word_list(words)
```

### `filter_reject()` — New Static Method

```gdscript
# New method in profanity_filter.gd
# Returns true if the text contains a blocked word (used for reject-at-boundary cases).
# Does NOT replace — callers show "Please choose another name." without echoing the input.
static func filter_reject(text: String) -> bool:
    if text.is_empty():
        return false
    _ensure_regex()
    if _regex == null:
        return false
    return _regex.search(text) != null
```

### FriendsClient Extensions — New Public API

```gdscript
# New signals (add to signals section)
signal user_blocked(uid: String)
signal user_unblocked(uid: String)
signal blocks_loaded(blocks: Array)
signal report_submitted()
signal consent_status_received(is_consented: bool, is_pending: bool)

# New HTTPRequest child nodes (add to _ready())
var _block_req: HTTPRequest = null    # For block/unblock operations
var _report_req: HTTPRequest = null   # For report submission
var _consent_req: HTTPRequest = null  # For parental consent operations

# New public methods
func block_user(uid: String) -> void:
    # POST /rest/v1/blocks with {blocker_uid: _user_id, blocked_uid: uid}
    pass  # Implementation follows Phase 4 create_friendship pattern

func unblock_user(uid: String) -> void:
    # DELETE /rest/v1/blocks?blocker_uid=eq.<uid>&blocked_uid=eq.<other>
    pass

func get_blocks() -> void:
    # GET /rest/v1/blocks?blocker_uid=eq.<uid>&select=*
    pass

func submit_report(surface: String, category: String, reason: String, evidence: Dictionary) -> void:
    # POST /rest/v1/reports
    pass

func request_parental_consent(parent_email: String) -> void:
    # POST to Go signaling /consent/request (authenticated with bearer token)
    pass

func check_consent_status() -> void:
    # GET /rest/v1/parental_consents?child_uid=eq.<uid>&select=consented_at,revoked_at
    pass
```

### Go Signaling — New Routes Registration

```go
// In cmd/signaling/main.go — add new routes alongside existing /ws
mux := http.NewServeMux()
mux.HandleFunc("/ws", h.HandleConn)

// Parental consent endpoints (unauthenticated by session — validated by token only)
consentHandler := &hub.ConsentHandler{Hub: h, DB: supabaseClient}
mux.HandleFunc("/consent/request", consentHandler.HandleRequest)   // POST (authenticated by JWT — child's token)
mux.HandleFunc("/consent/confirm", consentHandler.HandleConfirm)   // GET ?token=
mux.HandleFunc("/consent/revoke", consentHandler.HandleRevoke)     // GET ?token=

// Admin moderation endpoint (authenticated by ADMIN_SECRET env var)
mux.HandleFunc("/admin/reports", hub.RequireAdminSecret(h.HandleAdminReports, cfg.AdminSecret))
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Static profanity word lists shipped as constants in code | Loaded from external text files at runtime, hot-swappable via `set_word_list()` | Phase 4 → Phase 5 | Community can contribute word additions via PR without touching GDScript |
| Email-only COPPA consent (pre-2025) | Email-plus with parent identity confirmation statement | FTC COPPA 2025 amendments (in effect June 23, 2025) | Projects not updated for 2025 amendments may face FTC enforcement risk |
| IARC questionnaire per store (Apple, Google separately) | Single IARC questionnaire produces ratings for all participating stores | IARC's unified system, current | One questionnaire → ESRB (NA) + PEGI (EU) + USK (DE) + others |
| Apple privacy nutrition labels (self-reported categories) | Required for every App Store app; categories expanded in 2025 | Apple 2021 → expanded 2025 | `Gameplay Content` must be declared; crash data must be categorized |
| Godot iOS export (manual only, Phase 1 D-04) | iOS CI via `macos-15` runner + `dulvui/godot-ios-upload` Action | Phase 5 closure | DOCS §0 "5 platforms in CI" becomes literally true |

**Deprecated/outdated:**
- GoTrue's `GOTRUE_MAILER_TEMPLATES_*` for parental consent: not applicable (no built-in parental consent template type). Use `net/smtp` directly.
- COPPA email-plus without identity confirmation statement: the 2025 amendments expect a confirmation statement; add it to the consent page HTML.

---

## Open Questions (RESOLVED)

### Q1 — Word List Source (RESOLVED)

**Decision (locked):** LDNOOBW (CC-BY-4.0, not MIT as previously noted) bundled as curated plain-text files in `assets/profanity/`. Attribution in `assets/profanity/README.md` and in-app About screen. Refresh via PRs to the project repo. Word lists curated from the LDNOOBW EN and NL source files, with gaming-context false-positives trimmed (e.g., common brick/gaming terminology that collides with word roots).

**License clarification:** CC-BY-4.0 requires attribution but does not restrict distribution alongside GPL-3.0 code. Attribution is the only obligation. [CITED: github.com/LDNOOBW/List-of-Dirty-Naughty-Obscene-and-Otherwise-Bad-Words/blob/master/README.md]

### Q2 — Email Infrastructure (RESOLVED)

**Decision (locked):** Go signaling server sends parental consent emails directly via `net/smtp` standard library, using the same SMTP credentials already configured for GoTrue (sourced from `signaling.env`). This avoids adding a GoTrue email template type that does not exist, and keeps all transactional email routed through one SMTP server. The Go `net/smtp` package handles TLS, SMTP-AUTH, MIME encoding.

**Human review flag (not code):** COPPA attorney review of the email-plus implementation is flagged for `05-HUMAN-UAT.md`. The 2025 FTC COPPA amendments (in effect June 23, 2025) are the current standard. Email-plus remains valid for low-risk services without third-party data disclosure. [CITED: ftc.gov/business-guidance/resources/complying-coppa-frequently-asked-questions]

### Q3 — Block Enforcement at Server (RESOLVED)

**Decision (locked):** Go signaling server validates blocks on `offer` relay (session join) AND on `publish_session` (a blocked user cannot host a session that another blocked user will see in their friend list). Checks use the Supabase PostgREST API with the service-role key to bypass RLS. Both directions checked: `(blocker=A,blocked=B) OR (blocker=B,blocked=A)`.

The `session_list` response is already friend-filtered (the session list only shows sessions hosted by friends). Because blocks cascade to the friendship check, a blocked user will not appear in friend search results and their sessions will not appear in the friend's session list — enforcement is already structural.

### Q4 — Report Storage Retention (RESOLVED)

**Decision (locked):** Reports are retained for 90 days after `created_at` (no `resolved_at` column in v1 — operator triages manually). Reports with `category = 'csam'` are forwarded immediately to NCMEC (National Center for Missing & Exploited Children) by the operator — this is a legal obligation in the US (18 U.S.C. § 2258A), not a code item. The privacy policy must state that CSAM reports are forwarded to NCMEC and then purged from the operational database within 24 hours of forwarding. A `checkpoint:human-verify` item in `05-HUMAN-UAT.md` covers the NCMEC reporting setup.

---

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | GUT (Godot Unit Test) — already installed |
| Config file | `tests/gut_config.cfg` — existing |
| Quick run | `godot --headless -s tests/gut_main.gd -- -gtest=tests/unit/test_profanity_filter_extended.gd` |
| Full suite | `godot --headless -s tests/gut_main.gd` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| DOC-08 | `filter()` replaces blocked word with `[filtered]` (EN + NL words) | Unit | `-- -gtest=tests/unit/test_profanity_filter_extended.gd` | ❌ Wave 0 |
| DOC-08 | `filter_reject()` returns true for blocked words, false for clean | Unit | `-- -gtest=tests/unit/test_profanity_filter_extended.gd` | ❌ Wave 0 |
| DOC-08 | `filter_reject()` returns false for empty string | Unit | (same file) | ❌ Wave 0 |
| DOC-08 | Block: blocker cannot see blocked_uid rows; blocked_uid sees nothing | Unit (schema logic mock) | `-- -gtest=tests/unit/test_block_rls.gd` | ❌ Wave 0 |
| DOC-08 | Report: `reporter_uid` can SELECT own; `reported_uid` cannot | Unit (schema logic mock) | `-- -gtest=tests/unit/test_report_submission.gd` | ❌ Wave 0 |
| DOC-08 | Consent token: 128-bit, single-use, 7-day TTL logic | Unit | `-- -gtest=tests/unit/test_consent_token.gd` | ❌ Wave 0 |
| DOC-08 | Username policy: reserved prefix `admin` rejected | Unit | `-- -gtest=tests/unit/test_username_policy.gd` | ❌ Wave 0 |
| DOC-08 | Username policy: `^[a-zA-Z0-9_]{3,20}$` regex accepted/rejected | Unit | (same file) | ❌ Wave 0 |
| DOC-08 | Username change cooldown: second change within 30 days blocked | Unit | (same file) | ❌ Wave 0 |
| DOC-08 | EULA hash: SHA-256 of same file produces same 16-char hex prefix | Unit | `-- -gtest=tests/unit/test_eula_hash.gd` | ❌ Wave 0 |
| DOC-08 | EULA hash: different file produces different hash (mismatch detection) | Unit | (same file) | ❌ Wave 0 |
| DOC-08 | Block from player nameplate → report modal shows, submits | Manual UAT | — | — |
| DOC-08 | Under-13 sign-up → parental consent email sent → parent clicks → account unlocks | Manual UAT | — | — |
| DOC-08 | EULA re-acknowledge modal appears when EULA.md hash changes | Manual UAT | — | — |
| DOC-08 | iOS CI (GitHub Actions) build completes and uploads to TestFlight | Manual UAT | — | — |

### Sampling Rate
- Per task commit: `godot --headless -s tests/gut_main.gd -- -gtest=tests/unit/test_profanity_filter_extended.gd -gtest=tests/unit/test_username_policy.gd`
- Per wave merge: full GUT suite
- Phase gate: full suite green + human UAT rows signed off before `/gsd:verify-work`

### Wave 0 Gaps

- [ ] `tests/conftest_phase5.gd` — shared fixtures: mock `blocks` table, mock `reports` table, mock `parental_consents` row, mock `username_change_log`
- [ ] `tests/unit/test_profanity_filter_extended.gd` — covers filter(), filter_reject(), EN+NL word loading
- [ ] `tests/unit/test_block_rls.gd` — covers asymmetric RLS logic (mock Supabase response shapes)
- [ ] `tests/unit/test_report_submission.gd` — covers immutable audit trail, surface enum validation
- [ ] `tests/unit/test_consent_token.gd` — covers token generation (128-bit, base32), TTL logic, single-use semantics
- [ ] `tests/unit/test_username_policy.gd` — covers reserved prefixes, format regex, 30-day cooldown
- [ ] `tests/unit/test_eula_hash.gd` — covers SHA-256 computation via HashingContext, mismatch detection
- [ ] `assets/profanity/wordlist_en.txt` — must exist before filter tests can run (even a 10-word test list)
- [ ] `assets/profanity/wordlist_nl.txt` — same

---

## Security Domain

> `security_enforcement` not explicitly set to false in `.planning/config.json` → enabled.

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | Yes | Existing GoTrue JWT (Phase 4); Phase 5 adds `is_under_13` claim and parental consent status to JWT metadata |
| V3 Session Management | Yes | Parental consent revocation forces offline at next `check_consent_status()` poll — session is not instantly killed but is blocked at the next natural check |
| V4 Access Control | Yes | RLS on `blocks` (asymmetric), `reports` (immutable), `parental_consents` (write-only by service role); Go signaling enforces blocks-check and consent-check on session join |
| V5 Input Validation | Yes | `reason` field: max 500 chars (Postgres CHECK); `surface` and `category`: Postgres ENUM (invalid values rejected at DB level); username: `^[a-zA-Z0-9_]{3,20}$` (client + Postgres UNIQUE + trigger) |
| V6 Cryptography | Yes | Consent tokens: `Crypto.generate_random_bytes(16)` / `crypto/rand` — CSPRNG; SHA-256 for EULA hash — `HashingContext.HASH_SHA256`; never hand-roll crypto |

### Known Threat Patterns for This Stack

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Forged block INSERT (attacker sets blocker_uid to victim's UID) | Tampering | RLS `WITH CHECK ((SELECT auth.uid()) = blocker_uid)` — server rejects |
| Report flood from one reporter (DoS on moderation queue) | Denial of Service | Reporter rate limit: 5 reports/24h per reporter; enforced server-side before INSERT |
| Consent token brute-force | Spoofing | 128-bit entropy token; 7-day TTL; single-use; Postgres UNIQUE index prevents reuse |
| Username impersonation (register `admin_help`) | Elevation of Privilege | Reserved-prefix trigger on `profiles.username`; matches exact and prefix patterns |
| CSAM report not forwarded | Repudiation | Legal obligation (18 U.S.C. § 2258A); `checkpoint:human-verify` in HUMAN-UAT |
| Privacy nutrition label mismatch (claim "no data collected" when data is collected) | Repudiation | privacy-nutrition.json authored to match actual data flows; reviewed before store submission |

---

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Godot 4.6 | All client code | Inferred from project | 4.6 stable | — |
| GUT test framework | All unit tests | ✓ (installed Phase 1) | — | — |
| Go runtime | Go signaling server build | Inferred (Phase 4 built and deployed) | Go 1.22+ | — |
| Supabase self-hosted | Auth + new tables | Inferred (Phase 4 deployed) | Latest | — |
| `macos-15` GitHub Actions runner | iOS CI row | ✓ (GitHub-hosted, standard) | macOS 15 + Xcode 16 | — |
| Apple Developer Program | iOS CI + TestFlight | **Must be purchased by operator before Phase 5 ships** ($99/yr) | — | Manual export via `scripts/export-ios.sh` (Phase 1 D-04 path) |
| SMTP server | Parental consent emails | Inferred (GoTrue uses it for verification emails in Phase 4) | — | No fallback — must be configured |
| `dulvui/godot-ios-upload` Action | iOS CI TestFlight upload | ✓ (GitHub Marketplace, MIT) | v4+ | Custom xcrun script |

**Missing dependencies with no fallback:**
- Apple Developer Program membership: must be purchased before Phase 5 CI can upload to TestFlight. Without it, iOS CI can build but not upload. Plan must include a `checkpoint:human-verify` before the iOS CI task requiring confirmation that the membership is active.

**Missing dependencies with fallback:**
- SMTP server: if GoTrue's SMTP is not yet configured on the VPS, parental consent emails cannot be sent. The fallback is manual email delivery (operator pastes the consent link to the parent) — acceptable for early beta, not for store submission.

---

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | LDNOOBW has Dutch word list available at the `nl` path in the repository | Standard Stack | If the Dutch list is absent or very small (<50 words), NL coverage is insufficient; fallback: manual curation from gaming-context NL sources |
| A2 | CC-BY-4.0 attribution requirement is satisfied by a `README.md` in `assets/profanity/` and an entry in the in-app About screen | Standard Stack | Legal review might require more prominent attribution; low risk given the open-source ethos and GPL-3.0 license structure |
| A3 | GoTrue user metadata (custom claims) can store `is_under_13: true` and `consented_at` as custom fields accessible in the JWT | Parental Consent | If GoTrue's `user_metadata` is not reflected in the JWT claims on the signaling server, the consent check must fall back to a Supabase PostgREST lookup per join request |
| A4 | The `dulvui/godot-ios-upload` GitHub Action supports Godot 4.6 export templates without modification | Environment Availability | If it only supports up to Godot 4.5, a custom CI script must be written; fallback is the existing `scripts/export-ios.sh` pattern |
| A5 | Apple App Store will rate Cubicraftia at 12+ (not 17+) given friends-only sessions and no open chat with strangers | Store Readiness | If Apple rates it 17+, it becomes inaccessible to the target audience (kids/teens); mitigation: document the "friends-only" architecture prominently in the IARC questionnaire |
| A6 | `net/smtp` in Go handles TLS SMTP authentication correctly with the credentials already in `signaling.env` | Go Signaling | If the SMTP server requires a specific auth mechanism (e.g., XOAUTH2 instead of LOGIN/PLAIN), net/smtp alone is insufficient and a third-party mailer library would be needed |
| A7 | The COPPA email-plus method without FTC-certified third-party age verification is legally sufficient for Cubicraftia's scale and risk profile | Parental Consent | If FTC enforcement or App Store policy requires a higher-assurance VPC method (e.g., credit card check, knowledge-based auth), the parental consent flow must be redesigned; this is a HUMAN-UAT item |

---

## Sources

### Primary (HIGH confidence — official documentation and verified sources)

- [Godot 4.6 RichTextLabel BBCode docs](https://docs.godotengine.org/en/stable/tutorials/ui/bbcode_in_richtextlabel.html) — confirmed BBCode tag set (b, i, font_size, url)
- [Godot 4.6 HashingContext docs](https://docs.godotengine.org/en/stable/classes/class_hashingcontext.html) — SHA-256 via `HASH_SHA256`, chunked file hashing pattern
- [Apple App Store Review Guidelines §1.2 (UGC)](https://developer.apple.com/app-store/review/guidelines/) — confirmed: filter, block, report, rapid response all required
- [Apple App Store Privacy Details](https://developer.apple.com/app-store/app-privacy-details/) — confirmed: Gameplay Content and email address must be declared
- [Google Play Content Ratings — IARC](https://support.google.com/googleplay/android-developer/answer/9898843) — confirmed: single IARC questionnaire covers all participating store regions
- [LDNOOBW README — License](https://github.com/LDNOOBW/List-of-Dirty-Naughty-Obscene-and-Otherwise-Bad-Words/blob/master/README.md) — confirmed: CC-BY-4.0 (not MIT); Dutch word list exists at `nl` path
- [Supabase Auth Email Templates](https://supabase.com/docs/guides/auth/auth-email-templates) — confirmed: no built-in parental consent template type; available types listed
- [Supabase Self-Hosted Custom Email Templates](https://supabase.com/docs/guides/self-hosting/custom-email-templates) — confirmed: `GOTRUE_MAILER_TEMPLATES_*` env vars; templates directory setup
- [FTC COPPA Compliance FAQ](https://www.ftc.gov/business-guidance/resources/complying-coppa-frequently-asked-questions) — confirmed: email-plus method accepted for low-risk services
- [FTC COPPA 2025 Amendments (in effect June 23, 2025)](https://securiti.ai/ftc-coppa-final-rule-amendments/) — confirmed: first amendments since 2013; email-plus remains valid
- [04-RESEARCH.md — Phase 4 Supabase schema + RLS patterns](../04-multiplayer-seamless-host-failover/04-RESEARCH.md) — direct codebase reference

### Secondary (MEDIUM confidence — verified against official source + WebSearch)

- [Godot iOS export + macOS notarization docs](https://docs.godotengine.org/en/4.4/tutorials/export/exporting_for_macos.html) — code-signing + notarization setup; `xcrun notarytool`
- [dulvui/godot-ios-upload GitHub Action](https://github.com/marketplace/actions/godot-ios-upload) — Godot 4.x iOS CI upload to TestFlight; `macos-15` runner required for Xcode 16
- [MarkdownLabel Godot addon](https://github.com/daenvil/MarkdownLabel) — MIT, Godot 4.2+ compatible; alternative to custom GDScript parser
- [Apple App Store Guideline 1.2 UGC requirements](https://buddyboss.com/docs/app-store-guideline-1-2-safety-user-generated-content/) — secondary source confirming the four required mechanisms

### Tertiary (LOW confidence — WebSearch only, verify at implementation)

- Phase 5 COPPA attorney review recommendation: flagged as HUMAN-UAT item; FTC enforcement posture post-2025-amendments is still settling
- SMTP auth mechanism compatibility with `net/smtp` stdlib: assumed LOGIN/PLAIN; verify against actual VPS SMTP server configuration

---

## Metadata

**Confidence breakdown:**
- Supabase schema + RLS patterns: HIGH — Phase 4 patterns proven in codebase; schema additions follow established conventions
- Go signaling extensions: HIGH — extending existing hub with new HTTP handlers; patterns established in Phase 4
- Profanity filter hardening: HIGH — Phase 4 `set_word_list()` extension point exists; LDNOOBW license confirmed
- EULA/Privacy renderer: HIGH — Godot `RichTextLabel` + BBCode is well-documented; `HashingContext` SHA-256 confirmed
- Parental consent flow: MEDIUM-HIGH — COPPA email-plus method confirmed valid; GoTrue user metadata custom claims need verification (A3)
- Store compliance: MEDIUM-HIGH — Apple Guideline 1.2 requirements confirmed; IARC questionnaire confirmed; specific rating outcome is ASSUMED (A5)
- iOS CI: MEDIUM — `dulvui/godot-ios-upload` Action supports Godot 4.x; macos-15 runner requirement inferred from Xcode 16 requirement
- COPPA legal sufficiency: MEDIUM — email-plus valid per FTC FAQ; attorney review flagged as required

**Research date:** 2026-05-29
**Valid until:** 2026-06-29 (30 days; App Store guidelines and COPPA enforcement are moderately stable; LDNOOBW license is static)
