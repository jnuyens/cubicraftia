# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# chat_overlay.gd — Chat overlay controller (Surface 7, CanvasLayer layer=5).
#
# Behaviours:
#   - Activated by ui_chat_toggle action (Enter on desktop, TouchScreenButton on mobile).
#   - History panel auto-shows 5 s on new message when closed; manually toggled.
#   - Rate limit: 5 messages per 10-second window; LineEdit disabled on limit with countdown.
#   - History capped at 40 messages (oldest queue_freed when at cap).
#   - Per-player mute: local-only; muted peer messages arrive but are hidden.
#   - Sender sees their own original (unfiltered) message; peers receive the host-filtered copy.
#
# Security:
#   T-04-08-T — chat text sent to host via NetworkManager.send_chat(); host filters before relay.
#   T-04-08-D — rate limit enforced here; host also rate-limits in _receive_chat_from_peer.
#
# References:
#   04-UI-SPEC.md Surface 7 — Chat overlay
#   04-CONTEXT.md Area 4 — rate limit (5/10s), ephemeral, local mute
#   04-08-PLAN.md Task 1 — full behaviour spec
#   04-PATTERNS.md lines 554-565 — visibility gate + signal-driven update

class_name ChatOverlay
extends CanvasLayer

# ─── Constants ────────────────────────────────────────────────────────────────

## Maximum messages retained in history (oldest queue_freed at cap).
const MAX_HISTORY: int = 40

## Rate limit: max messages per window.
const RATE_LIMIT_MESSAGES: int = 5

## Rate limit window in seconds.
const RATE_LIMIT_WINDOW_S: float = 10.0

## Auto-hide delay after a new message arrives (seconds).
const AUTO_HIDE_DELAY_S: float = 5.0

## Countdown timer tick interval (seconds).
const COUNTDOWN_TICK_S: float = 1.0

# ─── Colors ───────────────────────────────────────────────────────────────────

const COLOR_SENDER_SELF: Color    = Color(0.96, 0.76, 0.05, 1.0)   # accent yellow
const COLOR_SENDER_OTHER: Color   = Color(0.6, 0.85, 1.0, 1.0)     # light blue
const COLOR_MESSAGE: Color        = Color(1.0, 1.0, 1.0, 1.0)      # white
const COLOR_RATE_LIMIT: Color     = Color(0.91, 0.54, 0.05, 1.0)   # relay amber

# ─── Node refs ────────────────────────────────────────────────────────────────

@onready var _history_panel: PanelContainer = $HistoryPanel
@onready var _history_container: VBoxContainer = $HistoryPanel/VBox/ScrollContainer/HistoryContainer
@onready var _scroll_container: ScrollContainer = $HistoryPanel/VBox/ScrollContainer
@onready var _input_field: LineEdit = $HistoryPanel/VBox/InputRow/InputField
@onready var _send_button: Button = $HistoryPanel/VBox/InputRow/SendButton
@onready var _rate_limit_label: Label = $HistoryPanel/VBox/RateLimitLabel

# ─── State ────────────────────────────────────────────────────────────────────

## Number of messages sent in the current rate-limit window.
var _message_count: int = 0

## Countdown seconds remaining for rate-limit display.
var _countdown_remaining: int = 0

## Muted player IDs (local-only). Dict[peer_id: int → true].
var _muted_peers: Dictionary = {}

## Whether the chat input row is open (user has toggled chat).
var _chat_active: bool = false

## Phase 5: structured history buffer for context capture in reports.
## Each entry: {uid: String, username: String, text: String, timestamp: int}
var _history: Array = []

## Phase 5: muted UIDs (string — for reported users auto-muted by uid, not peer_id).
var _muted_uids: Dictionary = {}

# ─── Timers ───────────────────────────────────────────────────────────────────

var _rate_window_timer: Timer = null   # 10 s one-shot; resets _message_count
var _countdown_timer: Timer = null     # 1 s repeating; decrements countdown display
var _auto_hide_timer: Timer = null     # 5 s one-shot; hides HistoryPanel if chat inactive

## Phase 5: long-press timer for context menu per message row (500ms, one-shot).
var _msg_long_press_timer: Timer = null
## Index into _history of the message being held.
var _msg_long_press_index: int = -1
## Screen position of the held message row.
var _msg_long_press_screen_pos: Vector2 = Vector2.ZERO

