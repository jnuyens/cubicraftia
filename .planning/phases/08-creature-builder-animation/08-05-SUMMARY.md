---
phase: 08-creature-builder-animation
plan: 05
subsystem: combat-animation
tags: [animation, hostile, shader-wobble, slime, ghost, gap-closure, ANIM-01]
requires:
  - "src/builder/shader_wobble_animator.gd (ShaderWobbleAnimator BodyType.SLIME/GHOST, all-mesh tint D-RECON-03)"
  - "src/combat/hostile_mob.gd (_anim field, _apply_art_mesh, _update_animator GPU no-op)"
  - "assets/meshes/avatars/slime/slime.glb, assets/meshes/avatars/ghost/ghost.glb"
provides:
  - "cube_slime (all 3 tiers) animates via ShaderWobbleAnimator(SLIME), sized per tier"
  - "ghost animates via ShaderWobbleAnimator(GHOST)"
  - "wiring-level tests asserting hostile soft-body wobble dispatch"
affects:
  - "src/combat/cube_slime.gd"
  - "src/combat/ghost.gd"
  - "tests/unit/test_anim_shader_wobble.gd"
tech-stack:
  added: []
  patterns:
    - "Hostile soft-body creatures construct ShaderWobbleAnimator in _ready and assign to inherited _anim (mirrors wildlife._setup_animator FISH branch + minifigure_animator_demo._spawn_wobble)"
    - "Per-tier slime size driven by scaling the wobble animator node by _art_target_height()"
    - "Textured Meshy art (_art_mesh_root) hidden so it does not double-render behind the wobble mesh"
key-files:
  created: []
  modified:
    - "src/combat/cube_slime.gd"
    - "src/combat/ghost.gd"
    - "tests/unit/test_anim_shader_wobble.gd"
decisions:
  - "slime-wobble-scale-by-target-height: per-tier slime size = ShaderWobbleAnimator.scale = _art_target_height() (0.6/0.9/1.3); reuses the existing tier sizing source rather than SCALE_PER_TIER so SMALL<MEDIUM<LARGE without a new constant"
  - "hostile-art-mesh-hidden-for-wobble: _art_mesh_root.visible=false (null-guarded) on both creatures so the textured Meshy art does not overlap the GPU wobble mesh"
metrics:
  duration: ~4 min
  completed: 2026-06-10
  tasks: 3 auto + 1 deferred checkpoint
  files: 3
---

# Phase 8 Plan 05: Hostile Soft-Body Wobble (Slime + Ghost) Summary

Re-wired the two hostile soft-body creatures (cube_slime all 3 tiers, ghost) from the transform-only ProceduralCreatureAnimator to the ShaderWobbleAnimator GPU wobble system that ROADMAP SC1 explicitly names — closing the slime + ghost portion of GAP 1 (SC1/ANIM-01). Fish were handled in 08-04; this plan completes SC1's soft-body set. All combat (hop, tier split, wall-pass, bed-bubble repel, chime) is preserved.

## What Was Built

- **cube_slime.gd** — `_ready()` now constructs a `ShaderWobbleAnimator(BodyType.SLIME)` (mesh_set `"slime"`, body_colour `#3DB560`, speed 2.4, amount 0.22, randomised time_offset), scales it by `_art_target_height()` per tier so a SMALL slime reads visibly smaller than a LARGE one, `add_child`s it and assigns it to the inherited `_anim`. The `$Body` placeholder and the textured Meshy `_art_mesh_root` are both hidden. The `_setup_procedural_anim(LAND)` call is removed.
- **ghost.gd** — `_ready()` now constructs a `ShaderWobbleAnimator(BodyType.GHOST)` (mesh_set `"ghost"`, body_colour `#F1F0EA`, speed 1.6, amount 0.30, randomised time_offset), `add_child`s it and assigns to `_anim`. `$Body` and `_art_mesh_root` hidden; `_setup_procedural_anim(AIR)` removed. The GHOST alpha/shimmer is driven inside `creature_wobble.gdshader`; `PHASE_SHIMMER_ALPHA` + the D-09 shimmer particles (SEEK-state VFX) are left untouched.
- **test_anim_shader_wobble.gd** — two new display-gated wiring tests assert `cube_slime._anim` / `ghost._anim` resolve to `ShaderWobbleAnimator` with `BodyType.SLIME` / `GHOST` after a frame; both `pending()` on headless per the canonical guard.

## Tasks Completed

