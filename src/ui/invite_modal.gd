# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# invite_modal.gd — Invite link generation modal (Surface 4).
#
# Shows a generated invite link with TTL countdown. User can copy or share.
# Opened by passing session_id to open(session_id).
#
# Security:
#   T-04-07-I: "Copy" is a deliberate user action; clipboard is ephemeral; link expires in 24h.
#   Gates: is_invite_send_allowed() (signed in + email verified), not is_friends_limit_reached().
#
# References:
#   04-07-PLAN.md Task 1
#   04-UI-SPEC.md Surface 4
#   04-PATTERNS.md lines 484, 494-505 — PanelContainer modal, timer pattern

class_name InviteModal
extends Control

# ─── Signals ─────────────────────────────────────────────────────────────────

## Emitted when the user copies the invite link.
signal invite_link_copied

# ─── Node refs ───────────────────────────────────────────────────────────────

@onready var _generating_label: Label = $Overlay/ModalPanel/VBox/GeneratingLabel
@onready var _link_field: LineEdit = $Overlay/ModalPanel/VBox/LinkField
@onready var _ttl_label: Label = $Overlay/ModalPanel/VBox/TtlLabel
@onready var _button_row: HBoxContainer = $Overlay/ModalPanel/VBox/ButtonRow
@onready var _copy_button: Button = $Overlay/ModalPanel/VBox/ButtonRow/CopyButton
@onready var _share_button: Button = $Overlay/ModalPanel/VBox/ButtonRow/ShareButton
@onready var _close_button: Button = $Overlay/ModalPanel/VBox/CloseButton
@onready var _error_label: Label = $Overlay/ModalPanel/VBox/ErrorLabel

# ─── Private state ────────────────────────────────────────────────────────────

## The invite token (26-char base32).
var _token: String = ""

## Unix timestamp when the invite expires (now + 86400).
var _expires_at: float = 0.0

## Periodic TTL countdown timer (1-second interval).
var _ttl_timer: Timer = null

## One-shot timer to revert "Copied!" label back to "Copy link" after 2 s.
var _copy_revert_timer: Timer = null

# ─── Lifecycle ───────────────────────────────────────────────────────────────

func _ready() -> void:
	# TTL countdown: fires every 1 second while the modal is open.
	_ttl_timer = Timer.new()
	_ttl_timer.one_shot = false
	_ttl_timer.wait_time = 1.0
	_ttl_timer.timeout.connect(_update_ttl_display)
	add_child(_ttl_timer)

	# Copy-revert: fires once 2 seconds after copy to reset button label.
	_copy_revert_timer = Timer.new()
	_copy_revert_timer.one_shot = true
	_copy_revert_timer.wait_time = 2.0
	_copy_revert_timer.timeout.connect(_revert_copy_label)
	add_child(_copy_revert_timer)

	# Wire buttons.
	_copy_button.pressed.connect(_on_copy)
	_share_button.pressed.connect(_on_share)
	_close_button.pressed.connect(queue_free)

	# Set button text from locale.
	_copy_button.text = tr("ui.invite.copy")
	_share_button.text = tr("ui.invite.share")
	_close_button.text = tr("ui.invite.close")

	# Start in loading state (no link shown yet).
	_set_loading_state()

	# Connect FriendsClient signals.
	if is_instance_valid(FriendsClient):
		FriendsClient.invite_created.connect(_on_invite_created)
		FriendsClient.invite_creation_failed.connect(_on_invite_failed)


## Open the modal for the given session. Fires the invite creation request.
func open(session_id: String) -> void:
	# WR-09: Show specific auth/verification errors rather than the generic
	# "network error" string when the user is not eligible to send invites.
	if is_instance_valid(FriendsClient) and not FriendsClient.is_signed_in():
		_on_invite_failed(tr("ui.invite.error_not_signed_in"))
		return
	if is_instance_valid(FriendsClient) and not FriendsClient.is_email_verified():
		_on_invite_failed(tr("ui.invite.error_not_verified"))
		return
	# Gate: friends list must not be full.
	if is_instance_valid(FriendsClient) and FriendsClient.is_friends_limit_reached():
		_on_invite_failed(tr("ui.friends.limit_reached"))
		return

	_set_loading_state()
	if is_instance_valid(FriendsClient):
		FriendsClient.create_invite(session_id)


# ─── FriendsClient callbacks ─────────────────────────────────────────────────

func _on_invite_created(token: String, link: String) -> void:
	_token = token
	_expires_at = Time.get_unix_time_from_system() + 86400.0
	_link_field.text = link
	_error_label.visible = false
	_generating_label.visible = false
	_link_field.visible = true
	_ttl_label.visible = true
	_button_row.visible = true
	_update_ttl_display()
	_ttl_timer.start()


func _on_invite_failed(reason: String) -> void:
	_generating_label.visible = false
	_error_label.text = reason
	_error_label.visible = true


# ─── TTL countdown ────────────────────────────────────────────────────────────

func _update_ttl_display() -> void:
	var remaining: int = int(_expires_at - Time.get_unix_time_from_system())
	if remaining <= 0:
		_ttl_timer.stop()
		_ttl_label.text = tr("ui.invite.ttl_countdown").replace("{hh_mm_ss}", "00:00:00")
		return
	var h: int = remaining / 3600
	var m: int = (remaining % 3600) / 60
	var s: int = remaining % 60
	_ttl_label.text = tr("ui.invite.ttl_countdown").replace("{hh_mm_ss}", "%02d:%02d:%02d" % [h, m, s])


# ─── Button handlers ──────────────────────────────────────────────────────────

func _on_copy() -> void:
	DisplayServer.clipboard_set(_link_field.text)
	_copy_button.text = tr("ui.invite.copied")
	_copy_revert_timer.start()
	invite_link_copied.emit()


func _revert_copy_label() -> void:
	_copy_button.text = tr("ui.invite.copy")


func _on_share() -> void:
	# On mobile this opens the OS share sheet; on desktop falls back to opening
	# the URL in the browser. Stub: copy + toast to inform the user.
	DisplayServer.clipboard_set(_link_field.text)
	if is_instance_valid(Toasts):
		Toasts.show(tr("ui.invite.copied"), "info")
	else:
		OS.shell_open(_link_field.text)


# ─── Helpers ─────────────────────────────────────────────────────────────────

func _set_loading_state() -> void:
	_generating_label.text = tr("ui.invite.generating")
	_generating_label.visible = true
	_link_field.visible = false
	_ttl_label.visible = false
	_button_row.visible = false
	_error_label.visible = false
