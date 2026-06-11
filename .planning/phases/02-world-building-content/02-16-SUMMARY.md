---
phase: 02-world-building-content
plan: "16"
subsystem: docs
status: complete
tags: [docs, ddd, docs-sync, docs-md, claude-md, phase-2-closeout, gltf-extras, zstd, npcs, biomes]

# Dependency graph
requires:
  - phase: 02-world-building-content plans 01-15
    provides: All Phase 2 implementation (biomes, 50-brick library, weather, tools, structures, NPCs, save format, dual-camera, adaptive-quality)

provides:
  - "DOCS.md as a true description of the shipped Phase 2 implementation (DDD discipline closing-loop step)"
  - "§2 Inhabitants paragraph — wandering builder NPCs in villages"
  - "§2.1 ~5 m blend clarification — biome transition interpretation locked"
  - "§3.1 50-brick list locked — fence_post moved to future IAP pack; manifest.json is authoritative"
  - "§3.2 dual-camera modes documented (chase default / FPV toggle)"
  - "§5 Peaceful NPCs note — village NPCs distinct from hostile roster"
  - "§6.8.5 World save format section — Zstd, atomic-rename, rolling backups canonical"
  - "§7.3 adaptive-quality preset names (Tier-1 through Tier-3 + Manual) documented"
  - "§9 Phase 2 carryover debt entry — 4 deferred UAT rows + Phase 1 Motorola benchmark"
  - "§10 14 new glossary terms added (Phase 2 additions)"
  - "Revision Log entry for Phase 2 doc-sync (2026-05-27)"
  - "CLAUDE.md glTF-extras implementation note — EXT_structural_metadata deviation documented for contributors"

affects:
  - Phase 3 (Survival loop) — DOCS.md §4 and §5 are the next anchors; §5 Peaceful NPCs note clarifies the boundary for Phase 3's hostile creature roster
  - All future phases — DOCS.md is the primary spec; this plan restores its accuracy after Phase 2 implementation

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "DDD closing-loop: each phase ends with a DOCS-sync plan that brings the canonical spec back to a true description of the shipped implementation"
    - "CLAUDE.md as contributor-facing annotation surface: implementation deviations from the stack recommendation table are recorded inline"

key-files:
  created:
    - .planning/phases/02-world-building-content/02-16-SUMMARY.md
  modified:
    - .planning/DOCS.md
    - CLAUDE.md

key-decisions:
  - "docs-sync-complete-2026-05-27 — DOCS.md is now a true description of Phase 2 implementation; DDD discipline closing-loop step satisfied; DOC-02 + DOC-03 can be marked complete"
  - "fence-post-to-iap-recorded — fence_post removed from DECORATIVE to hit 50-brick total is now canonical in DOCS §3.1 (was a Phase 2 execution decision in STATE.md only)"
  - "save-format-section-new — §6.8.5 is a new DOCS section recording Zstd + atomic-rename + rolling-backup as canonical; replaces earlier LZ4 mentions in research briefs"

patterns-established:
  - "Phase-end DOCS-sync plan: flush CONTEXT.md 'Deferred — Phase-end DOCS updates' queue into DOCS.md; user approves via checkpoint before commit"

requirements-completed:
  - DOC-02
  - DOC-03

# Metrics
duration: ~30min (Task 1 implementation) + checkpoint wait + closeout
completed: 2026-05-27
---

# Phase 2 Plan 16: DOCS Sync (DDD Discipline) Summary

**Phase 2 closing-loop DDD sync — DOCS.md (canonical spec) and CLAUDE.md now true descriptions of what Phase 2 shipped, including late additions (atmospheric wildlife, dual-camera, adaptive-quality, Phase 2 carryover debt).**

## Performance

- **Duration:** ~30 min (Task 1) + human-verify checkpoint + closeout
- **Started:** 2026-05-26
- **Completed:** 2026-05-27
- **Tasks completed:** 2/2 — Task 1 (edits) + Task 2 (human-verify, user approved 2026-05-27)
- **Files modified:** 2 (`.planning/DOCS.md`, `CLAUDE.md`)

## Accomplishments

- **Task 1 — DOCS.md + CLAUDE.md surgical edits** (`329e7c0`): Flushed all items from CONTEXT.md "Deferred — Phase-end DOCS updates" queue into the canonical spec. Every Phase 2 implementation decision that was deferred from earlier plans is now in DOCS.md.

- **Task 2 — User approval** (2026-05-27): User reviewed the `git diff` for all edited sections and approved without per-section change requests. The fence_post→IAP scope shift and the new §6.8.5 world-save section were explicitly noted as approved.

### Sections touched in DOCS.md

