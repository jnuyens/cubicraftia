---
phase: "05-safety-moderation-store-readiness"
plan: 11
subsystem: store-readiness
tags: [store, app-store, play-store, ios-ci, code-signing, accessibility, age-rating, privacy]

dependency_graph:
  requires: [05-06]
  provides: [store-readiness-docs, ios-ci-row]
  affects: [.github/workflows/ci.yml]

tech_stack:
  added: []
  patterns:
    - Apple App Store privacy nutrition label JSON schema
    - IARC age-rating questionnaire documentation
    - WCAG 2.1 AA accessibility self-assessment
    - dulvui/godot-ios-upload@v4 GitHub Actions action
    - Apple code signing via dedicated build.keychain on macos-15 runner

key_files:
  created:
    - docs/store-readiness/app-store-metadata.md
    - docs/store-readiness/play-store-metadata.md
    - docs/store-readiness/privacy-nutrition.json
    - docs/store-readiness/age-rating.md
    - docs/store-readiness/accessibility-statement.md
    - docs/store-readiness/screenshot-checklist.md
    - docs/store-readiness/code-signing-runbook.md
  modified:
    - .github/workflows/ci.yml

decisions:
  - "privacy-nutrition-data-categories: data_linked_to_user includes emailAddress, userID, username, gameplayContent, socialGraph (chat + friends); data_not_linked_to_user includes crashData (opt-in anonymous only)"
  - "ios-ci-skip-graceful: export_ios job conditional on APPLE_CERTIFICATE_P12 != '' — no secrets = silent skip, not a build failure"
  - "siwa-not-required-documented: SIWA not required for v1 (email-only auth, no third-party sign-in); documented in both code-signing-runbook.md and 05-CONTEXT.md Specifics §1"
  - "d-04-closed: Phase 1 D-04 deviation (manual iOS export) closed by export_ios job on macos-15 + dulvui/godot-ios-upload@v4"
  - "iarc-friends-only-mitigating: friends-only architecture documented as primary mitigating factor for online-interaction IARC rating bump; target Everyone 10+ / PEGI 7"

metrics:
  duration: "6m 39s"
  completed_date: "2026-05-29"
  tasks_completed: 2
  tasks_total: 2
  files_created: 7
  files_modified: 1
---

# Phase 05 Plan 11: Store Readiness Documentation Suite + iOS CI Summary

**One-liner:** Seven store-readiness documents (App Store/Play Store metadata, Apple privacy nutrition label JSON, IARC age-rating questionnaire, WCAG AA accessibility statement, screenshot checklist, code-signing runbook) plus iOS CI on macos-15 with `dulvui/godot-ios-upload@v4`, closing the Phase 1 D-04 deviation.

## Tasks Completed

