# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# connection_problem_overlay.gd: Shared connection-problem overlay (Surface A).
#
# The ONE reusable "connection problem" screen for the whole codebase (D-01/D-02).
# Driven exclusively by NetworkManager.connection_problem(reason: String); never
# instanced twice, never bypassed by an ad-hoc dialog elsewhere.
#
# show_reason(reason) is the single public entry point. All 7 reasons
# ("expired", "full", "ended", "blocked", "version_mismatch", "relay_failed",
# "timeout") share one heading and differ only in body copy + button set.
#
# Not dismissible by Escape or by clicking the background scrim: only its own
# PrimaryButton/SecondaryButton close it (13-UI-SPEC.md Surface A, "Modal / Focus /
# Input Behavior"). There is intentionally no _unhandled_key_input override here.
#
# Threat mitigations:
#   T-13-05-01: the `blocked` reason's body copy is a static, pre-authored i18n
#     string that never references block status, verified by an automated
#     substring-absence test (test_connection_problem_overlay_reasons.gd), not
#     merely by the presence of the key.
#   T-13-05-02: {host} interpolation reads locally-trusted SessionRegistry state,
#     never raw network input; Label nodes render plain text only (no markup).
#
# References:
#   13-05-PLAN.md Task 2
#   13-UI-SPEC.md Surface A: Connection-Problem Overlay
#   src/ui/handover_screen.gd: structural precedent (CanvasLayer scrim + content)
#   src/ui/join_screen.gd _get_host_username(): host-name-resolution precedent

class_name ConnectionProblemOverlay
extends CanvasLayer

# ─── Constants ────────────────────────────────────────────────────────────────

## Reasons that show BOTH a Retry (Primary) and Back-to-menu (Secondary) button.
## All other reasons in CONNECTION_PROBLEM_REASONS show Back-to-menu only.
const _REASONS_WITH_SECONDARY: Array[String] = ["relay_failed", "timeout"]

## Reasons whose body copy contains a "{host}" placeholder that must be resolved
## (13-UI-SPEC.md Copywriting Contract: only these 3 reasons reference the host).
const _REASONS_WITH_HOST_INTERP: Array[String] = ["expired", "version_mismatch", "relay_failed"]

## Reason → i18n body key. No fallback "echo the raw reason string" path exists
## here on purpose (T-13-05-01: an unrecognised reason cannot inject text).
const _BODY_KEYS: Dictionary = {
	"expired": "ui.connproblem.reason_expired",
	"full": "ui.connproblem.reason_full",
	"ended": "ui.connproblem.reason_ended",
	"blocked": "ui.connproblem.reason_blocked",
	"version_mismatch": "ui.connproblem.reason_version_mismatch",
	"relay_failed": "ui.connproblem.reason_relay_failed",
	"timeout": "ui.connproblem.reason_timeout",
}

# ─── Node refs ────────────────────────────────────────────────────────────────

@onready var _heading: Label = $Overlay/Content/Heading
@onready var _body: Label = $Overlay/Content/Body
@onready var _primary_button: Button = $Overlay/Content/ButtonRow/PrimaryButton
@onready var _secondary_button: Button = $Overlay/Content/ButtonRow/SecondaryButton

# ─── Private state ────────────────────────────────────────────────────────────

## The reason last passed to show_reason(); drives PrimaryButton's retry-vs-back behavior.
var _current_reason: String = ""

# ─── Lifecycle ────────────────────────────────────────────────────────────────

func _ready() -> void:
	visible = false
	_secondary_button.visible = false

	if is_instance_valid(NetworkManager):
		NetworkManager.connection_problem.connect(show_reason)

	_primary_button.pressed.connect(_on_primary_pressed)
	_secondary_button.pressed.connect(_on_secondary_pressed)


# ─── Public API ───────────────────────────────────────────────────────────────

## Single public entry point. Shows the overlay with the copy/button set for `reason`.
## `reason` must be one of NetworkManager.CONNECTION_PROBLEM_REASONS.
func show_reason(reason: String) -> void:
	_current_reason = reason

	show()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	_heading.text = tr("ui.connproblem.heading")

	var body_text: String = tr(_body_key_for_reason(reason))
	if reason in _REASONS_WITH_HOST_INTERP:
		body_text = body_text.replace("{host}", _resolve_host_name())
	_body.text = body_text

	if _reason_has_secondary_action(reason):
		_primary_button.text = tr("ui.connproblem.action_retry")
		_secondary_button.text = tr("ui.connproblem.action_back")
		_secondary_button.visible = true
	else:
		_primary_button.text = tr("ui.connproblem.action_back")
		_secondary_button.visible = false

	_primary_button.grab_focus()


# ─── Pure helpers (off-tree-testable, no node access) ───────────────────────

## True only for the two genuinely retryable reasons ("relay_failed", "timeout").
func _reason_has_secondary_action(reason: String) -> bool:
	return reason in _REASONS_WITH_SECONDARY


## Maps a reason to its ui.connproblem.reason_* i18n key.
func _body_key_for_reason(reason: String) -> String:
	return String(_BODY_KEYS.get(reason, ""))


# ─── Button handlers ──────────────────────────────────────────────────────────

func _on_primary_pressed() -> void:
	hide()
	if _reason_has_secondary_action(_current_reason):
		_attempt_retry()
	else:
		_do_back_to_menu()


func _on_secondary_pressed() -> void:
	hide()
	_do_back_to_menu()


## Retry entry point for relay_failed/timeout. Best-effort re-run of start_peer for
## the current session; exact reconnect semantics may be refined by a later plan.
func _attempt_retry() -> void:
	if is_instance_valid(NetworkManager) and NetworkManager.get_session_id() != "":
		NetworkManager.call("start_peer", NetworkManager.get_session_id(), 0)


## Ends the session (if one is active) and returns to the title flow. Shared by the
## Secondary button and by non-retryable reasons' sole Primary button.
func _do_back_to_menu() -> void:
	if is_instance_valid(NetworkManager) and NetworkManager.call("is_multiplayer_active"):
		NetworkManager.call("begin_graceful_disconnect")
		get_tree().change_scene_to_file("res://src/ui/title_scene.tscn")
	# Else: no session was ever active (e.g. a stale invite rejected before join
	# completed): the overlay is already hidden and the current scene is already
	# correct; nothing further to do.


# ─── Helpers ──────────────────────────────────────────────────────────────────

## Return the host's display name for {host} interpolation. Mirrors the resolution
## logic in JoinScreen._get_host_username() (SessionRegistry.get_host_uid(), falling
## back to a generic string) but localizes the fallback via tr(): JoinScreen's
## existing fallback is a hardcoded English literal; this overlay must never show
## English text under the Dutch locale, so its fallback uses the newly-added
## ui.common.generic_host key ("your host" / "je host") instead of a second
## hand-rolled resolution helper.
func _resolve_host_name() -> String:
	if is_instance_valid(SessionRegistry):
		var host_uid: String = SessionRegistry.get_host_uid() if SessionRegistry.has_method("get_host_uid") else ""
		if host_uid != "":
			return host_uid
	return tr("ui.common.generic_host")
