# Research Summary — v1.2 "Multiplayer & Distribution"

**Project:** Cubicraftia
**Milestone:** v1.2 — go-live backend + cross-platform signed distribution
**Researched:** 2026-07-08
**Confidence:** MEDIUM-HIGH overall (see Confidence Assessment)

---

## Overview

Cubicraftia enters v1.2 code-complete on gameplay and multiplayer logic, but with three backend services (Go signaling, coturn, self-hosted Supabase) still living only in dev-local config, and zero signed/distributed builds. This milestone has exactly two jobs: **(1) turn the already-built backend into a live, TLS-secured service on the existing single Linux host** and validate it against real devices and real networks, and **(2) turn "exports locally" into "signed, notarized, store-submitted, auto-updating builds"** across five platforms (macOS, Windows, Linux, iOS, Android).

The unifying theme across all four research files is that **very little new game code is needed** — this is overwhelmingly an ops/deployment/legal/packaging milestone layered on top of a stack that was already designed correctly in v1.0/v1.1. `network_manager.gd` and `friends_client.gd` already resolve every backend URL through a `ProjectSettings -> env -> localhost-default` precedence chain; the Build Stamp plugin already stamps every export with a version identifier; the HMAC TURN-credential scheme and JWT auth flow are already implemented and unit-tested. What's missing is deployment correctness (three secrets must match across three independently-deployed artifacts), real-network validation (headless CI tests prove the failover *logic* is correct but say nothing about real cellular/CGNAT behavior), and the entire distribution/signing/store pipeline, none of which existed before this milestone.

The single most urgent finding, surfaced independently by the pitfalls research and cross-referenced against the stack/architecture research, is a **legal hard blocker**: Cubicraftia's GPL-3.0-or-later license is fundamentally incompatible with Apple's App Store distribution terms (the same conflict that got VLC and GNU Go pulled from the App Store historically), and the fix — adding a GPLv3 section 7 supplemental permission to LICENSE/COPYING — is cheap and low-risk **only while the codebase remains 100% solo-authored**. This must be sequenced as an early, code-independent gate, resolved before any iOS CI/signing work begins, not discovered mid-milestone when it's much more expensive to fix. Beyond that, the research converges cleanly on a dependency-ordered build sequence (deploy, validate, harden, sign, distribute, submit-to-stores-last) and flags iOS CI export automation and desktop IAP as the two areas with the least existing precedent and the most implementation risk.

---

## Recommended Approach

1. **Resolve the licensing gate first** (GPLv3 section 7 App Store exception), in parallel with backend deployment, before any iOS-specific work starts.
2. **Deploy the backend in isolation and validate it before wiring the game client to it** — Caddy (reverse proxy/TLS) + coturn (native package, NOT Docker, NOT behind Caddy) + Supabase (official docker-compose, unmodified) + the Go signaling binary (systemd), all on the existing host (`m1.linuxbe.com` / `cubicraftia.com`). Confirm health/TLS/TURN-allocation from an external test client before pointing the actual game client at it.
3. **Smoke-test end-to-end on a single machine pair**, then run the **real-device, real-network validation harness** (the 6 deferred WebRTC tests) — this is the only way to honestly discharge NAT/CGNAT/host-failover risk that headless CI tests cannot prove.
4. **Harden reliability** based on what the real-device pass actually surfaces, not imagined failure modes.
5. **Add a coarser `protocol_version` field** alongside the existing git-sha build stamp, and wire a strict version-match gate into the join handshake — this is new (small) design work, not just a deploy task.
6. **Build the code-signing pipeline** (macOS notarize+staple, Windows Authenticode via Azure Trusted Signing, Android already-wired keystore + mandatory Play App Signing enrollment, iOS once legal + Apple enrollment land) — this can proceed in parallel with steps 3-5 since it doesn't depend on backend state.
7. **Wire distribution channels** (itch.io via `butler`, GitHub Releases attach-to-tag, one-link platform-detecting landing page with Universal Links / App Links `.well-known` fallback) once signed artifacts exist.
8. **Ship the desktop update-check** (lightweight version-check-and-redirect, NOT a self-replacing binary updater — Godot has no mature equivalent to Sparkle/Squirrel and building one is disproportionate for a 2-4-friends indie project).
9. **Submit to mobile stores last** — store review is the only step with an external, non-negotiable, non-parallelizable lead time, and the build submitted should be the final, signed, version-matched, backend-validated one.

