---
phase: 02-world-building-content
plan: "01"
subsystem: world-design
tags: [biomes, design-docs, content-planning, gdoc, grassland, desert, snow, jungle, savannah, ocean]

# Dependency graph
requires:
  - phase: 01-foundation-mobile-spike plan 07
    provides: Phase 1 complete — voxel terrain + builder + mobile spike proven

provides:
  - "Six approved per-biome design briefs (grassland_forest, desert, snow, jungle, savannah, ocean)"
  - "Biome index (02-BIOME-BRIEFS.md) with approval status table and sign-off log"
  - "Canonical ambient tints, Whittaker classification windows, flora species lists, signature props, structure ownership, NPC skin variants per biome"

affects:
  - "02-06-PLAN.md (biome compositor — reads ambient tint, terrain palette, flora species, Whittaker windows)"
  - "02-07-PLAN.md (structure templates — reads structures owned, NPC skin variants)"
  - "02-08-PLAN.md (mineshafts & dungeons — reads shared structures owned entries)"
  - "02-13-PLAN.md (wandering NPCs — reads NPC skin variants and village biomes)"

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Per-biome brief pattern: 10-section design doc (Identity, Whittaker, Ambient tint, Sun colour, Terrain palette, Signature flora, Signature props, Structures owned, Ambient sound, NPC skin variants)"
    - "Approval gate pattern: human-verify checkpoint with sign-off log before content-generation plans run"

key-files:
  created:
    - .planning/phases/02-world-building-content/02-BIOME-BRIEFS.md
    - .planning/phases/02-world-building-content/biomes/grassland_forest.md
    - .planning/phases/02-world-building-content/biomes/desert.md
    - .planning/phases/02-world-building-content/biomes/snow.md
    - .planning/phases/02-world-building-content/biomes/jungle.md
    - .planning/phases/02-world-building-content/biomes/savannah.md
    - .planning/phases/02-world-building-content/biomes/ocean.md
  modified: []

key-decisions:
  - "biome-briefs-locked-v1: Six biome briefs approved with atmospheric wildlife revision (CONTEXT D-04, D-06 fulfilled); downstream Plans 06/07/08/13 may bind to species lists in biomes/*.md"
  - "atmospheric-wildlife-added: pandas (grassland_forest), desert mouse (desert), reindeer + snowwomen (snow), monkeys + toucans (jungle), elephants + giraffes + gnu (savannah), manta rays + orcas + fish + jellyfish + kelp (ocean) — added per user request in revision 1"

patterns-established:
  - "Biome brief format: 10 mandatory sections, ≤ 80 lines per brief, locked terminology (brick/builder/terrain, never Lego/Minecraft)"
  - "Content-generation approval gate: D-06 pattern — no downstream content-generation plan starts until index shows all 6 approved"

requirements-completed: [DOC-02]

# Metrics
duration: ~60min (Task 1 authoring) + human-verify checkpoint + revision loop
completed: 2026-05-26
---

# Phase 2 Plan 01: Per-Biome Briefs Summary

**Six per-biome design briefs authored, revised for atmospheric wildlife on user request, and approved (revision 1) by jnuyens@gmail.com 2026-05-26 — locking ambient tints, flora species, structure ownership, and NPC skin variants as canonical input for Plans 06/07/08/13.**

## Performance

- **Duration:** ~60 min (Task 1 authoring) + 1 revision loop (atmospheric wildlife) + human-verify checkpoint
- **Started:** 2026-05-26
- **Completed:** 2026-05-26
- **Tasks completed:** 2/2 (Task 1 auto + Task 2 human-verify — approved)
- **Files created:** 7 (index + 6 biome briefs)
- **Files modified:** 0

## Accomplishments

- Authored six per-biome design briefs in `.planning/phases/02-world-building-content/biomes/` — each covering all 10 required sections (Identity, Whittaker classification, Ambient tint, Sun colour, Terrain palette, Signature flora, Signature props, Structures owned, Ambient sound, NPC skin variants).
- Created the index file `02-BIOME-BRIEFS.md` with approval status table and sign-off log, satisfying CONTEXT.md D-06 deliverable and T-02-03 (repudiation threat mitigated with date + approver).
- User-requested revision 1: added atmospheric wildlife to all six biomes (pandas, desert mouse, reindeer + snowwomen/snowmen, monkeys + toucans, elephants + giraffes + gnu, manta rays + orcas + fish + jellyfish + kelp) without changing any locked design knob (ambient tint, structures owned, NPC skin variants).
- User approved all six briefs on 2026-05-26 (revision 1). Plans 06, 07, 08, and 13 are now unblocked.

## Task Commits

1. **Task 1: Author six per-biome briefs + index** — `3cab3bc` (docs)
2. **Task 1.1: Atmospheric wildlife revision per user request** — `7852dc5` (feat)
3. **Task 2: User approval — lock six biome briefs (revision 1)** — `4bcb698` (docs)

