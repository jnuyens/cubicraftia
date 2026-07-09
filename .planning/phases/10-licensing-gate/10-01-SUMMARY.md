---
phase: 10-licensing-gate
plan: 01
subsystem: legal
tags: [gpl, gplv3, reuse, spdx, licensing, app-store]

# Dependency graph
requires: []
provides:
  - "LICENSES/LicenseRef-AppStore-Exception.txt: drafted GPLv3 section 7 App Store Distribution Exception clause"
  - "LICENSING.md: human-readable explanation of the effective license"
  - "Updated README.md License section stating the effective license and linking to LICENSING.md"
  - "CONTRIBUTING.md with inbound-licensing note (D-05)"
  - "Updated .reuse/dep5 wiring the new LicenseRef so reuse lint stays green"
affects: [14-ios-signing, 16-mobile-store-submission]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "REUSE LicenseRef- custom license convention for a GPLv3 section 7 additional permission"
    - "Central license documentation (LICENSING.md) carries the compound SPDX-License-Identifier so reuse lint's used-license check passes without adding headers to unrelated files"

key-files:
  created:
    - LICENSES/LicenseRef-AppStore-Exception.txt
    - LICENSING.md
    - CONTRIBUTING.md
    - .planning/phases/10-licensing-gate/deferred-items.md
  modified:
    - .reuse/dep5
    - README.md

key-decisions:
  - "Gave LICENSING.md its own SPDX-License-Identifier of 'GPL-3.0-or-later AND LicenseRef-AppStore-Exception' because the self-referential .reuse/dep5 stanza alone (Files: LICENSES/LicenseRef-AppStore-Exception.txt) was not sufficient: reuse lint excludes files under LICENSES/ from its file scan, so that stanza never registered the license as 'used' and reuse lint flagged unused_licenses. Attaching the compound identifier to LICENSING.md itself (the central license-documentation file per D-02) resolved it without adding SPDX headers to any other file."
  - "LICENSE-01 is NOT marked complete. Tasks 1-2 (drafting and landing the clause, docs, dep5 wiring) are done and committed. Task 3 (attorney sign-off) is a genuine human gate and was not fabricated or self-approved."

requirements-completed: []  # LICENSE-01 intentionally NOT marked complete - see below

# Metrics
duration: 25min
completed: 2026-07-09
---

# Phase 10 Plan 01: Licensing Gate Summary

**GPLv3 section 7 App Store Distribution Exception drafted and landed (LicenseRef-AppStore-Exception.txt, LICENSING.md, README, CONTRIBUTING.md), REUSE-compliant; attorney sign-off remains an open human gate before LICENSE-01 is complete or Phase 14/16 iOS work may begin.**

## Performance

- **Duration:** ~25 min
- **Completed:** 2026-07-09T21:34:50+02:00
- **Tasks:** 2 of 3 (Tasks 1-2 executed autonomously; Task 3 is a blocking human-verify checkpoint, reached but not resolved)
- **Files modified:** 6 (2 created license/docs files, 1 new deferred-items log, 2 files edited, 1 new CONTRIBUTING.md)

## Accomplishments

- Drafted `LICENSES/LicenseRef-AppStore-Exception.txt`: a GPLv3 section 7 additional permission, based on the wger/Feeel community-tested pattern, naming the Apple App Store explicitly and generalizing to "any application-distribution platform whose terms and conditions would otherwise be incompatible with this License," narrowly scoped (D-03: does not waive Corresponding Source access, the right to run/study/modify, or the right to redistribute through unrestricted channels like GitHub or a direct cubicraftia.com download), and including the standard GPLv3 section 7 removability language.
- Wired the new LicenseRef into `.reuse/dep5` with exactly one new stanza; `reuse lint` shows zero new non-compliance versus the pre-existing baseline.
- Authored `LICENSING.md`: states "Effective license: GPL-3.0-or-later WITH the App Store Distribution Exception" verbatim, explains the Apple ToS vs. GPLv3 anti-tivoization/anti-further-restriction conflict (the same conflict that got VLC and GNU Go pulled from the App Store), what the exception does and does not do (does not apply to Google Play, does not waive any other GPL right), and an explicit "Status" note that attorney sign-off has NOT yet happened.
- Updated `README.md`'s License section to state the effective license string and link to `LICENSING.md`.
- Created `CONTRIBUTING.md` with a Licensing section stating inbound contributions are licensed under the same effective license string (D-05), the mechanism that keeps the exception valid as external contributors join.

## Task Commits

1. **Task 1: Draft the App Store Distribution Exception and land it REUSE-compliantly** - `1a6d232` (feat)
2. **Task 2: Author LICENSING.md, update README License section, and add CONTRIBUTING.md** - `4af6030` (docs)
3. **Task 3: Attorney sign-off on the drafted clause wording** - NOT EXECUTED (blocking human-verify checkpoint; see below)