---

## Stack Additions

*(New capabilities layered on the already-locked v1.0 stack — Godot 4.6, godot_voxel, WebRTC/ENet, Go signaling, Supabase, coturn, SQLite are unchanged and not re-researched.)*

| Capability | Choice | Why |
|---|---|---|
| Reverse proxy / TLS | **Caddy 2.x** (Apache-2.0) | Zero-config automatic Let's Encrypt issuance/renewal; far lower single-maintainer ops burden than nginx+certbot or Traefik. |
| Backend orchestration | **docker-compose** (Supabase's own unmodified manifest) + **systemd** (Go binary, Caddy, coturn) | No Kubernetes/Nomad/PaaS layer — disproportionate for one host at 200-session-cap scale. Explicitly reject Coolify/CapRover/Dokploy for this milestone. |
| coturn TLS | Dedicated certbot (`turn.cubicraftia.com`) with a restart/reload hook, OR share Caddy's cert storage via read-only mount | coturn is not HTTP and cannot sit behind Caddy for its own TURNS listener; needs direct filesystem cert access either way. |
| macOS signing | Developer ID + `notarytool` (Godot 4.6 export dialog has first-class support) | HIGH confidence, well-documented, no external scripting needed for manual exports. |
| Windows signing | **Azure Trusted Signing** (~$9.99/mo, GA for individuals as of April 2026) rather than a traditional EV cert (~$400-500/yr) | Cheaper, no 3-year business history required; note embedded-PCK exports cannot be signed — export with a separate `.pck`. |
| Linux packaging | **AppImage** (built in CI via `appimagetool`) + tarball; **defer Flatpak/Flathub** | Flathub's review queue adds turnaround disproportionate to this milestone's goal; AppImage+tarball fully satisfies "signed, installable direct download." |
| Android signing | Upload keystore + **mandatory Play App Signing enrollment on first upload** | AAB export required; API level 36 (Android 16) target deadline is **August 31, 2026** — verify GDExtension ABI compatibility (godot_voxel, godot-sqlite, webrtc-native) against API 36 before the submission phase. |
| iOS signing | Team ID + provisioning + `xcodebuild`/`notarytool` — MEDIUM-LOW confidence specifically on **CI automation** | `barichello/godot-ci` does not support iOS; community actions (`dulvui/godot4-ios-export`) were last verified against Godot 4.3, not 4.6 — budget this as its own research/implementation spike. |
| Mobile IAP | **OpenIAP-conformant `hyodotdev/openiap` monorepo** (`libraries/godot-iap`, MIT, wraps StoreKit 2 + Play Billing 8.x) | Unified API across iOS+Android; MEDIUM confidence only because the monorepo migration is ~2-3 months old — have `godot-sdk-integrations/godot-google-play-billing` (mature, MIT) + a standalone iOS StoreKit plugin as fallback pairing. |
| Desktop auto-update | **Lightweight version-check + redirect** (no self-replacing binary patcher) | No mature Godot-native Sparkle/Squirrel equivalent exists; itch.io app users get real auto-update for free via `butler` channels — everyone else gets a non-blocking "update available" toast. |
| Version-match | **Custom application-layer handshake** exchanging `version.txt` (extended with a new coarser `protocol_version` field) at session-join time | Godot's multiplayer protocol deliberately has no built-in version handshake (confirmed open godot-proposals issue) — ~10 lines of code against the existing session-registry validation, not a library. |
| Distribution | `butler` (itch.io), GitHub Releases (`gh release create`, tag-triggered), static platform-detecting landing page on Caddy | All reuse existing CI patterns (tag-gated export matrix, stable `/releases/latest/download/` URL). |

**Explicitly rejected for v1.2:** Steamworks/GodotSteam, Nakama or any authoritative server, Firebase/Auth0/Clerk, Kubernetes/Nomad, HashiCorp Vault, self-hosted PaaS control planes, any subscription/consumable/loot-box IAP, Fastlane automation, Branch.io-style deep-link SaaS, hand-rolled StoreKit/Billing bindings.

---

## Feature Landscape

v1.2's player-facing promise is: **"you and your friends are always on the same build, connected the same way, no matter which of the 5 platforms you're each on."**

### Table stakes (live multiplayer)
- Persistent sign-in across launches (already built — deploy/validate only)
- Friends list with online/offline/"in a session" presence
- One-click join on a friend's active session (already built, `join_session_requested`)
- Deep-link -> land-in-join-flow (already built via `cubicraftia://`, needs *web fallback*)
- STUN-first, TURN-fallback, invisible unless asked (client logic done; coturn deployment is the new work)
- Visible, non-frozen "Connecting..." state with a sane 10-15s timeout before a clear failure
- Automatic host migration, no manual reconnect, no world-state loss — **already built and SLA-verified (<=4s)**, ahead of the ecosystem norm

### Differentiators
- Visible relay-vs-direct connection quality badge (honest about connection type, unusual among indie P2P titles)
- Live nameplates updating in real time as peers connect/reconnect
- Silent auto-reconnect grace window after a brief network blip (new: needs a short client-side "waiting to reconnect" state)
- True 5-platform crossplay (desktop <-> mobile-hosted sessions) — architecturally already supported, needs validation

### Anti-features (hard constraints, do not build)
Open lobbies / public matchmaking, server browser of strangers, spectator mode for non-friends, ranked/competitive matchmaking — all explicitly out of scope per PROJECT.md's friends-only social-safety model.

### Connection-failure/recovery UX — the key cross-cutting pattern
**Adopt one shared "connection problem" screen with a reason enum** (expired / full / ended / blocked-generic / version-mismatch / relay-failed / timeout) instead of N separate ad-hoc error dialogs. Vague "connection failed" messaging is consistently the top support-ticket driver across every comparable multiplayer title studied (Discord, Minecraft, Xbox GDK). This is cheap to build on the existing `NetworkManager` string-constant state pattern.

### Distribution/store IAP notes
- itch.io **app** installs auto-update for free via `butler` channels; itch.io **web-page zip downloads do not** — treat the same as any unmanaged GitHub Releases binary (version-check-and-redirect applies).
- Apple requires a working "Restore Purchases" affordance (Guideline 3.1.1); Google Play has **no OS-level equivalent** and must be built manually via a launch-time purchase-query call.
- Every IAP item (the EUR 1/$1 unlock, brick packs) must be modeled as **non-consumable, one-time, permanent** — never consumable/repeatable, both for platform-fit and to avoid inviting loot-box-adjacent scrutiny given under-13 players are in scope.
- **Desktop/direct-download has zero store receipt system** — needs its own web-checkout + `purchases(user_id, product_id)` entitlement table against the existing Supabase account system. This is genuinely new integration work with no existing precedent in the codebase, flagged by both FEATURES.md and ARCHITECTURE.md as the single highest-complexity IAP item.

---

## Architecture & Build Order

### Backend topology (single host, `m1.linuxbe.com` / `cubicraftia.com`)

| Service | Runtime | Public exposure |
|---|---|---|
| Caddy (reverse proxy, TLS) | systemd, native | Yes — 80/443, only HTTP(S)/WSS entry point |
| Go signaling | systemd (`signaling.service`, already committed) | No — loopback only, proxied by Caddy |
| Supabase (Kong/GoTrue/PostgREST/Postgres/Realtime/Storage) | docker-compose, official manifest | No — Kong loopback only, proxied by Caddy |
| coturn | systemd, native package (NOT Docker) | Yes — 3478/5349 + 49152-65535/udp relay range, bypasses Caddy entirely |

The client-side config-injection point (`ProjectSettings -> env -> localhost default` in `network_manager.gd` / `friends_client.gd`) **already exists** — production URLs just need to be baked into release export presets. STUN/TURN defaults already point at `cubicraftia.com`; signaling/Supabase URLs still default to `localhost` and need an `override.cfg` at release-export time.

**Secret parity is the single most important deploy-correctness risk:** `SUPABASE_JWT_SECRET` must match between the Go server and GoTrue; `TURN_SHARED_SECRET` must exactly match coturn's `static-auth-secret` — if these three artifacts (Go env file, Supabase compose env, coturn conf) drift, TURN relay silently fails for exactly the CGNAT/symmetric-NAT users who need it most, with no obvious client-side error.

### Dependency-ordered build sequence (both Architecture and Stack research converged independently on this order)

1. **Deploy backend infra** (Caddy + coturn + Supabase + Go signaling) — no game-code changes. Exit: all services reachable over TLS/WSS externally, `/health` green, external TURN allocation succeeds (`turnutils_uclient` or a trickle-ICE test page) — validated in isolation, before the client touches it.
2. **Point a release export at production endpoints and smoke-test end-to-end** (sign-up, invite, join, direct P2P + forced-TURN) on one real machine pair.
3. **Real-device, multi-network validation harness** — the 6 deferred WebRTC tests, on at least 2 physically distinct devices on 2 different real networks (home broadband + cellular/hotspot; same-LAN testing hides the symmetric-NAT bugs that matter). This is the first point host-failover SLA, relay badge, nameplates, freeze UI, and NAT traversal can be honestly verified rather than headlessly approximated.
4. **Reliability hardening** (reconnect, connection-failure UX, session recovery, invite-link robustness) — informed by what Phase 3 actually surfaces, not imagined failure modes.
5. **Protocol-version field + version-match gate** — added to the signaling handshake, validated against the harness from Phase 3 (deliberately mismatched builds joining the same session).
6. **Code-signing pipeline** (macOS notarize+staple, Windows Authenticode, Android already-wired, iOS once legal+enrollment land) — can start in parallel with Phases 3-5, doesn't depend on backend state.
7. **Release channels** (itch.io, GitHub Releases, platform-detecting landing page) — needs Phase 6's signed artifacts.
8. **Desktop update-check manifest** — needs Phase 5's protocol-version field and Phase 7's published channel URLs.
9. **Mobile store submission** — last, because store review has the longest, least controllable lead time, and should only start on the final signed/validated build.

**Rationale:** deploy before validate before harden before sign before submit. Every step after Phase 1 depends on a live backend; every step after Phase 6 depends on signed artifacts; store submission is deliberately last because it's the only external, non-negotiable-timeline dependency.

---

## Watch Out For

### HARD BLOCKERS (resolve before sequencing any dependent phase)

**1. GPL-3.0-or-later vs. Apple App Store Distribution Terms — CRITICAL, time-sensitive.**
Apple's App Store Terms impose exactly the kind of "further restriction on recipients' rights" that GPL forbids (the same conflict that got VLC and GNU Go pulled historically); GPLv3 section 6's anti-tivoization clause specifically targets iOS's mandatory code-signing lockout of user-modified builds. **This is Apple-only — Google Play has no equivalent conflict** (Shattered Pixel Dungeon, SuperTuxKart ship GPL on Play today with no issue).
- **Recommended fix, and why it's urgent now:** add a GPLv3 section 7 supplemental "App Store exception" clause to LICENSE/COPYING (the community-tested pattern used by wger and Feeel) — this is legally simple *today* because Cubicraftia's git history is 100% single-author (jnuyens). The moment external contributors land PRs without a CLA, retrofitting this exception requires tracking down consent from every contributor — in practice impossible past a few dozen contributors.
- **Action:** draft and land the clause now, in parallel with backend work, gated on attorney sign-off (already a scheduled review). Do NOT let iOS CI export / App Store Connect work start before this is resolved — treat it as a phase-0 gate for the mobile-stores workstream, not a parallel task.
- Related, lower severity: Apple mandates StoreKit-only IAP for digital goods — do not let store-listing copy imply a cheaper off-store purchase path (anti-steering risk).

**2. Every other flagged pitfall, roughly in the order the build sequence will hit them:**

| # | Pitfall | Phase |
|---|---|---|
| 1 | Port 443 contention: coturn wants 443 too (for CGNAT/corporate-firewall fallback) but Caddy already owns it — needs an explicit port-allocation plan (SNI muxing or accept the tradeoff) | Go-live multiplayer, before DNS cutover |
| 2 | TLS renewal silently breaks coturn: certbot/Caddy renewal hooks routinely cover nginx but miss coturn's separate cert reference — wire one renewal hook that reloads every TLS-terminating service | Go-live multiplayer, hardening |
| 3 | Resource contention on one box: coturn relay traffic is CPU/NIC-bound and can starve Postgres/auth latency during a burst of relayed sessions — set per-service resource limits, budget worst-case bandwidth | Go-live multiplayer + ongoing monitoring |
| 4 | Open signaling/TURN endpoints get abused (reflection/amplification DDoS, session-cap exhaustion) even at tiny scale — verify HMAC TURN credentials are wired end-to-end, add network-level rate limiting | Go-live multiplayer, security hardening |
| 5 | No tested disaster recovery for the one box — automated off-box Postgres backup + a written rebuild runbook, before DNS cutover | Go-live multiplayer, pre-cutover checklist |
| 6 | Headless failover tests prove the state machine, not real network behavior — the entire reason the real-device validation phase exists; don't let it get compressed | Real-device validation |
| 7 | Symmetric NAT/CGNAT still breaks direct P2P even when STUN "worked" — explicitly test both peers on cellular, different carriers (the single most important untested combination) | Real-device validation |
| 8 | TURN bandwidth cost may be higher than budgeted if real CGNAT prevalence exceeds design assumptions — instrument the direct-vs-relay ratio from day one | Reliability hardening |
| 9 | macOS notarization/stapling rejections are Godot-specific and easy to get subtly wrong (app-specific password, missing staple step, unaccepted Program terms) — pipeline must be codesign->notarize->staple->verify, all four as hard CI failures | Desktop direct download |
| 10 | Windows SmartScreen reputation **cannot be bought** — EV certs no longer bypass it (2024 policy change); sign with standard OV, expect and document the first-release warning | Desktop direct download + Auto-update |
| 11 | Android keystore loss = permanent publishing lockout **unless enrolled in Play App Signing on the very first upload** — the single most catastrophic, entirely avoidable signing mistake | Mobile app stores, first upload |
| 12 | iOS provisioning/entitlements mismatches block submission late — stand up a minimal TestFlight build *before* wiring the full feature set; test Universal Links as its own standalone step | Mobile app stores, signing spike first |
| 13 | "Friends-only" does not exempt the app from UGC moderation store requirements (Apple Guideline 1.2) — re-verify block/report/profanity/consent against the **live production backend**, not local dev, and prepare reviewer demo credentials | Mobile app stores, pre-submission QA |
| 14 | Apple's Kids Category is a poor fit for chat-enabled multiplayer — submit as general-audience with an honest age rating instead; re-run the 2026-overhauled age-rating questionnaire fresh | Mobile app stores, category decision |
| 15 | New 2026 state age-verification laws (TX/UT/LA, effective Jan 1 2026) layer on top of existing COPPA work — confirm with attorney whether the existing consent flow needs an Android-specific supplement | Mobile app stores, Play submission |
| 16 | Privacy nutrition labels / Data Safety forms must match a literal data-inventory audit (Supabase schema, TURN/signaling logs, IP retention) — not be drafted from Privacy Policy prose | Mobile app stores, data inventory |
| 17 | Version-mismatched peers can connect-and-silently-desync (worse than a clean rejection) — the compatibility check must be strict/binary, never best-effort; explicitly test a version-mismatched peer as a failover candidate | Auto-update + Reliability hardening |
| 18 | Save/protocol migration chains must keep working for every version jump, not just N-1, once auto-update makes "everyone's current" the assumed default | Auto-update |
| 19 | A public store listing is a materially bigger trademark-exposure event than a GitHub repo (LEGO/Mojang enforcement teams actively monitor store listings; both stores have independent takedown processes) — the trademark clearance search and visual/copy audit are hard gating tasks before submission, not a vague pre-launch checklist item | Mobile app stores, clearance + asset audit |

**Quick-reference top 5 (if the roadmap can only carry five forward):** (1) GPLv3 section 7 exception now, while solo-authored; (2) coturn needs 443 + its own cert-renewal hook; (3) enroll in Play App Signing on first Android upload; (4) budget real-device validation as seriously as backend deployment — headless tests prove nothing about CGNAT; (5) trademark clearance + store-asset audit as explicit gates before public listing.

---

## Operator/Legal Prerequisites (user-provided, in parallel with engineering)

These are NOT engineering tasks the roadmap should schedule as phases — they are external dependencies the operator/legal track must supply, several of which gate specific engineering phases above:

- **Host root + DNS control** on `m1.linuxbe.com` / `cubicraftia.com` (already held, per PROJECT.md) — confirm actual hardware spec (RAM/vCPU) meets Supabase's documented production floor (4GB/2vCPU minimum, 8GB/4vCPU comfortable) before scheduling backend deploy.
- **Apple Developer Program enrollment** ($99/yr) — gates the iOS signing spike and the entire mobile-stores iOS workstream.
- **Google Play Console enrollment** ($25 one-time) — gates Android AAB submission; Play App Signing enrollment decision must happen at first upload.
- **COPPA / EULA attorney sign-off** (already a deferred gating item from v1.0) — must explicitly bless the exact GPLv3 section 7 exception clause wording, the Kids-Category vs. general-audience decision, and whether the existing COPPA consent flow needs Android-specific state-law supplements.
- **Signing credentials/secrets:** Apple `.p12` + provisioning profile + notarization API key; Windows Azure Trusted Signing entity registration (confirm eligibility for whichever legal entity the project registers under); Android upload keystore (already partially scaffolded per `docs/CI_KEYSTORE_SETUP.md`).
- **Backend runtime secrets:** unique `JWT_SECRET`/`ANON_KEY`/`SERVICE_ROLE_KEY`/`POSTGRES_PASSWORD` for Supabase, a distinct `TURN_SHARED_SECRET`, SMTP credentials for parental-consent emails — none committed to git, root-owned `EnvironmentFile=` is sufficient at this scale.
- **Trademark clearance search** on the final name "Cubicraftia" across relevant markets (US/EU) — already flagged in v1.0 research as an open item; this milestone is the one that makes it a hard, dated gate rather than a someday-checklist line.
- **Legal entity decision** for Windows code-signing registration (individual vs. business) — affects Azure Trusted Signing eligibility.

---

## Open Questions

- **iOS CI export automation maturity for Godot 4.6 specifically** — community GitHub Actions were last verified against Godot 4.3; confirm compatibility or budget a manual-export interim fallback. Flag as its own phase-level research spike.
- **OpenIAP `godot-iap` monorepo maturity** — the migration from the standalone repo completed only ~2-3 months before this research; re-verify release cadence and real-world store acceptance at implementation time, with the `godot-sdk-integrations/godot-google-play-billing` + standalone iOS StoreKit plugin pairing as fallback.
- **Azure Trusted Signing exact entity eligibility** — confirm which legal entity the project registers under and re-check current US/Canada/EU/UK eligibility (this product has rebranded and changed eligibility rules multiple times within 2026).
- **`m1.linuxbe.com` current hardware spec** vs. Supabase's recommended production floor — verify before scheduling the backend-deploy phase.
- **coturn TLS certificate strategy** (dedicated certbot vs. sharing Caddy's ACME storage) — both viable, pick one during phase planning; no roadmap-level consequence either way.
- **Android API 36 (Android 16) target deadline (Aug 31, 2026)** impact on pinned GDExtension binaries (godot_voxel, godot-sqlite, webrtc-native) — verify ABI/target-SDK compatibility for all three before the Play Console submission phase; this is a hard gate.
- **Exact wire format for the new `protocol_version` handshake field** (envelope location, server-enforced vs. host-enforced) — an implementation detail for phase planning, not architecture.
- **Real VPS network capacity** (uplink bandwidth for TURN-relayed sessions) — not verified in this research pass; flag for a dedicated capacity check before assuming coturn can comfortably relay multiple concurrent 4-peer sessions.
- **Desktop IAP web-checkout provider** (Stripe or similar) — no existing precedent in the codebase; needs its own scoping pass, flagged as the single highest-complexity IAP item across all research files.

---

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack (backend deploy topology, code signing) | HIGH for backend/macOS/Android/Linux; MEDIUM for Windows cert provider eligibility; MEDIUM for mobile IAP plugin choice; MEDIUM-LOW for iOS CI automation | Backend deployment and desktop signing are mature, widely documented patterns. iOS CI export and the OpenIAP monorepo are the two genuinely novel, fast-moving pieces. |
| Features (live-MP UX, distribution UX) | HIGH for connection-failure taxonomy and mobile store auto-update; MEDIUM for desktop auto-update recommendation (reasoned synthesis, not an observed existing pattern for this exact stack) | Cross-referenced against Discord, Minecraft, and Xbox GDK's own documented failure-mode taxonomies. |
| Architecture (single-host topology, build order) | HIGH for topology and client endpoint-config strategy (verified directly against `network_manager.gd`/`friends_client.gd` source); MEDIUM for the protocol-version field recommendation (this document's own synthesis, not yet built) | The build order (deploy->validate->harden->sign->distribute->submit) was independently converged upon by both the Architecture and Stack research passes. |
| Pitfalls (legal/security/store) | HIGH for the GPL/Apple conflict, coturn/firewall mechanics, and Android/Apple signing-lockout risks (well-documented, multi-source); MEDIUM for 2026-specific policy details (Apple age-rating overhaul, state age-verification laws) — these move faster than any static research document | The GPLv3 section 7 exception recommendation is a community-tested pattern (wger, Feeel) but should still get explicit attorney sign-off on the exact clause wording. |

**Overall confidence: MEDIUM-HIGH.** The engineering path (deploy, validate, sign, distribute) is well-understood and low-risk. The two genuine unknowns are (a) whether the GPLv3 section 7 fix and attorney review land in time to avoid blocking iOS work, and (b) whether iOS CI automation and desktop IAP prove as straightforward as their Android/mobile-IAP counterparts once implementation actually starts.

### Gaps to Address During Roadmap/Phase Planning

- The licensing decision (HARD BLOCKER 1) has no engineering solution — it needs to be modeled as its own phase-0 gate in the roadmap, not folded into "mobile app stores," so the roadmap doesn't accidentally schedule iOS signing work before it clears.
- Real VPS capacity and Supabase resource-budget questions are operator-verification tasks that should be resolved before, not during, the backend-deploy phase — the roadmap should treat "confirm host spec" as an explicit pre-phase-1 checklist item.
- iOS CI automation and desktop IAP are the two items most likely to need a dedicated `--research-phase` pass during phase planning (see Research Flags below).

### Research Flags for Roadmap/Phase Planning

**Likely needs `/gsd:plan-phase --research-phase <N>` during planning:**
- The phase covering **iOS export CI automation** (community tooling verified only against Godot 4.3; needs a fresh compatibility spike against 4.6).
- The phase covering **desktop IAP / web checkout** (zero existing codebase precedent; provider choice, entitlement-table design, and Supabase integration all need scoping).
- The phase covering **mobile store submission specifics** (2026 age-rating overhaul, new state age-verification laws) — policy specifics should be re-verified against live guideline text at that time, not against this document.

**Standard, well-documented patterns (safe to skip a dedicated research pass):**
- Backend deployment topology (Caddy/coturn/Supabase/systemd) — thoroughly documented, low novelty.
- macOS/Android code signing — Godot has first-class export-dialog support for both.
- itch.io/GitHub Releases distribution — solved, widely-documented CI patterns.
- The version-match/protocol-version handshake — small, additive, well-scoped application code.

---

## Sources

Aggregated from the four underlying research files (each with full source lists):
- `.planning/research/STACK.md` — Godot export/signing docs, Azure Trusted Signing, Supabase self-host + Caddy guides, coturn docs, OpenIAP/Play Billing plugin repos, itch.io butler docs.
- `.planning/research/FEATURES.md` — Godot host-migration and auto-updater proposals, itch.io app update docs, Apple/Google IAP and Restore Purchases guidance, Discord/Minecraft/Xbox GDK invite-and-version-mismatch UX patterns.
- `.planning/research/ARCHITECTURE.md` — Repo-internal verification (`network_manager.gd`, `friends_client.gd`, `signaling-server/internal/hub/*.go`, `addons/build_stamp/*`, `ci.yml`), Supabase/Caddy self-host guides, coturn wiki, Google Play API-36 deadline sources.
- `.planning/research/PITFALLS.md` — FSF/GPL-Apple conflict sources (multiple, including direct FSF blog posts and precedent GitHub issues), coturn security guides, Godot notarization GitHub issues, Microsoft SmartScreen/Play App Signing docs, Apple/Google store policy pages (Kids category, Families policy, age-verification law coverage).

Full citation lists with individual URLs are preserved in each source file; not duplicated here to avoid drift between this summary and the underlying research.

---
*Research completed: 2026-07-08*
*Ready for roadmap: yes*
