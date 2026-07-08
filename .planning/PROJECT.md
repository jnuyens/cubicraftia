# Cubicraftia

> Splash-mockup: Lego-stijl logo, minifig-helden, Lego-dieren (varken, schaap, hond), drijvende eilanden, Lego-kasteel. (Werd door gebruiker geleverd als visuele richtlijn voor de art direction.)

## What This Is

Cubicraftia is een 3D game waarin de hele wereld gemaakt is van **bricks** (Lego-stijl onderdelen): terrein, **builders** (de poppetjes, spelers én vijanden), en alles wat je bouwt. Het combineert de procedureel oneindige wereld van Minecraft met echte brick-bouwmechaniek — onderdelen zoals bricks, plates, slopes, tiles en accessoires die op studs aansluiten, in plaats van enkel 1×1 kubussen. Je speelt alleen of samen met 2-4 vrienden over internet, met een creatieve modus en een survival-modus, op Mac, PC en mobiel.

> **Naam:** "Cubicraftia" is de **definitieve naam**, onder voorbehoud van trademark-clearance voor publieke release. Player-facing terminologie: brick / stud / builder. "Lego" of "Minecraft" verschijnen nooit in UI of docs.

## Core Value

**Het Lego-bouwgevoel in een Minecraft-achtige sandbox — alleen of met je vrienden.** De rijkere vormtaal van echte Lego (geen 1×1 cubes) maakt bouwen expressiever. Je begint solo, en wanneer een vriend joint groeit dezelfde sessie naar multiplayer — geen aparte modi.

## Current Milestone: v1.2 Multiplayer & Distribution

**Goal:** Take Cubicraftia from code-complete to actually-live and actually-downloadable. Deploy the multiplayer backend so friends connect over the internet, prove it works on real devices, and ship the game through direct download, a one-click join link, and both mobile app stores, with auto-update keeping every peer on the same build.

**Target features:**
- **Go-live multiplayer** — deploy the Go discovery/signaling server + coturn TURN/STUN + self-hosted Supabase on the existing Linux host (m1.linuxbe.com / cubicraftia.com) with TLS, DNS, and secrets management
- **Real-device validation** — discharge the 6 deferred multi-device WebRTC tests (host-failover SLA, relay badge, nameplates, freeze UI, NAT traversal)
- **Reliability hardening** — reconnect flows, connection-failure UX, session recovery, invite-link robustness
- **Desktop direct download** — signed, installable Mac / Windows / Linux builds (itch.io / GitHub Releases / own site)
- **Mobile app stores** — full submission pipeline (signed builds, store metadata/assets, IAP wiring) for Apple App Store + Google Play
- **One download link** — platform-auto-detecting landing page + "join my friend's session" flow
- **Auto-update** — version-match so multiplayer peers never mismatch

**Operator/legal prerequisites (user-provided, in parallel with the engineering):** root + DNS on the existing host, Apple Developer + Google Play Console enrollment, COPPA / EULA attorney sign-off (deferred from v1.0), signing credentials + backend secrets.

**Out of scope for v1.2:** combat/death animation polish, new multiplayer features (dream-view, voice chat), public lobbies / open discovery, audio pass.

## Requirements

### Validated (v1.0 shipped 2026-05-30)

