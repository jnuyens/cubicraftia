---
phase: 05-safety-moderation-store-readiness
plan: 07
subsystem: ui-safety
tags: [coppa, age-gate, parental-consent, dob-picker, restricted-account, surface-c, surface-d, surface-f, surface-k]
dependency_graph:
  requires: [05-01, 05-05]
  provides: [sign_in_panel_dob_picker, parental_gate_panel, restricted_account_banner]
  affects: [sign_in_panel.gd, FriendsClient sign_up]
tech_stack:
  added: []
  patterns:
    - DOB picker via OptionButton populated once in _build_dob_ui() (perf: no per-open re-creation)
    - Under-13 computed from unix timestamp delta (13 * 365.25 * 86400 seconds)
    - State machine (DEFAULT/LOADING/SUCCESS/ERROR) via _set_state() for parental gate panel
    - install_banner(canvas_layer) API for attaching Surface F banner to any HUD CanvasLayer
    - show_join_blocked_modal() for inline session-join gate (Surface F spec)
key_files:
  created:
    - src/ui/parental_gate_panel.gd
    - src/ui/parental_gate_panel.tscn
  modified:
    - src/ui/sign_in_panel.gd
decisions:
  - Raw DOB values (day/month/year) computed client-side only; is_under_13 bool passed to FriendsClient.sign_up(); raw DOB never in any HTTP body
  - DOB year dropdown descending order (current_year downward) for natural UX on age-gate form
  - _age_checkbox removed from code; ui.signin.age_checkbox msgid preserved in en.po per 05-UI-SPEC.md (Phase 6 cleanup)
  - Resend cooldown: 3600s client-side (Go server enforces hard rate limit server-side)
  - install_banner() API pattern (not autoload): caller controls which CanvasLayer receives the Surface F banner
metrics:
  duration: "7 minutes"
  completed: 2026-05-29
  tasks_completed: 2
  tasks_total: 2
  files_modified: 1
  files_created: 2
---

# Phase 5 Plan 7: DOB Picker + Age Gate + Parental Gate Panel + Restricted Account Banner Summary

**One-liner:** DOB picker replaces age checkbox in sign-up; is_under_13 bool forks to ParentalGatePanel with 4-state consent flow and amber restricted-account banner.

## Tasks Completed

| # | Name | Commit | Key Files |
|---|------|--------|-----------|
| 1 | sign_in_panel.gd DOB picker (Surface C/K) | 58fd8fa | src/ui/sign_in_panel.gd |
| 2 | parental_gate_panel.gd + restricted banner (Surface D + F) | 5d397ae | src/ui/parental_gate_panel.gd, src/ui/parental_gate_panel.tscn |

## What Was Built

### Task 1 — sign_in_panel.gd DOB Picker (Surface C/K)

- Removed `_age_checkbox` (CheckBox) and its references. The `ui.signin.age_checkbox` msgid is preserved in `locale/en.po` (Phase 6 locale sync will clean it up).
- Added `_dob_row` (HBoxContainer, sm=8px gap, 44px minimum height for mobile touch targets).
- Three OptionButtons: `_dob_day` (72px, values 1–31), `_dob_month` (120px, 12 localised month keys via `tr()`), `_dob_year` (96px, current_year to current_year–100 descending).
- `_build_dob_ui()` called once from `_ready()` — not on every panel open (performance constraint per 05-UI-SPEC.md).
- `_on_submit_create_account()`: validates all 3 fields non-zero, validates date via `Time.get_unix_time_from_datetime_dict()`, computes `is_under_13 = (today_unix - birth_unix) < 13 * 365.25 * 86400`.
- Raw DOB never sent to server; `FriendsClient.sign_up()` receives `dob_year/month/day` which it uses only to re-derive `is_under_13` before sending the boolean in GoTrue user metadata.
- On under-13 `sign_up_ok`: emits `under_13_signup_required` signal (parent scene transitions to ParentalGatePanel). On 13+ `sign_up_ok`: shows verification notice as before.
- New signal: `under_13_signup_required()`.

### Task 2 — ParentalGatePanel (Surface D) + Restricted Account Banner (Surface F)

**parental_gate_panel.gd:**
- Full-screen CanvasLayer layer=20 overlay (navy 60% alpha backdrop blocks all interaction below).
- 480px-wide inner PanelContainer, 24px content margin.
- Four states via `_set_state()`:
  - `DEFAULT`: heading + body + parent email LineEdit + "Send link" + "Why am I seeing this?" collapsible + "Skip for now"
  - `LOADING`: "Send link" disabled with "Sending…" text
  - `SUCCESS`: "Link sent!" heading + substituted body + "Done" button + "Resend" link
  - `ERROR`: destructive label below email field, button re-enabled
- "Why am I seeing this?" toggles a collapsible VBoxContainer explaining COPPA requirement in i18n text.
- Basic email validation: must contain `@` and `.` per 05-UI-SPEC.md Surface D.
- Client-side resend cooldown: 3600 seconds.
- Connects to `FriendsClient.consent_status_received`: hides panel + banner on `is_consented=true`; shows banner on `false`.
- Session-join gate: `show_join_blocked_modal()` builds an inline 400px "Parental approval needed" modal.

**Restricted-account banner (Surface F):**
- `_banner`: 40px full-width PanelContainer, amber `#E8890C` background, zero border/rounding/content-margin (flush with screen edges).
- Content: HBoxContainer centred — "Awaiting parent's confirmation —" label + "Resend email" button (navy text on amber).
- `install_banner(target_canvas_layer: CanvasLayer)`: installs banner as child of caller-supplied CanvasLayer (typically HUD layer 5).
- Banner hidden by default; shown on `_on_consent_status(false, *)`, hidden on `(true, *)`.
- "Resend email" button opens the panel in DEFAULT state with cached parent email pre-filled.

**parental_gate_panel.tscn:**
- Root: CanvasLayer layer=20, visible=false.
- Child: Control (full-rect) with parental_gate_panel.gd script.

## Deviations from Plan

None — plan executed exactly as written.

## Known Stubs

- `icon_email.png` (48×48 envelope) referenced conceptually in the SUCCESS state description but the panel does not load it via TextureRect — the icon asset stub (1×1 PNG from Phase 05-01) exists in `assets/textures/icons/`. A future polish plan should add the TextureRect to the SUCCESS state VBox. Logged here per stub tracking protocol.

## Threat Flags

None — no new network endpoints, auth paths, or schema changes introduced. The DOB field collects data client-side only; the existing `FriendsClient.sign_up()` trust boundary (T-05-S2, T-05-E3 in the plan threat register) is the applicable boundary and was already mitigated in Plan 05-04.

## Self-Check: PASSED

- [x] `src/ui/sign_in_panel.gd` exists and modified (commit 58fd8fa)
- [x] `src/ui/parental_gate_panel.gd` created (commit 5d397ae)
- [x] `src/ui/parental_gate_panel.tscn` created (commit 5d397ae)
- [x] `grep "_dob_day" src/ui/sign_in_panel.gd` — 8 matches
- [x] `grep "request_parental_consent" src/ui/parental_gate_panel.gd` — 2 matches
- [x] `grep "consent_status_received" src/ui/parental_gate_panel.gd` — 3 code matches
- [x] Raw DOB never in FriendsClient HTTP body (confirmed in friends_client.gd sign_up implementation)
- [x] All strings via `tr()` — no hardcoded English in either new file
