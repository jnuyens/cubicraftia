# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# friends_panel.gd — Friends list slide-in panel controller (Surface 2 + embedded Surface 3).
#
# Chrome is a verbatim copy of inventory_slide_in.gd:
#   - TWEEN_DURATION_S=0.22, SIDEBAR_WIDTH=360, PEEK_HEIGHT=48
#   - _setup_panel_style(), _animate_to(), _snap_to_nearest()
#   - _notify_mobile_overlay() calling notify_friends_open()
#
# Surface 3 (Sessions browser) is embedded: friends with open sessions show a
# "Join" button in their row. Tapping Join emits join_session_requested(session_id).
#
# Mutual exclusion: opening FriendsPanel closes Inventory and BrickPalette.
#
# Security:
#   T-04-06-S: friend UIDs are not displayed in UI; only display_name is shown.
#
# References:
#   04-UI-SPEC.md Surface 2 + Surface 3 — friends list, sessions browser spec
#   04-PATTERNS.md §friends_panel.gd — verbatim chrome, mutual exclusion, notify pattern
#   04-06-PLAN.md Task 2

class_name FriendsPanel
extends Control

# ─── Constants (verbatim from inventory_slide_in.gd) ─────────────────────────

## Panel background: #1B2C56 at 0.92α — verbatim from inventory_slide_in.gd.
const COLOR_NAVY: Color = Color(0.106, 0.173, 0.337, 0.92)
## Accent yellow: #F5C30D — tab underline + selected ring.
const COLOR_ACCENT: Color = Color(0.96, 0.76, 0.05, 1.0)
## Brick white: #F1F0EA — secondary text.
const COLOR_WHITE: Color = Color(0.945, 0.941, 0.918, 1.0)
## Animation duration — verbatim from inventory_slide_in.gd.
const TWEEN_DURATION_S: float = 0.22
## Sidebar width (desktop) — verbatim from inventory_slide_in.gd.
const SIDEBAR_WIDTH: int = 360
## Bottom-sheet peek height — verbatim from inventory_slide_in.gd.
const PEEK_HEIGHT: int = 48

## Online green: #3DB560 — online presence dot (UI-SPEC Surface 2).
const COLOR_ONLINE: Color = Color(0.239, 0.710, 0.376, 1.0)
## Offline grey: #6B7280 — offline presence dot (UI-SPEC Surface 2).
const COLOR_OFFLINE: Color = Color(0.420, 0.447, 0.502, 1.0)

# ─── Exported properties ──────────────────────────────────────────────────────

## Layout mode: "sidebar" (desktop) or "bottomsheet" (mobile).
@export var layout: String = "sidebar"

## When true, the panel is opened from the world select screen (not in-session).
## Admin controls (kick, freeze, roll-back) are hidden in standalone mode because
## those actions require an active multiplayer session.
## Spec: 06-UI-SPEC.md Surface 8.
@export var standalone_mode: bool = false

# ─── Signals ──────────────────────────────────────────────────────────────────

## Emitted when the player taps Join on a friend's open session.
## NetworkManager picks this up in Wave 4.
signal join_session_requested(session_id: String)

# ─── Node refs ────────────────────────────────────────────────────────────────

var _body: PanelContainer = null
var _search_field: LineEdit = null
var _friends_list: VBoxContainer = null
var _pending_list: VBoxContainer = null
var _pending_label: Label = null
var _empty_state: VBoxContainer = null
var _drag_handle: Control = null

# ─── State ────────────────────────────────────────────────────────────────────

var _tween: Tween = null
var _is_expanded: bool = false
var _expanded_y: float = 0.0
var _collapsed_y: float = 0.0
var _current_search: String = ""
var _cached_friends: Array = []

## Long-press timer for context menu (500ms, one-shot).
var _long_press_timer: Timer = null
## UID of the friend row currently being held.
var _long_press_uid: String = ""
## Username of the friend row currently being held.
var _long_press_username: String = ""
## Screen position of the held row for context menu anchoring.
var _long_press_screen_pos: Vector2 = Vector2.ZERO

# ─── Lifecycle ────────────────────────────────────────────────────────────────

