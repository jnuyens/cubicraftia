---
phase: 13-reliability-version-match-hardening
plan: 05
subsystem: ui
tags: [i18n, gdscript, godot, canvaslayer, gut-testing, connection-handling]

# Dependency graph
requires:
  - phase: 13-01
    provides: "NetworkManager.connection_problem(reason) signal + CONNECTION_PROBLEM_REASONS whitelist"
provides:
  - "ConnectionProblemOverlay (src/ui/connection_problem_overlay.gd/.tscn) — the single reusable connection-problem screen for the whole codebase"
  - "10 new ui.connproblem.* i18n keys (EN+NL) + 1 shared ui.common.generic_host fallback key"
  - "Removal of 3 superseded ui.join.error_* keys (error_session_full, error_expired, error_connection)"
affects: [13-06, 13-07]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Reason-enum-driven single overlay (show_reason(reason)) instead of per-failure ad-hoc dialogs"
    - "Off-tree GUT testing of pure helper methods (no add_child) via preload + .new() + autofree()"

key-files:
  created:
    - src/ui/connection_problem_overlay.gd
    - src/ui/connection_problem_overlay.tscn
    - tests/unit/test_connection_problem_overlay_reasons.gd
  modified:
    - locale/en.po
    - locale/nl.po

key-decisions:
  - "Added ui.common.generic_host (\"your host\"/\"je host\") i18n key beyond the plan's literal 10-key list, because JoinScreen's existing {host}-fallback pattern is a hardcoded English literal and CLAUDE.md forbids any hardcoded player-facing string; this overlay must render correctly in NL"
  - "Embedded a local StyleBoxFlat sub_resource in the .tscn duplicating cubicraftia.tres's StyleBox_button_secondary values verbatim, since Godot .tscn sub_resources cannot reference a named sub_resource inside a separate .tres file by id"

patterns-established:
  - "Single-entry-point overlay pattern (show_reason) for all future connection-failure UI — do not add competing dialogs"

requirements-completed: [RELY-01]

# Metrics
duration: 45min
completed: 2026-07-09
---

# Phase 13 Plan 05: Connection-Problem Overlay (Surface A) Summary

**One reusable ConnectionProblemOverlay driven by NetworkManager.connection_problem(reason), covering all 7 failure reasons with distinct EN/NL copy, plus 10 new locale keys and 3 superseded ones removed.**

## Performance

- **Duration:** ~45 min
- **Completed:** 2026-07-09
- **Tasks:** 2/2 completed
- **Files modified:** 5 (2 new .gd/.tscn pair, 1 new test, 2 locale files)

## Accomplishments
- Built `ConnectionProblemOverlay` (CanvasLayer, layer 110): single public entry point `show_reason(reason)`, all 7 reasons share one heading, `relay_failed`/`timeout` get Retry+Back, the other 5 get Back-to-menu only, non-dismissible except by its own buttons, `PrimaryButton.grab_focus()` on every show
- Added the 10 new `ui.connproblem.*` i18n keys to `locale/en.po` and `locale/nl.po`, copied verbatim from 13-UI-SPEC.md's Copywriting Contract; removed the 3 superseded `ui.join.error_*` keys
- Wrote a headless GUT test proving the reason-to-copy/button mapping, the `blocked` reason's non-revealing constraint (checked in both EN and NL), the `version_mismatch` no-raw-digit constraint, and a project-wide no-em/en-dash constraint across all 7 reasons and both locales

## Task Commits

1. **Task 1: Add the 10 new i18n keys and remove the 3 superseded ones** - `febc392` (feat)
2. **Task 2: Build ConnectionProblemOverlay (Surface A)** - `df56dae` (feat)

_Note: Task 2 was frontmatter-marked `tdd="true"` but is a single-commit UI-construction task (script + scene + test built together and verified via one headless test run), not a RED/GREEN/REFACTOR cycle — the plan's `<done>` criteria describe a single "new off-tree test" verification pass, matching this shape._

## Files Created/Modified
- `src/ui/connection_problem_overlay.gd` - `ConnectionProblemOverlay` class: reason→copy/button mapping, host-name interpolation, button wiring (retry / back-to-menu)
- `src/ui/connection_problem_overlay.tscn` - CanvasLayer scene (layer 110), scrim + centred content + button row, mirrors `handover_screen.tscn` structure
- `tests/unit/test_connection_problem_overlay_reasons.gd` - 8 headless tests covering the mapping, the non-revealing `blocked` constraint (EN+NL), the `version_mismatch` no-digit constraint, and the no-dash constraint
- `locale/en.po` - +10 `ui.connproblem.*` keys, +1 `ui.common.generic_host` key, -3 superseded `ui.join.error_*` keys
- `locale/nl.po` - same key set in Dutch