# ─── Lifecycle ────────────────────────────────────────────────────────────────

func _ready() -> void:
	# Visibility gate: only show when multiplayer is active.
	visible = is_instance_valid(NetworkManager) and NetworkManager.is_multiplayer_active()

	# Set placeholder and button text via tr().
	_input_field.placeholder_text = tr("ui.chat.input_placeholder")
	_send_button.text = tr("ui.chat.send")

	# Wire send button.
	_send_button.pressed.connect(_on_send_pressed)

	# Wire Enter key in LineEdit.
	_input_field.text_submitted.connect(_on_text_submitted)

	# Connect to NetworkManager signals.
	if is_instance_valid(NetworkManager):
		NetworkManager.chat_message_received.connect(_on_message_received)
		NetworkManager.session_state_changed.connect(_on_session_state_changed)

	# Rate window timer — resets the message count after 10 s.
	_rate_window_timer = Timer.new()
	_rate_window_timer.one_shot = true
	_rate_window_timer.wait_time = RATE_LIMIT_WINDOW_S
	_rate_window_timer.timeout.connect(_on_rate_window_expired)
	add_child(_rate_window_timer)

	# Countdown display timer — ticks every 1 s while rate limited.
	_countdown_timer = Timer.new()
	_countdown_timer.one_shot = false
	_countdown_timer.wait_time = COUNTDOWN_TICK_S
	_countdown_timer.timeout.connect(_on_countdown_tick)
	add_child(_countdown_timer)

	# Auto-hide timer — hides history panel 5 s after last message if chat not active.
	_auto_hide_timer = Timer.new()
	_auto_hide_timer.one_shot = true
	_auto_hide_timer.wait_time = AUTO_HIDE_DELAY_S
	_auto_hide_timer.timeout.connect(_on_auto_hide_timeout)
	add_child(_auto_hide_timer)

	# Start hidden.
	_history_panel.visible = false
	_chat_active = false

	# Phase 5: long-press timer for message row context menu (Surface I).
	_msg_long_press_timer = Timer.new()
	_msg_long_press_timer.one_shot = true
	_msg_long_press_timer.wait_time = 0.5
	_msg_long_press_timer.timeout.connect(_on_msg_long_press_timeout)
	add_child(_msg_long_press_timer)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_chat_toggle"):
		_toggle_chat()
		get_viewport().set_input_as_handled()


# ─── Chat toggle ─────────────────────────────────────────────────────────────

func _toggle_chat() -> void:
	_chat_active = not _chat_active
	_history_panel.visible = true  # Always show panel when toggling

	if _chat_active:
		# Stop auto-hide while chat is open.
		if _auto_hide_timer != null:
			_auto_hide_timer.stop()
		# Focus the input field.
		_input_field.grab_focus()
	else:
		# Start auto-hide countdown when chat closed.
		_input_field.release_focus()
		if _auto_hide_timer != null:
			_auto_hide_timer.start()


# ─── Send message ─────────────────────────────────────────────────────────────

func _on_send_pressed() -> void:
	_attempt_send()


func _on_text_submitted(_text: String) -> void:
	# Only handle text submission when chat is active (prevents hotkey conflicts).
	if _chat_active:
		_attempt_send()


func _attempt_send() -> void:
	if _message_count >= RATE_LIMIT_MESSAGES:
		# Already rate limited — drop silently (UI countdown is already visible).
		return

	var text: String = _input_field.text.strip_edges()
	if text.is_empty():
		return

	_message_count += 1

	# Send to NetworkManager (host filters before relay; sender sees original).
	if is_instance_valid(NetworkManager):
		NetworkManager.send_chat(text)

	# Show sender's own original message immediately (unfiltered).
	var my_id: int = 0
	if is_instance_valid(multiplayer):
		my_id = multiplayer.get_unique_id()
	_add_message_row(my_id, text, Time.get_ticks_msec() / 1000, true)

	_input_field.text = ""

	# Start rate window timer on first message.
	if _message_count == 1:
		_rate_window_timer.start()

	# Enforce limit.
	if _message_count >= RATE_LIMIT_MESSAGES:
		_input_field.editable = false
		_start_countdown()


## Start the rate-limit countdown display.
func _start_countdown() -> void:
	_countdown_remaining = int(RATE_LIMIT_WINDOW_S)
	_rate_limit_label.visible = true
	_rate_limit_label.add_theme_color_override("font_color", COLOR_RATE_LIMIT)
	_update_countdown_label()
	_countdown_timer.start()


