---
phase: 06-first-five-minutes
reviewed: 2026-05-30T00:00:00Z
depth: standard
files_reviewed: 19
findings:
  critical: 6
  warning: 8
  info: 3
  total: 17
status: issues_found
---

# Phase 06: Code Review Report

## Critical Issues

### CR-01: Thumbnail saved as JPEG but named `.png` — world select screen thumbnails silently broken
**File:** `src/autoload/world_save.gd`
`capture_thumbnail()` writes JPEG bytes (`save_jpg`) into a file named `thumbnail.png`. `Image.load_from_file` fails silently on the magic-byte mismatch, all world cards show placeholder.
**Fix:** Change extension to `.jpg` in both `world_save.gd` and `world_select_screen.gd._load_thumbnail()` and `test_world_thumbnail_capture.gd`.

### CR-02: `ui.title.continue` key absent from both `en.po` and `nl.po`
**File:** `src/ui/title_scene.gd` (~line 143, 255)
`tr("ui.title.continue")` returns raw key string. Only `ui.title.continue_as` exists.
**Fix:** Add `ui.title.continue` to en.po ("Continue") and nl.po ("Verdergaan").

### CR-03: Telemetry rotation sets `base_count = MAX_EVENTS` causing overwrite of retained event
**File:** `src/autoload/onboarding_telemetry.gd` `_rotate_oldest()`
After erasing oldest 2500 events, base_count stays at 10000. Next flush writes event_10000 = overwrites retained event 10000.
**Fix:** Renumber retained events down by drop_count; set `base_count -= drop_count`.

### CR-04: Base32 invite token produces 25 chars, not documented 26
**File:** `src/autoload/friends_client.gd._generate_invite_token`
128 bits / 5 = 25 full groups + 3 remainder bits never emitted. `INVITE_TOKEN_LENGTH = 26` is wrong.
**Fix:** Emit trailing-bit group: `if bit_count > 0: result += ALPHABET[(accumulator << (5 - bit_count)) & 0x1F]`.

### CR-05: `invite_error` signal does not exist on `FriendsClient`
**File:** `src/ui/title_scene.gd` (~line 594)
Connects to `fc.invite_error` but FriendsClient declares `invite_creation_failed`. Connection fails silently → invite errors never surfaced to UI.
**Fix:** Change connection to `fc.invite_creation_failed.connect(_on_invite_creation_failed)`.

### CR-06: `chests.*` and `items.*` translation keys fail Translations.t() prefix validation
**File:** `src/autoload/translations.gd:27`; `locale/*.po` (multiple `chests.*` and `items.*` keys)
Valid prefixes are only `ui.`, `bricks.`, `device.`, `toast.`. Every chests/items tr() triggers push_error in release builds (no `OS.is_debug_build()` guard despite docstring).
**Fix:** Add "chests." and "items." to _VALID_PREFIXES; gate push_error on `OS.is_debug_build()` per docstring.

## Warnings

### WR-01: `create_friendship()` doesn't set `_friends_pending_action` → POST response parsed as friends list, corrupts cache
**Fix:** `_friends_pending_action = "create"` before POST.

### WR-02: `_on_sign_in_pressed()` dead assignment to `_open_overlay`
**Fix:** Remove dead first assignment.

### WR-03: `sign_in_panel.gd` surfaces raw server reason string
**File:** `src/ui/sign_in_panel.gd:681`
**Fix:** Match on reason → translated user-friendly message.

### WR-04: FTUE chest signal connection retries only once
**File:** `src/ui/ftue_overlay.gd._connect_chest_signals`
**Fix:** Use timer-backed retry loop with max attempt cap (10 × 0.5s).

### WR-05: Empty world name shows profanity error instead of "empty"
**File:** `src/ui/world_select_screen.gd:913`
**Fix:** Check is_empty() first with `ui.new_world.name_error_empty` key.

### WR-06: `_load_world()` doesn't check `open_world()` return
**Fix:** Guard with `if not WorldSave.open_world(...): return`.

### WR-07: `translations.gd t()` push_error runs in release; docstring is wrong
**Fix:** Gate on `OS.is_debug_build()` for parity.

### WR-08: `title_bg_pan.gdshader` no fallback when texture is transparent/unassigned
**Fix:** `COLOR = mix(vec4(0.047, 0.082, 0.196, 1.0), col, col.a);`

## Info

### IN-01: `world_save.gd.create_world` local `world_id` shadows autoload property
### IN-02: `009_avatar.sql` no size CHECK on `avatar_json` — risk of large payload
### IN-03: `ftue_complete` stored via `var_to_bytes` — readers must `bytes_to_var`
