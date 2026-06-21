---
phase: 09-nl-localisation-review
plan: "01"
subsystem: localisation
tags: [nl, localisation, translations, profanity, review]
dependency_graph:
  requires: []
  provides: [corrected-nl-po, corrected-nl-wordlist, review-artifact-for-09-02]
  affects: [locale/nl.po, assets/profanity/wordlist_nl.txt]
tech_stack:
  added: []
  patterns: [gettext-po, profanity-regex-filter]
key_files:
  created:
    - .planning/phases/09-nl-localisation-review/09-01-REVIEW.md
  modified:
    - locale/nl.po
    - assets/profanity/wordlist_nl.txt
decisions:
  - "sandbox-mode-label: ui.hud.mode.sandbox corrected to 'Sandbox' (not 'Creatief') — game mode is called Sandbox; avoids confusion with world-select creative label"
  - "false-positive-list: 10 common Dutch words removed from profanity wordlist as they block innocent gaming chat"
  - "flemish-coverage: 7 common Flemish/Dutch oath forms added to wordlist (godverdomme, tering, eikel, etc.)"
metrics:
  duration: "~15 minutes"
  completed_date: "2026-06-21"
  tasks_completed: 2
  tasks_total: 2
  files_modified: 3
---

# Phase 9 Plan 1: AI NL Localisation First-Pass Review Summary

AI first-pass review of all NL strings + profanity wordlist: 73 missing translations added, 3 terminology/accuracy fixes applied, 10 profanity false-positives removed, 7 Flemish coverage gaps filled, and a complete side-by-side EN/NL sign-off document produced for the human reviewer in Plan 09-02.

## What Was Built

### Task 1: locale/nl.po corrections

**Header fix:** The comment on line 6 incorrectly said `nop = stud` (implying "stud" translates to "nop"). Corrected to explicitly state both `brick` and `stud` are untranslated brand terms, and `builder -> bouwer`.

**ui.signin.age_checkbox:** Was completely empty. Filled with "Ik ben 13 jaar of ouder." (informal register per D-02).

**ui.hud.mode.sandbox:** Was "Creatief". Corrected to "Sandbox" — the game mode is literally named Sandbox; "Creatief" conflicted with the world-select `mode_creative` label which also says "Creatief". Using the actual mode name eliminates the ambiguity.

**73 missing msgid entries added:**
- 44 brick name entries (bricks.axe, bricks.hammer, bricks.fishing_rod, bricks.compass, bricks.map, bricks.gold_ingot, bricks.coal, bricks.leather, bricks.string, bricks.wheat, bricks.sugar_cane, bricks.obsidian, bricks.furnace, bricks.bucket, bricks.sugar, bricks.bread, bricks.campfire, bricks.coal_block, bricks.bow, bricks.flint_and_steel, bricks.chestplate_iron, bricks.chestplate_leather, bricks.helmet_diamond, bricks.helmet_gold, bricks.nether_portal, bricks.raw_meat, bricks.sashimi, bricks.crafting_table_advanced, bricks.painting_small_1, bricks.painting_small_2, bricks.flower_pot, bricks.pot_red_flower, bricks.pot_blue_flower, bricks.pot_yellow_flower, bricks.pot_white_flower, bricks.pot_pink_flower, bricks.well, bricks.barrel, bricks.bookshelf, bricks.crate, bricks.chair_wood, bricks.anvil, bricks.table_wood, bricks.axe)
- 24 recipe name entries (recipes.pickaxe_stone through recipes.nether_portal)
- 5 UI entries (ui.builder.placed, ui.bed.picked_up, ui.crop.harvest_prompt, ui.title.customize, ui.mystery.orb)

**Result:** nl.po now has 551 msgids (matching en.po exactly). Zero empty msgstr for real strings. Only `ui.username.inline_valid` remains empty — intentional, EN is also empty.

**Terminology audit:** No "noppen", no untranslated "builder", no "Lego"/"Minecraft" outside the two allowlisted legal disclaimer strings. All existing strings passed the D-03 brand-term check.

### Task 2: wordlist_nl.txt corrections

**3 typos fixed:** homseksueel -> homosexueel, smerla -> smeerlap, stomaak removed (not a real Dutch word).

**10 false positives removed:** gore, ras, vent, vieze, vuil, waardeloos, prutsers, puffer, plasser, idioot. These are all ordinary Dutch words in constant use in innocent gaming chat. Blocking "wat een gore hekel heb ik hieraan" or "wat een idioot" would frustrate players without meaningful safety benefit.

**7 Flemish/Dutch coverage gaps filled:** eikel, godver, godverdomme, klere, klerezooi, tering, tyfus. These are among the most common Flemish profanity forms that were absent despite the list already containing similar-strength words.

**Word count:** 69 entries (well under the 500-word T-05-P2 mobile regex timeout limit).

### Task 2: 09-01-REVIEW.md produced

Full side-by-side EN/NL review document with 15 sections covering all 551 msgids, organized by UI surface. Key reviewer flags documented:
- 22 truncation risk strings (NL >50% longer than EN for meaningful strings)
- Reviewer notes on Flemish preference where AI was uncertain
- Profanity wordlist sections with rationale for all changes
- Complete post-correction wordlist verbatim

## Deviations from Plan

None — plan executed exactly as written. The count of "72 missing msgids" in the plan's interface notes was a rough count; the actual gap was 73 entries (the plan listed some overlap in category counts). All were added.

## Known Stubs

None — all translations are substantive. The `ui.username.inline_valid` empty msgstr is intentional (EN source is also empty; it is skipped by `translations.gd`).

## Threat Flags

No new threat surface introduced. Both files (locale/nl.po, wordlist_nl.txt) are bundled in the signed .pck per T-09-01 and T-09-03. The two legal disclaimer strings that name "LEGO Groep" and "Mojang Studios" are confirmed allowlisted per T-09-02 (nl-po-allowlisted-glossary STATE.md decision).

## Self-Check: PASSED

Files created/modified:
- locale/nl.po — FOUND (551 EN msgids now present, verified by overall verification script)
- assets/profanity/wordlist_nl.txt — FOUND (69 words, all checks PASS)
- .planning/phases/09-nl-localisation-review/09-01-REVIEW.md — FOUND (created, 15 sections)

Commits:
- 14b150c: feat(09-01): AI first-pass NL localisation review — correct nl.po
- 81b6d8f: feat(09-01): correct NL profanity wordlist + produce side-by-side review document