func _on_countdown_tick() -> void:
	_countdown_remaining = max(0, _countdown_remaining - 1)
	_update_countdown_label()


func _update_countdown_label() -> void:
	_rate_limit_label.text = tr("ui.chat.rate_limit_wait").format({"n": _countdown_remaining})


func _on_rate_window_expired() -> void:
	_message_count = 0
	_input_field.editable = true
	_rate_limit_label.visible = false
	_countdown_timer.stop()
	# WR-08: Reset the countdown so the label shows 0 rather than a stale value
	# if the rate window timer and the display countdown timer drifted apart.
	_countdown_remaining = 0


# ─── Receive messages ─────────────────────────────────────────────────────────

func _on_message_received(sender_id: int, message: String) -> void:
	# Skip messages from muted peers (by peer_id).
	if _muted_peers.has(sender_id):
		return

	# Phase 5: also skip messages from uid-muted senders (auto-mute after report).
	var sender_name_check := _get_peer_display_name(sender_id)
	# We check uid-mute in _add_message_row after resolving the uid.

	# Auto-show history panel on new message (5 s then hide if chat not active).
	if not _history_panel.visible:
		_history_panel.visible = true

	if not _chat_active:
		if _auto_hide_timer != null:
			if not _auto_hide_timer.is_stopped():
				_auto_hide_timer.stop()
			_auto_hide_timer.start()

	_add_message_row(sender_id, message, Time.get_ticks_msec() / 1000, false)


# ─── History management ────────────────────────────────────────────────────────

## Add a message row to the history.
## @param sender_id   Peer ID of the sender (0 = local system message).
## @param text        Message text.
## @param timestamp   Unix-style timestamp for ordering.
## @param is_self     True when this is the local sender's own message.
func _add_message_row(sender_id: int, text: String, timestamp: int, is_self: bool) -> void:
	# Enforce history cap — also trim structured _history.
	if _history_container.get_child_count() >= MAX_HISTORY:
		var oldest: Node = _history_container.get_child(0)
		oldest.queue_free()
		if _history.size() >= MAX_HISTORY:
			_history.remove_at(0)

	var sender_name: String = _get_peer_display_name(sender_id)

	# Phase 5: resolve uid for this peer (best-effort from SessionRegistry).
	var sender_uid: String = ""
	if not is_self and is_instance_valid(SessionRegistry):
		var peers: Dictionary = SessionRegistry.get_peer_list()
		if peers.has(sender_id):
			var info: Dictionary = peers[sender_id] as Dictionary
			sender_uid = info.get("uid", "")

	# Phase 5: skip if sender is uid-muted.
	if not sender_uid.is_empty() and _muted_uids.has(sender_uid):
		return

	# Phase 5: record in structured history buffer for context capture.
	_history.append({
		"uid":       sender_uid,
		"username":  sender_name,
		"text":      text,
		"timestamp": timestamp,
	})

	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# Sender label.
	var sender_label := Label.new()
	sender_label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var sender_color: Color = COLOR_SENDER_SELF if is_self else COLOR_SENDER_OTHER
	sender_label.add_theme_color_override("font_color", sender_color)
	sender_label.text = sender_name + ":"
	row.add_child(sender_label)

	# Message label.
	var msg_label := Label.new()
	msg_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	msg_label.add_theme_color_override("font_color", COLOR_MESSAGE)
	msg_label.text = " " + text
	msg_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(msg_label)

	# Phase 5: wire long-press on this row for context menu (Surface I).
	var history_index := _history.size() - 1
	row.gui_input.connect(_on_msg_row_input.bind(history_index, row))
	row.mouse_filter = Control.MOUSE_FILTER_STOP

	_history_container.add_child(row)

	# Scroll to bottom after layout.
	await get_tree().process_frame
	_scroll_container.scroll_vertical = _scroll_container.get_v_scroll_bar().max_value


