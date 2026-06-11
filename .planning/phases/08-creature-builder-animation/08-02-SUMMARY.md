---
phase: 08-creature-builder-animation
plan: "02"
subsystem: planning-ledger
tags: [reconciliation, doc-only, animation, state]
dependency_graph:
  requires: [08-01]
  provides: [08-CONTEXT.md reconciliation decisions, corrected STATE.md Phase 8 entry]
  affects: [08-03-PLAN.md context, STATE.md phase roster]
tech_stack:
  added: []
  patterns: []
key_files:
  created: []
  modified:
    - .planning/phases/08-creature-builder-animation/08-CONTEXT.md
    - .planning/STATE.md
decisions:
  - "D-RECON-01: hostile tier uses textured Meshy + ProceduralCreatureAnimator idle (not MinifigureAnimator/ShaderWobble as projected)"
  - "D-RECON-02: builder evolved to v1.1 Meshy avatar primary; MinifigureAnimator is fallback when asset absent"
  - "D-RECON-03: ShaderWobbleAnimator tints all non-eye meshes; _body-only rule was a bug that was fixed"
metrics:
  duration: "3 minutes"
  completed: "2026-06-09"
  tasks_completed: 2
  files_modified: 2
---

# Phase 8 Plan 02: Reconcile RESEARCH-vs-shipped divergences + fix stale STATE.md

**One-liner:** Ledger reconciliation recording the three shipped-reality divergences (hostile Meshy+procedural tier, builder Meshy-avatar-primary fallback, wobble all-mesh fix) and correcting the stale Phase 8 "Not started" / "08-animation" entry in STATE.md.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Record D-RECON-01..03 in 08-CONTEXT.md | 2a757ce | .planning/phases/08-creature-builder-animation/08-CONTEXT.md |
| 2 | Fix stale STATE.md Phase 8 status + dir name | 37cdd78 | .planning/STATE.md |

## What Was Done

### Task 1 — Reconciliation decisions in 08-CONTEXT.md

Appended a new "Reconciliation (shipped reality vs. pre-implementation projections)" section to 08-CONTEXT.md containing three decision entries, each explicitly superseding the corresponding pre-implementation projection while preserving the original decisions for historical context:

- D-RECON-01 (hostile animator tier): vampire, cube_slime, and ghost ship textured Meshy art via _apply_art_mesh() with _art_kind() returning "vampire"/"slime"/"ghost". ProceduralCreatureAnimator idle is attached on top. ANIM-05 is met by this path; ANIM-01 is met by wildlife.gd::_setup_animator. Sources: src/combat/vampire.gd:95-109, src/combat/cube_slime.gd:108-115.

- D-RECON-02 (builder avatar): builder uses v1.1 textured rigged Meshy avatar (builder_avatar.glb + AnimationPlayer) as primary; MinifigureAnimator is the fallback used only when the Meshy avatar asset is absent. Colour customisation preserved via rig-colour remap on fallback path. Source: src/builder/builder.gd:1955-1963.

- D-RECON-03 (shader wobble scope): ShaderWobbleAnimator applies to ALL MeshInstance3D except eyes/accessor/pupil; the earlier _body-only rule was a bug (Meshy meshes are named after the set, not "_body") that caused fish_orange to render blue. Source: src/builder/shader_wobble_animator.gd:54-68.

### Task 2 — STATE.md corrections

- Phase 8 roster row status: "Not started" → "Executing" (code shipped, ANIM-06 perf gate still open via Plan 08-03)
- Phase 8 Todos line: "08-animation" → "08-creature-builder-animation" (corrects directory drift)
- No other STATE.md lines modified

## Deviations from Plan

None — plan executed exactly as written.

## Known Stubs

None — documentation-only plan with no code stubs.

## Threat Flags

None — documentation-only plan; no security-relevant surface introduced.

## Self-Check: PASSED

- .planning/phases/08-creature-builder-animation/08-CONTEXT.md: FOUND (D-RECON-01, D-RECON-02, D-RECON-03 present; ProceduralCreatureAnimator cited)
- .planning/STATE.md: FOUND (08-creature-builder-animation present; 0 bare "08-animation" tokens; Phase 8 row reads "Executing")
- Commits: 2a757ce (08-CONTEXT.md), 37cdd78 (STATE.md) — both verified in git log
