# Cubicraftia — Roadmap

## Milestones

- ✅ **v1.0 Public Release** — Phases 1-6 (shipped 2026-05-30)
- ✅ **v1.1 Content & Polish** — Phases 7-9 (shipped 2026-07-08)
- 🚧 **v1.2 Multiplayer & Distribution** — Phases 10-16 (in progress)

## Phases

<details>
<summary>✅ v1.0 Public Release (Phases 1-6) — SHIPPED 2026-05-30</summary>

- [x] Phase 1: Foundation & mobile spike (7/7 plans) — completed 2026-05-25
- [x] Phase 2: World & building content (17/17 plans) — completed 2026-05-26
- [x] Phase 3: Survival loop (13/13 plans) — completed 2026-05-27
- [x] Phase 4: Multiplayer & seamless host failover (11/11 plans) — completed 2026-05-29
- [x] Phase 5: Safety, moderation & store readiness (12/12 plans) — completed 2026-05-29
- [x] Phase 6: First five minutes (11/11 plans) — completed 2026-05-30

Full details: `.planning/milestones/v1.0-ROADMAP.md`

</details>

<details>
<summary>✅ v1.1 Content & Polish (Phases 7-9) — SHIPPED 2026-07-08</summary>

- [x] Phase 7: Asset Integration (4/4 plans) — completed 2026-06-01
- [x] Phase 8: Creature & Builder Animation (6/6 plans) — completed 2026-07-08
- [x] Phase 9: NL Localisation Review (4/4 plans) — completed 2026-06-27

Full details: `.planning/milestones/v1.1-ROADMAP.md`

</details>

### 🚧 v1.2 Multiplayer & Distribution (Phases 10-16) — in progress

- [ ] **Phase 10: Licensing Gate** - GPLv3 §7 App Store exception lands while the codebase is solo-authored, unblocking the Apple track
- [ ] **Phase 11: Backend Go-Live** - nginx+certbot, Go signaling, Supabase, and coturn deployed and smoke-tested in production
- [ ] **Phase 12: Real-Device Multiplayer Validation** - the 6 deferred WebRTC scenarios discharged on real devices, real networks
- [ ] **Phase 13: Reliability & Version-Match Hardening** - connection failures are always explained, recoverable, and never silently desynced
- [ ] **Phase 14: Cross-Platform Code Signing** - signed builds for macOS, Windows, Linux, Android (must-ship) and iOS (spike-gated)
- [ ] **Phase 15: Desktop Distribution & Auto-Update** - itch.io, GitHub Releases, one-link landing page, non-blocking update prompt
- [ ] **Phase 16: Mobile Store Submission** - Google Play (must-ship) and Apple App Store (spike-gated) submission packages, IAP, and pre-listing audits

## Phase Details

### Phase 10: Licensing Gate
**Goal**: The GPLv3 license permits Apple App Store distribution while the codebase is still 100% solo-authored, unblocking downstream iOS work without blocking Android/desktop/backend work.
**Depends on**: Nothing (first phase; runs in parallel with Phase 11)
**Requirements**: LICENSE-01
**Success Criteria** (what must be TRUE):
  1. The project's REUSE-declared license (LICENSES/ + LICENSING.md) grants an attorney-blessed GPLv3 §7 "App Store" supplemental permission, landed while git history remains 100% single-author.
  2. The exact clause wording is reviewed and signed off by the retained attorney before any iOS signing work (Phase 14, SIGN-05) begins.
  3. Android, desktop, and backend work (Phases 11-13, and the non-iOS parts of Phase 14) proceed without waiting on this phase — this gate blocks only the Apple/iOS track.
**Plans**: 1 plan

Plans:
- [ ] 10-01-PLAN.md — Draft and land the GPLv3 §7 App Store Distribution Exception (LICENSES/LicenseRef-AppStore-Exception.txt, LICENSING.md, README, CONTRIBUTING.md), gated on attorney sign-off

