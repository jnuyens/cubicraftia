---
phase: 08-creature-builder-animation
plan: 04
subsystem: wildlife-animation
tags: [animation, dispatch, fish, panda, gap-closure, ANIM-01, ANIM-02]
requires:
  - "src/builder/shader_wobble_animator.gd (ShaderWobbleAnimator FISH — pre-built, verified)"
  - "src/builder/quadruped_animator.gd (QuadrupedAnimator panda rig — pre-built, verified)"
  - "assets/meshes/avatars/fish_blue/ (the single fish avatar; 3 kinds tint-distinguished)"
  - "assets/meshes/avatars/panda/ (layout.json facing -x + 7 piece .glb)"
provides:
  - "wildlife.gd dispatch live for fish (ShaderWobble FISH) + panda (QuadrupedAnimator)"
  - "wiring-level dispatch test coverage (const + display-gated in-tree)"
affects:
  - "src/world/wildlife.gd"
  - "tests/unit/test_anim_quadruped.gd"
  - "tests/unit/test_anim_wildlife_dispatch.gd"
tech-stack:
  added: []
  patterns:
    - "one-mesh-three-tints: fish_blue avatar drives fish_blue/orange/yellow via LINEAR body_colour"
    - "dispatch-dict-gate: _setup_animator branches reachable only when the const dict .has(kind)"
key-files:
  created:
    - tests/unit/test_anim_wildlife_dispatch.gd
  modified:
    - src/world/wildlife.gd
    - tests/unit/test_anim_quadruped.gd
decisions:
  - "fish-tints-brand-aligned: fish_blue #1E69C6 (matches demo), fish_orange #E8702A, fish_yellow #F2C037 — three distinct LINEAR-space tints per D-RECON-03"
  - "quadruped-sets-value-true: _QUADRUPED_SETS['panda']=true; the value is unread (branch only calls .has(kind) and hardcodes mesh_set='panda'), true chosen for clarity"
  - "ghost-branch-removed: deleted unreachable if kind=='ghost' branch — ghost is a hostile (plan 08-05), not a wildlife kind in _KIND_TYPE"
metrics:
  duration: ~8 min
  completed: 2026-06-10
  tasks: 2 auto + 1 deferred checkpoint
  files: 3
---

# Phase 8 Plan 04: Wildlife Animator Dispatch Re-Wire (Gap Closure) Summary

Re-enabled the two empty animator-dispatch dicts in `src/world/wildlife.gd` so the already-verified `ShaderWobbleAnimator` (FISH, GPU vertex-wobble + per-kind tint) and `QuadrupedAnimator` (panda 4-leg trot rig) reach live wildlife, and removed the unreachable ghost branch the verifier flagged. Closes GAP 1 (fish portion of SC1/ANIM-01) and GAP 2 (SC2/ANIM-02) at the dispatch level; headless tests now assert the dispatch (not just the classes).

## What Was Done

### Task 1 — Re-enable dispatch dicts + delete dead ghost branch (`feat(08-04)`, commit `0c7d21e`)
- `_FISH_TINTS` (was `{}`) populated with `fish_blue` → `Color("#1E69C6")`, `fish_orange` → `Color("#E8702A")`, `fish_yellow` → `Color("#F2C037")`. One avatar dir (`fish_blue`) exists on disk; the FISH branch already hardcodes `mesh_set = "fish_blue"` and distinguishes the three kinds purely by `body_colour` — the intended one-mesh-three-tints design (D-RECON-03: the shader tints all non-eye meshes).
- `_QUADRUPED_SETS` (was `{}`) populated with `"panda": true`. The branch reads only `.has(kind)` and hardcodes `quad.mesh_set = "panda"`, so the value is unread; `true` chosen for clarity.
- Deleted the entire unreachable `if kind == "ghost":` branch in `_setup_animator` (was wildlife.gd:398-409). `"ghost"` is not in `_KIND_TYPE`, so the branch was dead code; the hostile ghost soft-body is handled in plan 08-05.
- Stale comments above both consts and on the `_setup_animator` docstring updated to reflect the gap-closure replan (naming SC1/SC2) and the removed ghost path.
- `_process_land` / `_process_water` / `_process_air` were **not** touched — `(_anim as QuadrupedAnimator).gait = "walk" if _is_walking else "idle"` and the GPU-side fish wobble were already correctly wired for when `_anim` is the typed animator. ProceduralCreatureAnimator fallback for the other ~18 kinds is unchanged.
- Verified: `godot --headless --check-only --script src/world/wildlife.gd` exits 0; the verify grep returned PASS (ghost-branch count 0, fish_orange present, panda present).

