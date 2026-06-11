# Cubicraftia — Milestones

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
