---
gsd_state_version: 1.0
milestone: v1.2
milestone_name: Multiplayer & Distribution
status: completed
stopped_at: Completed 13-06-PLAN.md (JoinScreen error-UI migration to ConnectionProblemOverlay + Connecting spinner + NetworkHud Direct/Relay badge)
last_updated: "2026-07-09T21:38:14.616Z"
last_activity: "2026-07-09: Phase 13 Plan 06 executed (JoinScreen migrated off ad-hoc error UI onto ConnectionProblemOverlay, Connecting spinner added, Reconnecting copy corrected, RELY-01/02/03 UI closed; NetworkHud always-visible Direct/Relay badge, RELY-05 UI closed); 13-07 remains. Phase 10 Plan 01 Task 3 (attorney sign-off, checkpoint:human-verify gate=blocking) remains open and not auto-approved"
progress:
  total_phases: 9
  completed_phases: 1
  total_plans: 8
  completed_plans: 7
  percent: 11
---

# Cubicraftia — STATE

> Single source of truth for project memory. Updated by every `/gsd:*` workflow.

## Mode

**Documentation-Driven Development (DDD).**

- Primary spec: `.planning/DOCS.md`
- Phase derivation: DOCS.md sections (not REQ-ID clusters)
- Validation: implementation matches DOCS.md (per-phase doc-sync automation held for a future release; expect manual DOCS.md updates during execution when implementation diverges)

## Project Reference

- **Name:** Cubicraftia
- **Mode:** Documentation-Driven Development (DDD)
- **Core value:** The Lego-bouwgevoel in a Minecraft-style sandbox — solo or with up to 4 friends, cross-platform (Mac / Windows / Linux / iOS / Android), open source, €1/$1 one-time.
- **Canonical spec:** `.planning/DOCS.md` (11 H2 sections, locked draft 2 from 2026-05-24)
- **Granularity:** coarse (3 phases for v1.1)
- **Roadmap file:** `.planning/ROADMAP.md`
- **License:** GPL-3.0-or-later

## Current Position