| Task | Name | Commit | Files |
| ---- | ---- | ------ | ----- |
| 1 | Re-wire cube_slime to ShaderWobbleAnimator(SLIME), sized per tier | ef2068e | src/combat/cube_slime.gd |
| 2 | Re-wire ghost to ShaderWobbleAnimator(GHOST) | 376ec29 | src/combat/ghost.gd |
| 3 | Hostile soft-body wobble dispatch tests + green suites | f93bab4 | tests/unit/test_anim_shader_wobble.gd |
| 4 | checkpoint:human-verify (blocking) | — | DEFERRED — see below |

## Test Results (headless GUT)

- **Slime split suite** (`test_slime`): no Failing line — 4 pre-existing pending stubs (CubeSlime test-stub gating from Plan 03-09), unchanged by this plan.
- **Hostile suite** (`test_anim_hostiles`): 10/10 passing.
- **Anim suite** (`test_anim_`): 37 tests, 29 passing, 8 pending (display-gated incl. the 2 new ones), 0 failing.
- **Full unit suite**: 340 tests, 316 passing, 24 pending, 0 failing. (Up from the 08-01 baseline 331/312/19 — the new tests are accounted for; nothing regressed.)

Combat preserved: no edits to `_on_die`, `_spawn_children`, the hop mechanic, the tier/HP logic, the bed-bubble repel block (`is_inside_any_bed_bubble`, `BUBBLE_REPEL_FORCE`), the chime, `collision_layer=0 / collision_mask=0` wall-pass setup, or the ghost state machine.

## Decisions Made

- **slime-wobble-scale-by-target-height** — Per-tier slime size = `ShaderWobbleAnimator.scale = Vector3.ONE * _art_target_height()` (0.6 / 0.9 / 1.3). Reuses the creature's existing tier-height source rather than introducing a wobble-specific scale constant, so SMALL < MEDIUM < LARGE with no new tunable.
- **hostile-art-mesh-hidden-for-wobble** — Both creatures null-guard `_art_mesh_root.visible = false` so the textured Meshy art (loaded by the base `_apply_art_mesh` for the v1.1 art pass) does not double-render behind the GPU wobble mesh. Mirrors the wildlife `_hide_mesh_root()` pattern.

## Deviations from Plan

None — plan executed exactly as written.

## Deferred Visual Verification (Task 4 — blocking checkpoint, auto-approved per auto-mode)

Auto-mode is active. The final task is a `checkpoint:human-verify gate="blocking"` requiring a live Godot GUI survival session to confirm GPU wobble + combat coexistence. That visual + combat-behaviour confirmation **cannot be performed headlessly or by the executor**. Per auto-mode semantics (mirroring the 08-03 Tier-3 benchmark and 08-04 in-world deferrals), it is recorded here as **auto-approved-but-deferred**.

**Status: code wiring done + headless tests green; in-viewport visual + combat-coexistence confirmation NOT yet observed by a human.** The GPU rendering / combat behavior has NOT been visually verified — it is deferred pending a human eyeball in a running survival session.

**How to verify (preserved verbatim from the plan):**

1. Enter a survival session and trigger a slime encounter. Confirm: the slime visibly SQUASHES/STRETCHES (GPU wobble), a LARGE slime is clearly bigger than a SMALL one, it still HOPS toward you, and defeating a LARGE one still SPLITS it into smaller slimes.
2. Trigger a ghost encounter. Confirm: the ghost FLOATS with a soft alpha pulse/shimmer (wobble + D-09 shimmer), it still phases through walls/terrain, plays the chime on detection, and is REPELLED at a bed-bubble boundary (D-10).
3. Confirm neither creature shows a doubled/overlapping mesh (the textured Meshy art must be hidden behind the wobble mesh).

**Resume signal:** Type "approved" if slime squash + tier sizing + split and ghost float/alpha + wall-pass + bed-bubble repel all look correct with no doubled mesh, or describe what looks wrong.

## Known Stubs

None introduced by this plan. (The 4 `test_slime_split.gd` pending stubs are pre-existing Plan-03-09 test gating, not new.)

## Self-Check: PASSED

- src/combat/cube_slime.gd — FOUND (contains ShaderWobbleAnimator, no _setup_procedural_anim)
- src/combat/ghost.gd — FOUND (contains ShaderWobbleAnimator + BUBBLE_REPEL_FORCE, no _setup_procedural_anim)
- tests/unit/test_anim_shader_wobble.gd — FOUND (2 new dispatch tests)
- Commit ef2068e — FOUND
- Commit 376ec29 — FOUND
- Commit f93bab4 — FOUND
