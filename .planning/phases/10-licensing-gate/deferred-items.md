# Deferred Items: Phase 10 Plan 01

Out-of-scope, pre-existing findings discovered while running this plan's automated
verification checks. None of these were introduced by this plan; all predate it and
are excluded from this plan's fix scope per the executor's scope-boundary rule.

## 1. Pre-existing em-dash in .reuse/dep5 (Noto Sans stanza, line ~46)

`# Noto Sans fonts — OFL-1.1` contains a literal em-dash (U+2014). This line is part
of the pre-existing Noto Sans font stanza, introduced in the initial commit
(9b3123f), unrelated to the App Store Distribution Exception stanza this plan added.
This plan's hard constraint explicitly forbids touching any other `.reuse/dep5`
stanza, so this was left as-is. The plan's own Task 1 acceptance grep
(`! grep -Pn "\x{2014}|\x{2013}" ... .reuse/dep5`) therefore reports a match on this
pre-existing line even though the content this plan actually added
(`LICENSES/LicenseRef-AppStore-Exception.txt` and the new dep5 stanza) contains zero
em-dashes or en-dashes, confirmed by a scoped check.

## 2. Pre-existing em-dashes and one en-dash in README.md (Features/Tech-stack/Contributing sections)

Lines 12, 16, 26, 28, 31, 34, 36, 38, 48, 51, 72, 76, 77, 78 of README.md contain
em-dashes or en-dashes (e.g. "2-4 friends" is an en-dash in source, "bricks - not
just 1x1 cubes" style phrasing uses an em-dash). All predate this plan (commit
1493249, "docs: add project README and INSTALL guide") and sit outside the License
section this plan edited (lines 84-91 at the time of editing). This plan's own edits
to README.md (the License section) contain zero em-dashes or en-dashes, confirmed by
a scoped check (`sed -n '84,$p' README.md | grep -P ...` returns no match after this
plan's edit).

## 3. Pre-existing REUSE non-compliance baseline (unchanged by this plan)

`reuse lint` baseline, confirmed both before and after this plan's changes:
- `missing_licenses: ["MIT."]` (a malformed SPDX identifier, likely in a .planning
  doc)
- 30 "Invalid SPDX License Expressions" findings in `scripts/**/*.py` and
  `scripts/triposr/**/*.py` (a literal `\n` token appended to the
  `SPDX-License-Identifier` value in those files' headers)

Both are pre-existing, already tracked, continue-on-error in CI per
`.github/workflows/pr-checks.yml`, and out of scope for this plan.

None of the above block LICENSE-01's engineering deliverables from this plan. They
are logged here for visibility only; a future docs-hygiene pass could clean them up
separately.