func _ready() -> void:
	add_to_group("friends_panel")
	_build_ui()
	_setup_panel_style()
	_setup_positions()
	_connect_signals()
	# Hide admin controls when opened from world_select_screen (no active session).
	# Per 06-UI-SPEC.md Surface 8: kick/freeze/rollback are in-session actions only.
	_apply_standalone_mode()

	if layout == "bottomsheet":
		position.y = _collapsed_y
		visible = true
	else:
		visible = false

	# Phase 5: long-press timer for context menu (Surface H).
	_long_press_timer = Timer.new()
	_long_press_timer.name = "_LongPressTimer"
	_long_press_timer.wait_time = 0.5
	_long_press_timer.one_shot = true
	_long_press_timer.timeout.connect(_on_long_press_timeout)
	add_child(_long_press_timer)


## Build the friends panel UI tree programmatically.
func _build_ui() -> void:
	# _body: PanelContainer — chrome panel.
	_body = PanelContainer.new()
	_body.name = "Body"
	if layout == "sidebar":
		_body.anchor_left = 1.0
		_body.anchor_top = 0.0
		_body.anchor_right = 1.0
		_body.anchor_bottom = 1.0
		_body.offset_left = -SIDEBAR_WIDTH
		_body.offset_top = 0.0
		_body.offset_right = 0.0
		_body.offset_bottom = 0.0
		_body.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	else:
		_body.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
		_body.custom_minimum_size = Vector2(0, 400)
	add_child(_body)

	# MarginContainer for inner padding.
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	_body.add_child(margin)

	var inner_vbox := VBoxContainer.new()
	inner_vbox.add_theme_constant_override("separation", 8)
	margin.add_child(inner_vbox)

	# Panel title: "Friends" — Heading 20px semibold, brick white.
	var title_label := Label.new()
	title_label.text = tr("ui.friends.title")
	title_label.add_theme_color_override("font_color", COLOR_WHITE)
	inner_vbox.add_child(title_label)

	# Search field.
	_search_field = LineEdit.new()
	_search_field.name = "SearchField"
	_search_field.placeholder_text = tr("ui.friends.search_placeholder")
	_search_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner_vbox.add_child(_search_field)

	# Pending invites section label (hidden when count=0).
	_pending_label = Label.new()
	_pending_label.name = "PendingLabel"
	_pending_label.text = tr("ui.friends.section_pending")
	_pending_label.visible = false
	_pending_label.add_theme_color_override("font_color", COLOR_WHITE)
	inner_vbox.add_child(_pending_label)

	# Pending list.
	_pending_list = VBoxContainer.new()
	_pending_list.name = "PendingList"
	_pending_list.visible = false
	_pending_list.add_theme_constant_override("separation", 4)
	inner_vbox.add_child(_pending_list)

	# Friends section label.
	var friends_label := Label.new()
	friends_label.text = tr("ui.friends.section_list")
	friends_label.add_theme_color_override("font_color",
		Color(COLOR_WHITE.r, COLOR_WHITE.g, COLOR_WHITE.b, 0.7))
	inner_vbox.add_child(friends_label)

	# Scroll container for the friends list.
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inner_vbox.add_child(scroll)

	_friends_list = VBoxContainer.new()
	_friends_list.name = "FriendsList"
	_friends_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_friends_list.add_theme_constant_override("separation", 4)
	scroll.add_child(_friends_list)

	# Empty state.
	_empty_state = VBoxContainer.new()
	_empty_state.name = "EmptyState"
	_empty_state.visible = false
	_empty_state.alignment = BoxContainer.ALIGNMENT_CENTER
	inner_vbox.add_child(_empty_state)

	var empty_heading := Label.new()
	empty_heading.text = tr("ui.friends.empty_heading")
	empty_heading.add_theme_color_override("font_color", COLOR_WHITE)
	empty_heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty_state.add_child(empty_heading)

	var empty_body := Label.new()
	empty_body.text = tr("ui.friends.empty_body")
	empty_body.add_theme_color_override("font_color",
		Color(COLOR_WHITE.r, COLOR_WHITE.g, COLOR_WHITE.b, 0.7))
	empty_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	empty_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_empty_state.add_child(empty_body)

	# Mobile drag handle (only for bottomsheet).
	if layout == "bottomsheet":
		_drag_handle = ColorRect.new()
		_drag_handle.name = "DragHandle"
		_drag_handle.custom_minimum_size = Vector2(32, 4)
		_drag_handle.color = Color(COLOR_WHITE.r, COLOR_WHITE.g, COLOR_WHITE.b, 0.4)
		# Insert at top of body's child list via reparent to a HBoxContainer.
		var handle_row := HBoxContainer.new()
		handle_row.alignment = BoxContainer.ALIGNMENT_CENTER
		inner_vbox.add_child(handle_row)
		inner_vbox.move_child(handle_row, 0)
		handle_row.add_child(_drag_handle)
		_drag_handle.gui_input.connect(_on_drag_handle_input)


