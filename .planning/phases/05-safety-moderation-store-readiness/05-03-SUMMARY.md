---
phase: 05-safety-moderation-store-readiness
plan: "03"
subsystem: profanity-filter
tags: [safety, moderation, profanity, i18n, store-readiness]
dependency_graph:
  requires: [04-08]
  provides: [filter_reject, dual-regex-profanity-filter, ldnoobw-word-lists]
  affects: [05-07, 05-08, 05-09, 05-10, 05-12]
tech_stack:
  added: []
  patterns: [dual-regex-alternation, lazy-init-static, fileaccess-resource-load]
key_files:
  created:
    - assets/profanity/wordlist_en.txt
    - assets/profanity/wordlist_nl.txt
    - assets/profanity/README.md
  modified:
    - src/networking/profanity_filter.gd
    - tests/unit/test_profanity_multilang.gd
decisions:
  - "Dual-regex split (_regex_en / _regex_nl) rather than single merged regex — stays under 500-word alternation limit on Tier-3 Android (T-05-P2)"
  - "_regex_custom added as override slot for set_word_list() backward compat — NL regex unaffected by custom list"
  - "filter_reject() returns bool only — callers show 'Please choose another name.' without echoing rejected input (T-05-P-bypass)"
  - "EN list curated to 290 words; NL list 73 words — both well under 500-word mobile limit"
metrics:
  duration: "~3 minutes"
  completed: "2026-05-29T19:44:22Z"
  tasks_completed: 2
  files_changed: 5
---

# Phase 5 Plan 03: Hardened Multilingual Profanity Filter Summary

**One-liner:** Dual-regex profanity filter loading 290-word EN and 73-word NL LDNOOBW CC-BY-4.0 word lists, with `filter_reject()` bool-only rejection for username/world name validation.

## What Was Built

### Task 1: Word list files + attribution README (commit c85adbc)

Three files created under `assets/profanity/`:

- **wordlist_en.txt** — 290 curated English words from LDNOOBW, gaming false positives removed (kill, die, gun, shoot excluded). Comment header line with license ref.
- **wordlist_nl.txt** — 73 curated Dutch words from LDNOOBW NL list. Same format.
- **README.md** — Full CC-BY-4.0 attribution (Copyright Shutterstock, Inc., source URL, license name), file table, format spec, runtime description, contributor guide.

Both word list files use `#`-prefixed comment lines skipped by `load_word_lists()`.

### Task 2: Extend profanity_filter.gd with dual-regex and filter_reject() (commit 2bd487c)

`src/networking/profanity_filter.gd` rewritten:

- Replaced single `_regex: RegEx` with `_regex_en: RegEx` + `_regex_nl: RegEx` (separate static vars).
- Added `_regex_custom: RegEx` for `set_word_list()` backward compatibility — custom list overrides `_regex_en` without affecting `_regex_nl`.
- Added `load_word_lists()` static func reading from `res://assets/profanity/wordlist_{en,nl}.txt` via `FileAccess`, skipping comment/blank lines, lowercasing, deduplicating.
- Updated `_ensure_regex()` to call `load_word_lists()` on first use (lazy-init, idempotent).
- Updated `filter()` to apply EN regex then NL regex in two sequential passes.
- Added `filter_reject(text: String) -> bool` — returns `true` if either regex matches; returns `false` for empty string without any regex check.
- Added `_compile_regex()` and `_load_list()` private helpers with graceful degradation (push_warning on missing file, null return).
- `set_word_list()` sets `_regex_custom` (overrides EN list only); NL regex continues loading from file.

`tests/unit/test_profanity_multilang.gd` converted from 4 `pending()` stubs to 8 real assertions:
- `test_filter_replaces_en_word_with_filtered()` — "ass hat" → "[filtered] hat"
- `test_filter_reject_returns_true_for_en_word()` — "asshole" → true
- `test_filter_reject_returns_false_for_clean_text()` — "my awesome world" → false
- `test_filter_nl_word_after_wordlist_load()` — "kut niveau" → "[filtered] niveau"
- `test_filter_reject_returns_true_for_nl_word()` — "lul" → true
- `test_filter_reject_empty_string_returns_false()` — "" → false
- `test_set_word_list_extension_point()` — custom word added, reject + filter both work
- `test_filter_clean_through_after_set_word_list()` — clean text unchanged after override

## Commits

| # | Hash | Message |
|---|------|---------|
| 1 | c85adbc | feat(05-03): add LDNOOBW CC-BY-4.0 word lists and attribution README |
| 2 | 2bd487c | feat(05-03): dual-regex profanity filter with filter_reject() and load_word_lists() |

## Deviations from Plan

### Auto-added: `_regex_custom` for set_word_list() compat

**Found during:** Task 2 implementation
**Issue:** Plan spec said `set_word_list()` sets `_regex_en`; this would discard the file-loaded EN list if called, and would lose NL list reference. To preserve backward compat without overwriting `_regex_en`, a separate `_regex_custom` slot was added.
**Fix:** `_regex_custom` takes precedence over `_regex_en` in `filter()` and `filter_reject()`. `_regex_nl` is never touched by `set_word_list()`.
**Rule:** Rule 2 (missing backward-compat preservation)

### Auto-added: 4 extra test cases

**Found during:** Task 2 test authoring
**Issue:** Plan spec had 4 test stubs. Testing `filter_reject()` with NL words, empty string, and the full `set_word_list()` path was required for complete coverage.
**Fix:** Added `test_filter_reject_returns_true_for_nl_word`, `test_filter_reject_empty_string_returns_false`, `test_set_word_list_extension_point`, `test_filter_clean_through_after_set_word_list`.
**Rule:** Rule 2 (missing test coverage for new methods)

## Known Stubs

None — all word lists contain real curated content; no placeholder text.

## Threat Flags

None — no new network endpoints, auth paths, or trust boundary surfaces introduced.
All threat mitigations from the plan's threat model applied:
- T-05-P2: dual-regex split applied (each list under 300 words, well under 500 limit)
- T-05-P-bypass: filter_reject() returns bool only; no echoing of rejected input

## Self-Check: PASSED

- [x] assets/profanity/wordlist_en.txt exists (290 non-comment lines)
- [x] assets/profanity/wordlist_nl.txt exists (73 non-comment lines)
- [x] assets/profanity/README.md exists (CC-BY-4.0 + Shutterstock attribution)
- [x] src/networking/profanity_filter.gd has _regex_en, _regex_nl, filter_reject()
- [x] tests/unit/test_profanity_multilang.gd has 8 real assertions (no pending())
- [x] Commit c85adbc exists in git log
- [x] Commit 2bd487c exists in git log