### Phase 11: Backend Go-Live
**Goal**: The multiplayer backend is deployed, TLS-secured, and reachable in production on the existing host, with secrets, backups, and release endpoints correctly wired — proven by a first end-to-end smoke test before any real-device validation begins.
**Depends on**: Nothing (first phase; runs in parallel with Phase 10)
**Requirements**: DEPLOY-01, DEPLOY-02, DEPLOY-03, DEPLOY-04, DEPLOY-05, DEPLOY-06, DEPLOY-07
**Success Criteria** (what must be TRUE):
  1. An operator can reach `https://cubicraftia.com` and `wss://cubicraftia.com` over a valid, auto-renewing Let's Encrypt certificate served by nginx + certbot, with the Go signaling server and Supabase both reachable only through the nginx proxy (never directly).
  2. coturn accepts public STUN/TURN allocations on its own binds (3478/5349 + the UDP relay range) independent of nginx, and a single certbot renewal hook reloads both nginx and coturn — no cert renewal silently breaks TURN.
  3. JWT and TURN shared-secret values match exactly across the Go signaling environment, Supabase environment, and coturn config, verified against an operator checklist, with none of the three committed to git.
  4. An automated off-box Postgres backup runs on a schedule and a written rebuild runbook exists, both completed before DNS cutover.
  5. A release-exported client with no localhost defaults can sign up, add a friend, and join a session against the live production endpoints end-to-end on a single machine pair (the go-live smoke test).
**Plans**: TBD

### Phase 12: Real-Device Multiplayer Validation
**Goal**: The six deferred v1.0 WebRTC test scenarios are honestly discharged against real devices on physically distinct real networks — not headless approximations.
**Depends on**: Phase 11
**Requirements**: NETVAL-01, NETVAL-02, NETVAL-03, NETVAL-04, NETVAL-05
**Success Criteria** (what must be TRUE):
  1. Two players on two physically distinct real networks (e.g. home broadband + cellular) can sign in, become friends, and join the same session over the internet.
  2. Direct P2P connects when the network allows it, and TURN relay fallback works when both peers are on cellular/CGNAT/symmetric-NAT connections.
  3. Host-failover handover completes in ≤4 seconds on real devices with no observable world-state loss.
  4. The relay-vs-direct connection badge, live nameplates, and the non-frozen "Connecting…" UI all show correct state under real relay and real failover conditions.
  5. A desktop-hosted and a mobile-hosted session cross-play successfully together in one live multi-platform session.
**Plans**: TBD
**UI hint**: yes

### Phase 13: Reliability & Version-Match Hardening
**Goal**: Connection failures — including version mismatches — are always clearly explained and recoverable, never silent, frozen, or desynced.
**Depends on**: Phase 12 (informed by what real-device validation actually surfaces, not imagined failure modes)
**Requirements**: RELY-01, RELY-02, RELY-03, RELY-04, RELY-05, VER-01, VER-02
**Success Criteria** (what must be TRUE):
  1. Every connection failure surfaces on one shared "connection problem" screen with a specific, correct reason (expired / full / ended / blocked / version-mismatch / relay-failed / timeout).
  2. A brief real-world network blip triggers a silent auto-reconnect within a grace window before any failure is ever shown to the player.
  3. The "Connecting…" state never appears frozen — it always resolves to success or a clear failure within a sane timeout — and a stale or invalid invite link resolves to an actionable error rather than a hang.
  4. The connection-quality badge honestly reflects relay vs. direct at all times, matching what Phase 12 validated on real networks.
  5. A coarse `protocol_version` field accompanies the build stamp and is exchanged in the join handshake; a build carrying a mismatched version is cleanly rejected — including when it is evaluated as a host-failover candidate — and never connects-and-silently-desyncs.
**Plans**: 7 plans