- ✓ DOC-00 — Name/license/terminology/pricing/5 platforms/friends-only — v1.0
- ✓ DOC-01 — First five minutes (title, sign-up, avatar, world select, FTUE, EN+NL locale) — v1.0
- ✓ DOC-02 — Two-grid world (terrain cubes + stud bricks), biomes, structures, day-night, rain — v1.0
- ✓ DOC-03 — 50 bricks × 18-color palette, tools, palette UI — v1.0
- ✓ DOC-04 — Inventory 6×8 @ 64-stack, hotbar, 5 chest tiers, 2x2 inline + 3x3 workbench crafting — v1.0
- ✓ DOC-05 — Sandbox/survival modes, 5 hostile creatures, HP, death-drop + bed respawn, starter chest — v1.0
- ✓ DOC-06 — Accounts/friends/blocking, sessions 1-4, WebRTC P2P + 2-4s host failover, chat, host admin — v1.0
- ✓ DOC-07 — 5 platforms, 4-tier device matrix, mobile controls, TURN relay — v1.0 (Tier-3 Motorola benchmark deferred to operator)
- ✓ DOC-08 — Block/report 3 surfaces, profanity (LDNOOBW 5-lang), parental consent (COPPA email-plus), EULA + Privacy — v1.0
- ✓ DOC-09 — Deferred-list scope discipline — v1.0
- ✓ DOC-10 — Glossary lock (no "Lego" in player-facing UI) — v1.0
- ✓ ASSET — Committed art wired into every live scene; zero 1×1 placeholder stubs remain (title hero, FTUE arrow + storyboards, avatar preset thumbnails, world thumbnail, HUD hearts) — v1.1
- ✓ ANIM-01 — Shader-wobble soft bodies (3 slime tiers, fish, ghost) animate idle + movement — v1.1
- ✓ ANIM-02 — Quadruped wildlife (panda) animate idle + movement via the quadruped rig — v1.1
- ✓ ANIM — Rigid-piece / Meshy builder + humanoid hostiles animate idle + walk; all entities animate in-world — v1.1 (desktop perf smoke PASS 0.00085 ms/creature; Tier-3 hardware benchmark deferred)
- ✓ LOCALE-01 — Native Flemish speaker reviewed + signed off the profanity wordlist — v1.1
- ✓ LOCALE-02 — All NL msgid translations (552 keys) reviewed and corrected by a native speaker — v1.1

### Active (v1.2 Multiplayer & Distribution — in scope)

**Go-live multiplayer:**
- [ ] Deploy discovery/signaling server + coturn + Supabase on the existing Linux host with TLS/DNS/secrets
- [ ] Friends can find and connect to each other over the internet end-to-end
- [ ] Discharge the 6 multi-device WebRTC tests on real machines/networks
- [ ] Harden reconnect, connection-failure UX, session recovery, invite-link robustness

**Distribution:**
- [ ] Signed desktop builds (Mac/Windows/Linux) published for direct download
- [ ] Mobile store submission pipeline (signing, metadata, IAP) for Apple App Store + Google Play
- [ ] One platform-detecting download + join link
- [ ] Auto-update keeping peers on matching builds

_Requirements are finalized in REQUIREMENTS.md during this milestone's definition step._

### Future (candidates for the next milestone)

**Audio:**
- [ ] Title music track (silent placeholder ships in v1.0)
- [ ] Sound effects pass (mining, placing, pickup, mob, UI)

**Launch readiness (operator/legal):**
- [ ] Apple Developer Program + iOS code-signing credentials → enables `export_ios` CI job
- [ ] Google Play Console upload key + bundletool aab signing
- [ ] coturn TURN/STUN server deployment
- [ ] Supabase self-hosted deployment (currently dev-local)
- [ ] SMTP infrastructure for parental consent emails
- [ ] iOS Universal Links + Android App Links `.well-known` server config
- [ ] COPPA attorney review of email-plus parental consent
- [ ] EULA + Privacy attorney review for jurisdiction

**Hardware UAT discharge:**
- [ ] Phase 3 — 5 hardware items (ghost wall-pass, fire VFX, force-quit persistence, Motorola benchmark, sleep lapse)
- [ ] Phase 4 — 6 multi-device WebRTC tests (handover SLA, relay badge, nameplates, freeze UI, NAT traversal)
- [ ] Phase 6 — 4 live-device items (FTUE walkthrough, deep-link, 3D avatar preview, NL locale)

**Gameplay feature candidates (from backlog):**
- [ ] Phase 999.1 — Avatar customisation as gameplay progression (transformation pods, paint stations, hair-dye crops, pets, temporary abilities via rain dance)
- [ ] Combat/death animation polish (attack/hurt/death states — follow-on to v1.1 locomotion)
- [ ] Voice chat
- [ ] Public lobbies / open discovery
- [ ] Discord SSO
- [ ] Avatar mesh sculpted by artist (replacing programmatic primitives)

---

#### Original v1 requirements (all shipped — kept for archive)