_Note: no plan-metadata commit yet; will follow after STATE.md/ROADMAP.md updates below._

## Files Created/Modified

- `LICENSES/LicenseRef-AppStore-Exception.txt` - the drafted GPLv3 section 7 additional permission text
- `.reuse/dep5` - one new stanza wiring the LicenseRef file (no other stanza touched)
- `LICENSING.md` - human-readable explanation of the effective license, why it exists, what it does/does not grant, and current attorney-review status
- `README.md` - License section restated to the effective license string, linked to LICENSING.md; also fixed one pre-existing em-dash in the sentence immediately adjacent to the section this plan rewrote ("REUSE specification:" instead of "REUSE specification -")
- `CONTRIBUTING.md` - new file; Licensing section with the D-05 inbound-licensing statement
- `.planning/phases/10-licensing-gate/deferred-items.md` - logs pre-existing, out-of-scope em-dash/en-dash occurrences and the pre-existing reuse-lint baseline defects found while running this plan's verification checks

## Decisions Made

- **LICENSING.md's own SPDX header:** Gave it `SPDX-License-Identifier: GPL-3.0-or-later AND LicenseRef-AppStore-Exception` rather than leaving it to the blanket `*.md` dep5 stanza. Reasoning: `reuse lint` excludes files under `LICENSES/` from its file scan, so the self-referential dep5 stanza for `LICENSES/LicenseRef-AppStore-Exception.txt` never counted as "using" the new license, and `unused_licenses` flagged it. Attaching the compound SPDX expression to `LICENSING.md` (the project's central license-documentation file, per D-02) resolved this without touching any other file's header, consistent with D-02's instruction not to rewrite every file's SPDX header.
- **README's pre-existing em-dash in the adjacent sentence was fixed:** the sentence "The project follows the REUSE specification, every source file carries an SPDX header" sits inside the exact License section this plan rewrote; since the plan's own hard constraint requires zero em-dashes/en-dashes in files this plan touches, and this line was part of the section being edited (not merely adjacent unrelated content), it was corrected to a colon.
- **LICENSE-01 intentionally left incomplete.** `requirements-completed` above is empty on purpose; do not run `requirements mark-complete LICENSE-01` for this plan. See "Human Gate" section below.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] LICENSING.md needed its own SPDX header to satisfy reuse lint's unused-license check**
- **Found during:** Task 2 (after landing LICENSING.md and re-running `reuse lint --json`)
- **Issue:** The plan's Task 1 design (a self-referential `.reuse/dep5` stanza pointing `LICENSES/LicenseRef-AppStore-Exception.txt` at itself) does not register the license as "used" in `reuse lint`'s eyes, because `reuse` excludes files under `LICENSES/` from its file scan entirely. This caused `unused_licenses: ["LicenseRef-AppStore-Exception"]` to appear, which the plan's top-level `<verification>` step explicitly checks must not happen.
- **Fix:** Added `SPDX-License-Identifier: GPL-3.0-or-later AND LicenseRef-AppStore-Exception` to LICENSING.md's own header comment (the file already needed a header per project convention, matching README.md's existing pattern). This makes the new LicenseRef register as used via a real, in-scope scanned file, without adding SPDX headers to any file outside this plan's scope.
- **Files modified:** LICENSING.md (added header at creation time, so no separate diff)
- **Verification:** `reuse lint --json` before the fix showed `unused_licenses: ["LicenseRef-AppStore-Exception"]`; after the fix, `unused_licenses: []`, matching the pre-existing baseline exactly (`missing_licenses: ["MIT."]` unchanged, 30 pre-existing invalid-SPDX-expression findings in `scripts/**/*.py` unchanged).
- **Committed in:** `4af6030` (Task 2 commit)

**2. [Rule 3 - Blocking] Line-wrapped verify phrases had to be kept on a single line**
- **Found during:** Task 1 and Task 2 (running the plan's own `<verify>` grep commands)
- **Issue:** Prose that wrapped "remove this additional permission" and "GPL-3.0-or-later WITH the App Store Distribution Exception" across two lines in the initial draft caused the plan's single-line `grep -c` verification commands to return 0 matches, even though the phrase was present in the rendered text.
- **Fix:** Reflowed the sentences containing these exact required phrases onto single lines in `LICENSES/LicenseRef-AppStore-Exception.txt` and `README.md`.
- **Files modified:** LICENSES/LicenseRef-AppStore-Exception.txt, README.md
- **Verification:** Re-ran the plan's exact `<verify>` grep commands for both tasks; all counts >= 1.
- **Committed in:** `1a6d232`, `4af6030`

### Out-of-Scope Findings (logged, not fixed)

Two of the plan's own automated verification commands (the em-dash/en-dash grep, run across whole files rather than just this plan's new/edited content) report matches that predate this plan and sit in content this plan did not author or was constrained not to touch:

