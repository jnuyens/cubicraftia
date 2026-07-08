# Cubicraftia — Milestones

## v1.1 — Content & Polish

**Shipped:** 2026-07-08 (release build tagged `v1.1` on 2026-06-30)
**Phases:** 3 (Phases 7-9)
**Plans:** 14 (all complete)
**Tasks:** 19 (across 14 plans)
**Timeline:** ~3.5 weeks (2026-06-11 → 2026-07-04)
**Commits:** 220 since v1.0
**Files changed:** 3,554 (+47,158 / -1,455 — mostly committed art assets)
**Known deferred items at close:** hardware/operator/visual-pass gated (see STATE.md § Deferred Items, v1.1 block)

### Delivered

v1.1 makes Cubicraftia look and feel shipped. The art that was already drawn now appears in the live game, every creature and the player's builder animate through idle + locomotion, and the Dutch localisation carries a native-speaker sign-off. Beyond the three formal phases, a large wave of world and avatar polish landed: a MOUNTAIN biome with wavy snow caps, a spawn-showcase diorama (voxel lake, shipwrecks, landmark village), completed crafting recipes (axes, swords, tools), iterative box-minifig avatar work, and crash-guard fixes for null-PackedScene segfaults across spawners.

### Key Accomplishments

1. **Asset integration (Phase 7)** — Every 1×1 transparent placeholder stub replaced with real committed art: title hero composition (VRAM-optimised import), FTUE arrow + 4 storyboard panels, HUD heart icons, world thumbnails, avatar preset thumbnails via SubViewport capture. A headless GUT stub-detection harness scans all shipped `.tscn`/`.gd` for sub-200 B PNG references and stays green.
2. **Creature & builder animation (Phase 8)** — All three rig archetypes productionised into idle + locomotion: shader-wobble soft bodies (3 slime tiers + fish + ghost), quadruped wildlife (panda), and the rigid-piece / Meshy-avatar builder shared with humanoid hostiles. Desktop perf smoke PASS at 0.00085 ms/creature (1180× under the < 1 ms target); Tier-3 hardware benchmark deferred as explicit debt.
3. **NL localisation review (Phase 9)** — 552 msgid keys translated with a native Flemish speaker sign-off in `nl.po`; profanity wordlist corrected (3 typos, 10 false positives, 7 Flemish additions) with 7 GUT regression tests green. Avatar-creator Character section localised (Bouwer / Avonturier / Verkenner), grey-capsule preview replaced by a live SubViewport builder that re-renders on every selection, and a ScrollContainer fix made every section plus the footer reachable.
4. **World & avatar polish (out-of-phase)** — MOUNTAIN biome (terraced cliffs, wavy snow line, clouds around peaks), enriched spawn diorama, full crafting recipe set, textured rigged builder avatar, build-stamp version plugin, CI artifact retention tuning.
5. **Stability** — Null-guard crash fixes across crop/balloon/generic spawners eliminating engine segfaults on null `PackedScene`; all-platform builds green (the `v1.1` release tag).

### Archives

- `milestones/v1.1-ROADMAP.md` — full Phase 7-9 breakdown
- `milestones/v1.1-REQUIREMENTS.md` — ASSET / ANIM / LOCALE requirements with outcomes

---

## v1.0 — Public Release

**Shipped:** 2026-05-30
**Phases:** 6 (Phases 1-6)
**Plans:** 72 (all complete)
**Tasks:** ~145 (across 72 plans)
**Timeline:** 6 days (2026-05-24 → 2026-05-30)
**Commits:** 352
**LOC:** ~52k (GDScript + Go + SQL + PO + Markdown)
**Known deferred items at close:** 9 (see STATE.md § Deferred Items)

### Delivered

Cubicraftia v1.0 is a Lego-style brick voxel sandbox shipping on macOS, Windows, Linux, iOS, and Android. Players sign in, customise a builder avatar, complete a 4-step in-world tutorial, explore an infinite procedurally generated world (50 brick types × 18 colors, biomes, structures, day-night, rain), host 1-4-friend WebRTC P2P sessions with seamless 2-4s host failover, and use full UGC safety pipeline (mutual blocks, 3-surface reporting, profanity filter, COPPA parental consent, EULA + Privacy).

### Key Accomplishments

1. **Cross-platform engine + voxel + Lego brick stack** — Godot 4.6 (MIT) + Zylann/godot_voxel + glTF stud-anchor metadata; 5 platforms in CI matrix
2. **Infinite procedural world with 50-brick library** — multiple biomes, structures (villages/temples/shipwrecks/dungeons/mineshafts), WorldClock day-night, rain + rain-dance
3. **Event-sourced survival loop** — `Inventory.apply_event` foundation (extended for multiplayer in Phase 4), 5 hostile creatures, 6×8 inventory, 5 chest tiers, 2x2 + 3x3 crafting, bed respawn + dropped-item recovery
4. **WebRTC P2P multiplayer with seamless host failover** — Go signaling server (200-session cap, 4-peer per session, JWT-gated, HMAC-SHA1 TURN credentials), Supabase friends graph with `CHECK (user_a < user_b)` + RLS, deterministic local election (RTT EWMA + join-order tiebreaker), 2-4s handover validated by time-bounded GUT test
5. **Full UGC safety pipeline** — Global mutual blocks + 3-surface reporting (friends/chat/nameplate), LDNOOBW CC-BY-4.0 multilang profanity filter (en+nl+fr+es+de), COPPA email-plus parental consent (CSPRNG single-use 7-day TTL token, CRLF-safe SMTP), EULA + Privacy bundled markdown with SHA-256 re-acknowledge gate, store readiness suite (7 docs for App Store + Play Store)
6. **First-five-minutes onboarding** — Title screen replacing boot.gd, 5-part avatar creator (8 presets + Randomise + 3D SubViewport preview), world select with 5-world cap + thumbnails, UNSKIPPABLE 4-step FTUE walkthrough (find chest → take axe → mine tree → place plank), deep-link invite joiner skip via cubicraftia:// URI, Dutch localisation (478 msgids), 15-event onboarding telemetry (local-only, 10k FIFO cap)

### Audit

`.planning/milestones/v1.0-MILESTONE-AUDIT.md` — 11/11 requirements satisfied, 7/7 e2e flows PASS, 6/6 phases verified, Nyquist compliant.

### Archives

- `milestones/v1.0-ROADMAP.md` — full phase breakdown + key decisions + tech debt
- `milestones/v1.0-REQUIREMENTS.md` — all 11 DOC-* requirements validated
- `milestones/v1.0-MILESTONE-AUDIT.md` — integration check, cross-phase wiring, e2e flow verdicts
