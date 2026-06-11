# Cubicraftia — Roadmap

## Milestones

- ✅ **v1.0 Public Release** — Phases 1-6 (shipped 2026-05-30)
- 🚧 **v1.1 Content & Polish** — Phases 7-9 (started 2026-06-01)

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

### 🚧 v1.1 Content & Polish (Phases 7-9)

- [x] **Phase 7: Asset Integration** — Wire all committed art into live scenes; remove every placeholder stub (completed 2026-06-01)
- [x] **Phase 8: Creature & Builder Animation** — Productionize all three rig archetypes into idle + locomotion for all entities (3 plans) (completed 2026-06-09)
- [ ] **Phase 9: NL Localisation Review** — Native Dutch speaker review of profanity wordlist and all 478 translations

## Phase Details

### Phase 7: Asset Integration

**Goal**: Players see the real committed art everywhere in the game — no 1×1 transparent placeholder remains in any shipped scene
**Depends on**: Nothing (first v1.1 phase; v1.0 codebase is the foundation)
**Requirements**: ASSET-01, ASSET-02, ASSET-03, ASSET-04, ASSET-05, ASSET-06, ASSET-07
**Success Criteria** (what must be TRUE):

  1. The title screen shows the real background and wordmark on launch (not a transparent stub)
  2. The avatar creator shows the 8 real preset thumbnails; the world-select screen shows a real world thumbnail
  3. The FTUE walkthrough displays the real arrow and storyboard art across all 4 steps
  4. In-game HUD, toasts, and map markers use real sprites; achievement badges, rarity borders, and biome minimap tiles appear wherever those surfaces render
  5. A scene audit finds zero 1×1 transparent placeholder assets referenced by any shipped scene

**Plans**: 4 plans

Plans:

- [x] 07-01-PLAN.md — ASSET-07 audit test scaffold (Wave 0: headless GUT stub-size scanner)
- [x] 07-02-PLAN.md — Code path fixes: hp_bar hearts, FTUE arrow + storyboard panels, world-select dead path
- [x] 07-03-PLAN.md — Asset replacements: title_bg hero art + VRAM import, world_thumb placeholder
- [x] 07-04-PLAN.md — Avatar preset thumbnails: SubViewport capture + Button.icon wiring + final audit green

### Phase 8: Creature & Builder Animation

**Goal**: Every creature and the player's builder visibly animates in-world — idle when still, locomotion when moving — with no measurable frame-rate regression
**Depends on**: Phase 7
**Requirements**: ANIM-01, ANIM-02, ANIM-03, ANIM-04, ANIM-05, ANIM-06
**Success Criteria** (what must be TRUE):

  1. Soft-body creatures (3 slime tiers, fish, ghost) play idle and movement animation via the shader-wobble system when active in the world
  2. Quadruped wildlife play idle and movement animation when active in the world
  3. All 5 hostile creature types animate (idle + locomotion) when encountered during play
  4. The player's builder visibly plays idle when still and walk/run when moving during normal play, driven by the rigid-piece rig shared with humanoid hostiles
  5. Animation introduces no measurable frame-rate regression against the v1.0 mobile performance targets on the reference Tier-3 device

**Plans**: 6 plans (3 original + 3 gap-closure)

Plans:
**Wave 1**

- [x] 08-01-PLAN.md — Verify the committed animation tests are headless-green (ANIM-01..05) and record the result
- [x] 08-02-PLAN.md — Reconcile RESEARCH-vs-shipped divergences in 08-CONTEXT.md + fix the stale STATE.md Phase 8 ledger

**Wave 2** *(blocked on Wave 1 completion)*

- [x] 08-03-PLAN.md — ANIM-06 frame-budget gate: desktop FPS smoke + manual Tier-3 benchmark run-or-defer

**Gap closure** *(re-wire shipped code to meet ROADMAP SC1/SC2 — from 08-VERIFICATION.md)*

Wave 1 (parallel — no file overlap):
- [x] 08-04-PLAN.md — Re-wire wildlife dispatch: populate _FISH_TINTS (fish→ShaderWobble FISH, SC1) + _QUADRUPED_SETS (panda→QuadrupedAnimator, SC2); remove dead ghost branch
- [x] 08-05-PLAN.md — Re-wire hostile soft-body: cube_slime (3 tiers) + ghost → ShaderWobbleAnimator (SLIME/GHOST), preserving split/hop/wall-pass/bed-bubble combat (SC1)

Wave 2 (blocked on 08-04 + 08-05):
- [ ] 08-06-PLAN.md — Reconcile docs: correct D-RECON-01 in 08-CONTEXT.md; flip REQUIREMENTS ANIM-02 to Complete
### Phase 9: NL Localisation Review

**Goal**: The Dutch localisation is validated by a native speaker in a gaming context — profanity wordlist and all 478 translations are correct, and the NL locale is clean in-game
**Depends on**: Phase 7 (in-game text surfaces fully visible with real art; Phase 8 not required)
**Requirements**: LOCALE-01, LOCALE-02, LOCALE-03
**Success Criteria** (what must be TRUE):

  1. A native Dutch speaker in a gaming context has reviewed and signed off on the profanity wordlist
  2. All ~478 NL msgid translations have been reviewed and any corrections applied by a native Dutch speaker
  3. The NL locale displays correctly in-game with no untranslated, truncated, or garbled strings across all surfaces (title, avatar creator, world select, FTUE, HUD, chat, modals)

**Plans**: TBD

## Progress

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 1. Foundation & mobile spike | v1.0 | 7/7 | Complete | 2026-05-25 |
| 2. World & building content | v1.0 | 17/17 | Complete | 2026-05-26 |
| 3. Survival loop | v1.0 | 13/13 | Complete | 2026-05-27 |
| 4. Multiplayer & seamless host failover | v1.0 | 11/11 | Complete | 2026-05-29 |
| 5. Safety, moderation & store readiness | v1.0 | 12/12 | Complete | 2026-05-29 |
| 6. First five minutes | v1.0 | 11/11 | Complete | 2026-05-30 |
| 7. Asset Integration | v1.1 | 4/4 | Complete   | 2026-06-01 |
| 8. Creature & Builder Animation | v1.1 | 5/6 | In Progress|  |
| 9. NL Localisation Review | v1.1 | 0/? | Not started | - |

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
