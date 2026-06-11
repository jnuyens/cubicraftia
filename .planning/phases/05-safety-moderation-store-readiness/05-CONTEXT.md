# Phase 5: Safety, Moderation & Store Readiness — Context

**Gathered:** 2026-05-29
**Status:** Ready for planning
**Mode:** Smart discuss (autonomous) — 6/6 grey areas decided with defensible defaults

<domain>
## Phase Boundary

Cubicraftia clears the App Store and Play Store UGC checklist. By the end of this phase every user-authored string passes through a hardened, multi-language profanity filter; a declared-under-13 account cannot join sessions or chat until a parent confirms a consent email; block and report work from all three DOCS §8.2 surfaces; the EULA and privacy policy are bundled, version-hashed, and force-re-acknowledged on update; store metadata and privacy nutrition labels are authored; and full iOS CI (Apple Developer Program + signing + TestFlight + the iOS row in `.github/workflows/ci.yml`) lands here, making the DOCS §0 "5 platforms in CI" claim literally true.

Phase 4 shipped email+password auth, the friends graph, profanity filter stub, and chat relay. Phase 5 hardens all of it and extends FriendsClient + Supabase schema with block, report, and parental consent tables.

</domain>

<decisions>
## Implementation Decisions

### Area 1 — Block + Report Architecture

**Locked: Global mutual block, separate `blocks` Supabase table.**

- `blocks(blocker_uid UUID, blocked_uid UUID, created_at TIMESTAMPTZ)` — direction matters (blocker vs. blocked), so no canonical-ordering constraint unlike `friendships`. Primary key on `(blocker_uid, blocked_uid)`.
- Mutual enforcement is logical, not stored: when user A blocks user B, the Go signaling service queries `SELECT 1 FROM blocks WHERE (blocker_uid=$A AND blocked_uid=$B) OR (blocker_uid=$B AND blocked_uid=$A)` before admitting a join or returning a friend-search result. The client also checks locally for fast UI hiding.
- RLS: a user can `SELECT` only rows where they are `blocker_uid` (they see who they blocked); they cannot see rows where they are `blocked_uid` (no reverse discovery). `INSERT` allowed only as `blocker_uid = auth.uid()`. `DELETE` allowed only as `blocker_uid = auth.uid()` (unblock).
- Block cascades to: friend-search queries (filter results), session join (Go signaling rejects), invite redemption (Go signaling rejects if block exists either direction), nameplate (client hides).
- Existing `friendships` row is NOT deleted on block — it is soft-overridden by the block check. If A unfriends B and blocks B, the block persists independently. This matches the UGC requirement that block is not the same operation as unfriend.

**Locked: Report flow — Supabase `reports` table + Go signaling moderation endpoint.**

- `reports(id UUID PK, reporter_uid UUID, reported_uid UUID, surface TEXT, category TEXT, reason TEXT, evidence JSONB, session_id TEXT, created_at TIMESTAMPTZ)`.
- `surface`: `'player' | 'build' | 'chat_message'` (three DOCS §8.2 surfaces, all required).
- `category`: `'harassment' | 'spam' | 'cheating' | 'csam' | 'other'`.
- `reason`: free-text, 500 char max.
- `evidence`: JSONB blob — for `chat_message` surface: `{messages: [...5 context messages...], verbatim: "..."}`. For `build`: `{world_id, chunk_coords, screenshot_path_optional}`. For `player`: null or `{session_id}`.
- RLS: reporter can INSERT; reporter can SELECT their own reports (for UI confirmation); `reported_uid` cannot SELECT (no discovery). No one can UPDATE or DELETE (immutable audit trail).
- Go signaling server exposes `GET /admin/reports` (operator-authenticated, separate admin JWT secret). No auto-action in v1 — operator triages manually.
- After submitting a report: confirmation toast ("Report submitted. Our team will review."), reporter's client auto-mutes the reported user for the remainder of that session (local display filter only — does not block; that is a separate deliberate action). No notification to the reported user.

**Locked: All three report surfaces.**

- Player nameplate / friends list overflow menu → `surface = 'player'`.
- Long-press a placed build → `surface = 'build'`.
- Long-press a chat message → `surface = 'chat_message'` with 5-message context captured from the local chat buffer.

