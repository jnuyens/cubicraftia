# Cubicraftia — Living Retrospective

Rolling record of what worked, what didn't, and the patterns worth keeping across milestones.

## Milestone: v1.1 — Content & Polish

**Shipped:** 2026-07-08
**Phases:** 3 (Phases 7-9) | **Plans:** 14 | **Tasks:** 19
**Timeline:** ~3.5 weeks (2026-06-11 → 2026-07-04) | **Commits:** 220 since v1.0

### What Was Built

The milestone turned a pile of already-drawn-but-unwired art and animation POCs into a game that looks shipped: real art in every scene (Phase 7), all three rig archetypes productionised into idle + locomotion for every entity (Phase 8), and a native-Flemish-reviewed Dutch locale (Phase 9). A large wave of world/avatar polish (MOUNTAIN biome, spawn diorama, crafting recipe completion, box-minifig iterations) and crash-guard segfault fixes landed alongside the formal phases.

### What Worked

- **Gap-closure waves as first-class plans.** Phase 8 shipped 3 original plans, then 08-04/05/06 as an explicit gap-closure wave after 08-VERIFICATION proved the shader-wobble/quadruped dispatch was dead code. Treating the fix-up as numbered plans (not ad-hoc edits) kept the ledger honest and traceable.
- **Verification caught a real "marked-complete-but-actually-dead-code" gap.** REQUIREMENTS had ANIM-01 checked while `_FISH_TINTS = {}` silently routed fish to the wrong animator. Goal-backward verification surfaced it; the checkbox alone would have hidden it.
- **The hardware-gated deferral pattern held.** Same discipline as v1.0: desktop perf smoke + explicit, runnable Tier-3 instructions, deferred with user approval rather than blocking the milestone.

### What Was Inefficient

- **Doc drift between the ledger and reality.** 08-VERIFICATION frontmatter stayed `gaps_found` after the gaps were closed; ROADMAP showed Phase 9 as 3/3 when 09-04 had shipped. Both were cosmetic but had to be reconciled at milestone close. A re-stamp step at end of each gap-closure wave would avoid it.
- **STATE.md accumulated orphaned table rows** (stray phase-stat lines) that had to be cleaned at close.
- **Large art commits inflated the diff** (3,554 files) making the git range a poor proxy for engineering effort.

### Patterns Established

- Post-verification gap-closure waves get their own plan numbers within the phase.
- Deferred visual/hardware passes ship with a runnable how-to (e.g. `09-03-SCREENSHOTS.md`, `08-ANIM-06-PERF.md`) so the debt is dischargeable later without re-derivation.
- Release build gets a git tag at build time (`v1.1` on 2026-06-30); the planning-side milestone close reconciles docs afterward.

### Key Lessons

- A checked requirement box is not evidence — wire-level verification is. Keep goal-backward checks even when plans report complete.
- Re-stamp verification/roadmap status the moment a gap-closure wave lands, not at milestone close.

## Cross-Milestone Trends

### Shipping cadence

| Milestone | Phases | Plans | Timeline | Commits |
|-----------|--------|-------|----------|---------|
| v1.0 Public Release | 6 | 72 | 6 days | 352 |
| v1.1 Content & Polish | 3 | 14 | ~3.5 weeks | 220 |

### Recurring themes

- **Hardware-gated deferral is the standing pattern.** Both milestones closed with a documented, user-approved set of hardware/operator/visual-pass deferrals rather than blocking. The backlog of these is growing and will need a dedicated discharge milestone before public release.
- **Verification earns its keep.** In both milestones, goal-backward verification found gaps that task-completion tracking missed.
