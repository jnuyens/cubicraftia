---
phase: 05-safety-moderation-store-readiness
plan: "06"
subsystem: legal-documents
tags: [eula, privacy-policy, coppa, gdpr, legal, store-readiness]
dependency_graph:
  requires: [05-02, 05-04, 05-05]
  provides: [docs/EULA.md, docs/PRIVACY.md]
  affects: [src/ui/legal_viewer.gd, supabase/migrations/008_profiles_safety_columns.sql]
tech_stack:
  added: []
  patterns: [renderer-compatible-markdown, plain-language-summary-plus-legal-text]
key_files:
  created:
    - docs/EULA.md
    - docs/PRIVACY.md
  modified: []
decisions:
  - "Both documents are templates requiring attorney review before public release (stated explicitly in each file)"
  - "Size constraint met: EULA 1913 bytes (under 2048), PRIVACY 2558 bytes (under 2560)"
  - "Only renderer-supported Markdown used: H1-H3, bold, italic, unordered lists, plain paragraphs"
  - "GPL-3.0-or-later referenced as the project licence in EULA per plan requirement"
  - "No-affiliation disclaimer covers both the LEGO Group and Mojang Studios"
metrics:
  duration_seconds: 349
  completed_date: "2026-05-29"
  tasks_completed: 2
  tasks_total: 2
  files_created: 2
  files_modified: 0
---

# Phase 05 Plan 06: EULA and Privacy Policy Summary

GPL-3.0-or-later Terms of Use and COPPA/GDPR Privacy Policy in renderer-compatible Markdown, sized within in-app viewer limits.

## What Was Built

Two bundled legal documents for Cubicraftia v1:

- **docs/EULA.md** (1913 bytes): End-User License Agreement with a 5-bullet plain-language summary, GPL-3.0-or-later licence grant, no-affiliation disclaimer (LEGO Group, Mojang Studios), acceptable-use clause including CSAM/NCMEC forwarding reference, 7-day account-deletion grace period, disclaimer of warranty, and a governing-law placeholder for operator localisation.

- **docs/PRIVACY.md** (2558 bytes): Privacy Policy with a 4-bullet plain-language summary, full data-collection inventory (email, hashed password, username, friend list, blocked list, world ownership, parental consent record with timestamp, opt-in anonymous crash data), COPPA email-plus parental consent flow, GDPR data-subject rights (access, rectification, erasure, portability, objection), NCMEC CSAM forwarding obligation, Supabase as the sole data processor, and a data portability note (manual export for v1).

Both files are formatted using only the Markdown subset supported by the in-app renderer (H1-H3, bold, italic, unordered lists, plain paragraphs — no tables, code blocks, or images).

## Commits

| Hash | Message |
|------|---------|
| ac1d11e | feat(05-06): add EULA.md and PRIVACY.md for Cubicraftia v1 |

## Task Results

| Task | Name | Status | Commit |
|------|------|--------|--------|
| 1 | docs/EULA.md — End-User License Agreement | Done | ac1d11e |
| 2 | docs/PRIVACY.md — Privacy Policy | Done | ac1d11e |

## Verification Results

- docs/EULA.md exists: PASS
- docs/PRIVACY.md exists: PASS
- GPL-3.0 reference in EULA: PASS
- Summary section in EULA: PASS
- Summary section in PRIVACY: PASS
- NCMEC reference in PRIVACY: PASS
- NCMEC reference in EULA: PASS
- blocked list enumerated in PRIVACY: PASS
- Parental consent / COPPA in PRIVACY: PASS
- 7-day deletion grace in EULA: PASS
- No-affiliation disclaimer in EULA: PASS
- No tables in either file: PASS
- No code blocks in either file: PASS
- EULA under 2048 bytes (1913): PASS
- PRIVACY under 2560 bytes (2558): PASS

## Deviations from Plan

None — plan executed exactly as written. Both files were iteratively trimmed to meet the byte-size constraints specified in the verification block while preserving all required content.

## Known Stubs

- Governing-law clause in EULA.md Section 7: placeholder tells operators to localise the jurisdiction. This is intentional — the template cannot know the operator's jurisdiction.
- Contact email in PRIVACY.md Section 9: placeholder `operator-contact-email@example.com` must be replaced before public release.

## Threat Flags

| Flag | File | Description |
|------|------|-------------|
| threat_flag: repudiation | docs/PRIVACY.md | Privacy nutrition label (Plan 05-11) must exactly match the data categories enumerated in Section 1 (email, hashed password, username, friend list, blocked list, world ownership, parental consent record, opt-in crash data) |

## Self-Check: PASSED

- docs/EULA.md: FOUND
- docs/PRIVACY.md: FOUND
- 05-06-SUMMARY.md: FOUND
- commit ac1d11e: FOUND