### Area 2 — Profanity Filter Hardening

**Locked: Bundled word list, English + Dutch, all user-authored strings.**

- The Phase 4 stub (`src/networking/profanity_filter.gd`) is already structured with `set_word_list()` as the Phase 5 extension point. Phase 5 replaces the 20-word stub with a curated list loaded from `assets/profanity/wordlist_en.txt` and `assets/profanity/wordlist_nl.txt`. DOCS §8.3 specifies English + Dutch in v1 as the locked requirement. Additional languages (FR, ES, DE) are contributable via the same file pattern but are not required for v1 store submission.
- Source: [LDNOOBW](https://github.com/LDNOOBW/List-of-Dirty-Naughty-Obscene-and-Otherwise-Bad-Words) (MIT licensed) is the reference. The repo list will be curated (trimmed of false positives in a gaming context, verified against Dutch-specific terms). The curated lists live in `assets/profanity/` and are included in the GPL-3.0 repo.
- Target size: 300–500 words per language (enough for store compliance, small enough to compile into a single regex without regex engine timeout on mobile).
- Filtered chars replacement: chat messages → `[filtered]` (per DOCS §8.3, sender sees original). Rejected strings (username / world name / avatar name) → show "Please choose another name." error — do NOT echo the attempted profanity in the error message.
- Coverage: chat (already Phase 4), username at sign-up (new — validate before POST to Supabase), world name at creation (new — validate in WorldSave.create_world()), avatar name at save time (new — validate in avatar customisation flow, Phase 6 surface, but the filter API is Phase 5).
- Defense-in-depth: client validates before submission, Supabase CHECK or trigger validates server-side for username (Postgres trigger calling a plpgsql function). Chat is host-relay filtered (already Phase 4 pattern).

**Locked: Remote-update of word list deferred to v1.x.** Bundled list only for v1.

### Area 3 — Parental Consent Flow (Under-13)

**Locked: Date-of-birth field at sign-up, email-based consent, 7-day link expiry.**

- Sign-up form adds a mandatory date-of-birth field (day/month/year dropdowns). Under-13 is calculated as: `birth_date + 13 years > today`. The calculated `is_under_13` boolean is stored in GoTrue user metadata; the raw date of birth is NOT stored (GDPR minimum-data principle).
- Under-13 restricted-account behaviours before consent:
  - Cannot create invites (`FriendsClient.create_invite()` checks consent status before sending)
  - Cannot join sessions (Go signaling rejects join for accounts with `consented_at IS NULL AND is_under_13 = true`)
  - Cannot use chat (`NetworkManager` drops outbound chat packets for unconsented under-13 accounts)
  - Solo play: unlimited (local session, no server interaction required)
  - Friend requests: blocked (cannot send or accept)
- `parental_consents(child_uid UUID PK REFERENCES auth.users(id), parent_email TEXT NOT NULL, requested_at TIMESTAMPTZ NOT NULL DEFAULT NOW(), consented_at TIMESTAMPTZ, revoked_at TIMESTAMPTZ, consent_token TEXT UNIQUE NOT NULL)`.
- `consent_token`: random 128-bit base32 (same pattern as invite tokens in FriendsClient), single-use, 7-day TTL. Token is embedded in the consent email link: `https://cubicraftia.com/consent?token=<token>`.
- On parent click: Go signaling server validates token (not expired, not already consumed), sets `consented_at = NOW()`, clears `consent_token` (single-use). GoTrue user metadata `consented_at` is also updated via Supabase admin API so the game client can poll it.
- Revocation: parent visits the same link pattern (`/consent/revoke?token=<revoke_token>`); a second `revoke_token` (generated alongside the original and stored in a `revoke_token` column) allows revocation without requiring the parent to log in. On revoke: `revoked_at = NOW()`, client is forced offline at next session check.
- RLS: child can SELECT their own row (to show "Waiting for parent approval" UI); child cannot INSERT or UPDATE (only Go server can write via service role). Parent has no Supabase account — all parent interactions go through the Go signaling server's unauthenticated consent endpoints (validated by the token itself).
- COPPA/GDPR-K compliance checklist (Phase 5 must verify):
  - Minimum data: DOB stored as `is_under_13` boolean only; parent email stored only to send the consent link (can be deleted on account deletion).
  - No targeted ads (we have none).
  - Account deletion during grace period deletes the `parental_consents` row and all child data (CASCADE from `auth.users`).
  - Privacy policy explicitly enumerates the `parent_email + consent_record` as collected data (DOCS §8.5 already locks this).

### Area 4 — EULA + Privacy Policy Linking

**Locked: Bundled markdown, hash-versioned, re-acknowledge on update.**

- Files: `docs/EULA.md` and `docs/PRIVACY.md` in the project repo. Rendered in a custom in-app viewer (Markdown subset: headings H1-H3, bold, italic, unordered lists, inline links). No external fetch — bundled in the export.
- Linked from: title screen (small text links at bottom-left, always visible), and `Settings → About` tab (text button row). Both links open the same in-app viewer scene.
- Versioning: SHA-256 hash of the file content (first 16 hex chars displayed as a build artifact). Stored as `eula_hash` in `user://settings.cfg` after acknowledgement. On next launch, if the bundled hash differs from stored hash, a modal is shown before the title screen: "We updated our Terms of Use. Please review and accept to continue." Accept = update stored hash. Decline = sign out and return to title (account remains, cannot play without accepting).
- Languages: English only for v1. The in-app viewer shows a localised header: "The following legal text is provided in English only. This is the binding version." (keyed as `ui.legal.english_only_notice` in `locale/en.po` and `locale/nl.po`).
- Plain-language summaries: each document begins with a 3–5 bullet "plain language summary" box before the full legal text, per DOCS §8.5.

### Area 5 — Store Submission Checklist

**Locked: `docs/store-readiness/` directory with structured metadata files.**

- `docs/store-readiness/app-store-metadata.md` — App name, subtitle (30 chars), description (4000 chars), keywords (100 chars), support URL, marketing URL, primary category (Games → Simulation), secondary category (Games → Adventure).
- `docs/store-readiness/play-store-metadata.md` — Same structure for Google Play Console (short description 80 chars, full description 4000 chars, feature graphic spec, content rating questionnaire answers).
- `docs/store-readiness/privacy-nutrition.json` — Structured JSON matching Apple's privacy nutrition label categories: data collected (email address, user ID, username, gameplay content, crash data), data linked to user (email, user ID, username), data used to track (none — no cross-app tracking, no advertising IDs), data not linked (crash data is opt-in anonymous).
- `docs/store-readiness/age-rating.md` — IARC questionnaire answers leading to 12+ (App Store) / Everyone 10+ (Play Store): mild fantasy violence, online interactions with other players, no user-generated content visible to strangers, no in-app chat with strangers (friends-only). Rationale documented per question.
- `docs/store-readiness/accessibility-statement.md` — Color contrast ratio targets (WCAG AA), current controller support state (desktop keyboard/gamepad Phase 1), mobile font-size respect (UI uses theme font scale), subtitle support roadmap (no voice = no subtitles needed in v1), touch target size compliance.
- `docs/store-readiness/screenshot-checklist.md` — Required screenshot sizes per platform and locale: iPhone 6.9" (1320×2868), iPhone 6.5" (1242×2688), iPad 13" (2064×2752); Android phone (1080×1920 minimum), Android tablet (1600×2560 minimum); 6 screenshots per device per locale for v1 (EN only).
- `docs/store-readiness/code-signing-runbook.md` — Step-by-step for: Apple Developer ID + notarisation (macOS), Apple Developer Program + provisioning profile (iOS/TestFlight), Windows Authenticode signing (optional for v1, no store required), Google Play app signing key setup.
- Not blocking code: this directory is documentation only. Code-signing credentials are operator secrets, not committed to the repo.

**Locked: iOS CI lands in this phase** (per Phase 1 D-04 deviation). The `.github/workflows/ci.yml` iOS row is added, using the Apple Developer Program credentials as GitHub Actions secrets. This fulfils the DOCS §0 "5 platforms in CI" promise.

### Area 6 — Username Gating + Identity Hygiene

**Locked: Single `username` field, 3–20 chars, reserved-prefix list, rate-limited changes.**

- Username format: 3–20 characters, alphanumeric plus underscore only (`^[a-zA-Z0-9_]{3,20}$`), case-insensitive uniqueness enforced by the `profiles.username` UNIQUE index (already exists in migration 003). Validation runs client-side (immediate feedback) and server-side (Postgres constraint is the hard gate).
- Profanity filter applied at sign-up: if the username matches any word in the bundled filter, reject with "Please choose another name." No echo.
- Reserved patterns (rejected at sign-up and username-change): exact matches or prefix matches for `admin`, `mod`, `moderator`, `cubicraftia`, `support`, `staff`, `system`, `official`. Stored as a constant array in a new `src/autoload/username_policy.gd` helper. Validated client-side and via a Postgres trigger on `profiles.username`.
- No separate display name: `username` is the player-visible identity everywhere (nameplate, friends panel, chat attribution, invite link, search). Simplifies the identity model and matches DOCS §8.3 / §8.4.
- Username changes: rate-limited to 1 per 30 days. Enforced by a `username_change_log(uid, old_username, new_username, changed_at)` Supabase table. A Postgres function `can_change_username(uid)` returns false if a row exists within the last 30 days. Client checks before showing the change form; server trigger is the hard gate.
- Audit trail: every username change is appended to `username_change_log` (immutable INSERT-only; no DELETE policy for users). Allows moderation team to trace identity changes.

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets from Phase 4

- **`src/networking/profanity_filter.gd`** — Phase 4 stub with `set_word_list(words)` extension point and `filter(text)` API. Phase 5 calls `set_word_list()` at startup with words loaded from `assets/profanity/wordlist_en.txt` + `wordlist_nl.txt`. The `_ensure_regex()` recompile logic already handles dynamic lists. File path: `/Users/jnuyens/src/LegoMinecraft/src/networking/profanity_filter.gd`.
- **`src/autoload/friends_client.gd`** — GoTrue auth + Supabase REST CRUD. Phase 5 extends it with:
  - `block_user(uid)` → POST to `blocks` table, emit `user_blocked(uid)`
  - `unblock_user(uid)` → DELETE from `blocks`, emit `user_unblocked(uid)`
  - `get_blocks()` → GET blocks list, emit `blocks_loaded(blocks)`
  - `submit_report(surface, category, reason, evidence)` → POST to `reports` table, emit `report_submitted()`
  - `request_parental_consent(parent_email)` → POST to `parental_consents` via Go signaling `/consent/request`
  - `check_consent_status()` → GET `parental_consents` where `child_uid = auth.uid()`, emit `consent_status_received(is_consented, is_pending)`
  - A new `_block_req: HTTPRequest` and `_report_req: HTTPRequest` child node (following the existing pattern of one HTTPRequest per concurrent call type).
- **`supabase/migrations/001_friendships.sql`** — RLS pattern for adjacency tables; blocks table follows the same INSERT + SELECT + DELETE policy structure. File: `/Users/jnuyens/src/LegoMinecraft/supabase/migrations/001_friendships.sql`.
- **`supabase/migrations/003_profiles.sql`** — `username` UNIQUE constraint and RLS already in place. Username-change rate limiting requires a new migration with `username_change_log` table and `can_change_username()` function.
- **`src/autoload/network_manager.gd`** — Phase 4 10-state failover machine. Phase 5 adds:
  - Check `blocks` before emitting `peer_joined` (local client hides blocked peers' nameplates)
  - Suppress outbound chat packets for unconsented under-13 accounts
  - Local auto-mute of reported user for session duration (display filter, not a block)
- **`src/autoload/session_registry.gd`** — Phase 4 session metadata. No changes needed; the Go signaling server validates blocks + consent, not the client registry.

### Established Patterns

- Autoloads: `extends Node`, single-file, registered in `project.godot`. New autoload: `src/autoload/username_policy.gd` (pure utility, no HTTP, static methods only — may be `class_name UsernamePol` without `extends Node` and accessed directly).
- Signals + connect-on-_ready for decoupling (all FriendsClient signals follow this).
- GUT tests in `tests/unit/` and `tests/integration/`; Phase 5 needs `tests/conftest_phase5.gd` with fixtures for `blocks`, `reports`, `parental_consents` table mocks.
- Every UI string via `tr("ui.<surface>.<key>")` in `locale/en.po`. Phase 5 adds new i18n keys for: block/unblock confirmation, report modal labels and categories, parental consent waiting state, EULA re-acknowledge modal, profanity rejection errors, username validation errors, age-gate form labels.
- DOCS-driven: all decisions above must be reflected in DOCS.md §8 sync plan (final plan of Phase 5, analogous to Plan 02-16 and Plan 04-11).

### Integration Points

- Phase 4 `04-RESEARCH.md` STRIDE register (T-04-xx-* threat IDs) is the baseline for Phase 5 security work. Phase 5 adds threats: T-05-block-bypass (player routes around block via invite deep-link), T-05-underage-session-join (unconsented under-13 joins via direct WebRTC if client validation is bypassed — server-side Go validation is the hard gate), T-05-profanity-bypass (homoglyph substitution, leet-speak — v1 mitigation is word-boundary regex, accepted limitation; ML detection is post-v1).
- The Go signaling server (`signaling/`) gains two new endpoint groups:
  - `POST /consent/request` and `GET /consent/confirm?token=` and `GET /consent/revoke?token=` — unauthenticated (validated by token), handles parental consent lifecycle.
  - `GET /admin/reports` — operator-authenticated (separate `ADMIN_SECRET` env var), returns paginated report queue.
- `WorldSave.create_world(name)` must validate `name` through `ProfanityFilter.filter_reject(name)` before creating the SQLite file. A new `filter_reject(text) -> bool` static method on `ProfanityFilter` (returns true if any word matches, without replacing — used for reject-at-boundary cases).

</code_context>

<specifics>
## Specific Implementation Considerations

### Apple/Google Sign-In (Phase 4 stub, Phase 5 activates)

`FriendsClient.sign_in_with_provider(provider)` currently emits `sign_in_failed("not_implemented_phase_5")`. Phase 5 must activate Sign-in-with-Apple (SIWA) because Apple requires it for any iOS app that offers third-party sign-in. However, DOCS §8.4 explicitly locks "Email + password only in v1, no third-party identity." This creates a conflict: Apple's review guidelines require SIWA if the app offers any other third-party sign-in, but the spec says no third-party identity. Resolution: since Cubicraftia v1 uses only email+password (no Google/Facebook/etc.), there is NO third-party sign-in, so SIWA is not required by Apple's guideline. The `sign_in_with_provider` stub can remain a stub through v1. Confirm this during App Store pre-submission review. Document the decision in `docs/store-readiness/code-signing-runbook.md`.

### COPPA Legal Review Hookup

The parental consent flow as designed (self-declared DOB, email-based parent consent, 7-day TTL) meets the spirit of COPPA's "verifiable parental consent" requirement for a game this size, but is not FTC-certified. For a production v1 release, the operator should:
1. Consult a COPPA compliance attorney to confirm the email-click mechanism is sufficient (the FTC's "email plus" method is accepted for low-risk services).
2. Consider adding a ToS acknowledgement on the parent consent page confirming the parent's identity.
3. Ensure the privacy policy explicitly names the "email plus" method used.
This is a human-review item, not a code item. Flag it in `05-HUMAN-UAT.md`.

### Profanity Filter Regex Performance on Mobile

The Phase 4 filter compiles a single `(?i)\b(word1|word2|...)\b` regex from the combined word list. At 300–500 words per language, the alternation length may hit GDScript `RegEx` engine limits or cause visible latency on Tier-3 Android. Mitigation: pre-split into two compiled regexes (EN and NL), and apply only the relevant one(s) based on the account's language setting. If a single 500-word regex proves too slow (>2 ms on Tier-3 benchmark), switch to Aho-Corasick via a small Rust GDExtension (same toolchain as the meshing GDExtension). Flag as a perf spike item in Phase 5 planning.

### iOS CI (Phase 1 D-04 Deviation Closure)

Adding the iOS row to `.github/workflows/ci.yml` requires:
- Apple Developer Program membership ($99/yr) — operator must purchase before Phase 5 ships.
- An Apple Distribution certificate + provisioning profile stored as GitHub Actions secrets (`APPLE_CERTIFICATE_P12`, `APPLE_CERTIFICATE_PASSWORD`, `APPLE_PROVISIONING_PROFILE`).
- Xcode 16+ runner (`macos-15` GitHub-hosted runner has Xcode 16).
- The Godot iOS export template must be pre-built or pulled from Godot's official release (4.6 export templates include iOS).
- TestFlight upload via `xcrun altool` or `xcrun notarytool` after the export step.
The `scripts/export-ios.sh` manual script from Phase 1 is the template for the CI step.

### Report Evidence Storage

For `chat_message` reports, the 5-message context window is captured from the local in-RAM chat buffer (already maintained by `chat_overlay.gd` from Phase 4). The chat buffer holds the last N messages in session — Phase 5 must ensure N ≥ 5 and that the buffer is accessible from the report UI. No server-side chat history is stored (Phase 4 explicitly deferred this); the context is client-captured at report time. This means if the client crashes before reporting, the context is lost — acceptable limitation for v1.

### Block vs. Unfriend Interaction

When a user blocks another, the block must be enforced even if they are currently friends (the `friendships` row is not deleted). The UI must handle the state: a blocked user appears neither in the active friends list nor in the session player list. FriendsClient.get_friends() should filter out blocked UIDs from the returned list client-side after loading both lists. A Postgres view joining `friendships` with `blocks` would be cleaner but adds schema complexity; client-side filtering is acceptable for the 50-friend cap.

</specifics>

<deferred>
## Deferred — Explicitly Out of Scope for Phase 5

- **Real-time moderation pipeline** — no auto-action on reports (e.g., auto-suspend after N reports). Manual triage only in v1. Auto-action is v1.x after moderation team has processed enough reports to calibrate thresholds.
- **ML / AI profanity detection** — Aho-Corasick or transformer-based detection deferred. Regex word-list is v1. ML detection is v2 or after community-reported bypass volume justifies the complexity.
- **Third-party identity providers (SIWA, Google, Discord)** — DOCS §8.4 locks email+password only in v1. Provider stubs remain stubs. SIWA is not required because Cubicraftia has no other third-party sign-in (see Specifics above).
- **Advertising IDs / analytics SDKs** — no third-party analytics, no IDFA/GAID. The privacy nutrition label correctly declares "no tracking." This is not deferred; it is a permanent decision.
- **GDPR Right-to-Portability export** — account deletion (7-day grace) is Phase 5. Data portability (download-your-data endpoint) is post-v1. Note it in the privacy policy as "available on request via email" for v1.
- **Username display name separation** — single `username` field locked. No separate display name in v1.
- **Voice chat moderation** — voice chat is §9 deferred (not in v1 at all). No moderation needed.
- **Open-lobby content moderation** — open lobbies are §9 deferred indefinitely. Cubicraftia is friends-only.
- **Community moderation tooling (mod dashboard UI)** — the operator's moderation queue is a `GET /admin/reports` JSON endpoint. No full dashboard UI in v1; operators use the raw JSON or a lightweight external tool (e.g., Metabase pointed at Supabase). A proper dashboard is v1.1.
- **Multi-language profanity lists (FR, ES, DE)** — contributable by community via `assets/profanity/wordlist_<lang>.txt` pattern, but not required for v1 store submission (EN + NL per DOCS §8.3).
- **TOTP / hardware-key MFA** — DOCS §8.4 does not require it in v1. GoTrue supports TOTP as an optional add-on; surface it in Settings as a future option but do not implement in Phase 5.
- **Breach-check on sign-up passwords (HaveIBeenPwned integration)** — listed in STACK.md PITFALLS.md SOCIAL-4 but not locked in DOCS §8.4. Defer to v1.x; note in the privacy policy that passwords are hashed (bcrypt via GoTrue) but not breach-checked at sign-up.
- **Dedicated server software packaging** — §9 deferred. The headless host build exists; packaging a "Cubicraftia Server" distribution is v1.1.

</deferred>