Plans:
- [x] 13-01-PLAN.md — NetworkManager reason plumbing + signaling "error" wiring + Connecting/failover-reconnect bounded timeouts (RELY-01/02/03)
- [x] 13-02-PLAN.md — BuildInfo.PROTOCOL_VERSION + SessionRegistry per-peer version tracking + failover-election exclusion filter (VER-01/02)
- [x] 13-03-PLAN.md — Fix silent stale/invalid invite-redeem bug in FriendsClient + title_scene (RELY-04)
- [x] 13-04-PLAN.md — PROTOCOL_VERSION P2P join-handshake + host-authoritative reject + ICE candidate-type tracking for the relay badge (VER-01/02, RELY-05)
- [x] 13-05-PLAN.md — ConnectionProblemOverlay (Surface A) + 10 new i18n keys (RELY-01)
- [x] 13-06-PLAN.md — JoinScreen migration (spinner + delegate to overlay) + NetworkHud Direct/Relay badge (RELY-01/02/03/05)
- [ ] 13-07-PLAN.md — Wire all three UI surfaces into title_scene/main_scene + human-verify checkpoint (RELY-01/02/03/05)
**UI hint**: yes

### Phase 14: Cross-Platform Code Signing
**Goal**: A build for each of the five target platforms is signed (and for macOS, notarized) to the standard its install/launch path requires, with Android's signing choice made safely-irreversible on first upload and iOS attempted but not blocking milestone completion.
**Depends on**: Phase 10 (gates SIGN-05 / iOS only — SIGN-01..04 have no dependency and may start immediately, in parallel with Phases 11-13)
**Requirements**: SIGN-01, SIGN-02, SIGN-03, SIGN-04, SIGN-05
**Success Criteria** (what must be TRUE):
  1. A macOS build passes `codesign` → `notarytool` → staple → verify as four hard CI failures, with no manual override path.
  2. A Windows build is Authenticode-signed via Azure Trusted Signing using a separate `.pck` (not an embedded PCK).
  3. A Linux build ships as a verifiable AppImage plus a tarball.
  4. An Android AAB is signed with Play App Signing enrolled on the very first upload, targeting API level 36.
  5. (Spike-gated, best-effort) An iOS build is signed and provisioned only after Phase 10 clears; if the CI export spike doesn't clear in this milestone, iOS slips to v1.3 without blocking the other four platforms.