## Get a display name for a peer. Falls back to "Player {id}".
func _get_peer_display_name(peer_id: int) -> String:
	if peer_id == 0:
		return tr("ui.chat.send")  # System messages label
	var my_id: int = 0
	if is_instance_valid(multiplayer):
		my_id = multiplayer.get_unique_id()
	if peer_id == my_id:
		# Local player — try to get username from FriendsClient.
		if is_instance_valid(FriendsClient) and FriendsClient.has_method("get_username"):
			var uname: String = FriendsClient.get_username()
			if not uname.is_empty():
				return uname
		return "You"
	# Remote peer — try SessionRegistry.
	if is_instance_valid(SessionRegistry):
		var peers: Dictionary = SessionRegistry.get_peer_list()
		if peers.has(peer_id):
			var info: Dictionary = peers[peer_id] as Dictionary
			var uname: String = info.get("username", "")
			if not uname.is_empty():
				return uname.left(16)
	return "Player %d" % peer_id


# ─── Mute management ──────────────────────────────────────────────────────────

## Toggle mute state for a peer. Mute is local-only; messages still arrive at the network level.
## @param peer_id  The peer to mute or unmute.
func toggle_mute(peer_id: int) -> void:
	if _muted_peers.has(peer_id):
		_muted_peers.erase(peer_id)
	else:
		_muted_peers[peer_id] = true


## Returns true if the given peer is muted locally.
func is_muted(peer_id: int) -> bool:
	return _muted_peers.has(peer_id)


# ─── Session state ────────────────────────────────────────────────────────────

func _on_session_state_changed(new_state: String) -> void:
	visible = new_state in ["CONNECTED_AS_HOST", "CONNECTED_AS_PEER",
		"FAILOVER_DETECTING", "FAILOVER_ELECTED", "FAILOVER_PROMOTING",
		"FAILOVER_COMPLETE", "FAILOVER_WAITING", "RECONNECTING"]
	if not visible:
		_history_panel.visible = false
		_chat_active = false


# ─── Auto-hide timer ──────────────────────────────────────────────────────────

func _on_auto_hide_timeout() -> void:
	if not _chat_active:
		_history_panel.visible = false


# ─── Phase 5: UID-based mute (auto-mute after report, Surface I) ─────────────

## Mute a user by their Supabase UID. Called by ReportModal after report submission.
## This is a local display filter for the session — not a real block.
func mute_by_uid(uid: String) -> void:
	if not uid.is_empty():
		_muted_uids[uid] = true


# ─── Phase 5: message row long-press (Surface I) ──────────────────────────────

## Handle gui_input on a message row for long-press detection.
func _on_msg_row_input(event: InputEvent, history_index: int, row: Control) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_msg_long_press_index = history_index
				_msg_long_press_screen_pos = row.get_global_rect().position
				_msg_long_press_timer.start()
			else:
				_msg_long_press_timer.stop()
	elif event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			_msg_long_press_index = history_index
			_msg_long_press_screen_pos = row.get_global_rect().position
			_msg_long_press_timer.start()
		else:
			_msg_long_press_timer.stop()


## Called when the long-press timer fires — show context menu for message row.
func _on_msg_long_press_timeout() -> void:
	if _msg_long_press_index < 0 or _msg_long_press_index >= _history.size():
		return

	var msg: Dictionary = _history[_msg_long_press_index] as Dictionary
	var msg_uid: String = msg.get("uid", "")
	var msg_username: String = msg.get("username", "")
	var screen_pos := _msg_long_press_screen_pos

	# Capture up to 5 messages of context ending at the tapped message.
	var start_idx: int = max(0, _msg_long_press_index - 4)
	var context_msgs: Array = _history.slice(start_idx, _msg_long_press_index + 1)
	var evidence: Dictionary = {"messages": context_msgs}

	var items: Array = [
		{
			"label": tr("ui.chat.mute_user").format({"username": msg_username}),
			"action": func():
				# Resolve peer_id for peer-mute (toggle_mute uses int peer_id).
				# For uid-based auto-mute after report, use mute_by_uid.
				if not msg_uid.is_empty():
					mute_by_uid(msg_uid),
		},
		{
			"label": tr("ui.chat.report_context_menu_item"),
			"action": func():
				var rm: Node = get_node_or_null("/root/ReportModal")
				if rm != null and rm.has_method("open"):
					rm.call("open", msg_uid, msg_username, "chat_message", evidence),
		},
	]

	var ctx_menu: Node = get_node_or_null("/root/ContextMenu")
	if ctx_menu != null and ctx_menu.has_method("show_menu"):
		ctx_menu.call("show_menu", items, screen_pos)