**Account & sociaal:**
- [ ] Spelers maken een account aan (email + wachtwoord)
- [ ] Spelers stellen een avatar samen (Lego minifig: hoofd, lichaam, benen, accessoires) of kiezen uit presets
- [ ] Vriendensysteem: vrienden zoeken, uitnodigen, accepteren
- [ ] **Invite-by-link**: een speler kan een niet-vriend uitnodigen in een sessie; geaccepteerde uitnodiging maakt automatisch wederzijdse vrienden tot een van de twee unfriendt
- [ ] Sessies zijn vrienden-only (geen open lobbies); je speelt alleen of met vrienden/uitgenodigden

**Solo en multiplayer (één model, geen aparte modi):**
- [ ] Je start altijd een sessie als enige speler — als niemand joint, is dat singleplayer
- [ ] Wanneer een vriend joint, wordt dezelfde sessie multiplayer; mechanieken zijn identiek
- [ ] Sessies kunnen lokaal blijven (geen internet nodig voor solo) maar zijn ook online joinbaar door vrienden

**Multiplayer-architectuur:**
- [ ] Centrale discovery-server (Linux) doet matchmaking en NAT-traversal voor peer-to-peer
- [ ] Vriend met beste internet-connectie wordt host (in solo is de speler zelf host van zijn lokale sessie)
- [ ] Automatische host-failover naar volgende beste connectie als host wegvalt
- [ ] Discovery-server bevat geen game-state (privacy + lage hostingkosten)

**Wereld:**
- [ ] Hybride wereld: Minecraft-stijl terrein in grote blokken + Lego-stijl bouwen op studs (zoals Lego Worlds)
- [ ] Procedureel oneindige wereld
- [ ] Day/night-cyclus (zacht — mobs spawnen ook overdag in donkere plekken)

**Bouwsysteem (Lego):**
- [ ] Onderdelen-bibliotheek voor v1: bricks (1×1, 1×2, 2×2, 2×4...), plates, slopes, tiles, een paar wheels en minifig-accessoires
- [ ] Plaatsen: 1 onderdeel per actie, snapt op studs
- [ ] Tools voor sneller breken: drill, schop, dynamiet (verschillend bereik / snelheid)
- [ ] Onderdelen kunnen niet altijd kubus zijn — vormen, rotaties, kleuren

**Inventory:**
- [ ] 6×8 raster (48 vakjes)
- [ ] Max 64 onderdelen van hetzelfde type per vakje
- [ ] Drag-and-drop herordening, stacking, splitsen

**Items in de wereld:**
- [ ] Wanneer je iets hakt, opblaast met dynamiet, of een mob iets dropt: het item verschijnt als een verkleinde versie van zichzelf, zwevend in de lucht met een glow eromheen — zichtbaar 's nachts
- [ ] Item oppakken door erop te lopen of erlangs te bewegen
- [ ] Items verdwijnen na een redelijke tijd als ze niet worden opgeraapt (despawn-timer)

**Creative-modus:**
- [ ] Alle onderdelen onbeperkt beschikbaar
- [ ] Geen mobs, geen schade, geen honger
- [ ] Vliegen mogelijk
- [ ] Focus op samen bouwen

**Survival-modus:**
- [ ] Lego-twist op survival: resources zijn echte Lego-onderdelen die je vindt
- [ ] Hakken/breken levert onderdelen op (afhankelijk van wat je sloopt)
- [ ] Mobs moeten verslagen worden voor ze onderdelen droppen
- [ ] Crafting: combineer onderdelen om gereedschap, dynamiet, decoratieve items te maken
- [ ] Starter-pakket: elke speler begint met een Lego-kist en een Lego-bed, zodat de eerste nacht veilig overbrugd kan worden
- [ ] HP-systeem, dood = inventory drop op de plek waar je stierf

**Mobs:**
- [ ] Vijandelijke Lego-creaturen, opgebouwd uit bricks (skeletten, draken, monsters)
- [ ] Spawn meer 's nachts en in donkere plekken
- [ ] Drop verkleinde Lego-onderdelen wanneer verslagen
- [ ] Minimum 2-3 vijandige soorten voor v1

**Platforms:**
- [ ] Cross-platform speelbaar: Mac, PC (Windows + Linux?), mobiel (iOS + Android)
- [ ] Cross-play tussen platformen