### Task 2 — Wiring-level dispatch tests (`test(08-04)`, commit `ec69171`)
- New file `tests/unit/test_anim_wildlife_dispatch.gd` (SPDX GPL-3.0-or-later, `extends GutTest`):
  - `test_fish_tints_has_all_three_fish_kinds` — const-level, headless: all three fish keys present.
  - `test_fish_tints_are_distinct_colours` — const-level: the three tints are pairwise distinct (D-RECON-03 guard against "all blue").
  - `test_quadruped_sets_has_panda` — const-level: panda key present.
  - `test_in_tree_fish_resolves_to_shader_wobble_fish` — display-gated (`pending()` on headless): live `fish_blue` Wildlife resolves `_anim` to a `ShaderWobbleAnimator` with `body_type == BodyType.FISH`.
  - `test_in_tree_panda_resolves_to_quadruped` — display-gated: live `panda` Wildlife resolves `_anim` to a `QuadrupedAnimator`.
- Extended `tests/unit/test_anim_quadruped.gd`: added `test_wildlife_quadruped_sets_has_panda` (const-level) and `test_in_tree_panda_wildlife_resolves_to_quadruped` (display-gated). All 6 original tests retained.
- Anim suite (`-gprefix=test_anim_`): **35 tests, 29 passing, 6 pending (display-gated), 0 failing.** No "Failing" total line.
- Full unit suite: **338 tests, 316 passing, 22 pending, 0 failing** (baseline 08-01 was 331/312/19 — the deltas are exactly the 4 new dispatch tests, 3 of which are display-gated). No regression to the procedural fallback for the other wildlife kinds.

## Deviations from Plan

None — plan executed exactly as written. Rules 1-3 not triggered.

## Deferred Visual Verification (Task 3 — blocking human-verify, auto-approved per auto-mode)

The plan's final task is a `checkpoint:human-verify gate="blocking"` that requires a human to launch the Godot GUI and visually confirm the GPU shader wobble + per-kind tints and the panda leg-rig trot **in a running game world**. This CANNOT be performed headlessly or by the executor — GPU vertex deformation and rig motion need a real viewport.

Per the active auto-mode policy (and mirroring the 08-03 Tier-3 deferral precedent), this is recorded as ⚡ auto-approved-but-DEFERRED. **Code wiring is done and headless dispatch tests are green; the in-viewport visual confirmation has NOT been observed by a human and remains pending.** The exact verification steps are preserved verbatim below so a human can eyeball it later:

> 1. Launch the game and enter a world with an ocean biome (fish) and a land biome with panda spawns. (If a faster path exists, the animator demo scene `src/builder/minifigure_animator_demo.gd` already shows panda walk + fish wobble side by side — but in-WORLD confirmation is what closes SC1/SC2.)
> 2. Find fish underwater: confirm each fish visibly WOBBLES (tail-sway vertex deform), and that fish_orange / fish_yellow render in distinct orange/yellow tints (NOT all blue — D-RECON-03 all-mesh-tint must hold).
> 3. Find a panda: confirm it stands on the ground (feet not buried/floating) and that its FOUR LEGS visibly swing in a trot when it walks, and it does a subtle idle motion when stopped — i.e. it animates via the leg rig, not just a whole-body bob.
>
> **Resume signal:** Type "approved" if fish wobble + tints and panda leg-rig walk/idle are visibly correct in-world, or describe what looks wrong.

## Known Stubs

None. The dispatch is fully wired; no empty-data placeholders introduced.

## Verification Status

- ANIM-01 (fish soft-body via shader-wobble): `_FISH_TINTS` populated; fish resolve to ShaderWobbleAnimator FISH; const + display-gated tests pass. **In-world wobble + tints: deferred visual (above).**
- ANIM-02 (quadruped wildlife): `_QUADRUPED_SETS` populated; panda resolves to QuadrupedAnimator; gait already driven from `_is_walking`; tests pass. **In-world leg-rig motion: deferred visual (above).**
- Dead ghost branch removed (08-VERIFICATION.md anti-pattern resolved).
- Full anim suite: 0 failing.
- No regression to the ProceduralCreatureAnimator fallback for the other ~18 wildlife kinds.

## Self-Check: PASSED

- FOUND: src/world/wildlife.gd
- FOUND: tests/unit/test_anim_wildlife_dispatch.gd
- FOUND: tests/unit/test_anim_quadruped.gd
- FOUND: commit 0c7d21e (feat 08-04 dispatch re-wire)
- FOUND: commit ec69171 (test 08-04 dispatch tests)