## Apply the panel StyleBoxFlat — verbatim from inventory_slide_in.gd _setup_panel_style.
func _setup_panel_style() -> void:
	if _body == null:
		return
	var style := StyleBoxFlat.new()
	style.bg_color = COLOR_NAVY
	if layout == "sidebar":
		style.corner_radius_top_left = 16
		style.corner_radius_bottom_left = 16
		style.corner_radius_top_right = 0
		style.corner_radius_bottom_right = 0
	else:
		style.corner_radius_top_left = 16
		style.corner_radius_top_right = 16
		style.corner_radius_bottom_left = 0
		style.corner_radius_bottom_right = 0
	_body.add_theme_stylebox_override("panel", style)


## Calculate expanded / collapsed positions (same logic as inventory_slide_in.gd).
func _setup_positions() -> void:
	if layout == "bottomsheet":
		var vp_height := get_viewport_rect().size.y
		_expanded_y = vp_height * 0.30
		_collapsed_y = vp_height - PEEK_HEIGHT
	else:
		# Sidebar: start off-screen right.
		var vp_width := get_viewport_rect().size.x
		_expanded_y = vp_width - SIDEBAR_WIDTH  # reused as "expanded X" conceptually
		_collapsed_y = vp_width                  # off-screen right


## Connect FriendsClient signals and search field.
func _connect_signals() -> void:
	# Search field.
	if _search_field != null and _search_field.has_signal("text_changed"):
		_search_field.text_changed.connect(_on_search_changed)

	# FriendsClient signals.
	var fc: Node = get_node_or_null("/root/FriendsClient")
	if fc == null:
		return
	if fc.has_signal("friends_loaded"):
		fc.friends_loaded.connect(_on_friends_loaded)
	if fc.has_signal("friendship_created"):
		fc.friendship_created.connect(_on_friendship_changed)
	if fc.has_signal("friendship_deleted"):
		fc.friendship_deleted.connect(_on_friendship_changed)
	if fc.has_signal("profiles_found"):
		fc.profiles_found.connect(_on_profiles_found)

## Apply standalone_mode: hide any in-session admin controls.
## In the current implementation (Phase 6) no admin control nodes exist yet; this
## method provides a stable hook for Phase 4+ admin UI that will call
## _admin_controls_container.visible = false when standalone_mode is true.
## See 06-UI-SPEC.md Surface 8.
func _apply_standalone_mode() -> void:
	if not standalone_mode:
		return
	# Find admin controls container by name if it exists (added in a later plan).
	var admin_section: Node = null
	if _body != null:
		admin_section = _body.find_child("AdminControlsSection", true, false)
	if admin_section != null:
		admin_section.visible = false

# ─── Public API ───────────────────────────────────────────────────────────────