### Out of Scope

- **Open lobbies / spelen met onbekende vreemden** — alleen vrienden of via expliciete uitnodiging; bewaakt sociale ervaring
- **Subscriptions / cosmetics-shop model** — éénmalige aankoop + optionele brick-packs alleen
- **Voice chat in v1** — kan later toegevoegd worden, niet kernfunctionaliteit
- **Modding / plugin systeem in v1** — code is open source, gevorderde users kunnen forken; officieel mod-systeem is post-v1
- **VR-modus** — buiten scope voor de eerste versie
- **PvP combat (vrienden tegen elkaar)** — focus op PvE en bouwen; PvP later overwegen
- **Officiële Lego-onderdelen 1-op-1** — we gebruiken brick-stijl onderdelen, niet de exacte Lego-bibliotheek (handelsmerk-risico)

## Context

**Inspiratiebronnen:**
- *Minecraft*: voor wereldgeneratie, day/night cyclus, mobs, inventory-conventies, survival-loop
- *Lego Worlds* (TT Games, 2017): voor het hybride concept (Minecraft-stijl terrein + echte Lego-bouwen)
- *Lego sets in het echt*: voor de onderdeelvariatie (slopes, tiles, plates) die meer expressie geeft dan kubussen

**Open source als principe:**
- Code is publiek vanaf dag 1 (licentie te bepalen, te overwegen: MIT, GPL, Apache-2)
- Geen monetisatie, gemeenschap drijft groei
- Architectuur moet duidelijk en bijdragenvriendelijk zijn
- Discovery-server hosting moet betaalbaar blijven (vandaar P2P-game-state)

**Doelpubliek:**
- Vriendengroepen (kinderen, tieners, volwassenen) die samen willen bouwen
- Spelers die Minecraft kennen maar de Lego-expressie missen
- Open-source / DIY gaming community

## Constraints

- **Tech stack:** Cross-platform vereist een engine met goede mobile-prestaties en open-source-compatibel ecosysteem (research-fase: Godot vs. Unity vs. eigen / Bevy etc.)
- **Multiplayer-architectuur:** P2P met variabele connecties betekent zorgvuldig netwerk-protocol; host-failover moet game-state synchroon overdragen zonder merkbare onderbreking
- **Performance:** Mobile performance is bottleneck — voxel + Lego-detail moet werken op gemiddelde telefoons
- **Open source licensing:** Alle dependencies moeten compatibel zijn met de gekozen licentie
- **Handelsmerk-risico:** Werknaam "LegoMinecraft" en visuele stijl moeten genoeg afwijken van LEGO/Minecraft om geen juridische problemen te krijgen vóór release
- **Hosting:** Discovery-server draait op één Linux-machine (in eerste instantie); architectuur moet horizontaal schaalbaar zijn voor latere groei
- **Doel-sessie-grootte:** 2-4 spelers per wereld, dus we hoeven geen massive-multiplayer-architectuur te bouwen

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Hybride wereld (Minecraft-terrein + Lego-bouw op studs) | Lego Worlds heeft dit beproefd; pure stud-grid is prestatie-onhaalbaar voor mobile; pure block-grid mist de Lego-expressie | — Pending |
| Open source (GPL-3.0) + €1/$1 one-time + optionele brick-packs IAP | Open-source ethos + financiering voor infra/maintenance; gratis codes voor familie/vrienden; geen progression-IAP | ✓ Locked |
| Player-facing terminologie: brick + stud + builder | Trademark-veiligheid; vermijdt "Lego" en "minifig" in UI/docs/marketing | ✓ Locked |
| License: GPL-3.0-or-later | Alle derivaten blijven open; voorkomt proprietary forks | ✓ Locked |
| v1 scope brede biomes + structuren + 5 mobs + host-failover | Bewuste keuze: ambitieus v1 dat het volle Cubicraftia-gevoel laat zien; risico op uitloop wordt aangenomen | — Pending |
| P2P met centrale discovery (host = beste connectie, failover) | Lage hosting-kosten; goede latency tussen geografisch dichtbij vrienden; discovery-server is licht | — Pending |
| Friends-only multiplayer (geen open lobbies) | Veiligere sociale ervaring; minder moderation-overhead; sluit aan bij doelgroep | — Pending |
| Solo = multiplayer-sessie met 1 speler (geen aparte modi) | Eén codebase, eén model voor wereld/sessie; vrienden kunnen altijd naadloos joinen | ✓ Locked |
| Invite-by-link maakt wederzijdse vrienden tot unfriend | Lage drempel om nieuwe spelers mee te laten doen, geen voorafgaande add-flow nodig | ✓ Locked |
| Beide modi (creative + survival) in v1, klein | Toont kerngameplay van beide kanten; survival heeft Lego-twist als onderscheidend punt | — Pending |
| Inventory 6×8, max 64 per vakje | Gebruiker-opgelegd; vertrouwd voor Minecraft-spelers maar net groter | ✓ Locked |
| Gedropte items zweven verkleind met glow | Speelse Lego-look; zichtbaarheid 's nachts vermijdt frustratie | ✓ Locked |

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `/gsd:transition`):
1. Requirements invalidated? → Move to Out of Scope with reason
2. Requirements validated? → Move to Validated with phase reference
3. New requirements emerged? → Add to Active
4. Decisions to log? → Add to Key Decisions
5. "What This Is" still accurate? → Update if drifted