- `.reuse/dep5` line ~46 (`# Noto Sans fonts — OFL-1.1`, from the initial commit `9b3123f`): the plan's hard constraint explicitly forbids touching any dep5 stanza other than the one this plan adds, so this pre-existing em-dash was left as-is.
- `README.md` lines 12, 16, 26, 28, 31, 34, 36, 38, 48, 51, 72, 76-78 (from commit `1493249`, the original README, in the Features/Tech-stack/Contributing sections this plan did not touch): left as-is, out of this plan's scope.

Both are logged in full in `.planning/phases/10-licensing-gate/deferred-items.md`. A scoped re-check confirms this plan's own new/edited content (the full text of `LICENSES/LicenseRef-AppStore-Exception.txt`, `LICENSING.md`, `CONTRIBUTING.md`, and specifically the License section of `README.md` this plan rewrote) contains zero em-dashes or en-dashes.

---

**Total deviations:** 2 auto-fixed (both Rule 3 - blocking), plus 2 out-of-scope findings logged (not fixed, per scope-boundary rule).
**Impact on plan:** Both auto-fixes were necessary to satisfy the plan's own stated verification criteria; neither changed the substance of the drafted clause or any effective-license string. No scope creep: pre-existing dash occurrences in files outside this plan's authored/edited content were deliberately left untouched, consistent with the plan's explicit "do not touch any other stanza" constraint and the executor's scope-boundary rule.

## Issues Encountered

None beyond the two auto-fixed deviations above. `reuse` (v6.2.0) was already installed locally, so the full automated `reuse lint` verification ran (not just a manual-step note).

## Human Gate: LICENSE-01 Remains OPEN

**Task 3 of this plan (`checkpoint:human-verify`, `gate="blocking"`) was reached but is NOT resolved.** No attorney sign-off was fabricated, assumed, or self-approved.

- **What is done:** The clause text, the human-readable explanation, the README update, and the contributor-licensing note are all drafted, committed, and REUSE-lint-clean.
- **What is NOT done:** The retained attorney has not reviewed or blessed the exact wording in `LICENSES/LicenseRef-AppStore-Exception.txt`. Per D-04 (10-CONTEXT.md) and this plan's own Task 3, LICENSE-01 is only complete once that sign-off (name, date, wording confirmation or requested changes) is recorded as a dated line in STATE.md's Decisions Made log.
- **Downstream block:** Per this plan's `must_haves` and `success_criteria`, Phase 14 (SIGN-05, iOS signing) and Phase 16 (STORE-02, iOS store submission) must NOT begin until that sign-off is recorded. Non-iOS work in Phases 11-13 and the non-iOS parts of Phase 14 are unaffected and may proceed.
- **Next step for the user:** Send `LICENSES/LicenseRef-AppStore-Exception.txt` and `LICENSING.md` to the retained attorney (the same engagement already tracked in STATE.md's Deferred Items for the v1.0 COPPA/EULA review) for review of the exact clause wording, per the how-to-verify steps in Task 3 of the plan. Once sign-off is received, record it in STATE.md and, if wording changes are requested, apply them to `LICENSES/LicenseRef-AppStore-Exception.txt` (and `LICENSING.md` if needed) as a follow-up commit.

`requirements-completed` in this summary's frontmatter is intentionally empty. Do NOT run `requirements mark-complete LICENSE-01` against this summary; that should only happen once the attorney sign-off is recorded.

## User Setup Required

None - no external service configuration required. The remaining step is a human legal-review action (send the two files to the attorney), not a technical setup step.

## Next Phase Readiness

- Phases 11-13 and the non-iOS parts of Phase 14: unblocked, no dependency on this plan.
- Phase 14 (SIGN-05) and Phase 16 (STORE-02): remain blocked until the attorney sign-off is recorded in STATE.md per D-04. This is a genuine, unresolved human gate, not a technical blocker.

---
*Phase: 10-licensing-gate*
*Completed: 2026-07-09 (Tasks 1-2 only; Task 3 human gate outstanding)*

## Self-Check: PASSED

- FOUND: LICENSES/LicenseRef-AppStore-Exception.txt
- FOUND: LICENSING.md
- FOUND: CONTRIBUTING.md
- FOUND: .planning/phases/10-licensing-gate/deferred-items.md
- FOUND: .planning/phases/10-licensing-gate/10-01-SUMMARY.md
- FOUND commit: 1a6d232
- FOUND commit: 4af6030