## Open the friends panel (mutual exclusion: closes inventory + palette first).
func open() -> void:
	# Close brick palette (mutual exclusion).
	if is_inside_tree():
		var palette: Node = null
		if get_tree().has_group("brick_palette"):
			palette = get_tree().get_first_node_in_group("brick_palette")
		if palette == null:
			palette = get_tree().get_root().find_child("BrickPaletteBottomsheet", true, false)
		if palette != null and palette.has_method("close"):
			palette.call("close")

		# Close inventory (mutual exclusion).
		if get_tree().has_group("inventory_slide_in"):
			var inv: Node = get_tree().get_first_node_in_group("inventory_slide_in")
			if inv != null and inv.has_method("close"):
				inv.call("close")

	visible = true

	if layout == "bottomsheet":
		_animate_to(_expanded_y)
		_is_expanded = true
	else:
		# Sidebar: animate in from the right.
		var vp_width: float = get_viewport_rect().size.x
		position.x = vp_width  # Off-screen right.
		_animate_sidebar_to(vp_width - SIDEBAR_WIDTH)

	_notify_friends_open(true)

	# Fetch friends from FriendsClient.
	var fc: Node = get_node_or_null("/root/FriendsClient")
	if fc != null and fc.has_method("get_friends"):
		fc.call("get_friends")


## Close the friends panel.
func close() -> void:
	if layout == "bottomsheet":
		_animate_to(_collapsed_y)
		_is_expanded = false
	else:
		var vp_width: float = get_viewport_rect().size.x
		_animate_sidebar_to(vp_width, true)

	_notify_friends_open(false)

# ─── Animation (verbatim from inventory_slide_in.gd) ─────────────────────────

## Animate the bottom-sheet to a target Y — verbatim from inventory_slide_in.gd.
func _animate_to(target_y: float) -> void:
	if _tween != null and _tween.is_running():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, "position:y", target_y, TWEEN_DURATION_S)\
		.set_ease(Tween.EASE_OUT)\
		.set_trans(Tween.TRANS_CUBIC)


## Animate desktop sidebar to a target X position.
func _animate_sidebar_to(target_x: float, hide: bool = false) -> void:
	if _tween != null and _tween.is_running():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, "position:x", target_x, TWEEN_DURATION_S)\
		.set_ease(Tween.EASE_OUT)\
		.set_trans(Tween.TRANS_CUBIC)
	if hide:
		_tween.tween_callback(func(): visible = false)


## Snap to nearest position after drag release — verbatim from inventory_slide_in.gd.
func _snap_to_nearest() -> void:
	var mid: float = (_expanded_y + _collapsed_y) * 0.5
	if position.y <= mid:
		_animate_to(_expanded_y)
		_is_expanded = true
		_notify_friends_open(true)
	else:
		_animate_to(_collapsed_y)
		_is_expanded = false
		_notify_friends_open(false)

# ─── Mobile overlay notification ─────────────────────────────────────────────

## Notify MobileOverlay of friends panel open/close state.
## Mirrors inventory_slide_in.gd _notify_mobile_overlay pattern.
func _notify_friends_open(is_open: bool) -> void:
	if not is_inside_tree():
		return
	var overlay: Node = null
	if get_tree().has_group("mobile_overlay"):
		overlay = get_tree().get_first_node_in_group("mobile_overlay")
	if overlay == null:
		overlay = get_tree().get_root().find_child("MobileOverlay", true, false)
	if overlay != null:
		if overlay.has_method("notify_friends_open"):
			overlay.call("notify_friends_open", is_open)

# ─── Bottom-sheet drag (verbatim from inventory_slide_in.gd) ─────────────────

func _on_drag_handle_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if not touch.pressed:
			_snap_to_nearest()
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		var new_y: float = clampf(position.y + drag.relative.y, _expanded_y, _collapsed_y)
		position.y = new_y
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
			_snap_to_nearest()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if mm.button_mask & MOUSE_BUTTON_MASK_LEFT:
			var new_y: float = clampf(position.y + mm.relative.y, _expanded_y, _collapsed_y)
			position.y = new_y

# ─── Friend list rendering ────────────────────────────────────────────────────

## Called when FriendsClient emits friends_loaded(friends: Array).
func _on_friends_loaded(friends: Array) -> void:
	_cached_friends = friends
	_render_friends_list(friends)


