# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# toasts.gd — Toast notification manager singleton
#
# Registered as autoload "Toasts" in project.godot.
#
# Provides a queue + emit API for transient UI notifications.
# Plan 06 wires the actual scene renderer that listens to toast_requested.
# In Phase 1 (before Plan 06) the toasts are emitted but not yet rendered
# on-screen — this is intentional (the API is load-bearing from Plan 02 onwards).
#
# Usage:
#   Toasts.show("toast.graphics_adjusted")            # info severity
#   Toasts.show("toast.graphics_adjusted", "error")   # error severity
#
# Severity values (per UI-SPEC §Color and §Copywriting Contract):
#   "info"  — left border 4px #F5C30D (brick yellow)
#   "error" — left border 4px #D63828 (brick red / destructive)
#
# The key must start with "toast." (enforced by Translations.t() which the
# renderer calls). Plan 06 listens to toast_requested and renders the overlay.
extends Node

## Emitted when a toast is requested.
## Plan 06 connects a scene node to this signal to render the overlay.
signal toast_requested(key: String, severity: String)

## Valid severity levels per UI-SPEC.md Color contract.
const VALID_SEVERITIES: PackedStringArray = ["info", "error"]


## Enqueue a toast notification.
##
## @param key       A "toast.*" translation key (e.g. "toast.graphics_adjusted").
##                  Validated by the renderer via Translations.t() — must start with "toast.".
## @param severity  One of "info" (yellow border) or "error" (red border).
##                  Defaults to "info".
func show(key: String, severity: String = "info") -> void:
	if not severity in VALID_SEVERITIES:
		push_error(
			"Toasts.show(): invalid severity '%s'. " % severity +
			"Valid values: info, error."
		)
		severity = "info"

	emit_signal("toast_requested", key, severity)