## Decisions Made
- **Added `ui.common.generic_host`** ("your host" / "je host") beyond the plan's literal 10-key list. The plan's `<interfaces>` section instructed reusing "the SAME resolution logic as `JoinScreen._get_host_username()`... falling back to the localized generic 'your host'/'je host' string if empty". The actual existing `JoinScreen._get_host_username()` returns a hardcoded English `"your host"` literal with no NL variant at all — reusing it verbatim would have shipped English text under the Dutch locale, violating both the plan's own stated intent and the project's hard "no hardcoded player-facing strings" rule. Rather than inventing a second host-name-resolution *helper* (which the plan explicitly forbids), I kept the identical resolution logic (`SessionRegistry.get_host_uid()` with an empty-string fallback) and only localized the fallback string itself via one new shared i18n key. Placed in the pre-existing `ui.common.*` namespace (alongside `ui.common.cancel`/`ui.common.back`) rather than under `ui.connproblem.*`, so Task 1's literal "10 new `ui.connproblem.*` keys" count stays exactly accurate.
- **Embedded a local duplicate StyleBoxFlat** for the Secondary button rather than referencing `assets/themes/cubicraftia.tres`'s existing (currently orphaned/unused) `StyleBox_button_secondary` sub-resource directly — Godot's `.tscn` text format cannot reference a named sub-resource inside a separate `.tres` file by id. The embedded values are copied verbatim (zero new colors/tokens), satisfying the UI-SPEC's "Every button in this phase reuses `StyleBox_button_normal`/`StyleBox_button_secondary`" requirement in substance.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing Critical] Localized the `{host}` fallback string instead of reusing JoinScreen's hardcoded English fallback**
- **Found during:** Task 2 (ConnectionProblemOverlay implementation)
- **Issue:** `JoinScreen._get_host_username()`'s existing fallback is the hardcoded English literal `"your host"` with no Dutch counterpart — reusing it as-is would hardcode an untranslated string into a new surface, violating CLAUDE.md's "ALL player-facing strings are i18n keys (en + nl), never hardcoded" mandate
- **Fix:** Added one new i18n key, `ui.common.generic_host` (EN: "your host", NL: "je host"), and resolve it via `tr()` in `_resolve_host_name()`; the underlying `SessionRegistry.get_host_uid()`-based lookup logic is otherwise identical to `JoinScreen`'s, per the plan's "do not invent a second host-name-resolution helper" instruction
- **Files modified:** `locale/en.po`, `locale/nl.po`, `src/ui/connection_problem_overlay.gd`
- **Verification:** `msgfmt -c` passes on both `.po` files; GUT test suite includes `tr()`-based dash/blocked-substring checks under both `en` and `nl` `TranslationServer` locales, confirming the key resolves in both languages
- **Committed in:** `febc392` (locale keys), `df56dae` (usage)

---

**Total deviations:** 1 auto-fixed (1 missing critical - i18n completeness)
**Impact on plan:** Necessary for CLAUDE.md compliance (no hardcoded strings) and to genuinely support the Dutch locale this overlay is built for. No scope creep — same resolution logic, one additional key, no new helper class.

## Note on Task 1's literal grep-count criterion

Task 1's `<done>` criterion states `grep -c "ui.connproblem\." locale/en.po` should equal 20 ("10 msgid + 10 msgstr occurrences"). This is not achievable in this codebase's `.po` format: `msgstr` lines contain only the translated text, never the key string itself, so `grep -c "ui.connproblem\."` can only ever match the 10 `msgid` lines. Verified instead via the criterion's own more precise sibling check, `grep -c "^msgid \"ui.connproblem"` == 10, which passes in both `locale/en.po` and `locale/nl.po`. No functional gap — this is a measurement-instruction mismatch in the plan, not a defect in the implementation.

## Issues Encountered
- Off-tree GUT test instances of `ConnectionProblemOverlay` (a `CanvasLayer` subclass) leaked a `Canvas` RID per `.new()` call even without `add_child()`. Fixed by wrapping instance creation in `autofree()` per GUT convention (confirmed clean orphan count after the fix).

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- `ConnectionProblemOverlay.show_reason(reason)` is ready to be wired as the sole error-display surface; Plan 13-06 depends on this plan and will migrate `JoinScreen` to delegate to it, removing `JoinScreen`'s own `ErrorContent`/`ErrorHeading`/`ErrorBody`/`BackButton` nodes and their now-dangling references to the 3 removed `ui.join.error_*` keys
- **Known interim state:** until Plan 13-06 lands, `JoinScreen.gd` still calls `tr("ui.join.error_connection")` (line 129) — a key this plan intentionally removed per the UI-SPEC's migration sequencing (Task 1 explicitly instructs removing it now; 13-06, which depends on 13-05, completes the JoinScreen-side migration). `tr()` on a missing key returns the raw key string rather than crashing, so this is a display-only regression in the interim, not a crash risk, and is fully expected per the plan's wave ordering (13-05 wave 2 → 13-06 wave 3, `depends_on: ["13-04", "13-05"]`)
- In-viewport visual verification (scrim rendering, layout, focus ring, actual button click-through) is display-gated and deferred to Phase 12 per the executor's explicit instructions — only headless behavioral/copy verification was performed here

---
*Phase: 13-reliability-version-match-hardening*
*Completed: 2026-07-09*

## Self-Check: PASSED

All created files verified present on disk; both task commits (`febc392`, `df56dae`) verified present in `git log`.