**Plans**: TBD
**Research flag**: yes — `/gsd:plan-phase --research-phase 14` recommended for the iOS export-CI slice (community tooling last verified against Godot 4.3, not 4.6; macOS/Windows/Linux/Android slices are standard, well-documented patterns and don't need a research pass).

### Phase 15: Desktop Distribution & Auto-Update
**Goal**: Signed desktop builds reach players through a paid convenience channel and a free channel, a single link routes each visitor to the right download or a join flow, and out-of-date clients are nudged (never blocked) toward updating.
**Depends on**: Phase 13 (needs the `protocol_version` field for the update-check manifest), Phase 14 (needs signed artifacts)
**Requirements**: DIST-01, DIST-02, DIST-03, DIST-04, DIST-05
**Success Criteria** (what must be TRUE):
  1. Signed desktop builds are published to itch.io via `butler` as the paid convenience build.
  2. Signed desktop builds are attached to GitHub Releases automatically on each tag push (the free / open-source channel).
  3. A platform-detecting one-link landing page (served by nginx) serves the correct build for the visiting platform and exposes a "join my friend's session" entry point.
  4. Opening a `cubicraftia://` deep link on a device without the app installed falls back to the web landing page via Universal Links / App Links `.well-known` config.
  5. A desktop client on an older build sees a non-blocking "update available" prompt driven by a version manifest, without ever being force-closed or blocked from playing.
**Plans**: TBD
**UI hint**: yes

### Phase 16: Mobile Store Submission
**Goal**: Signed, version-matched, backend-validated Android and (spike-permitting) iOS builds reach their respective stores with complete, accurate metadata, and live-backend-verified moderation.
**Depends on**: Phase 10 (License, for the Apple/iOS submission only), Phase 11 (live backend for the STORE-04 re-verification), Phase 14 (signed AAB / iOS build), Phase 15 (final distribution channels exist)
**Requirements**: STORE-01, STORE-02, STORE-03, STORE-04, STORE-05
**Success Criteria** (what must be TRUE):
  1. A Google Play submission (signed AAB, Data Safety declaration, content rating, reviewer demo credentials) is prepared and submitted — this is must-ship for v1.2.
  2. (Spike-gated, best-effort) An Apple App Store submission (signed build, metadata, age rating, privacy labels, reviewer demo credentials) is prepared and submitted only if Phase 10 and the Phase 14 iOS signing spike both cleared; otherwise this item explicitly slips to v1.3 without blocking milestone completion.
  3. The one-time non-consumable IAP (€1/$1 unlock + brick packs) works via OpenIAP, with Restore Purchases functioning on Apple and a launch-time purchase query on Google.
  4. UGC moderation (block / report / profanity filter / parental consent) is re-verified against the live production backend — not local dev — as part of store review prep.
  5. A trademark clearance search and a store-asset visual/copy audit are both completed and signed off before any public store listing goes live.
**Plans**: TBD
**Research flag**: yes — `/gsd:plan-phase --research-phase 16` recommended for the store-submission specifics slice (2026 Apple age-rating overhaul, new state age-verification laws move faster than any static research document; re-verify against live guideline text at planning time).

## Progress

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 1. Foundation & mobile spike | v1.0 | 7/7 | Complete | 2026-05-25 |
| 2. World & building content | v1.0 | 17/17 | Complete | 2026-05-26 |
| 3. Survival loop | v1.0 | 13/13 | Complete | 2026-05-27 |
| 4. Multiplayer & seamless host failover | v1.0 | 11/11 | Complete | 2026-05-29 |
| 5. Safety, moderation & store readiness | v1.0 | 12/12 | Complete | 2026-05-29 |
| 6. First five minutes | v1.0 | 11/11 | Complete | 2026-05-30 |
| 7. Asset Integration | v1.1 | 4/4 | Complete | 2026-06-01 |
| 8. Creature & Builder Animation | v1.1 | 6/6 | Complete | 2026-07-08 |
| 9. NL Localisation Review | v1.1 | 4/4 | Complete | 2026-06-27 |
| 10. Licensing Gate | v1.2 | 0/1 | Not started | - |
| 11. Backend Go-Live | v1.2 | 0/TBD | Not started | - |
| 12. Real-Device Multiplayer Validation | v1.2 | 0/TBD | Not started | - |
| 13. Reliability & Version-Match Hardening | v1.2 | 6/7 | In Progress|  |
| 14. Cross-Platform Code Signing | v1.2 | 0/TBD | Not started | - |
| 15. Desktop Distribution & Auto-Update | v1.2 | 0/TBD | Not started | - |
| 16. Mobile Store Submission | v1.2 | 0/TBD | Not started | - |

## Backlog

### Phase 999.1: Avatar customisation as gameplay progression (BACKLOG)

**Goal:** [Captured for future planning] Grow the builder/avatar customisation surface from the initial Phase 6 character creator into an *ongoing reward loop* — players unlock new looks, body parts, and even temporary abilities by finding/crafting/using things in the world. Customisation becomes a gameplay system, not just a one-time menu.

**Captured ideas (verbatim user prompt 2026-05-26):**

> Maybe we want to add that during the game the avatar selection can grow, so the users can fully customise themselves, but it is part of the gameplay as the customisations are the result of accessories or transformation pods found in the game. Maybe some are temporarily? Maybe some are pets? Some can change gender, others the skin color through paint stations, others the hair colors through harvesting certain crop and putting it in your hair? Raindancing can give maybe gills to breath underwater?

**Threads worth exploring when this is promoted:**

- **Transformation pods** as found-in-world structures (similar mechanic to chests/workbenches?) — could couple with Phase 2's structure templates (villages/temples/shipwrecks/dungeons may host them).
- **Paint stations** — workbench-adjacent; skin / brick-built-body recolour using the 18-colour palette already locked in Plan 02-04.
- **Hair-dye crops** — a survival crop loop tying into Phase 3 (DOC-04 crafting + DOC-05 survival). Harvest → process → apply.
- **Pet companions** — small follower builders or wildlife (the panda / desert mouse / monkey / toucan / orca atmospheric wildlife species locked in Plan 02-01's biome briefs become candidate pet adoptees).
- **Temporary transformations** — rain dance → gills (breathe underwater) is a beautiful coupling: existing rain-dance API in Plan 02-05 already returns `{accepted, message_key}`; could extend to grant a timed `BuilderAbility` ("gills_for_5_min") in v1.1. Mineshafts (Plan 02-08) imply a "deep dark" zone — gills would gate certain dives.
- **Gender / body presets** — must reuse the avatar customisation system from Phase 6 (DOC-01 first-five-minutes). Decision needed: is gender a swappable cosmetic mid-game, or a creator-only choice with body silhouette presets that can be toggled at a transformation pod?
- **Persistence** — every customisation change must round-trip through `WorldSave` (Plan 02-03) and survive multiplayer host-failover (Phase 4 concern).
- **Trademark sanity** — "transformation pods" wording will need brand-clearance pass alongside the existing CRIT-1 trademark sweep before public release. Avoid any "minifig" / "minifigure" terminology in player-facing copy.

**Requirements:** TBD (likely extends DOC-01 first-five-minutes + DOC-04 crafting + DOC-05 survival; may require a new DOC-NN section if customisation grows large enough to warrant its own DOCS.md chapter).

**Plans:** 0 plans

Plans:

- [ ] TBD (promote with `/gsd:review-backlog` when ready — likely after Phase 3 survival loop and Phase 6 character creator both ship)

### Phase 999.2: Multiplayer "dream-view" while a player sleeps (BACKLOG — networking)

**Goal:** When one player sleeps but the others in the session aren't asleep yet, the sleeping
player doesn't just stare at a black screen waiting — they watch a low-resolution, dreamy view
of an awake friend's screen until everyone is sleeping, at which point the shared night-skip
happens. It turns the multiplayer sleep wait into an atmospheric "you're dreaming of what your
friends are doing" moment rather than dead time.

**Captured idea (verbatim user prompt 2026-06-03):**

> in multiplayer if the other ones arent sleeping yet, view a low resolution version of their
> screen till they are sleeping too, like in a dream.

**Why this is a networking feature (deferred to the multiplayer workstream):**
This requires getting one player's rendered view onto another player's screen in real time over
the existing friends-only P2P link. It sits squarely on top of the Phase 4 multiplayer
foundation (WebRTC `WebRTCMultiplayerPeer` + High-Level Multiplayer). It is **not** worth
building until/unless we revisit networking polish — it depends on a live session and must not
compete with gameplay RPC bandwidth.

#### Approaches considered

1. **WebRTC video media track** — capture the awake player's framebuffer, HW-encode (VP8/H.264),
   send as a real WebRTC video track.

   - ✓ True "their screen", smooth, low sender CPU if HW-encoded.
   - ✗ Godot's `WebRTCMultiplayerPeer` exposes **data channels only** — no media-track API. Would
     need a custom GDExtension over `libdatachannel`'s media support + platform HW-encode access
     (not surfaced by Godot, especially on mobile). **HIGH** complexity / engine work. Rejected for v1.

2. **Periodic low-res image frames over a data channel (RECOMMENDED).** The awake "broadcaster"
   grabs `get_viewport().get_texture().get_image()`, downscales to ~128×72, encodes
   `Image.save_jpg_to_buffer()` (~2–8 KB/frame), and sends ~2–3 fps over a dedicated
   **unreliable, low-priority** data channel. The sleeping "dreamer" displays frames on a
   fullscreen `TextureRect` under a dream shader (heavy blur, desaturate, chromatic wobble, dark
   vignette, slow drift).

   - ✓ Works entirely within the existing data-channel transport — no media tracks, no new
     GDExtension. Cross-platform (`save_jpg_to_buffer` is core). Bandwidth modest (~10–40 KB/s).

   - ✓ The low res + low frame-rate **is** the intended "like in a dream" aesthetic, not a
     compromise.

   - ✓ Works even if friends are in a completely different biome — it streams their *output*, not
     their chunks (the decisive advantage over approach 3).

   - ✗ Sender must read back the GPU framebuffer each capture → potential stall on low-end mobile.
     Mitigate: cap resolution/cadence, capture async where possible, feature-flag off on Tier-3
     devices.

3. **State replication (reconstruct their camera locally)** — send the awake player's camera
   transform + nearby entity state; the dreamer renders the scene from that camera.

   - ✗ Requires the dreamer to have the broadcaster's (possibly distant) chunks streamed in →
     huge streaming cost; fails outright when players are far apart. Defeats the low-res dream
     intent. Rejected.

#### Recommended architecture (approach 2)

- **Sleep-state sync (the gameplay-meaningful core):** add a host-authoritative `SleepCoordinator`
  with a replicated per-peer `is_sleeping` flag. The existing `main_scene.sleep_in_bed()` enters
  "dream mode" (instead of immediate skip-to-morning) whenever `NetworkManager` reports >1 peer
  and not all are asleep. The shared `WorldClock.skip_to_morning()` + `despawn_all_hostiles()`
  fires **only when every connected peer is asleep**, decided by the host.

- **Dream feed:** the dreamer picks an awake peer (host, or nearest awake friend) and RPCs
  `request_dream_feed(target)`. The target starts a throttled capture→downscale→JPEG→`dream_frame(bytes)`
  send loop on a separate low-priority channel. Dreamer renders frames under the dream shader.

- **Teardown / hand-off:** stop the feed when the target wakes, disconnects, or all are asleep; if
  the target falls asleep before the dreamer, pick another still-awake peer. When all asleep →
  cross-fade into the **existing** fade-to-black sleep cutscene → morning.

#### Effort / risk

- Sleep-state sync + host-authoritative morning gate: **MEDIUM** (clean reuse of High-Level
  Multiplayer; ~1 plan). This is independently valuable even without the visual feed.

- Frame capture + encode + throttled send + dream shader: **MEDIUM**; main risk is mobile
  framebuffer-readback stalls (mitigated by tiny res, low fps, feature flag).

- **Total ≈ 2–3 plans**, best slotted as a multiplayer **polish** item after core MP is proven
  (Phase 4 already shipped, so this is a v1.2+ networking enhancement).

#### Dependencies / constraints / open questions

- Depends on an active multiplayer session (Phase 4 foundation — ✓ shipped).
- Must use a dedicated low-priority data channel so it never starves gameplay RPCs.
- **Safety/privacy:** you are showing another player's screen. Fine for friends-only sessions, but
  the Phase 5 moderation surface should note it; add a per-player "allow others to dream of my
  screen" opt-out setting.

- Mobile performance is the gating risk per the project's mobile-first constraint.
- Open design Qs: whose screen do you dream of (host / nearest / cycle through all awake)? Passive
  view only, or can the dreamer pan? (Passive recommended for v1.) Behaviour when the chosen peer
  has nothing interesting on screen?

**Requirements:** TBD (extends Phase 4 multiplayer + the Phase 3 sleep/bed loop; the sleep-state
sync portion may warrant its own small DOC-NN section).

**Plans:** 0 plans

Plans:

- [ ] TBD (promote with `/gsd:review-backlog` when the networking/multiplayer workstream is
  revisited — the sleep-state sync sub-task can ship independently of the visual dream feed)
</content>