| Task | Name | Commit | Key files |
|------|------|--------|-----------|
| 1 | Store-readiness documents (7 files) | 90d03a9 | docs/store-readiness/* (7 new files) |
| 2 | iOS CI row in .github/workflows/ci.yml | 75b7563 | .github/workflows/ci.yml |

## What Was Built

### Task 1 — Store-Readiness Documents

**`docs/store-readiness/app-store-metadata.md`**
Complete App Store Connect submission template: name "Cubicraftia: Brick Sandbox" (26 chars), subtitle "Build worlds. With friends." (27 chars), ~1980-char description using neutral terminology (no "Lego"/"Minecraft"), keywords string 76/100 chars, screenshot slot table, pricing, localisation note, and a pre-submission checklist.

**`docs/store-readiness/play-store-metadata.md`**
Google Play Console metadata adapted from the App Store template: short description 65/80 chars, full description ~1730/4000 chars, feature graphic spec (1024×500 JPEG), content rating summary table, data safety table (email, userID, username, gameplay, crashData), pre-submission checklist.

**`docs/store-readiness/privacy-nutrition.json`**
Valid JSON following Apple's privacy nutrition label schema with:
- `data_used_to_track: []` — no cross-app tracking, no advertising IDs
- `data_linked_to_user`: emailAddress (auth), userID (Supabase UUID), username (display name), gameplayContent (world saves), otherUserContent (chat relay evidence on reports), socialGraph (friends + blocks)
- `data_not_linked_to_user`: crashData (opt-in, anonymous)
- `not_collected` list: dateOfBirth, advertisingData, location, voice, financials, etc.
- `parental_consent_data` section documenting parent_email + consent_record + raw DOB never stored (matches PRIVACY.md §1 and GDPR minimum-data decision)
- Cross-reference note to docs/PRIVACY.md for reviewer consistency check

**`docs/store-readiness/age-rating.md`**
Full IARC questionnaire answers with rationale per question. Target ratings: 12+ (App Store), Everyone 10+ (ESRB), PEGI 7 (Europe), USK 6 (Germany). Key factors documented:
- Violence: Mild fantasy (brick constructs, no blood/gore)
- Online interaction: Yes, friends-only — strong mitigating factor per 05-RESEARCH.md Assumption A5
- UGC: Yes, friends-only scope + profanity filter + block/report + parental gate
- No gambling, no real-money purchases, no ads, no voice chat
- COPPA under-13 gate documented as independent of IARC rating

**`docs/store-readiness/accessibility-statement.md`**
WCAG 2.1 AA self-assessment: colour contrast table showing dominant surfaces exceed 4.5:1 (white on navy ~8.5:1, white on dark panel ~7:1, button labels ~4.7:1). Input coverage: full keyboard, touch targets 44px minimum, gamepad planned v1.1. Screen reader deferred (Godot 4.6 a11y APIs maturing). Font scaling deferred to v1.1. Reduce-motion detection via Godot 4.6 `get_setting("accessibility/screen_reader/enabled")` in progress.

**`docs/store-readiness/screenshot-checklist.md`**
Required sizes: iPhone 6.9" (1320×2868), iPhone 6.5" (1242×2688), iPad 13" (2064×2752), Android phone (1080×1920 min), feature graphic (1024×500). Six suggested shot scenes with content guidance. Manual capture workflow and per-shot review checklist. File naming convention. Completion status table (0/6 per device — not yet captured).

**`docs/store-readiness/code-signing-runbook.md`**
Step-by-step for all platforms:
1. macOS: Apple Developer ID + `xcrun notarytool` notarisation + stapling
2. iOS: Apple Developer Program + Distribution cert + provisioning profile → base64 secrets → TestFlight via App Store Connect API key
3. Android: Google Play App Signing (upload key vs. app signing key distinction), `keytool` key generation, Play Console enrolment
4. Windows: Authenticode (optional for v1, not required for itch.io)
5. GitHub Actions secrets reference table (11 secrets named)
6. SIWA decision: not required for v1 (email-only auth)
7. Annual renewal reminders table

### Task 2 — iOS CI Row

Added `export_ios` job to `.github/workflows/ci.yml`:
- Runner: `macos-15` (Xcode 16, required for Godot 4.6 iOS export templates)
- Conditional: `if: ${{ secrets.APPLE_CERTIFICATE_P12 != '' }}` — skips gracefully when secrets absent
- `needs: [scope-checks]` — blocked by failing scope checks, same as other exports
- Steps: checkout → install Godot 4.6 native → download iOS export templates from official release → decode cert + provisioning profile into `build.keychain` (dedicated keychain avoids polluting the runner's default keychain) → `godot --headless --export-release "iOS"` → `dulvui/godot-ios-upload@v4` for TestFlight → upload IPA as GitHub artifact
- Header updated from "4-target" to "5-target export matrix" with platforms list

## Phase 1 D-04 Deviation — CLOSED

Phase 1 D-04 documented that iOS CI was deferred: "manual M4 MBA export in Phase 1; full iOS CI deferred to Phase 5". This plan adds the automated iOS CI job, making DOCS §0's "5 platforms in CI" claim literally true. The comment in ci.yml marks the closure explicitly.

## Deviations from Plan

None — plan executed exactly as written. The ci.yml job structure follows the spec in the plan exactly (macos-15, dulvui/godot-ios-upload@v4, three required secrets, D-04 closure comment). The privacy-nutrition.json data categories match docs/PRIVACY.md §1 exactly (email, social data, crash data, parental consent data structure).

## Known Stubs

**Screenshot checklist completion status: 0/6 per device.** Screenshots have not yet been captured. This is expected and intentional — the `screenshot-checklist.md` tracks this explicitly. Screenshots are a human-production artifact requiring the final export build to be available. The checklist document itself is the deliverable for this plan; actual screenshots are a pre-submission gate tracked separately.

## Threat Surface Scan

No new network endpoints, auth paths, or trust boundaries introduced. These are documentation files and a CI job. The CI job handles Apple signing secrets correctly:
- `APPLE_CERTIFICATE_P12` decoded at runtime, not echoed
- Dedicated `build.keychain` cleaned up by runner teardown
- No `-x` shell tracing flag in steps that handle secret values
- Consistent with T-05-CI-secrets mitigation from the plan's threat model

## Self-Check: PASSED

Files exist:
- `/Users/jnuyens/src/LegoMinecraft/docs/store-readiness/app-store-metadata.md` — FOUND
- `/Users/jnuyens/src/LegoMinecraft/docs/store-readiness/play-store-metadata.md` — FOUND
- `/Users/jnuyens/src/LegoMinecraft/docs/store-readiness/privacy-nutrition.json` — FOUND (JSON valid)
- `/Users/jnuyens/src/LegoMinecraft/docs/store-readiness/age-rating.md` — FOUND
- `/Users/jnuyens/src/LegoMinecraft/docs/store-readiness/accessibility-statement.md` — FOUND
- `/Users/jnuyens/src/LegoMinecraft/docs/store-readiness/screenshot-checklist.md` — FOUND
- `/Users/jnuyens/src/LegoMinecraft/docs/store-readiness/code-signing-runbook.md` — FOUND

Commits exist:
- `90d03a9` (Task 1) — FOUND
- `75b7563` (Task 2) — FOUND

CI verification:
- `macos-15` in ci.yml — FOUND
- `dulvui/godot-ios-upload` in ci.yml — FOUND
- `APPLE_CERTIFICATE_P12 != ''` conditional — FOUND
- `D-04` closure comment — FOUND
- YAML valid — CONFIRMED