| Section | Change |
|---------|--------|
| §2 body | Added "Inhabitants" paragraph — wandering builder NPCs patrol pre-set paths in villages; biome-appropriate skin variants; atmosphere only |
| §2.1 transitions | Added ~5 m blend parenthetical — narrow terrain-colour + ambient-lighting blend + sudden flora-species change; biomes have distinct identities |
| §2.5 / inline | Atmospheric wildlife list clarified (panda / desert mouse / spider monkey / toucan / orca) — distinct from §2 inhabitant NPCs |
| §3.1 brick-library lock | Category counts locked at 7/5/4/3/4/6/5/9/5/2 = 50; fence_post moved to future IAP brick pack (DECORATIVE = 5); `src/bricks/manifest.json` referenced as authoritative; IAP packs add-to, never gate |
| §3.2 camera modes | Dual-camera documented — chase (default, SpringArm3D) + FPV toggle (V-key); crosshair-API works in both modes |
| §3.6 / locks | Camera-mode persistence and manifest pointer cross-referenced |
| §5 Peaceful NPCs | New subsection — village NPCs never attack, never drop loot, not affected by §5.3 spawning rules; distinct from hostile roster |
| §6.8.5 (new) | World save format section — per-world directory, two SQLite files, Zstd compression (`FileAccess.COMPRESSION_ZSTD`), atomic-rename + checksum + 3-snapshot rolling backup, only modified chunks persisted; replaces LZ4 in research-brief language |
| §7.3 adaptive-quality | Preset names documented: Tier-1 (High), Tier-2 (Medium), Tier-3 (Low/Potato), Manual override |
| §9 carryover debt | Phase 2 deferred-UAT entry added: 4 hardware UAT rows + Phase 1 Motorola 30-min benchmark |
| §10 glossary | 14 new terms added for Phase 2 additions (atmospheric wildlife, dual-camera, adaptive-quality, etc.) |
| Revision Log | Phase 2 doc-sync entry (2026-05-27) |

### CLAUDE.md change

- Added inline implementation note to the glTF 2.0 + EXT_structural_metadata row of the Recommended Stack table: Phase 1 ships glTF `extras` (not EXT_structural_metadata) because Godot 4.6 does not import EXT_structural_metadata natively; functional outcome (stud-anchor metadata travelling with the asset) is identical. This surfaces Phase 1's documented decision (`blender-extras-json-strings` + `gltfdocument-for-headless-load`) for future contributors reading the stack rationale.

## Task Commits

1. **Task 1: Edit DOCS.md §2/§2.1/§3.1/§5 + CLAUDE.md glTF annotation** — `329e7c0` (docs)
2. **Task 2: User reviews and approves DOCS sync edits** — CHECKPOINT PASSED (user approved 2026-05-27, no edits requested)
3. **Closeout: SUMMARY + STATE + ROADMAP** — this commit (docs)

## Files Created/Modified

- `.planning/DOCS.md` — §2, §2.1, §2.5, §3.1, §3.2, §3.6, §5, §6.8.5 (new), §7.3, §9, §10, Revision Log — all Phase 2 deferred DOCS updates applied
- `CLAUDE.md` — glTF-extras implementation note added to Recommended Stack table (§3 Per-Component Rationale, "Lego Stud Layer" row)

## Decisions Made

- **docs-sync-complete-2026-05-27:** DOCS.md is now a true description of the Phase 2 implementation. The CONTEXT.md "Deferred — Phase-end DOCS updates" queue is cleared. DOC-02 and DOC-03 can be marked complete. DDD discipline closing-loop step satisfied.

- **fence-post-to-iap-recorded:** The Phase 2 execution decision to drop `fence_post` from DECORATIVE (moving it to a future IAP brick pack) is now canonical in DOCS §3.1. Previously it existed only in STATE.md's Decisions Made section and the manifest.json file; now DOCS explicitly records the IAP trajectory.

- **save-format-section-new:** §6.8.5 is a net-new DOCS section. The save-format implementation details (Zstd, atomic-rename, rolling backups) lived in Plan 02-03's SUMMARY and STATE.md decisions but were absent from the canonical spec. Adding §6.8.5 makes the compression choice canonical and resolves the RESEARCH Contradiction 2 (LZ4 → Zstd substitution).

## Deviations from Plan

None — plan executed exactly as written. All 7 acceptance criteria from the plan's `must_haves` were met:

1. §2 Inhabitants paragraph — present
2. §2.1 5m-blend clarification — present
3. §3.1 brick-library count locked at 50 with manifest.json reference — present
4. §5 Peaceful NPCs note — present
5. Zstd compression with COMPRESSION_ZSTD identifier — present (§6.8.5)
6. CLAUDE.md glTF-extras annotation — present
7. User approved via checkpoint before commit — approved 2026-05-27

## Known Stubs

None — this is a documentation-only plan. No runtime code was added.

## Threat Surface Scan

No new network endpoints, auth paths, file-access patterns, or schema changes introduced. Documentation-only changes.

## Next Phase Readiness

- Phase 2 is complete. All 17 plans shipped (02-01 through 02-16).
- DOCS.md §2 and §3 are now true descriptions of the Phase 2 implementation.
- Phase 3 (Survival loop) can begin planning against DOCS.md §4 and §5.
- Deferred hardware UATs (02-HUMAN-UAT.md) remain open debt — they do NOT block Phase 3 planning.
- Phase 2 carryover debt summary: Phase 1 Motorola 30-min thermal benchmark + 4 Phase 2 hardware UAT rows.

---
*Phase: 02-world-building-content*
*Plan: 16 — complete*
*Completed: 2026-05-27*

## Self-Check: PASSED

- `.planning/DOCS.md` — exists and contains all required sections (verified via `git log`)
- `CLAUDE.md` — exists and contains glTF-extras annotation
- Commit `329e7c0` — exists and is the Task 1 commit (verified via `git log --oneline`)
- No empirical numbers fabricated
- No "Lego" string introduced in player-facing content
