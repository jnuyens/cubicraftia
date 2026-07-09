# Requirements: Cubicraftia — v1.2 Multiplayer & Distribution

**Defined:** 2026-07-09
**Core Value:** Het Lego-bouwgevoel in a Minecraft-style sandbox — solo or with up to 4 friends, cross-platform, open source, €1/$1 one-time.

**Milestone goal:** Take Cubicraftia from code-complete to actually-live and actually-downloadable — deploy the multiplayer backend so friends connect over the internet, prove and harden it on real devices, and distribute signed builds via desktop direct download + one-link + both mobile app stores, with a version-match gate so peers never mismatch.

**Milestone stack decisions (override research defaults where noted):**
- **Reverse proxy / TLS: nginx + certbot** (Let's Encrypt) — chosen over the research-recommended Caddy per project owner. certbot deploy-hook must reload every TLS-terminating service (nginx AND coturn).
- Desktop purchasing: itch.io paywall for the paid convenience build + free open-source builds on GitHub Releases. Custom web-checkout/entitlement system deferred to v1.3.
- Auto-update: lightweight version-check + non-blocking prompt; the enforcement teeth is a strict `protocol_version` join gate. Full self-updating installer deferred to v1.3.
- iOS: full pipeline attempted, but spike-gated — if it doesn't clear, Android + desktop still ship v1.2 and iOS slips to v1.3.

## v1 Requirements

Requirements for this milestone. Each maps to a roadmap phase.

### License (phase-0 gate)

- [ ] **LICENSE-01**: GPLv3 §7 "App Store" supplemental-permission clause added to the project's REUSE-declared license (LICENSES/ + LICENSING.md, attorney-blessed wording), unblocking Apple distribution while copyright is 100% solo-held

### Deploy — go-live backend (single host: m1.linuxbe.com / cubicraftia.com)

- [ ] **DEPLOY-01**: nginx + certbot (Let's Encrypt) reverse proxy terminates HTTPS/WSS for the signaling server and Supabase, with automatic renewal
- [ ] **DEPLOY-02**: Go signaling server runs as a systemd service, reachable over WSS in production (loopback-only, proxied by nginx)
- [ ] **DEPLOY-03**: Self-hosted Supabase (GoTrue auth + Postgres friends graph + RLS) runs in production via docker-compose (Kong loopback-only, proxied by nginx)
- [ ] **DEPLOY-04**: coturn runs with correct public STUN/TURN binds (3478/5349 + UDP relay range, bypassing nginx) and a certbot deploy-hook that reloads coturn on cert renewal
- [ ] **DEPLOY-05**: JWT + TURN shared-secret parity verified across signaling, Supabase, and coturn; all secrets off-git (root-owned EnvironmentFile)
- [ ] **DEPLOY-06**: Automated off-box Postgres backup + a written rebuild runbook exist before DNS cutover
- [ ] **DEPLOY-07**: Release export presets point the client at production endpoints (no localhost defaults survive into release builds)

### NetVal — real-device multiplayer validation (discharges the 6 deferred v1.0 WebRTC tests)

- [ ] **NETVAL-01**: Two players on two physically distinct real networks can sign in, become friends, and join a session over the internet
- [ ] **NETVAL-02**: Direct P2P connects when possible; TURN relay fallback works for symmetric-NAT / CGNAT peers (tested with both peers on cellular)
- [ ] **NETVAL-03**: Host-failover handover verified ≤ 4s on real devices with no world-state loss
- [ ] **NETVAL-04**: Relay-vs-direct badge, live nameplates, and freeze UI verified against real relay/failover conditions
- [ ] **NETVAL-05**: Desktop ↔ mobile-hosted crossplay verified in one live session

### Reliability — connection UX hardening

- [x] **RELY-01**: A single shared "connection problem" screen shows a specific reason (expired / full / ended / blocked / version-mismatch / relay-failed / timeout)
- [x] **RELY-02**: A brief network blip triggers a silent auto-reconnect grace window before surfacing failure
- [x] **RELY-03**: The "Connecting…" state is non-frozen, with a sane timeout and a clear failure path
- [x] **RELY-04**: Stale or invalid invite links resolve to a clear, actionable error
- [ ] **RELY-05**: A relay-vs-direct connection-quality badge shows the honest connection type

### Version — build compatibility gate

- [ ] **VER-01**: A coarse `protocol_version` field accompanies the build stamp and is exchanged in the join handshake
- [ ] **VER-02**: Version-mismatched peers are cleanly rejected (never connect-and-silently-desync), including when evaluated as a host-failover candidate

### Sign — cross-platform code signing

- [ ] **SIGN-01**: macOS builds are Developer-ID signed, notarized, and stapled in CI (codesign → notarize → staple → verify, all hard failures)
- [ ] **SIGN-02**: Windows builds are Authenticode-signed via Azure Trusted Signing (separate `.pck`, not embedded-PCK)
- [ ] **SIGN-03**: Linux builds ship as a verifiable AppImage + tarball
- [ ] **SIGN-04**: Android builds are AAB-signed with Play App Signing enrolled on first upload, targeting API level 36
- [ ] **SIGN-05**: iOS builds are signed/provisioned (spike-gated; best-effort per the iOS-slip decision)

### Dist — desktop distribution + auto-update

- [ ] **DIST-01**: Signed desktop builds published to itch.io via butler (the paid convenience build)
- [ ] **DIST-02**: Signed desktop builds attached to GitHub Releases on tag (free / open-source)
- [ ] **DIST-03**: A platform-detecting one-link landing page serves the right build + a join entry point (served by nginx)
- [ ] **DIST-04**: Deep-link join (`cubicraftia://`) has a web fallback via Universal Links / App Links `.well-known`
- [ ] **DIST-05**: Desktop shows a non-blocking "update available" prompt driven by a version manifest

### Store — mobile app stores

- [ ] **STORE-01**: Google Play submission package (signed AAB, Data Safety form, content rating, reviewer demo creds) prepared and submitted
- [ ] **STORE-02**: Apple App Store submission package (signed build, metadata, age rating, privacy labels, reviewer demo creds) prepared and submitted (iOS spike-gated)
- [ ] **STORE-03**: One-time non-consumable IAP (€1/$1 unlock + brick packs) wired via OpenIAP, with Restore Purchases (Apple) + launch-time purchase query (Google)
- [ ] **STORE-04**: UGC moderation (block / report / profanity / parental consent) re-verified against the live production backend for store review
- [ ] **STORE-05**: Trademark clearance search + store-asset visual/copy audit completed before any public listing

## Future Requirements

Deferred beyond v1.2. Tracked, not in this roadmap.

### Desktop monetization
- **Custom desktop web-checkout** (Stripe-style) + Supabase `purchases` entitlement table + in-game unlock — highest-novelty item, deferred; itch.io paywall covers v1.2 desktop purchasing
- **Full self-updating desktop installer** (Sparkle / Squirrel-style) — deferred; version-check prompt covers v1.2

### Distribution reach
- **Flatpak / Flathub** desktop distribution — review-queue turnaround disproportionate to v1.2
- **iOS App Store** if it slips the v1.2 spike — fast-follow in v1.3
- **Steam / GodotSteam** — post-v1 platform optimization

### Gameplay / polish (from prior backlog)
- Combat/death animation polish (follow-on to v1.1 locomotion)
- Audio pass (title music + SFX)
- Avatar customisation as progression (backlog 999.1), multiplayer dream-view (999.2), voice chat

## Out of Scope

Explicitly excluded. Documented to prevent scope creep.

| Feature | Reason |
|---------|--------|
| Open lobbies / public matchmaking / server browser | Friends-only social-safety model is a hard constraint |
| Ranked / competitive matchmaking, non-friend spectator | Same friends-only model; not the product |
| Kubernetes / Nomad / PaaS (Coolify/CapRover/Dokploy) | Disproportionate for one host at 200-session cap |
| Authoritative game server (Nakama) | P2P game-state is a locked v1.0 decision |
| Consumable / subscription / loot-box IAP | Non-consumable one-time only; avoids under-13 monetization scrutiny |
| Firebase / Auth0 / Clerk | Supabase self-host is the locked auth decision |
| Fastlane / Branch.io-style deep-link SaaS | Reuse existing CI patterns + `.well-known`; no new SaaS dependency |

## Traceability

Which phases cover which requirements. Populated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| LICENSE-01 | Phase 10 | Pending |
| DEPLOY-01 | Phase 11 | Pending |
| DEPLOY-02 | Phase 11 | Pending |
| DEPLOY-03 | Phase 11 | Pending |
| DEPLOY-04 | Phase 11 | Pending |
| DEPLOY-05 | Phase 11 | Pending |
| DEPLOY-06 | Phase 11 | Pending |
| DEPLOY-07 | Phase 11 | Pending |
| NETVAL-01 | Phase 12 | Pending |
| NETVAL-02 | Phase 12 | Pending |
| NETVAL-03 | Phase 12 | Pending |
| NETVAL-04 | Phase 12 | Pending |
| NETVAL-05 | Phase 12 | Pending |
| RELY-01 | Phase 13 | Complete |
| RELY-02 | Phase 13 | Complete |
| RELY-03 | Phase 13 | Complete |
| RELY-04 | Phase 13 | Complete |
| RELY-05 | Phase 13 | Pending |
| VER-01 | Phase 13 | Pending |
| VER-02 | Phase 13 | Pending |
| SIGN-01 | Phase 14 | Pending |
| SIGN-02 | Phase 14 | Pending |
| SIGN-03 | Phase 14 | Pending |
| SIGN-04 | Phase 14 | Pending |
| SIGN-05 | Phase 14 | Pending |
| DIST-01 | Phase 15 | Pending |
| DIST-02 | Phase 15 | Pending |
| DIST-03 | Phase 15 | Pending |
| DIST-04 | Phase 15 | Pending |
| DIST-05 | Phase 15 | Pending |
| STORE-01 | Phase 16 | Pending |
| STORE-02 | Phase 16 | Pending |
| STORE-03 | Phase 16 | Pending |
| STORE-04 | Phase 16 | Pending |
| STORE-05 | Phase 16 | Pending |

**Coverage:**
- v1.2 requirements: 35 total (corrected from the 31 figure in this milestone's original definition header; the requirement list itself always had 35 checkbox items — LICENSE 1 + DEPLOY 7 + NETVAL 5 + RELY 5 + VER 2 + SIGN 5 + DIST 5 + STORE 5)
- Mapped to phases: 35 (roadmap created 2026-07-09)
- Unmapped: 0 ✓

---
*Requirements defined: 2026-07-09*
*Last updated: 2026-07-09 after roadmap creation — all 35 requirements mapped to Phases 10-16*