**After each milestone** (via `/gsd:complete-milestone`):
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state

---
## Current State

**Milestone v1.1 Content & Polish SHIPPED 2026-07-08.** Phases 7-9 complete (14 plans). The drawn art is wired into every live scene (no placeholder stubs), all creatures and the builder animate via the three rig archetypes, and the NL locale carries a native Flemish speaker sign-off (552 keys). Release build tagged `v1.1` on 2026-06-30; all platforms green. Remaining v1.1 items are hardware/operator/visual-pass gated deferrals (Tier-3 animation benchmark, in-game NL screenshot pass) documented in STATE.md § Deferred Items.

**Milestone v1.0 SHIPPED 2026-05-30.** All 6 phases complete, all 11 DOC-* requirements validated, all 7 e2e flows verified, 11/11 cross-phase wiring checks pass.

**Codebase:**
- ~52k LOC across GDScript / Go / SQL / PO / Markdown
- 352 commits over 6 days (2026-05-24 → 2026-05-30)
- 6 phases, 72 plans, ~145 tasks
- Test suite: 40+ Phase 4 tests, full GUT scaffold across phases, Go signaling server `go test ./...` green

**Tech stack (locked):**
- Engine: Godot 4.6 (MIT)
- Voxel: Zylann/godot_voxel (MIT)
- Brick metadata: glTF 2.0 `extras` (stud-anchor implementation; `EXT_structural_metadata` deferred)
- Networking: WebRTCMultiplayerPeer (libdatachannel) + ENet LAN fallback
- Signaling: custom Go server (single binary, JWT-gated, 200-session cap, HMAC TURN credentials)
- TURN/STUN: coturn (BSD-3) on same host
- Auth + friends graph: Supabase self-hosted (GoTrue + Postgres + RLS)
- Persistence: SQLite per world via godot-sqlite with Zstd chunk compression + 30s snapshots

**Known deferred items at close** (see STATE.md § Deferred Items):
- 9 verification/UAT gaps split between hardware-gated UAT (Phases 3/4/6) and operator/legal prerequisites (Phase 5)
- All documented in `.planning/v1.0-MILESTONE-AUDIT.md` § Tech Debt
- None block code release

**Post-v1.0 work in flight:** ~56 commits of raw art + animation POCs landed after the v1.0 tag (procedural brick library, ~390-item art catalogue, creature meshes via TripoSR, avatar presets, HUD sprites, biome tiles, shader-wobble animation POCs). Milestone v1.1 formalizes and completes that work.

**Next:** Milestone **v1.2 Multiplayer & Distribution** started 2026-07-08 — deploy the live backend, validate + harden multiplayer, and ship via desktop download + mobile stores + one-link + auto-update. Phases continue from 9 → start at Phase 10.

---
*Last updated: 2026-07-08 after starting v1.2 milestone*
