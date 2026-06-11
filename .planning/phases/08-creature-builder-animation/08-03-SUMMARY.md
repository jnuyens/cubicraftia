---
phase: 08-creature-builder-animation
plan: 03
subsystem: testing
tags: [performance, animation, anim-06, frame-budget, tier-3, deferred]

# Dependency graph
requires:
  - phase: 08-creature-builder-animation/08-01
    provides: ANIM-01..05 headless test evidence (animation archetypes confirmed green)
  - phase: 08-creature-builder-animation/08-02
    provides: CONTEXT.md reconciled with shipped reality; STATE.md Phase 8 ledger corrected
provides:
  - ANIM-06 frame-budget evidence: desktop smoke PASS (0.00085 ms/creature vs < 1 ms/creature target)
  - 08-ANIM-06-PERF.md with desktop FPS delta and explicit Tier-3 hardware-gated deferral
  - STATE.md line 74 updated from "result — TBD" to desktop smoke result + deferral notice
  - tests/perf/anim_frame_budget.gd headless harness measuring ProceduralCreatureAnimator cost
affects: [phase-9-nl-localisation-review, v1.1-milestone-close]

# Tech tracking
tech-stack:
  added: [tests/perf/anim_frame_budget.gd — headless frame-budget harness (ProceduralCreatureAnimator)]
  patterns:
    - "Headless perf harness: Time.get_ticks_usec() bracketing over SAMPLE_FRAMES with animated vs static baseline delta; captures per-creature cost without GPU context"
    - "Two-leg gate pattern: autonomous desktop smoke (Phase 1 precedent) + Tier-3 hardware run deferred with exact runnable instructions when device unavailable"
    - "Deferral record format: exact command, device model+SKU, prerequisites, pass threshold — mirrors v1.0 hardware debt format"

key-files:
  created:
    - .planning/phases/08-creature-builder-animation/08-ANIM-06-PERF.md
    - tests/perf/anim_frame_budget.gd
  modified:
    - .planning/STATE.md

key-decisions:
  - "anim-06-desktop-smoke-pass: desktop ProceduralCreatureAnimator cost 0.00085 ms/creature (23-creature roster, 1000 sample frames, Option A headless fallback sub-case); well under < 1 ms/creature target (1180x margin)"
  - "anim-06-tier3-deferred-hardware-gated: Tier-3 authoritative run deferred with exact instructions (bash scripts/run-benchmark.sh, Motorola One Macro XT2016-1, adb + Android export template + mains power, >= 30 FPS pass threshold); mirrors v1.0 hardware debt precedent; approved by user 2026-06-09"

patterns-established:
  - "Pattern: performance tests under tests/perf/ are standalone headless scripts (not GUT suites), run via godot --script; SPDX-headered GPL-3.0-or-later; parametric creature count + sample size constants"

requirements-completed: [ANIM-06]

# Metrics
duration: 15min
completed: 2026-06-09
---

# Phase 8 Plan 03: ANIM-06 Frame-Budget Gate Summary

**Desktop ProceduralCreatureAnimator smoke PASS (0.00085 ms/creature, 1180x under target); Tier-3 Motorola hardware run deferred as explicit hardware debt with runnable instructions — approved by user.**

## Performance

- **Duration:** ~15 min
- **Started:** 2026-06-09T20:00:00Z
- **Completed:** 2026-06-09T20:22:26Z
- **Tasks:** 2 (Task 1 autonomous + Task 2 deferral confirmation)
- **Files modified:** 3

## Accomplishments