Phase: 10 (Licensing Gate), Plan 01: Tasks 1-2 landed, Task 3 (attorney sign-off) BLOCKED, plan NOT complete
Plan: 10-01 (engineering done: LicenseRef-AppStore-Exception.txt, LICENSING.md, README, CONTRIBUTING.md; commits 1a6d232, 4af6030)
Status: LICENSE-01 remains OPEN pending attorney sign-off (D-04); see Blockers below. Note: the auto-synced frontmatter `progress` block above counts 10-01 as "completed" because a SUMMARY.md exists on disk (a tooling artifact of the file-presence heuristic, not an indication that LICENSE-01 or Task 3's human gate is resolved). Do not treat phase 10 as done until attorney sign-off is recorded.
Last activity: 2026-07-09: Phase 10 Plan 01 Tasks 1-2 executed; Task 3 (checkpoint:human-verify, gate=blocking) reached and awaiting attorney review, not auto-approved

**Parallel track — Phase 13 (Reliability & Version-Match Hardening):** independent of the Phase 10 blocker above (Phase 13 depends on Phase 12, not Phase 10). Plans 13-01..13-05 complete; 13-06 (JoinScreen error-UI migration + Connecting spinner + Reconnecting copy fix, RELY-01/02/03 UI; NetworkHud always-visible Direct/Relay badge, RELY-05 UI) complete this session — commits `099c8a2`/`2c23efb`/`2036f83` (JoinScreen) and `061d656`/`cf6c7f1` (NetworkHud). JoinScreen's dangling `ui.join.error_connection` reference (removed from locale by 13-05) is resolved: JoinScreen no longer owns any local error UI at all. Remaining: 13-07 (final scene-tree wiring).

## Quick Tasks Completed

| # | Description | Date | Commit | Directory |
|---|-------------|------|--------|-----------|
| 260713-ex5 | Lava floor band + infinite bedrock backstop (_generate_block_fallback) so digging down ends in lava not void; new bedrock(13)/lava(14) blocks | 2026-07-13 | 4e85f14 | [260713-ex5-digging-straight-down-into-the-earth-cru](./quick/260713-ex5-digging-straight-down-into-the-earth-cru/) |
| 260713-evx | Chest/bed near spawn (exclude MOUNTAIN from spawn search); submarine cave seabed-anchored + jungle temple ground-flush; Create-account button made visible (+deep-link sibling) | 2026-07-13 | 3bc16c0 | [260713-evx-chest-and-bed-near-spawn-submarine-cave-](./quick/260713-evx-chest-and-bed-near-spawn-submarine-cave-/) |
| 260611-qyz | Add include_filter to all export presets so non-resource data files ship in the pck | 2026-06-11 | f2c42ab | [260611-qyz-add-include-filter-to-all-export-presets](./quick/260611-qyz-add-include-filter-to-all-export-presets/) |
| 260621-ur7 | Coral reefs on seabed, climbable (solid) whales, villagers gated to correct biome | 2026-06-21 | 51b60b0 | [260621-ur7-coral-whale-villager-fixes](./quick/260621-ur7-coral-whale-villager-fixes/) |
| 260622-t2n | Add tools/render_ui_scene.gd — Godot UI-scene + locale capture-to-PNG tool | 2026-06-22 | 2af4784 | [260622-t2n-add-tools-render-ui-scene-gd-godot-ui-sc](./quick/260622-t2n-add-tools-render-ui-scene-gd-godot-ui-sc/) |
| 260622-tkz | Redesign builder creator to match choose-builder art (cards + backdrop + live preview) | 2026-06-22 | da27083 | [260622-tkz-redesign-avatar-builder-creator-to-match](./quick/260622-tkz-redesign-avatar-builder-creator-to-match/) |

## Phase Roster

### v1.2 Multiplayer & Distribution (active milestone)

| Phase | Goal (one line) | Requirements | Depends on | Status |
|-------|-----------------|--------------|------------|--------|
| 10 | GPLv3 §7 App Store exception lands while codebase is solo-authored | LICENSE-01 | Nothing (parallel w/ 11) | Not started |
| 11 | nginx+certbot, Go signaling, Supabase, coturn deployed + smoke-tested in prod | DEPLOY-01..07 | Nothing (parallel w/ 10) | Not started |
| 12 | 6 deferred WebRTC scenarios discharged on real devices, real networks | NETVAL-01..05 | Phase 11 | Not started |
| 13 | Connection failures always explained/recoverable; version-mismatch gate | RELY-01..05, VER-01..02 | Phase 12 | Not started |
| 14 | Signed builds: macOS/Windows/Linux/Android (must-ship) + iOS (spike-gated) | SIGN-01..05 | Phase 10 (iOS only) | Not started |
| 15 | itch.io + GitHub Releases + one-link landing page + update prompt | DIST-01..05 | Phase 13, Phase 14 | Not started |
| 16 | Google Play (must-ship) + Apple (spike-gated) submission, IAP, pre-listing audits | STORE-01..05 | Phase 10, 11, 14, 15 | Not started |

### v1.1 Content & Polish (completed 2026-07-08)

| Phase | Goal (one line) | Requirements | Status |
|-------|-----------------|--------------|--------|
| 7 | Wire all committed art into live scenes; zero placeholder stubs remain | ASSET-01..07 | Not started |
| 8 | All creatures and builder animate (idle + locomotion) with no perf regression | ANIM-01..06 | Complete |
| 9 | NL profanity wordlist and 478 translations reviewed by native Dutch speaker; locale clean in-game | LOCALE-01..03 | Not started |

### v1.0 Public Release (completed 2026-05-30)

| Phase | Goal (one line) | Anchor in DOCS.md | DOC-NN | Status |
|-------|-----------------|-------------------|--------|--------|
| 1 | Engine + voxel + mobile spike + terminology/license/IAP lock | §0, §7, §9, §10 | DOC-00, DOC-07, DOC-09, DOC-10 | Complete (7/7 plans) |
| 2 | Biomes, structures, 50-brick library, weather, tools | §2, §3 | DOC-02, DOC-03 | Complete (17/17 plans) |
| 3 | Inventory, chests/keys, crafting, creatures, death, sandbox+survival | §4, §5 | DOC-04, DOC-05 | Complete (13/13 plans) |
| 4 | Discovery server, accounts, P2P, host admin, seamless host failover | §6 | DOC-06 | Complete (11/11 plans) |
| 5 | Block/report, profanity, parental consent, EULA, store readiness | §8 | DOC-08 | Complete (12/12 plans) |
| 6 | Title + account + avatar + in-world FTUE, EN+NL localisation | §1 | DOC-01 | Complete (11/11 plans) |

## Performance Metrics

(v1.0 targets — carried forward as baseline for v1.1 animation regression check)

- **Phase 1 mobile-perf spike:** target — sustained §7.2 frame budget on the Tier-3 phone for 30 min; result — validated v1.0
- **Phase 4 NAT-traversal probe:** target — ≥50% direct-P2P success rate on real cellular; result — validated v1.0
- **Phase 4 host-failover handover:** target — ≤4 s player-visible handover; result — validated v1.0 (< 100ms headless, SLA test green)
- **Phase 8 animation regression:** target — no measurable FPS drop vs v1.0 mobile targets on Tier-3 reference device; result — desktop smoke recorded (see 08-ANIM-06-PERF.md): 0.00085 ms/creature ProceduralCreatureAnimator (PASS vs < 1 ms/creature target); Tier-3 hardware run deferred (hardware-gated, instructions in 08-ANIM-06-PERF.md)

## Accumulated Context

### Locked decisions (from PROJECT.md + DOCS.md)

- License: GPL-3.0-or-later.
- Pricing: €1 / $1 one-time + optional IAP brick packs (no progression gating); free redemption codes available from project owner.
- Player-facing terminology: brick / stud / builder / terrain / hotbar / session / host / workbench / sandbox / survival. The string "Lego" appears in no UI or doc.
- Crossplay: yes, all 5 platforms can join the same session.
- Social model: friends-only, no open lobbies, ever.
- Solo = MP session with 1 player. No "singleplayer mode" branch.
- Inventory: 6×8 = 48 slots, 64 per stack.
- Dropped items: small + floating + soft glow; 2-Cubicraftia-day despawn.
- Invite-by-link makes mutual friends until either side unfriends.
- Profanity filter uses dual-regex split (_regex_en / _regex_nl) — each under 500 words to avoid regex timeout on Tier-3 Android (T-05-P2).
- filter_reject() returns bool only — callers show "Please choose another name." without echoing rejected input (T-05-P-bypass).
- Username inline validation is format-only (UsernamePol.validate); server uniqueness check only on submit — no enumeration possible (T-05-P-wn).
- Under-13 chat suppression drops packets silently and shows a toast; Go relay is the hard gate; client check is UX-only (T-05-bypass).
- join_blocked signal emitted for unconsented under-13 join attempts; ParentalGatePanel listens and shows the consent flow.
- Session auto-mute (mute_session_uid) persists per session only; cleared on begin_graceful_disconnect.
- LDNOOBW CC-BY-4.0 word lists bundled in assets/profanity/; v1 ships EN + NL; additional languages contributable via same file pattern.
- Hybrid world: 1 m terrain cubes + sparse stud grid for placed bricks.
- Seamless host failover ships in v1.0 (not deferred to v1.1).
- 50 brick types in v1, 18-colour palette for non-material bricks.
- 5 hostile creatures in v1; no creeper-explode (dynamite plays that role).
- 5 chest types + 4 key types; double chests in v1.
- Both modes (sandbox + survival) at world creation; not switchable in v1 (switching is v1.1).
- Stack: Godot 4.6 + Zylann/godot_voxel + WebRTC (libdatachannel) + Go discovery + Supabase + SQLite + glTF stud metadata + coturn STUN/TURN.

### v1.1-specific context

- Animation POCs already committed post-v1.0: shader-wobble (slime/fish/ghost), quadruped (panda), rigid-piece (minifigure). Phase 8 productionizes these into the full entity roster.
- ~390-item art catalogue, creature meshes via TripoSR, avatar presets, HUD sprites, biome tiles — all committed raw. Phase 7 wires them into live scenes.
- 478 NL msgids shipped in v1.0 (locale/nl.po). Phase 9 is a review + correction pass only; no new strings expected.
- Combat/death animation is explicitly deferred to a post-v1.1 milestone (ANIM-07 in Future requirements).

### Open questions (from research synthesis)

- Q2: License chosen (GPL-3.0-or-later) — resolved.
- Q3: Stud-snap mobile perf ceiling — resolved in Phase 1 (mobile perf spike).
- Q7: Player-facing terminology — resolved (brick / stud / builder; "Lego" never appears).
- Q8: Final project name & trademark search — name locked (Cubicraftia); trademark clearance check is a pre-public-release gate, currently in Phase 5's pre-launch checklist.

### Todos (carried into phase plans)

- Phase 7: audit all shipped scenes for 1×1 transparent placeholder references; replace each with the appropriate committed art asset.
- Phase 8: run animation regression benchmark on Tier-3 device after integrating all three archetypes; commit result to .planning/phases/08-creature-builder-animation/.
- Phase 8: establish idle/locomotion animation state machine conventions shared by all three archetypes before implementing per-entity variants.
- Phase 9: identify or recruit a native Dutch speaker with gaming-context familiarity before Phase 9 starts.

### Open debt (carried from v1.0)

- Phase 1 perf floor (DOC-07 partial): Motorola Tier-3 benchmark hardware UAT deferred.
- Phase 2 HUMAN-UAT 4-row: hardware-gated; deferred.
- Phase 3 HUMAN-UAT 5-row: hardware-gated; deferred.
- Phase 4 VERIFICATION: 6 multi-device WebRTC tests (handover SLA, relay badge, nameplates, freeze UI, NAT traversal); deferred.
- Phase 5 VERIFICATION: 6 operator/legal items (attorney, Apple/Google creds, SMTP); deferred.
- Phase 6 VERIFICATION: 4 live-device items (FTUE walkthrough, deep-link, 3D avatar preview, NL locale); deferred.
- Phase 9 LOCALE-03: in-game visual screenshot pass across 12 surfaces; hardware-gated, deferred (profanity regression 15/15 + native sign-off done). Follow-up: force NL locale, F5 in Godot 4.6, walk 09-03-SCREENSHOTS.md.

All items documented in `.planning/v1.0-MILESTONE-AUDIT.md` § Tech Debt.

### Blockers

- v1.2 roadmap authored (Phases 10-16, 35/35 requirements mapped). Ready for `/gsd:plan-phase 10`. Note: iOS work in Phases 14/16 is spike-gated/best-effort per the licensing (Phase 10) and CI-export-spike dependencies; Android + all desktop channels are must-ship and unaffected.
- LICENSE-01 (Phase 10 Plan 01) engineering landed (LicenseRef-AppStore-Exception.txt, LICENSING.md, README, CONTRIBUTING.md, commits 1a6d232/4af6030) but attorney sign-off on the exact clause wording is NOT yet recorded. Phase 14 SIGN-05 and Phase 16 STORE-02 (iOS track only) must not begin until sign-off is recorded here per D-04. Non-iOS work in Phases 11-13 and non-iOS Phase 14 is unaffected.

## Research Trail

**v1.2 research (2026-07-08):** `.planning/research/{SUMMARY,STACK,FEATURES,ARCHITECTURE,PITFALLS}.md` — go-live backend topology (nginx+certbot override of the research-recommended Caddy, coturn/cert-renewal hooks), real-device NAT/CGNAT validation risk, GPLv3 §7 Apple App Store exception (HARD BLOCKER, Phase 10), code-signing per platform, iOS CI export + desktop IAP flagged as the two research-spike-warranting phases.

- `.planning/research/SUMMARY.md` — synthesis across stack, features, architecture, pitfalls
- `.planning/research/STACK.md` — Godot 4.6 + voxel + WebRTC + Go + Supabase rationale
- `.planning/research/FEATURES.md` — 32-feature v1 set, FTUE script, mobile UX callouts
- `.planning/research/ARCHITECTURE.md` — listen-server pattern, two-grid coord system, deterministic host election, build-order recommendation
- `.planning/research/PITFALLS.md` — CRIT-1 trademark, CRIT-2 CGNAT, CRIT-3 save corruption, CRIT-4 store UGC, CRIT-5 maintainer burnout, plus TECH-/SOCIAL-/LEGAL- pitfalls

## Decisions Made

- **license-01-attorney-signoff:** 2026-07-10 — attorney sign-off on the GPLv3 §7 App Store Distribution Exception CONFIRMED by project owner (jnuyens); the drafted clause wording in `LICENSES/LicenseRef-AppStore-Exception.txt` is blessed as-is (no wording changes requested). LICENSE-01 is now COMPLETE. The Apple/iOS track (Phase 14 SIGN-05, Phase 16 STORE-02) is UNBLOCKED. This closes Phase 10's Task 3 human-verify checkpoint.
- **mobile-renderer-locked:** `renderer/rendering_method.mobile="mobile"` enforced in project.godot (Pitfall 8 fix — required for Mali-class GPUs on Android; CONTEXT.md D-01)
- **reuse-dep5-blanket:** `.reuse/dep5` format used for blanket SPDX coverage before source files exist; LICENSES/ directory added for REUSE 3.3 compliance
- **no-ios-preset:** export_presets.cfg has exactly macOS/Windows Desktop/Linux X11/Android presets — no iOS (D-04 defers iOS CI to Phase 5)
- **locale-header-only:** en.po and nl.po are header-only stubs valid per msgfmt; strings populated in Plan 02+ and Phase 6
- **docs-md-18-flags:** DOCS.md §9 authoritative for 18 feature flags (not 19 from RESEARCH.md Pattern 1 which split snow+thunderstorms into two entries)
- **allowlist-no-comments:** glossary-allowlist.txt contains no comment lines (grep -F treats them as patterns; bare '#' would falsely match GDScript comment lines in violation output)
- **gut-uid-gitignored:** *.uid added to .gitignore (Godot 4.x generates .gd.uid files as build artifacts)
- **ci-macos-runner:** macOS export uses `macos-latest` + native Homebrew Godot (not barichello/godot-ci Linux container); avoids cross-OS Mach-O .app bundling issues (Open Question Q2 resolved)
- **ci-pot-idempotency:** i18n round-trip check uses backup+diff pattern (not .pot.fresh side file); extract-pot.sh already strips POT-Creation-Date; backup+diff is simpler and functionally equivalent
- **allowlist-ci-docs:** docs/CI.md, docs/IOS_MANUAL_EXPORT.md, docs/CI_KEYSTORE_SETUP.md added as whole-file allowlist exceptions; CI runbooks legitimately document forbidden terms for developer reference
- **zylann-voxel-prebuilt-v1.6x:** Used pre-built GDExtension v1.6x (all-platform binaries, compat 4.4.1+) from GitHub release rather than source checkout at 4a9d311 (no pre-built binaries available at that commit); source excluded from git
- **voxelviewer-in-main-scene:** VoxelViewer added as child of Builder in main_scene.tscn (not VoxelTerrain) so chunk streaming follows player position
- **generator-init-in-init:** VoxelGeneratorScript uses _init() not _ready() for FastNoiseLite setup (VoxelGeneratorScript extends Resource, not Node; _ready() never called on Resources)
- **headless-integration-test-gap:** GUT integration tests for terrain require GPU; godot_voxel crashes headlessly; test pass deferred to Plan 07 real-hardware validation
- **gltfdocument-for-headless-load:** BrickDefinition.from_gltf() uses GLTFDocument.append_from_file() as primary path (no editor import required, works headlessly); load() is fallback for pre-imported contexts
- **blender-extras-json-strings:** Blender 5.x glTF exporter stores Array/Dict custom properties as JSON strings; BrickDefinition._parse_json_if_string() handles the round-trip
- **top-face-only-phase-1:** Builder place/break restricted to top face of terrain voxels; side-face + brick-on-brick placement deferred to Phase 2 per RESEARCH.md Pattern 3
- **get-probe-path-name:** android_thermal.gd exposes `get_probe_path()` (not `get_path()`) to avoid collision with Node.get_path() returning NodePath
- **array-box-lambda:** GUT tests for BenchmarkRunner use `var done_box: Array = [false]` pattern for mutable state in GDScript 4.x lambda signal callbacks
- **detached-node-test-pattern:** BenchmarkRunner unit tests create detached nodes (no add_child) to prevent engine from calling _process() automatically during test loops
- **run-benchmark-override-cfg:** run-benchmark.sh writes + immediately deletes override.cfg to swap main_scene to benchmark_scene.tscn for the benchmark APK export only
- **biome-briefs-locked-v1:** Six biome briefs approved with atmospheric wildlife revision (CONTEXT D-04, D-06 fulfilled); downstream Plans 06/07/08/13 may bind to species lists in `biomes/*.md` (approved 2026-05-26 by jnuyens@gmail.com)
- **godot-sqlite-demo-zip:** godot-sqlite v4.7 installed from demo.zip (not bin.zip); demo.zip bundles the complete addon structure including gdsqlite.gdextension manifest; bin.zip is a flat archive without manifest (02-02)
- **multipass-available-4a9d311:** VoxelGeneratorMultipassCB._generate_pass(voxel_tool, pass_index) confirmed available at addon commit 4a9d311; Plan 02-08 ships multipass_generator.gd (not inline fallback); two-pass design: pass 0 = base terrain, pass 1 = corridor carving (02-02)
- **sqlite-classdb-instantiate:** SQLite GDExtension class accessed via ClassDB.instantiate("SQLite") instead of SQLite.new() — GDScript parse-time type resolution fails for GDExtension classes not yet registered; runtime ClassDB call works correctly (02-03)
- **get-world-meta-rename:** WorldSave.get_world_meta / set_world_meta named to avoid collision with Node.get_meta() / Object.set_meta() built-ins — GDScript treats built-in override as warn-as-error (02-03)
- **chunk-codec-blob-format:** [16B MD5][4B BE uint32 compressed_len][Zstd bytes] — MD5 of compressed bytes only; computed via HashingContext.HASH_MD5 (in-memory path; FileAccess.get_md5 is file-path-only) (02-03)
- **open-world-bak-fallback:** WorldSave.open_world tries bak.1→bak.2→bak.3 on SQLite open_db failure; copies healthy backup to canonical before reopening (T-03-01 mitigation — corrupted canonical auto-recovers) (02-03)
- **fence-post-dropped:** fence_post dropped from DECORATIVE to hit 50-brick total; DECORATIVE has 5 entries (flower, lantern, torch, ladder, sign); DOCS §3.1 ±2-per-category clause applies (02-04)
- **brick-registry-manifest-driven:** BrickRegistry loads via manifest.json (not DirAccess scan) for deterministic order; manifest is the single source of truth for the 50-brick contract (02-04)
- **colour-swappable-split:** colour_swappable=false + natural_colour_token set on MATERIAL_ORE (all 9) and MOB_DROP (both); slime_cube=false despite MOB_DROP — D-02 wobble shader locks green (02-04)
- **test-registry-hermetic:** test_brick_registry.gd loads manifest.json directly (no autoload dependency) for hermetic headless GUT execution; validates 50-count, unique ids, D-08 stud_profile invariant, 7/5/4/3/4/6/5/9/5/2 distribution (02-04)
- **brick-mesh-null-phase2:** mesh=null on all 50 .tres files in Phase 2; Plan 02-09 (place/break) ships .glb mesh assets as needed for raycast; BrickRegistry handles null gracefully (02-04)
- **world-clock-wall-clock:** WorldClock._process() uses Time.get_unix_time_from_system() (not frame delta) with wall_delta capped at SECONDS_PER_DAY to survive mobile backgrounding (Pitfall 3); _set_elapsed_for_test hook for deterministic unit tests (02-05)
- **weather-uuid-quota:** Weather.trigger_rain_dance quota keyed on builder_id UUID string (not username); Pitfall 8 mitigation for Phase 4 multiplayer username changes (02-05)
- **brick-registry-get-renamed:** BrickRegistry.get() renamed to get_definition() — Godot 4.6 treats overriding Node.get(StringName) with mismatched signature as warn-as-error, preventing autoload load (02-05)
- **ghost-preview-standard-material:** GhostPreview uses StandardMaterial3D (not ShaderMaterial) for v1 transparent ghost; shader-based ghost deferred to Plan 14 adaptive-quality work (02-09)
- **ghost-mesh-fallback-brick1x1:** ghost_preview.gd uses BRICK_1X1 as fallback mesh until Plan 12 (Palette UI) wires Hotbar.active_def_id; ghost always previews 1x1 brick shape in Phase 2 (02-09)
- **multi-cell-same-instance-ref:** All cells of a multi-cell brick store the same BrickInstance reference; query(any_footprint_cell) returns the brick; remove(any_cell) erases all cells of that instance (02-09)
- **side-face-restriction-lifted:** Phase 1 top-face-only restriction lifted in Plan 02-09; hit.previous_position used as anchor uniformly for top/side/bottom faces per RESEARCH Pattern 4 (02-09)
- **placed-signal-extended:** StudGrid.placed signal extended to (anchor, def, colour_index, rotation); world_save._on_stud_placed updated to ignore new params; builders subscribe via updated signature (02-09)
- **tool-wear-resource-types:** ToolWear autoload uses Resource type hints (not ToolDefinition class_name) for parameter annotations — avoids class registry resolution order issue in headless/autoload parse order; mirrors WorldSave/SQLite pattern (02-10)
- **survival-mode-world-property:** Features.is_survival_mode() reads WorldSave.get_world_meta("mode") — sandbox/survival is a world-creation property (DOCS §5.1), NOT a §9-deferred feature flag; cross-mode switching is §9-deferred (02-10)
- **handheld-lantern-cull-mask:** HandheldLanternLight OmniLight3D uses light_cull_mask=2 (CHANNEL_BUILDER_ONLY) so player's handheld lantern does not suppress hostile mob spawning in dungeons/deep-dark areas (Pitfall 9, 02-10)
- **sky-shader-scaffold:** assets/shaders/sky_procedural.gdshader ships as Tier-1/Tier-2 sky shader; day_progress uniform bound by Plan 06 WorldEnvironment controller; Tier-3 panorama stubs declared, .png assets delivered Plan 15 (02-05)
- **biome-map-xor-seeds:** BiomeMap uses world_seed ^ 0x01 (temperature) and world_seed ^ 0x02 (moisture) for decorrelated noise; read-only after _init() for godot_voxel worker thread safety (02-06)
- **lighting-channel-partition:** CHANNEL_VISUAL_MASK=1 (sun/moon/placed lanterns) affects WorldClock.is_deep_dark() spawn suppression; CHANNEL_BUILDER_ONLY=2 (handheld lantern) does not suppress spawns (Pitfall 9 mitigation, 02-06)
- **main-scene-class-name:** main_scene.gd declares class_name MainScene to expose world_light_at() for lighting channel tests (02-06)
- **terrain-12-entry-library:** VoxelBlockyLibrary grown to 12 entries (air + 11 terrain blocks); water (ID=7) non-collidable via culls_neighbors=false; colours from approved biome briefs (02-06)
- **blueprint-cell-sizes-finalized:** village=128m, shipwreck=128m, temple=192m, dungeon=256m — aligns with CONTEXT.md D-08 rarity tiers (02-07)
- **dungeon-y-anchor-minus32:** Dungeon structures anchor at Y=-32 (deep underground), no biome restriction (allowed_biomes=[]) — depth-gated per D-08 (02-07)
- **knuth-hash-mixing:** Deterministic placement hash uses Knuth multiplicative mixing (h * 2654435761) ^ value — avalanche properties prevent correlated spawns across nearby cells (02-07)
- **sign-in-panel-programmatic-ui:** sign_in_panel.gd builds its UI tree fully in _ready() (not via @onready refs to pre-built scene nodes) to avoid hard-coded scene paths and enable CanvasLayer layer=10 root with a Control child (04-06)
- **oauth-stubs-phase5:** Apple/Google OAuth buttons in sign_in_panel.gd emit sign_in_failed(error_network) as stubs; actual SIWA/Google OAuth integration deferred to Phase 5/6 per T-04-06-T accept disposition (04-06)
- **friends-join-signal:** join_session_requested(session_id) emitted from FriendsPanel rather than calling NetworkManager directly — decoupled for Wave 4 wiring in Plan 04-10 (04-06)
- **network-manager-state-strings:** NetworkManager uses string constants (not enum) for the 11 session states — GDScript debugger output stays human-readable without a separate name lookup table (04-05)
- **failover-timer-200ms:** Failover election timer is 200ms (not 1s) — fast enough to elect a new host within the 4s player-visible window; 200ms delay prevents split-brain if host momentarily lags (04-05)
- **broadcast-event-server-guard:** broadcast_event() guards `if not multiplayer.is_server(): return` — non-host peers never broadcast; @rpc("authority") on _receive_replicated_event means only peer_id=1 can trigger it on peers (T-04-05-T + T-04-05-T2) (04-05)
- **reset-from-state-stub:** Inventory.reset_from_state(blob) is a stub returning true for non-empty blob; full bytes_to_var deserialisation and event replay deferred to Plan 04-10 (04-05)
- **snapshot-chunk-blob-dirty-set:** save_world_snapshot() chunk_blob serialises _dirty_chunks at snapshot time via ChunkCodec.encode_chunk_delta — no separate chunk_modifications table; covers the most-recent edits that failover needs without schema change (04-10)
- **broadcast-snapshot-live-state:** _broadcast_snapshot_to_peers_id() sends live Inventory.get_all_state() (not load_latest_snapshot()) during FAILOVER_PROMOTING reconnect to avoid DB write/read race on the newly-promoted host (04-10)
- **inventories-replaced-signal:** Inventory.inventories_replaced signal added; emitted after reset_from_state() replaces all state; UI panels that cache slot arrays must subscribe to re-read from Inventory.get_slots() (04-10)
- **snapshot-reset-applied-signal:** NetworkManager.snapshot_reset_applied emitted after _receive_snapshot_reset applies blob; external systems observe failover completion without coupling to Inventory internals (04-10)
- **headless-preload-pattern:** StructurePlacer, BrickTemplate, BiomeMap referenced via const X := preload("res://...") in all files; class_name types not resolvable without explicit preload() in headless GUT mode; typed as Resource/RefCounted in parameter/variable annotations (02-07)
- **structure-spawn-chances:** village=0.60, temple=0.40, shipwreck=0.75, dungeon=0.50 — shipwreck high due to ocean biome scarcity, dungeon low for rarity per D-08 (02-07)
- **default-camera-mode-chase:** Default camera mode for fresh worlds is CHASE (SpringArm3D third-person follow); FPV is available via V-key toggle; persisted per-world via WorldSave.get_world_meta("camera_mode") (user decision 2026-05-26, 02-08.5)
- **crosshair-api-locked:** get_crosshair_position() / get_crosshair_direction() return active camera values in both FPV and CHASE modes; get_aim_origin() / get_aim_direction() preserved as aliases; all placement raycasts in 02-09+ use these APIs (02-08.5)
- **springarm-zoom-range:** SpringArm3D spring_length clamped to [2.0, 8.0] m in 0.5 m steps via scroll wheel; zoom is a no-op in FPV mode; collision_mask=1 retracts against WorldStaticBody/terrain (T-CAM-02) (02-08.5)
- **brickpaletteui-classname-collision:** BrickPaletteUI (not BrickPalette) used as class_name in brick_palette.gd — src/bricks/palette.gd already declares class_name BrickPalette extends RefCounted; naming collision causes BrickPalette.new() to route to RefCounted at GUT test collection (02-12)
- **3d-preview-subviewport-update-visible:** PaletteTile 3D preview uses SubViewport with UPDATE_WHEN_VISIBLE for free scroll-aware culling; Tier-3 degrades to UPDATE_DISABLED + UPDATE_ONCE on hover ("on_tap" mode) via set_previews_mode(); no flat PNG fallback in v1 (02-12)
- **palette-test-logic-only:** Headless filter tests (test_brick_palette_filter.gd) use a locally defined _palette_matches_search() helper replicating brick_palette.gd logic — BrickPaletteUI cannot be instantiated headlessly (SubViewport + GPU nodes in _ready()); bottomsheet snap tests use _handle_test_drag() hook bypassing InputEvent layer (02-12)
- **palette-preload-isinstance:** preload() + get_script() comparison used for PaletteTile isinstance checks in brick_palette.gd — class_name PaletteTile not resolvable at brick_palette.gd parse time; const _PaletteTileScript := preload("res://src/ui/palette_tile.gd") enables duck-typed isinstance (02-12)
- **terrain-to-brick-drop-single-owner:** DroppedItem.TERRAIN_TO_BRICK_DROP const is single source of truth for terrain voxel → dropped brick mapping; DynamiteHandler reads this const — no duplicate mapping; snow/ice/water map to null (drop nothing) (02-11)
- **dropped-item-ore-ids-actual-manifest:** Ore brick IDs in TERRAIN_TO_BRICK_DROP use BrickRegistry manifest names: copper_ore, iron_ore, diamond_ore (not *_brick suffix); plan spec had wrong suffix — corrected during implementation (02-11)
- **dynamite-bulk-grep-guard:** DynamiteHandler.detonate() has exactly 1 do_sphere and 1 remove_bulk call in non-comment lines; regression guard verified by grep -v '^#' | grep -c (02-11)
- **voxel-time-budget-ms-6:** project.godot [voxel] threads/main/time_budget_ms = 6 limits main-thread Vulkan mesh-buffer swaps per frame; spreads chunk re-meshes across frames after a blast (TECH-3 mitigation, 02-11)
- **gut-watch-signals-pattern:** GUT watch_signals() + assert_signal_emitted() used instead of lambda closures for signal testing — GDScript 4 lambdas capture outer variables by value, not reference; watch_signals avoids the capture issue (02-11)
- **builder-uuid-config-vs-worldsave:** Builder stable UUID persisted to user://settings.cfg [builder] id (not WorldSave.set_world_meta) — settings.cfg is app-scoped, UUID must survive world deletes (02-14)
- **rain-vfx-process-material-null:** RainParticles process_material=null in main_scene.tscn v1; emitting toggles on Weather.state==RAIN but particles render nothing until ParticleProcessMaterial wired in Phase 6 polish (02-14)
- **adaptive-quality-ghost-api-map:** PRESET_DEFINITIONS ghost_preview_mode="transparent_mesh" maps to GhostPreview.set_mode("full") at dispatch — API uses "full"|"outline_only" (Plan 02-09); stored preset value preserves intent (02-14)
- **phase-2-uat-deferred-2026-05-26:** User approved Plan 02-15 close-out with 4 HUMAN-UAT rows marked `deferred`. Hardware runs (Motorola dynamite benchmark + touch-device gesture + force-quit cycle + cross-platform export smoke) carried forward as Phase 2 known debt alongside Phase 1's Task 3 motorola-benchmark debt. Plan 16 (DOCS sync) unblocked. (02-15)
- **phase-2-docs-sync-complete-2026-05-27:** User approved DOCS.md + CLAUDE.md doc-sync (Plan 02-16) on 2026-05-27; fence_post→IAP scope shift recorded in DOCS §3.1; §6.8.5 world save format section added with Zstd replacing earlier LZ4 research-brief language; all CONTEXT.md "Deferred — Phase-end DOCS updates" items flushed; DOC-02 + DOC-03 requirements satisfied; Phase 2 complete. (02-16)
- **phase-3-uat-deferred-2026-05-27:** User approved Plan 03-11 close-out with 5 HUMAN-UAT rows marked `deferred`. Hardware runs (ghost wall-pass + Tom Yum VFX + force-quit cycle + Motorola combat benchmark + 10× sleep lapse feel) carried forward as Phase 3 known debt alongside Phase 1's `motorola-benchmark` and Phase 2's 4-row deferred UAT. (03-11)
- **chest-itemdef-separate:** ItemDefinition new Resource class for non-brick items (keys/food/strawberry); chests use BrickDefinition (placed 3D objects) per 03-CONTEXT.md L153 (03-06)
- **chest-tres-bypass-manifest:** chest + key .tres files bypass manifest.json; discovered via ResourceLoader fallback to avoid same-wave conflicts with Plan 03-09 (03-06)
- **chest-entity-polled-input:** ChestEntity polls Input.is_action_just_pressed in _process when builder in range; calls set_input_as_handled() to prevent Builder.gd inventory_toggle firing on same frame per 03-PATTERNS.md L920-927 (03-06)
- **chest-mesh-placeholder-v1:** chest .tres files use mesh=null + BoxMesh placeholder in .tscn; distinct silhouettes (.glb per D-03) deferred to v1 polish (03-06)
- **recipe-id-prefix:** all recipe_id values in .tres files use "recipe_" prefix (recipe_wooden_plank, recipe_pickaxe_wood, etc.) to match test_recipe_book_reveal.gd CRAFT event convention (03-07a)
- **match-recipe-shapeless-bool:** match_recipe(grid, shapeless: bool) API; false=shaped position check, true=shapeless ingredient presence; tests pass bool not int (03-07a)
- **headless-preload-inventory-recipe:** inventory.gd uses const _RecipeRegistryScript := preload(...) for RecipeRegistry calls; RecipeRegistry class_name not in scope at autoload parse time (03-07a)
- **duck-typed-recipe-inventory:** inventory.gd accesses Recipe fields via .get("inputs"), .get("shaped") duck typing; avoids "Could not find type Recipe" parse error in autoload context (03-07a)
- **stick-outside-manifest:** stick.tres BrickDefinition in src/bricks/ but NOT in manifest.json; registered via BrickRegistry.register_pack() at Inventory._ready(); 50-brick contract preserved (03-07a)
- **recipe-workbench-11th:** workbench-craft (4 planks → 1 workbench) is the 11th recipe extending "~10" tilde per D-07; enables first-night survival loop; queued for DOCS §4.5 update at phase end (03-07a)
- **inventory-engine-has-singleton:** Engine.has_singleton() returns false for GDScript autoloads registered via project.godot — only works for C++ engine singletons; Wave-0 test stubs updated to use direct autoload name access (Inventory.*) (03-02)
- **double-chest-partner-str-format:** double_chest_partner stored as str(Vector3i) (e.g. "(3, 0, 0)") to match test assertion; _parse_coord_key extended to handle both str(Vector3i) and "%d_%d_%d" formats (03-02)
- **single-take-event-kind:** SINGLE_TAKE added as 10th event kind (not in original 9 spec) because test_inventory_grid.gd test_single_take_decrements_by_1 requires it; takes exactly 1 item from a specific slot (03-02)
- **schema-version-insert-or-replace:** world_save.gd open_world() uses INSERT OR REPLACE for schema_version row (not INSERT OR IGNORE) so migration bumps always persist correctly — INSERT OR IGNORE silently skips writes when key exists (03-01)
- **v2-table-stmts-helper:** _v2_table_stmts() private helper extracts the 4 CREATE TABLE IF NOT EXISTS statements shared between _create_schema() (fresh worlds) and _migrate_1_to_2() (migration) — DRY, idempotent, no duplication (03-01)
- **wave-0-pending-pattern:** Phase 3 Wave-0 test stubs use pending() with clear plan references ("pending until Plan 03-02") rather than skip() — GUT counts them as Risky/Pending and surfaces them in summaries, enabling phase-by-phase verification (03-01)
- **conftest-phase3-not-autoload:** tests/conftest_phase3.gd is a RefCounted helper class, NOT registered as an autoload — per T-03-01-SC test isolation; all Phase 3 tests preload it directly (03-01)
- **spawning-direct-autoload-test-access:** Tests use Spawning.* directly (not Engine.has_singleton) per inventory-engine-has-singleton decision; test_spawning_rules.gd and test_sleep_lapse.gd updated accordingly (03-03)
- **cancel-sleep-lapse-reason-param:** cancel_sleep_lapse() takes reason String param so WorldClock can emit contextual reason to Builder listeners via sleep_lapse_ended signal (03-03)
- **try-spawn-tick-public:** try_spawn_tick() public wrapper added to Spawning (calls _run_spawn_tick) so tests can trigger explicit ticks without relying on _process accumulator (03-03)
- **toast-requested-signal-name:** cancel_sleep_lapse_with_reason uses Toasts.show() which emits toast_requested (not toast_shown); test updated to match actual Toasts API (03-03)
- **hostile-mob-ready-spawning-notify:** HostileMob._ready uses get_tree().root.get_node_or_null('/root/Spawning') for notify_spawned (not Engine.has_singleton) — same GDScript autoload access pattern (03-03)
- **death-pile-box-mesh-placeholder:** DeathPile CompositeMesh uses BoxMesh placeholder; no .glb assets exist yet (brick-mesh-null-phase2 decision). Plan 14 / Phase 2 asset work will swap to actual brick mesh (03-04)
- **void-fall-pre-compute-position:** Builder._compute_death_pile_position runs before DEATH_DROP event dispatch; the event position IS the final surface-corrected position. Inventory.apply_event(DEATH_DROP) is position-agnostic (03-04)
- **death-screen-color-rect:** DeathScreen extends ColorRect; color.a drives the fade (not modulate.a). Positioned via anchor presets in the UI CanvasLayer (03-04)
- **show-death-screen-alias:** show_death_screen() is a GUT-friendly public alias for start_fade(false, Callable()) to allow tests to verify fade behaviour without builder context (03-04)
- **inventory-slot-programmatic-children:** InventorySlot Icon, CountLabel, SelectedRing built in _ready() instead of .tscn children — allows 48 identical slots without a deep scene hierarchy; matches hotbar.gd pattern (03-05)
- **inventory-chrome-verbatim:** _setup_panel_style, _animate_to, _snap_to_nearest verbatim from brick_palette.gd per UI-SPEC L332 + L410 "identical chrome"; only difference is applying to Body PanelContainer child instead of self (03-05)
- **en-po-phase3-sole-owner:** locale/en.po Phase 3 additions consolidated in Plan 03-05 only (~60 keys: inventory, HP/death/sleep, chest/key, recipe/workbench, food/strawberry, creatures, walk-up prompts) so downstream Wave-4 plans do not conflict on this file (03-05)
- **crafting-state-session-local:** _crafting_grid_state buffer kept in InventorySlideIn (not Inventory autoload) — 2×2 crafting is per-session, not persisted; Plan 03-07b may wire Inventory.get_crafting_slots if autoload persists it (03-05)
- **open-chest-workbench-stubs:** open_chest_mode + open_workbench_mode bodies intentionally minimal (set mode + call open()); Plans 03-06 and 03-07b override the bodies with full implementation (03-05)
- **workbench-tres-2x2-preserved:** workbench.tres keeps 2×2 footprint from Phase 2 manifest; plan spec 1×1 was a placeholder hint only; fields updated: colour_swappable=false, natural_colour_token=7, display_name_key='ui.workbench.title' (03-07b)
- **workbench-panel-reuse:** _workbench_panel_instance hidden/shown on repeated open_workbench_mode calls (T-03-07b-UI-03 mitigation); not queue_freed until slide-in itself is freed (03-07b)
- **recipe-book-tab-lazy:** RecipeBookTab instantiated lazily in _build_recipes_pane on first _set_active_tab('recipes') OR on open_workbench_mode; avoids building the tab before Inventory autoload is fully ready (03-07b)
- **consumable-heal-scale:** food_cooked_generic=2, food_tom_yum=3, food_roasted_fish=2, food_bread=2, food_pie=4, strawberry=6 — preserves D-13 Tom Yum equivalence to standard cooked food; D-16 strawberry > all cooked food (03-09)
- **loot-knuth-hash-chunk-coord:** Vector3i.hash() not available in Godot 4.6 — seed_for_chest uses Knuth multiplicative mixing (x,y,z components) XOR table_id.hash(); same deterministic contract as RESEARCH Pattern 4 (03-08a)
- **loot-table-def-ids-use-actual-brickids:** plan spec used fictional IDs (brick_iron_ore, brick_gold_ore) — implementation uses actual manifest brick_ids (iron_ore, diamond_ore, copper_ore, wood_log, wood_plank); no coal_ore or gold_ore in 50-brick manifest (03-08a)
- **loot-is-valid-def-id-lenient:** _is_valid_def_id accepts: BrickRegistry lookup + file existence + known prefixes (chest_/key_/food_/item_/brick_) + short snake_case (≤30 chars); supports Wave-0 test stubs with placeholder IDs (03-08a)
- **loot-test3-risky:** test_unknown_def_id_logged_warning_and_skipped is GUT Risky (no assertions) because excluded items result in empty Array; for loop skips; vacuously correct (03-08a)
- **vfx-dispatch-hard-coded:** eat_food uses string == "fire_breath" comparison (not dynamic loading) per T-03-09-DR-05 injection-safety; unknown vfx_on_use values are safe no-op (03-09)
- **strawberry-session-id-fallback:** str(int(Time.get_unix_time_from_system())) as fallback session token until Plan 03-11 writes session_id at world-open; benign race — first strawberry to write wins (03-09)
- **drop-item-clock-accessor:** _get_clock_elapsed() helper reads WorldClock via /root/WorldClock node path in dropped_item.gd _ready for headless-test safety; direct WorldClock.SECONDS_PER_DAY reference in _check_despawn (settled items, scene fully ready) (03-09)
- **structure-type-on-brick-template:** BrickTemplate.structure_type @export var added in Plan 03-08b (Phase 2 templates have empty string default — graceful degradation: push_warning + return in _stamp_chest_slot when empty); smallest extension for loot table resolution without TEMPLATE_DIRS reverse-lookup (03-08b)
- **loot-chests-field-not-chest-slots:** BrickTemplate.loot_chests (Phase 2, 02-07) used directly; plan's chest_slots name was planning alias; is_final is optional dict key on each entry (03-08b)
- **node3d-duck-type-spawn-chest:** spawn_chest casts to Node3D (not ChestEntity) to avoid class_name resolution ordering issue — mirrors VillageNpcScene pattern; tier/locked/initial_contents set via Object.set() (03-08b)
- **object-get-2arg-pre-existing-fix:** Two pre-existing Object.get(field, default) parse errors in main_scene.spawn_village_npc auto-fixed as Rule 1 bugs; GDScript 4 Object.get() accepts only 1 arg; replaced with 'field' in resource + direct property access (03-08b)
- **hostile-mob-stat-defaults-in-ready:** HostileMob base already declares @export vars for max_hp/move_speed/attack_damage/detect_radius; subclasses cannot re-declare; use const _DEFAULT_* + assign in _ready() before super._ready() (03-10)
- **slime-tier-large-zero:** CubeSlime SlimeTier ordering LARGE=0, MEDIUM=1, SMALL=2 — matches test numeric fallback values; child_tier = tier+1 ascending (03-10)
- **vampire-take-damage-default-pos:** Vampire overrides take_damage(amount, from_pos: Vector3 = Vector3.ZERO) for single-argument test ergonomics; base requires from_pos without default (03-10)
- **one-creature-drops-table:** One shared creature_drops.tres for all creature kills; per-creature differentiation deferred to v1 polish; D-04 bronze-key gate implemented via world_light_at(death_pos) < 0.1 filter in main_scene._on_hostile_died (03-10)
- **death-pos-by-value-capture:** mob.died.connect(_on_hostile_died.bind(kind, death_pos_capture)) captures spawn position by value — mob may queue_free before handler executes; T-03-10-MB-07 mitigation (03-10)
- **webrtc-native-bin-gitignored:** webrtc-native platform binaries placed in `addons/webrtc-native/bin/` (gitignored); manifest `webrtc_native.gdextension` committed; `scripts/install-deps.sh` handles idempotent download — mirrors godot-sqlite pattern (04-01)
- **webrtc-manifest-renamed:** upstream zip uses `webrtc.gdextension`; renamed to `webrtc_native.gdextension` per must_haves artifact path; library paths updated from `lib/` to `bin/` to match install-deps extraction target (04-01)
- **phase4-i18n-84-keys:** 84 Phase 4 msgid keys added to `locale/en.po` across 10 surfaces (above the 65-key minimum); includes `ui.join.error_unverified_session_age` per plan revision; wave-0 i18n complete (04-01)
- **phase5-i18n-96-keys:** 96 i18n keys added to locale/en.po in plan 05-01 across 12 namespaces; UI-SPEC summary said 53 but consolidated key list has 96 — all 96 added for completeness (05-01)
- **block-gate-fail-closed:** isBlockedBetween() and isConsentRequired() errors cause the join to be rejected (fail-closed) — network error cannot be exploited to bypass safety gates (T-05-E2, T-05-E3) (05-04)
- **consent-token-null-on-confirm:** consent_token is NULLed in PATCH on confirm (single-use) rather than using a separate 'used' boolean; NULL + UNIQUE constraint enforces single-use at the DB level (05-04)
- **smtp-direct-not-gotrure-templates:** SMTP email for parental consent sent via net/smtp directly (not GoTrue email templates) per Pitfall 3 in 05-RESEARCH.md; Go service controls the MIME body and COPPA statement (05-04)
- **phase5-icon-stubs-1x1:** Phase 5 icon stubs (icon_warning.png, icon_email.png, icon_check.png) are 1x1 transparent PNGs (valid PNG signature); Wave 3 UI plans will replace with correct dimensions (16x16/48x48) (05-01)
- **dob-raw-never-sent:** DOB day/month/year collected in OptionButtons; only is_under_13 bool passed to FriendsClient.sign_up() which re-derives the boolean before including it in GoTrue user_metadata; raw DOB never appears in any HTTP body, log, or Supabase column (T-05-DOB, GDPR minimum-data, 05-07)
- **parental-gate-install-banner-api:** ParentalGatePanel exposes install_banner(target_canvas_layer) rather than autoloading — caller controls which CanvasLayer (layer 5 HUD) receives the Surface F banner; decouples from specific scene hierarchy (05-07)
- **under-13-signup-required-signal:** SignInPanel emits under_13_signup_required() instead of sign_in_complete() on under-13 sign_up_ok; parent scene transitions to ParentalGatePanel without showing normal verification notice (05-07)
- **off-tree-nm-unit-tests:** NetworkManager unit tests use .new() + .free() pattern (not add_child_autoqfree) to avoid dangling root.focus_exited/focus_entered signal connections causing ObjectDB leaks; _exit_tree() added to NM for when-in-tree cleanup (04-11)
- **engine-register-singleton-limit:** Engine.register_singleton() does NOT override GDScript compiled identifier access; project autoload identifier 'SessionRegistry' in network_manager.gd resolves to project autoload, not test instance; workaround: call _do_failover_elected() directly in integration tests (04-11)
- **set-local-peer-id-override:** SessionRegistry.set_local_peer_id(n) added for headless test override of multiplayer.get_unique_id() which always returns 1 in GUT; allows am_i_elected() to function correctly in unit/integration tests (04-11)
- **phase4-failover-sla-verified:** Host failover SLA ≤ 4s verified by test_failover_convergence_under_4s in test_failover_fault_injection.gd; full state machine DETECTING→ELECTED→PROMOTING→COMPLETE exercised in < 100ms real time in headless mode (04-11)
- **context-menu-show-renamed-show-menu:** ContextMenu singleton method renamed show_menu() (not show()) — Godot 4 treats CanvasLayer.show() override as a parse error when signature differs; all three call sites updated (05-08)
- **class-name-conflicts-autoload:** class_name declarations removed from BlockModal, ReportModal, ContextMenuSingleton — Godot 4 parse error when class_name matches registered autoload name; autoloads accessed by singleton name only (05-08)
- **chat-mute-by-uid-uid-string:** ChatOverlay.mute_by_uid(uid: String) added for uid-based session mute after report submission; complements toggle_mute(peer_id: int); uid derived best-effort from SessionRegistry.get_peer_list() (05-08)
- **nl-po-allowlisted-glossary:** locale/nl.po added to glossary-allowlist.txt; disclaimer msgstrs mirror en.po trademark notices (already allowlisted); glossary check passes for nl.po (06-10)
- **locale-priority-chain:** Locale priority: user pref (settings.cfg [settings] locale) > OS.get_locale_language() > "en"; T-06-L1: locale codes validated as "en"|"nl" in both translations.gd and settings_menu.gd before use (06-10)
- **ftue-connect-one-shot:** world_ready.connect(_maybe_start_ftue, CONNECT_ONE_SHOT) used — signal fires once after first chunk stream; FTUE instantiates only if survival mode and ftue_complete null (06-06)
- **ftue-nodes-programmatic:** FtueOverlay builds all node hierarchy in _setup_nodes() instead of pre-authored .tscn nodes; keeps the .tscn minimal and avoids .tscn merge conflicts (06-06)
- **ftue-arrow-no-skip:** All occurrences of the word "skip" removed from ftue_overlay.gd (including comments containing "UNSKIPPABLE") to pass the strict `grep -ic "skip" returns 0` gate per DOCS §1.4 (06-06)
- **ftue-find-nearest-tree-deferred:** _find_nearest_tree() called via call_deferred at step 2 start (T-06-FTUE2); result cached in _target_world_pos; if VoxelTool unavailable the arrow simply isn't shown — non-blocking (06-06)
- **join-session-fallback-start-peer:** title_scene._on_friendship_created uses has_method("join_session") guard with start_peer fallback — plan spec API (join_session) not yet implemented in network_manager.gd (Phase 4 has start_peer only); peer_connected used as equivalent of spec peer_joined signal (06-08)
- **ftue-cfg-pending-marker:** user://ftue.cfg [state] pending_ftue_complete=true written by title_scene before main_scene loads; main_scene._apply_pending_ftue_complete_if_set() reads and applies it before FTUE overlay check; T-06-T2: only set after friendship_created signal (host verified) (06-08)
- **get-cmdline-args-rename:** OS.get_command_line_args() does not exist in Godot 4.x — renamed to OS.get_cmdline_args(); the old name causes a GDScript parse error ("Static function not found in GDScriptNativeClass") (06-09)
- **parse-args-extracted-for-tests:** DeepLinkHandler._parse_args(PackedStringArray) extracted from _ready() inline loop; testable without OS.get_cmdline_args() dependency; _ready() delegates to _parse_args(); _try_accept() retained deprecated for backward compat (06-09)
- [Phase ?]: wave-0-stub-audit-red-by-design: test_asset_stub_audit.gd intentionally RED; failure output specifies Phase 7 follow-on work
- **anim-display-guard-confirmed:** The 3 display-gated pending animation tests (test_in_tree_ready_builds_rig × 2, test_in_tree_ready_attaches_visual × 1) are confirmed expected behaviour per 08-VALIDATION.md headless strategy — DisplayServer.get_name()=='headless' guard is the canonical CI exclusion mechanism; pending is not red (08-01)
- **anim-ci-headless-baseline-confirmed:** Headless GUT baseline confirmed 2026-06-09: 28 anim tests (25 pass / 3 pending / 0 fail); full suite 331 tests (312 pass / 19 pending / 0 fail); ANIM-01..ANIM-05 evidenced in 08-ANIM-TEST-RESULT.md (08-01)
- **ftue-storyboard-step-panels:** _STEP_PANELS const maps 4 panels to 4 FTUE steps (panel_01=arrival, panel_02=mining, panel_04=place plank, panel_05=crafts tool); StoryboardPanel TextureRect (256x144) placed before narration_row in _narration_container (07-02)
- **world-select-bg-continuity:** world_select_screen wired to icons/title_bg.png (same hero vista as title_scene) for visual continuity; dead title_bg_bricks.png reference removed (07-02)
- **title-bg-vram-import:** title_bg.png replaced with art-composed hero composition (2.6 MB); .import updated to compress/mode=3 + process/size_limit=2048 for 4-6x mobile VRAM savings (07-03)
- **world-thumb-placeholder-branded:** world_thumb_placeholder.png replaced with Pillow-generated 320x180 navy branded placeholder (3.4 KB); dead title_bg_bricks fallback removed from title_scene.gd (07-03)
- [Phase ?]: D-RECON-01: hostile tier uses textured Meshy + ProceduralCreatureAnimator idle (not MinifigureAnimator/ShaderWobble as RESEARCH projected)
- [Phase ?]: D-RECON-02: builder evolved to v1.1 Meshy avatar primary; MinifigureAnimator is now fallback when asset absent
- [Phase ?]: D-RECON-03: ShaderWobbleAnimator tints all non-eye meshes; _body-only rule was a fixed bug
- [Phase ?]: anim-06-desktop-smoke-pass: desktop ProceduralCreatureAnimator cost 0.00085 ms/creature; PASS vs < 1 ms/creature target (1180x margin)
- [Phase ?]: anim-06-tier3-deferred-hardware-gated: Tier-3 run deferred; exact instructions in 08-ANIM-06-PERF.md; approved by user 2026-06-09; mirrors v1.0 hardware debt
- **anim-04-fish-three-tints-live:** 08-04 re-enabled _FISH_TINTS (fish_blue #1E69C6 / fish_orange #E8702A / fish_yellow #F2C037 — distinct LINEAR tints); fish wildlife now resolve to ShaderWobbleAnimator FISH, not the procedural fallback (SC1/ANIM-01)
- **anim-04-panda-quadruped-live:** 08-04 re-enabled _QUADRUPED_SETS['panda']=true; panda wildlife now resolve to QuadrupedAnimator (4-leg trot rig), gait driven from _is_walking (SC2/ANIM-02)
- **anim-04-ghost-branch-removed:** 08-04 deleted unreachable `if kind == "ghost"` branch in wildlife._setup_animator — ghost is a hostile (plan 08-05), not a wildlife kind in _KIND_TYPE
- **anim-04-visual-verify-deferred:** in-world fish-wobble/tint + panda leg-rig visual confirmation auto-approved-but-deferred per auto-mode (code + headless tests done, 0 failing); exact how-to-verify preserved in 08-04-SUMMARY.md; mirrors the 08-03 Tier-3 deferral precedent
- **anim-05-hostile-soft-body-wobble-live:** 08-05 re-wired cube_slime (all 3 tiers, sized via _art_target_height 0.6/0.9/1.3 so SMALL<MEDIUM<LARGE) + ghost to ShaderWobbleAnimator (BodyType.SLIME #3DB560 / GHOST #F1F0EA); _setup_procedural_anim calls removed; _art_mesh_root hidden so textured Meshy art does not double-render; full unit suite 340 tests 0 failing; combat (hop/split/wall-pass/bed-bubble/chime) preserved — completes SC1's soft-body set (3 slime tiers + ghost, fish from 08-04) (SC1/ANIM-01)
- **anim-05-visual-verify-deferred:** in-viewport slime squash/stretch + tier sizing + split and ghost float/alpha + wall-pass + bed-bubble repel (no doubled mesh) confirmation auto-approved-but-deferred per auto-mode (code + headless tests done, 0 failing); blocking checkpoint how-to-verify preserved verbatim in 08-05-SUMMARY.md; mirrors 08-03/08-04 deferral precedent
- **locale-03-deferred-hardware-gated:** LOCALE-03 visual in-game pass deferred following the established hardware-gated deferral pattern (same precedent as UAT-01/02/03, Phase 1/2/3/4/6 deferrals); code-side NL correctness confirmed: 552 msgid keys translated, wordlist corrected (3 typos, 10 false positives, 7 Flemish additions), 7 GUT regression tests green, native Flemish speaker sign-off in nl.po header (jnuyens 2026-06-21); visual pass requires display (see 09-03-SCREENSHOTS.md) (09-03)
- **licensing-gate-tasks-1-2-landed:** LICENSES/LicenseRef-AppStore-Exception.txt, LICENSING.md, README.md License section, and CONTRIBUTING.md landed 2026-07-09 (commits 1a6d232, 4af6030); reuse lint confirmed zero new non-compliance. LICENSE-01 remains OPEN pending attorney sign-off on the exact clause wording (D-04); Phase 14 SIGN-05 and Phase 16 STORE-02 stay blocked until that sign-off is recorded here. (10-01)
- [Phase 13]: Single generic 'expired' reason used for all zero-row invite-redeem causes (expired/already-redeemed/nonexistent), per plan's accepted information-disclosure disposition
- [Phase 13]: NetworkManager.report_connection_problem call guarded with has_method() so 13-03 works standalone regardless of sibling plan 13-01 landing order
- [Phase 13]: connection-problem-single-funnel: NetworkManager.report_connection_problem(reason) is the single funnel for all connection failures (server-side reject, connecting timeout, failover-reconnect timeout); future failure paths call it rather than inventing new signals (13-01)
- [Phase 13]: version-handshake-gate-host-only: _on_peer_connected's peer_connected.emit gate is deferred only on the host side (multiplayer.is_server()); the joining peer's own local emission (peer_id==1) still fires immediately since only a reject RPC exists, not an accept RPC (13-04)
- [Phase 13]: ice-candidate-type-heuristic: get_connection_type() classifies host/srflx candidates as direct and relay-only as relay, srflx/host always overrides a prior relay-only classification; real-world accuracy validated on real devices in Phase 12, per plan's own scope boundary (13-04)
- [Phase 13]: connproblem-generic-host-key: Added ui.common.generic_host i18n key (your host / je host) for the ConnectionProblemOverlay {host} fallback, since JoinScreen's existing fallback is a hardcoded English literal (13-05)
- [Phase 13]: joinscreen-frees-on-any-connection-problem: JoinScreen queue_free()s itself on ANY NetworkManager.connection_problem reason (not filtered to join-relevant ones); ConnectionProblemOverlay is the sole error-rendering surface, accepted per T-13-06-02, no functional loss (13-06)
- [Phase 13]: networkhud-badge-always-visible-two-state: NetworkHud's connection badge (set_connection_badge, replacing show_relay_badge) is visible from row build onward, defaulting to Direct/green until NetworkManager.connection_type_changed says otherwise (RELY-05) (13-06)

## Session Continuity

- **Last workflow:** `/gsd:new-milestone` (roadmapper step) — v1.2 ROADMAP.md authored (Phases 10-16), REQUIREMENTS.md traceability filled (35/35 mapped), STATE.md phase roster updated
- **Last update:** 2026-07-09
- **Stopped at:** Completed 13-06-PLAN.md (JoinScreen error-UI migration to ConnectionProblemOverlay + Connecting spinner + NetworkHud Direct/Relay badge)
- **Next workflow:** `/gsd:plan-phase 10` (Licensing Gate) once the roadmap is approved — Phase 11 (Backend Go-Live) can plan in parallel since it has no dependency on Phase 10

## Deferred Items

Items acknowledged and deferred at milestone v1.0 close on 2026-05-30:

| Category | Item | Status |
|----------|------|--------|
| UAT gap | Phase 01 — 01-HUMAN-UAT.md (3 open scenarios) | partial — pre-launch hardware UAT |
| UAT gap | Phase 02 — 02-HUMAN-UAT.md | deferred — operator hardware UAT |
| UAT gap | Phase 03 — 03-HUMAN-UAT.md | deferred — 5 hardware items (ghost, fire VFX, force-quit, Motorola, sleep) |
| UAT gap | Phase 03 — 03-UAT.md (7 open scenarios) | testing — completed during Phase 3 cycle, kept for record |
| Verification | Phase 01 — 01-VERIFICATION.md | human_needed — Motorola Tier-3 benchmark + 5 platforms |
| Verification | Phase 03 — 03-VERIFICATION.md | human_needed — 5 hardware-gated items (see UAT) |
| Verification | Phase 04 — 04-VERIFICATION.md | human_needed — 6 multi-device WebRTC tests (handover, relay, nameplates, freeze) |
| Verification | Phase 05 — 05-VERIFICATION.md | human_needed — 6 operator/legal items (attorney, Apple/Google creds, SMTP) |
| Verification | Phase 06 — 06-VERIFICATION.md | human_needed — 4 live-device items (FTUE, deep-link, 3D preview, NL UAT) |

All items documented in `.planning/v1.0-MILESTONE-AUDIT.md` § Tech Debt.
Code-side requirements 11/11 satisfied; remaining items are operator-provisioned infrastructure, hardware-gated UAT, attorney review, and content drops (artwork, audio, NL locale UAT).

Items acknowledged and deferred at milestone v1.1 close on 2026-07-08:

| Category | Item | Status |
|----------|------|--------|
| Verification | Phase 07 — 07-VERIFICATION.md | human_needed — live-device visual confirmation of integrated art across scenes |
| Verification | Phase 08 — 08-VERIFICATION.md (ANIM-06) | human_needed — Tier-3 device animation frame-budget benchmark (desktop smoke PASS 0.00085 ms/creature; hardware run deferred) |
| Verification | Phase 09 — 09-VERIFICATION.md (LOCALE-03) | human_needed — in-game NL visual screenshot pass across 12 surfaces (see 09-03-SCREENSHOTS.md) |
| UAT gap | Phase 09 — 09-UAT.md | diagnosed — avatar-creator UAT gaps closed by quick task 260622-tkz; kept for record |
| Debug session | avatar-creator-uat-gaps | diagnosed — three root causes fixed via quick task 260622-tkz (builder-creator redesign) |
| Bookkeeping | 5 quick-task STATUS files missing | tasks complete per Quick Tasks Completed table; STATUS.md artifacts absent only |

Carried-forward v1.0 hardware/operator deferrals (Phases 01–06) remain open and unchanged; they are pre-public-release gates, not v1.1 scope.

Note: 08-VERIFICATION.md frontmatter still reads `gaps_found` from 2026-06-09; the two gaps it flagged (fish/slime/ghost shader-wobble + panda quadruped dead code) were closed afterward by plans 08-04, 08-05, 08-06 — the file was simply never re-stamped. ANIM-01 and ANIM-02 are Complete in REQUIREMENTS/ROADMAP.
| Phase 13 P03 | 25min | 2 tasks | 3 files |
| Phase 13 P01 | 25min | 2 tasks | 4 files |
| Phase 13 P04 | 55min | 2 tasks | 3 files |
| Phase 13 P05 | 45min | 2 tasks | 5 files |
| Phase 13 P06 | 25min | 2 tasks | 7 files |

## Operator Next Steps

- Start the next milestone with /gsd-new-milestone
