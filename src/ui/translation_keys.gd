# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# translation_keys.gd — Greppable constant list of every Phase 1 translation key.
#
# Used by extract-pot.sh (via xgettext scanning tr() calls in .gd files) to ensure
# every key declared here ends up in locale/messages.pot.
#
# DOC-10 contract: every UI string must route through tr() or Translations.t().
# These constants are used by UI scripts to avoid magic string literals.
#
# Key namespace contract (RESEARCH.md Pitfall 6):
#   ui.*       — UI chrome (settings, HUD, dialogs, about screen)
#   bricks.*   — brick display names and descriptions
#   device.*   — device-tier names and warnings
#   toast.*    — transient notification messages

class_name UIKeys
extends RefCounted

# ─── Mobile control overlay ──────────────────────────────────────────────────

## Place brick action label (icon-only button; label is screen-reader fallback).
const BUILDER_PLACE := tr("ui.builder.place")

## Break brick/terrain action label (icon-only button; screen-reader fallback).
const BUILDER_BREAK := tr("ui.builder.break")

## Jump action label (icon-only button; screen-reader fallback).
const BUILDER_JUMP := tr("ui.builder.jump")

# ─── Hotbar ──────────────────────────────────────────────────────────────────

## Screen-reader label for an empty hotbar slot. {n} = slot number 1-8.
const HOTBAR_SLOT_EMPTY := tr("ui.hotbar.slot_empty")

## Screen-reader label for a hotbar slot with a brick. {n} = slot, {brick_name} = brick name.
const HOTBAR_SLOT_FILLED := tr("ui.hotbar.slot_filled")

# ─── Graphics presets ─────────────────────────────────────────────────────────

## "Apply preset" button label in Graphics settings.
const SETTINGS_GRAPHICS_APPLY := tr("ui.settings.graphics.apply")

## Auto preset chip label.
const SETTINGS_GRAPHICS_PRESET_AUTO := tr("ui.settings.graphics.preset.auto")

## Low preset chip label.
const SETTINGS_GRAPHICS_PRESET_LOW := tr("ui.settings.graphics.preset.low")

## Medium preset chip label.
const SETTINGS_GRAPHICS_PRESET_MEDIUM := tr("ui.settings.graphics.preset.medium")

## High preset chip label.
const SETTINGS_GRAPHICS_PRESET_HIGH := tr("ui.settings.graphics.preset.high")

## Reset graphics to defaults button label.
const SETTINGS_GRAPHICS_RESET := tr("ui.settings.graphics.reset")

## Destructive confirmation body text for reset graphics.
const SETTINGS_GRAPHICS_RESET_CONFIRM := tr("ui.settings.graphics.reset.confirm")

## Destructive button label in reset confirmation dialog.
const SETTINGS_GRAPHICS_RESET_DO := tr("ui.settings.graphics.reset.do")

# ─── IAP stub ─────────────────────────────────────────────────────────────────

## Section title for the Brick Packs IAP entry.
const SETTINGS_IAP_TITLE := tr("ui.settings.iap.title")

## Subtitle shown when IAP is unavailable (Phase 1).
const SETTINGS_IAP_COMING_LATER := tr("ui.settings.iap.coming_later")

# ─── About screen ─────────────────────────────────────────────────────────────

## About screen title.
const ABOUT_TITLE := tr("ui.about.title")

## Full disclaimer copy (allowlisted in glossary-allowlist.txt for the Group mention).
const ABOUT_DISCLAIMER := tr("ui.about.disclaimer")

## Version label. {version} injected at runtime.
const ABOUT_VERSION := tr("ui.about.version")

## License label.
const ABOUT_LICENSE := tr("ui.about.license")

# ─── First-launch disclaimer ──────────────────────────────────────────────────

## First-launch disclaimer body (same copy as ui.about.disclaimer).
const FIRST_LAUNCH_DISCLAIMER := tr("ui.first_launch.disclaimer")

## Acknowledgement button label ("Got it").
const FIRST_LAUNCH_ACKNOWLEDGE := tr("ui.first_launch.acknowledge")

# ─── Toast notifications ─────────────────────────────────────────────────────

## Toast shown when adaptive quality reduces graphics settings.
const TOAST_GRAPHICS_ADJUSTED := tr("ui.toast.graphics_adjusted")

## Toast shown when a feature is not yet available (e.g. Build palette button tap).
const TOAST_FEATURE_IN_LATER_RELEASE := tr("ui.toast.feature_in_later_release")

# ─── Device tier warnings ─────────────────────────────────────────────────────

## Warning shown on Tier-4 / unsupported device.
const DEVICE_UNSUPPORTED := tr("ui.device.unsupported")

## "Continue anyway" button label for unsupported device dialog.
const DEVICE_CONTINUE_ANYWAY := tr("ui.device.continue_anyway")

## "Quit" button label for unsupported device dialog.
const DEVICE_QUIT := tr("ui.device.quit")

# ─── Common controls ──────────────────────────────────────────────────────────

## Shared "Cancel" button label.
const COMMON_CANCEL := tr("ui.common.cancel")

## Shared "Done" button label (closes the settings panel).
const COMMON_DONE := tr("ui.common.done")

## Shared "Back" button label.
const COMMON_BACK := tr("ui.common.back")

# ─── Brick names ──────────────────────────────────────────────────────────────

## Display name for the 1x1 brick type.
const BRICK_1X1_NAME := tr("bricks.brick_1x1.name")