## Rebuild the friends list from an array of friend Dictionaries.
func _render_friends_list(friends: Array) -> void:
	if _friends_list == null:
		return
	# Clear existing rows.
	for child in _friends_list.get_children():
		child.queue_free()

	# Filter by current search text if any.
	var filtered: Array = friends
	if _current_search.length() >= 2:
		filtered = []
		for f in friends:
			var name_str: String = f.get("username", "") as String
			if name_str.to_lower().contains(_current_search.to_lower()):
				filtered.append(f)

	if filtered.is_empty():
		if _empty_state != null:
			_empty_state.visible = true
		return

	if _empty_state != null:
		_empty_state.visible = false

	for friend in filtered:
		var row := _build_friend_row(friend)
		if row != null:
			_friends_list.add_child(row)


## Build a single friend row HBoxContainer.
## T-04-06-S: only display_name is shown; raw UID is never surfaced in UI.
func _build_friend_row(friend: Dictionary) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.custom_minimum_size = Vector2(0, 48)

	# Online/offline status dot (10×10 ColorRect).
	var dot := ColorRect.new()
	dot.custom_minimum_size = Vector2(10, 10)
	var is_online: bool = friend.get("status", "") == "online" \
		or friend.get("current_session_id", null) != null
	dot.color = COLOR_ONLINE if is_online else COLOR_OFFLINE
	row.add_child(dot)

	# VBoxContainer for name + status.
	var name_vbox := VBoxContainer.new()
	name_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_vbox.add_theme_constant_override("separation", 2)
	row.add_child(name_vbox)

	var name_label := Label.new()
	name_label.text = friend.get("username", tr("ui.friends.search_empty"))
	name_label.add_theme_color_override("font_color", COLOR_WHITE)
	name_vbox.add_child(name_label)

	var session_id: Variant = friend.get("current_session_id", null)
	var status_label := Label.new()
	if session_id != null:
		var world_name: String = friend.get("world_name", "")
		if world_name.is_empty():
			status_label.text = tr("ui.friends.status_online")
		else:
			status_label.text = tr("ui.friends.status_in_world").replace("{world_name}", world_name)
	elif is_online:
		status_label.text = tr("ui.friends.status_online")
	else:
		status_label.text = tr("ui.friends.status_offline")
	status_label.add_theme_color_override("font_color",
		Color(COLOR_WHITE.r, COLOR_WHITE.g, COLOR_WHITE.b, 0.6))
	name_vbox.add_child(status_label)

	# Join button (80px wide) — only if friend has an open session.
	if session_id != null:
		var join_btn := Button.new()
		join_btn.text = tr("ui.friends.join")
		join_btn.custom_minimum_size = Vector2(80, 0)
		join_btn.pressed.connect(_on_join_pressed.bind(str(session_id)))
		row.add_child(join_btn)

	# Phase 5: long-press detection for Block/Report/Unfriend context menu (Surface H).
	var uid_str: String = str(friend.get("id", friend.get("uid", "")))
	var username_str: String = str(friend.get("username", ""))
	row.gui_input.connect(_on_friend_row_input.bind(uid_str, username_str, row))
	row.mouse_filter = Control.MOUSE_FILTER_STOP

	return row


## Build a pending invite row.
func _build_pending_row(invite: Dictionary) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.custom_minimum_size = Vector2(0, 40)

	# Avatar placeholder (24×24 ColorRect).
	var avatar := ColorRect.new()
	avatar.custom_minimum_size = Vector2(24, 24)
	avatar.color = COLOR_NAVY
	row.add_child(avatar)

	var name_label := Label.new()
	name_label.text = invite.get("username", "")
	name_label.add_theme_color_override("font_color", COLOR_WHITE)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)

	var accept_btn := Button.new()
	accept_btn.text = tr("ui.friends.accept")
	accept_btn.custom_minimum_size = Vector2(80, 0)
	accept_btn.pressed.connect(_on_accept_pressed.bind(invite.get("uid", "")))
	row.add_child(accept_btn)

	var decline_btn := Button.new()
	decline_btn.text = tr("ui.friends.decline")
	decline_btn.custom_minimum_size = Vector2(80, 0)
	decline_btn.pressed.connect(_on_decline_pressed.bind(invite.get("uid", "")))
	row.add_child(decline_btn)

	return row


