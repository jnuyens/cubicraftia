# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# join_screen.gd — Join-from-invite overlay (Surface 5).
#
# Full-screen CanvasLayer (layer=20) shown during WebRTC handshake.
# Receives _session_id and _invite_token from the caller before opening.
#
# Session-age gate (CONTEXT Area 3, point b):
#   Unverified accounts cannot join sessions older than 24 h.
#   IMPORTANT: published_at == 0 means "unknown" (cache miss) — do NOT block on
#   unknown age. Only block when published_at > 0 AND age > 86400 s AND unverified.
#
# Security:
#   T-04-07-T: guest-visible only; admin controls in Players tab (host-only).
#
# References:
#   04-07-PLAN.md Task 1
#   04-UI-SPEC.md Surface 5
#   04-PATTERNS.md lines 494-505 — signal subscription pattern

class_name JoinScreen
extends CanvasLayer

# ─── Signals ─────────────────────────────────────────────────────────────────

## Emitted when the unverified-account session-age gate fires.
signal verification_required_for_old_session

# ─── Public state ─────────────────────────────────────────────────────────────

## Session to join.
var _session_id: String = ""

## Invite token (used by NetworkManager.join_session).
var _invite_token: String = ""

# ─── Node refs ───────────────────────────────────────────────────────────────

@onready var _content: VBoxContainer = $Overlay/Content
@onready var _heading: Label = $Overlay/Content/Heading
@onready var _status_label: Label = $Overlay/Content/StatusLabel
@onready var _error_content: VBoxContainer = $Overlay/ErrorContent
@onready var _error_heading: Label = $Overlay/ErrorContent/ErrorHeading
@onready var _error_body: Label = $Overlay/ErrorContent/ErrorBody
@onready var _back_button: Button = $Overlay/ErrorContent/BackButton

# ─── Lifecycle ───────────────────────────────────────────────────────────────

func _ready() -> void:
	# Subscribe to NetworkManager signals (safe if NetworkManager is not present).
	if is_instance_valid(NetworkManager):
		NetworkManager.session_state_changed.connect(_on_session_state_changed)
		NetworkManager.peer_connected.connect(_on_peer_connected)

	# Wire back button.
	_back_button.text = tr("ui.join.back")
	_back_button.pressed.connect(queue_free)

	# Initial state: content visible, error hidden.
	_content.visible = true
	_error_content.visible = false
	_status_label.text = tr("ui.join.status_connecting")
	_heading.text = tr("ui.join.heading").replace("{username}", _get_host_username())


## Set the session and token before adding to the scene tree.
func setup(session_id: String, invite_token: String) -> void:
	_session_id = session_id
	_invite_token = invite_token


# ─── NetworkManager signal handlers ──────────────────────────────────────────

func _on_session_state_changed(state: String) -> void:
	match state:
		NetworkManager.STATE_CONNECTING:
			show()
			_content.visible = true
			_error_content.visible = false
			_heading.text = tr("ui.join.heading").replace("{username}", _get_host_username())
			_status_label.text = tr("ui.join.status_connecting")

		NetworkManager.STATE_CONNECTED_AS_PEER:
			# Session-age gate (CONTEXT Area 3, point b).
			# published_at == 0 → unknown age → do NOT block (cache miss guard).
			var published_at: int = 0
			if is_instance_valid(FriendsClient):
				published_at = FriendsClient.get_session_published_at(_session_id)
			if published_at > 0 and is_instance_valid(FriendsClient) \
					and not FriendsClient.is_email_verified() \
					and (Time.get_unix_time_from_system() - published_at) > 86400:
				_show_error(tr("ui.join.error_unverified_session_age"))
				verification_required_for_old_session.emit()
				return
			_on_join_success()

		NetworkManager.STATE_FAILOVER_WAITING, NetworkManager.STATE_RECONNECTING:
			_status_label.text = tr("ui.join.status_loading")

		NetworkManager.STATE_DISCONNECTED:
			_show_error(tr("ui.join.error_connection"))


func _on_peer_connected(_peer_id: int) -> void:
	# Optional: could update status here. Join success is driven by state machine.
	pass


# ─── Success / error ─────────────────────────────────────────────────────────

func _on_join_success() -> void:
	if is_instance_valid(Toasts):
		Toasts.show(
			tr("ui.join.new_friends_toast").replace("{username}", _get_host_username()),
			"info"
		)
	queue_free()


func _show_error(reason: String) -> void:
	_content.visible = false
	_error_content.visible = true
	# CR-09: The .replace(reason, "") call was wrong — it attempted to remove the
	# reason string from the heading key, but tr() keys never contain the reason
	# text, so the heading was shown unchanged (best case) or corrupted (worst case).
	# The heading should always show the generic connection-error label; the body
	# shows the specific reason.
	_error_heading.text = tr("ui.join.error_connection")
	_error_body.text = reason


# ─── Helpers ─────────────────────────────────────────────────────────────────

## Return the host's display username for the heading and toast.
## Reads from SessionRegistry if available; falls back to generic string.
func _get_host_username() -> String:
	if is_instance_valid(SessionRegistry):
		var host_uid: String = SessionRegistry.get_host_uid() if SessionRegistry.has_method("get_host_uid") else ""
		if host_uid != "":
			return host_uid
	return "your host"