- Wrote `tests/perf/anim_frame_budget.gd` — a headless harness that instantiates 23 `Node3D` stand-ins + `ProceduralCreatureAnimator` instances, runs 200 warmup frames then 1000 animated and 1000 static sample frames, and computes the per-creature CPU cost with sub-millisecond precision via `Time.get_ticks_usec()` bracketing.
- Desktop result: 0.0201 ms/frame animated vs 0.0004 ms/frame static → delta 0.0197 ms/frame → **0.00085 ms/creature** — PASS vs the CONTEXT.md `< 1 ms/creature` target (1180x margin). At the Tier-3 33.3 ms/frame budget the full 23-creature roster consumes ~0.06% of the frame budget.
- Created `08-ANIM-06-PERF.md` recording the complete measurement environment, method, results table (animated/static/delta/p95/p99), verdict, and full Tier-3 run-or-defer instructions. The deferral is unambiguous: exact command, device model (XT2016-1), prerequisites, and the >= 30 FPS pass threshold are all present.
- Updated STATE.md line 74 from "result — TBD" to the desktop smoke result + explicit deferral notice, consistent with the existing v1.0 hardware-debt format (Phases 1–6 Tier-3/UAT deferral entries).
- User approved Option B (CONFIRM THE DEFERRAL) on 2026-06-09: the authoritative on-device benchmark remains outstanding hardware debt.

## ANIM-06 Outcome

| Leg | Status | Detail |
|-----|--------|--------|
| Part 1 — Desktop smoke (autonomous) | PASS | 0.00085 ms/creature ProceduralCreatureAnimator; 23 creatures, 1000 frames |
| Part 2 — Tier-3 Motorola hardware run | DEFERRED (hardware-gated) | Approved by user 2026-06-09; instructions in `08-ANIM-06-PERF.md` Part 2 |

**The authoritative on-device benchmark (bash scripts/run-benchmark.sh on Motorola One Macro XT2016-1) remains outstanding debt**, recorded alongside the existing v1.0 Tier-3 hardware items (Phase 1 mobile-perf spike, Phase 2 hardware UAT, Phase 3 hardware UAT).

## Task Commits

1. **Task 1: Autonomous desktop FPS smoke** - `da5fec5` (perf)
   - Created `tests/perf/anim_frame_budget.gd`
   - Created `.planning/phases/08-creature-builder-animation/08-ANIM-06-PERF.md`
   - Updated `.planning/STATE.md` line 74

2. **Task 2: Tier-3 deferral confirmation** - no new code commit required; the deferral was fully recorded in Task 1 commit `da5fec5`. SUMMARY.md and metadata committed below.

**Plan metadata:** (final docs commit — see below)

## Files Created/Modified

- `tests/perf/anim_frame_budget.gd` — Headless ANIM-06 frame-budget harness; 23 creatures × 1000 frames animated vs static baseline; prints per-creature cost and PASS/FAIL verdict
- `.planning/phases/08-creature-builder-animation/08-ANIM-06-PERF.md` — ANIM-06 perf record: desktop smoke (Part 1) + Tier-3 deferral with exact runnable instructions (Part 2)
- `.planning/STATE.md` — Performance Metrics line 74 updated from "result — TBD" to desktop smoke result + Tier-3 deferred

## Deviations from Plan

None. Task 1 executed as specified (Option A, headless fallback sub-case — `.glb` assets not loadable without GPU context; ProceduralCreatureAnimator path measured, which is the dominant path for ~18 of 23 creatures). Task 2 resolved as Option B (deferral) per user approval on 2026-06-09.

## Known Stubs

None in this plan — the plan produces a measurement record and updates planning documents only; no UI or game code was created or modified.

## Hardware Debt Tracking

The Tier-3 hardware run for ANIM-06 is now formally tracked in STATE.md Deferred Items alongside the existing v1.0 hardware debt. The run can be discharged at any time by a developer with:
- Physical Motorola One Macro (XT2016-1), USB debugging enabled, mains power connected
- `adb devices` confirming the device is listed
- Android export template for Godot 4.6.3 installed
- Command: `bash scripts/run-benchmark.sh` from the repo root (~31 minutes)
- Pass threshold: worst-30s-window min-FPS >= 30 FPS over the last 10 minutes

## Self-Check: PASSED

- [x] `da5fec5` exists in git log
- [x] `tests/perf/anim_frame_budget.gd` exists on disk
- [x] `.planning/phases/08-creature-builder-animation/08-ANIM-06-PERF.md` exists on disk
- [x] STATE.md line 74 reads "desktop smoke recorded ... Tier-3 hardware run deferred" (not "TBD")
- [x] ANIM-06 outcome documented as desktop PASS + Tier-3 deferred (approved by user)