## Render pending invite rows.
func _render_pending_list(invites: Array) -> void:
	if _pending_list == null:
		return
	for child in _pending_list.get_children():
		child.queue_free()

	var has_pending: bool = not invites.is_empty()
	if _pending_label != null:
		_pending_label.visible = has_pending
	_pending_list.visible = has_pending

	for invite in invites:
		var row := _build_pending_row(invite)
		if row != null:
			_pending_list.add_child(row)

# ─── Signal handlers ──────────────────────────────────────────────────────────

## Join button pressed — emit signal for NetworkManager to handle.
func _on_join_pressed(session_id: String) -> void:
	emit_signal("join_session_requested", session_id)
	close()


## Accept friend request.
func _on_accept_pressed(uid: String) -> void:
	if uid.is_empty():
		return
	var fc: Node = get_node_or_null("/root/FriendsClient")
	if fc != null and fc.has_method("create_friendship"):
		fc.call("create_friendship", uid)


## Decline friend request.
func _on_decline_pressed(uid: String) -> void:
	if uid.is_empty():
		return
	var fc: Node = get_node_or_null("/root/FriendsClient")
	if fc != null and fc.has_method("delete_friendship"):
		fc.call("delete_friendship", uid)


## Called when friendship is created or deleted — refresh list.
func _on_friendship_changed(_uid: String = "") -> void:
	var fc: Node = get_node_or_null("/root/FriendsClient")
	if fc != null and fc.has_method("get_friends"):
		fc.call("get_friends")


## Search field text changed — filter or search.
func _on_search_changed(text: String) -> void:
	_current_search = text
	if text.length() >= 2:
		var fc: Node = get_node_or_null("/root/FriendsClient")
		if fc != null and fc.has_method("search_friend"):
			fc.call("search_friend", text)
	else:
		# Restore cached friends list.
		_render_friends_list(_cached_friends)


## Called when FriendsClient.profiles_found fires (search results).
func _on_profiles_found(profiles: Array) -> void:
	_render_friends_list(profiles)


# ─── Phase 5: long-press context menu (Surface H) ─────────────────────────────

## Handle gui_input on a friend row to detect long-press.
func _on_friend_row_input(event: InputEvent, uid: String, username: String, row: Control) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_long_press_uid = uid
				_long_press_username = username
				_long_press_screen_pos = row.get_global_rect().position + Vector2(row.size.x, 0)
				_long_press_timer.start()
			else:
				_long_press_timer.stop()
	elif event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			_long_press_uid = uid
			_long_press_username = username
			_long_press_screen_pos = row.get_global_rect().position + Vector2(row.size.x, 0)
			_long_press_timer.start()
		else:
			_long_press_timer.stop()


## Called when the long-press timer fires — show context menu.
func _on_long_press_timeout() -> void:
	if _long_press_uid.is_empty():
		return

	var uid := _long_press_uid
	var username := _long_press_username
	var screen_pos := _long_press_screen_pos

	var items: Array = [
		{
			"label": tr("ui.friends.block").format({"username": username}),
			"action": func(): _open_block_modal(uid, username),
		},
		{
			"label": tr("ui.friends.report").format({"username": username}),
			"action": func(): _open_report_modal(uid, username),
		},
		{"label": "---", "action": Callable()},
		{
			"label": tr("ui.friends.unfriend"),
			"action": func(): _unfriend(uid),
		},
	]

	var ctx_menu: Node = get_node_or_null("/root/ContextMenu")
	if ctx_menu != null and ctx_menu.has_method("show_menu"):
		ctx_menu.call("show_menu", items, screen_pos)


func _open_block_modal(uid: String, username: String) -> void:
	var bm: Node = get_node_or_null("/root/BlockModal")
	if bm != null and bm.has_method("open"):
		bm.call("open", uid, username)


func _open_report_modal(uid: String, username: String) -> void:
	var rm: Node = get_node_or_null("/root/ReportModal")
	if rm != null and rm.has_method("open"):
		rm.call("open", uid, username, "player")


func _unfriend(uid: String) -> void:
	if uid.is_empty():
		return
	var fc: Node = get_node_or_null("/root/FriendsClient")
	if fc != null and fc.has_method("delete_friendship"):
		fc.call("delete_friendship", uid)