## Files Created/Modified

- `.planning/phases/02-world-building-content/02-BIOME-BRIEFS.md` — Index with 6-row approval table, sign-off log; all six rows marked `approved 2026-05-26 (revision 1)`
- `.planning/phases/02-world-building-content/biomes/grassland_forest.md` — Ambient tint #7EC850; pandas as atmospheric wildlife; oak + birch + fern + daisy + lily_of_valley + mushroom flora
- `.planning/phases/02-world-building-content/biomes/desert.md` — Ambient tint #F5C842; desert mouse as atmospheric wildlife; cactus + dead_bush flora; desert village NPC: tan/sand-yellow tunics
- `.planning/phases/02-world-building-content/biomes/snow.md` — Ambient tint #B8D8F0; reindeer + snowwomen/snowmen as atmospheric wildlife; snow village NPC: white/light-blue parkas
- `.planning/phases/02-world-building-content/biomes/jungle.md` — Ambient tint #3CB84C; monkeys + toucans as atmospheric wildlife; jungle temple structures owned
- `.planning/phases/02-world-building-content/biomes/savannah.md` — Ambient tint #D4A83A; elephants + giraffes + gnu as atmospheric wildlife; savannah village NPC: brown/orange leather wraps
- `.planning/phases/02-world-building-content/biomes/ocean.md` — Ambient tint #1E90D8; manta rays + orcas + fish + jellyfish + kelp as atmospheric wildlife/flora; shipwrecks + underwater temples owned

## Decisions Made

- **biome-briefs-locked-v1:** Six biome briefs locked as canonical design references (CONTEXT D-04, D-06 fulfilled). Downstream Plans 06/07/08/13 bind to species lists in `biomes/*.md`.
- **atmospheric-wildlife-as-additive-revision:** Wildlife entries were added as a new section-level addition to Signature flora / Signature props without altering any other locked knob. This kept the revision minimal and re-approval straightforward.
- **revision-1-approved-same-session:** User reviewed and approved in the same working session (2026-05-26). No second checkpoint needed.

## Deviations from Plan

### User-Requested Revision

**1. [User Revision] Atmospheric wildlife added to all six biomes**
- **Found during:** Task 2 human-verify checkpoint
- **User request:** Add ambient, non-hostile wildlife to each biome for atmosphere
- **Action:** Added wildlife as atmospheric detail within the existing brief structure (Signature flora and Signature props sections extended where appropriate)
- **Biomes revised:** All six
- **Committed in:** `7852dc5` (revision commit)
- **Impact:** Brief line counts increased slightly but stayed within the ≤ 80-line constraint. No locked design knobs (ambient tint, structures owned, NPC skin variants) were changed. Revision 1 approved same session.

---

**Total deviations:** 1 user-requested revision (non-breaking, additive)
**Impact on plan:** Revision was additive and approved within the same session. Plan objective fully met.

## Issues Encountered

None — plan executed without technical blockers. The only iteration was the user-driven wildlife revision, which was handled at the Task 2 checkpoint as designed.

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

- Plans 06, 07, 08, and 13 are unblocked. Each may read `biomes/*.md` as canonical design input.
- Plan 02-02 (Wave 0 infrastructure: godot-sqlite + GUT skeletons) is next and has no dependency on these briefs — it can proceed immediately.
- The six biome briefs are the stable contract for biome identity through the rest of Phase 2. Changes to `biomes/*.md` after this point require a re-approval checkpoint.

## Known Stubs

None — all six briefs are complete, covering all 10 required sections. No placeholder text or "TODO" entries remain in the brief files.

## Threat Flags

None — glossary-check.sh passes on all brief files (no "Lego" or "Minecraft" in any brief). T-02-01 and T-02-03 mitigations both applied (glossary CI + dated sign-off log).

## Self-Check

Verified:

- `.planning/phases/02-world-building-content/02-BIOME-BRIEFS.md` — exists, all six rows show `approved 2026-05-26 (revision 1)`
- `.planning/phases/02-world-building-content/biomes/grassland_forest.md` — exists
- `.planning/phases/02-world-building-content/biomes/desert.md` — exists
- `.planning/phases/02-world-building-content/biomes/snow.md` — exists
- `.planning/phases/02-world-building-content/biomes/jungle.md` — exists
- `.planning/phases/02-world-building-content/biomes/savannah.md` — exists
- `.planning/phases/02-world-building-content/biomes/ocean.md` — exists

Commits verified:
- `3cab3bc` — docs(02-01): author six per-biome briefs + index (Task 1)
- `7852dc5` — feat(02-01): add atmospheric wildlife per biome (user revision)
- `4bcb698` — docs(02-01): user approval — lock six biome briefs (revision 1)

## Self-Check: PASSED

---

*Phase: 02-world-building-content*
*Plan: 01 — complete*
*Completed: 2026-05-26*
