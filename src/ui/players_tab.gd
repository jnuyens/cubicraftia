# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# players_tab.gd — Players tab for the pause menu (Surface 6).
#
# Host view: player list + Kick (inline confirm), Freeze toggle, Roll-back (modal confirm).
# Non-host view: read-only peer list with connection quality.
#
# Security:
#   T-04-07-T: admin controls shown only when NetworkManager.is_session_host().
#              kick_peer is @rpc("authority") — peers cannot trigger it remotely.
#   T-04-07-R: roll-back requires 2-step confirmation modal.
#              Action logged via push_warning for audit trail.
#
# References:
#   04-07-PLAN.md Task 2
#   04-UI-SPEC.md Surface 6
#   04-PATTERNS.md lines 511-542 — tab injection pattern

class_name PlayersTab
extends VBoxContainer

# ─── Constants ────────────────────────────────────────────────────────────────

## Destructive red (kick, roll-back) per UI-SPEC.
const COLOR_DESTRUCTIVE: Color = Color(0.839, 0.220, 0.157, 1.0)

## Accent yellow (freeze toggle active, host label) per UI-SPEC.
const COLOR_ACCENT: Color = Color(0.96, 0.76, 0.05, 1.0)

## Relay-amber for "Laggy" label per UI-SPEC.
const COLOR_RELAY_AMBER: Color = Color(0.910, 0.537, 0.047, 1.0)

## Brick-white (full opacity) for primary text.
const COLOR_BRICK_WHITE: Color = Color(0.945, 0.941, 0.918, 1.0)

## Brick-white at 70% alpha for secondary text.
const COLOR_BRICK_WHITE_DIM: Color = Color(0.945, 0.941, 0.918, 0.7)

## Navy background for the panel.
const COLOR_NAVY: Color = Color(0.106, 0.173, 0.337, 0.95)

## Event kind for the freeze-build replication event (broadcast via NetworkManager).
const EVENT_FREEZE_BUILD: StringName = &"FREEZE_BUILD"

## Standard player row height in pixels.
const ROW_HEIGHT: int = 56

## Expanded row height when kick-confirm is shown.
const ROW_HEIGHT_EXPANDED: int = 112

# ─── Signals ─────────────────────────────────────────────────────────────────

## Emitted after a player is kicked.
signal player_kicked(peer_id: int)

## Emitted when a player's freeze state changes.
signal player_frozen(peer_id: int, frozen: bool)

# ─── Private state ────────────────────────────────────────────────────────────

## Active player row containers indexed by peer_id.
var _peer_rows: Dictionary = {}

## Reference to the roll-back confirmation modal (created on demand).
var _rollback_modal: Control = null

# ─── Lifecycle ───────────────────────────────────────────────────────────────

func _ready() -> void:
	# Subscribe to NetworkManager peer lifecycle signals.
	if is_instance_valid(NetworkManager):
		NetworkManager.peer_connected.connect(_on_peer_connected)
		NetworkManager.peer_disconnected.connect(_on_peer_disconnected)
		NetworkManager.peer_laggy.connect(_on_peer_laggy)
		NetworkManager.freeze_build_changed.connect(_on_freeze_build_changed)

	# Build initial player list.
	_build_player_list()


# ─── List building ────────────────────────────────────────────────────────────

func _build_player_list() -> void:
	# Clear existing children.
	for child in get_children():
		child.queue_free()
	_peer_rows.clear()

	# Invite button (shown when session has fewer than 4 players).
	var peer_count: int = 0
	if is_instance_valid(SessionRegistry):
		peer_count = SessionRegistry.get_peer_list().size() if SessionRegistry.has_method("get_peer_list") else 0
	if peer_count < 4:
		var invite_btn := Button.new()
		invite_btn.name = "InviteButton"
		invite_btn.text = tr("ui.players.invite_action")
		invite_btn.pressed.connect(_on_invite_pressed)
		add_child(invite_btn)

	# Build a row for each peer.
	if is_instance_valid(SessionRegistry) and SessionRegistry.has_method("get_peer_list"):
		var peers: Dictionary = SessionRegistry.get_peer_list()
		for peer_id: int in peers:
			var peer_data: Dictionary = {}
			if SessionRegistry.has_method("get_peer_data"):
				peer_data = SessionRegistry.get_peer_data(peer_id)
			var row: Control = _build_player_row(peer_id, peer_data)
			add_child(row)
			_peer_rows[peer_id] = row
	else:
		# Fallback: show local player only (no session / solo mode guard).
		var local_id: int = multiplayer.get_unique_id() if is_instance_valid(multiplayer) else 1
		var row: Control = _build_player_row(local_id, {})
		add_child(row)
		_peer_rows[local_id] = row

	# Roll-back section (host only) at the bottom.
	if is_instance_valid(NetworkManager) and NetworkManager.is_session_host():
		_build_rollback_section()


func _build_player_row(peer_id: int, peer_data: Dictionary) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = "PeerRow_%d" % peer_id
	panel.custom_minimum_size = Vector2(0, ROW_HEIGHT)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	panel.add_child(hbox)

	# Colour swatch for this peer's builder.
	var swatch := ColorRect.new()
	swatch.custom_minimum_size = Vector2(24, 24)
	swatch.color = _peer_color(peer_id, peer_data)
	hbox.add_child(swatch)

	# Username label.
	var username_label := Label.new()
	username_label.name = "Username"
	username_label.text = _peer_username(peer_id, peer_data)
	username_label.add_theme_font_size_override("font_size", 16)
	username_label.add_theme_color_override("font_color", COLOR_BRICK_WHITE)
	username_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(username_label)

	# "(Host)" badge (peer_id == 1 is the host / authoritative server).
	if peer_id == 1:
		var host_label := Label.new()
		host_label.text = tr("ui.players.host_label")
		host_label.add_theme_font_size_override("font_size", 14)
		host_label.add_theme_color_override("font_color", COLOR_ACCENT)
		hbox.add_child(host_label)

	# RTT label.
	var rtt_label := Label.new()
	rtt_label.name = "RttLabel"
	var rtt: float = 0.0
	if is_instance_valid(SessionRegistry) and SessionRegistry.has_method("get_peer_rtt"):
		rtt = SessionRegistry.get_peer_rtt(peer_id)
	rtt_label.text = "%dms" % int(rtt)
	rtt_label.add_theme_font_size_override("font_size", 13)
	rtt_label.add_theme_color_override("font_color", COLOR_BRICK_WHITE_DIM)
	hbox.add_child(rtt_label)

	# "Laggy" label (hidden by default — shown by peer_laggy signal).
	var laggy_label := Label.new()
	laggy_label.name = "LaggyLabel"
	laggy_label.text = tr("ui.players.laggy_label")
	laggy_label.visible = false
	laggy_label.add_theme_font_size_override("font_size", 14)
	laggy_label.add_theme_color_override("font_color", COLOR_RELAY_AMBER)
	hbox.add_child(laggy_label)

	# Admin buttons (host only, and not for the host's own row).
	var is_host: bool = is_instance_valid(NetworkManager) and NetworkManager.is_session_host()
	var local_peer_id: int = multiplayer.get_unique_id() if is_instance_valid(multiplayer) else 1
	if is_host and peer_id != local_peer_id:
		var admin_hbox := HBoxContainer.new()
		admin_hbox.add_theme_constant_override("separation", 8)

		# Kick button.
		var kick_btn := Button.new()
		kick_btn.name = "KickButton"
		kick_btn.text = tr("ui.players.kick")
		kick_btn.custom_minimum_size = Vector2(80, 0)
		_style_destructive_button(kick_btn)
		kick_btn.pressed.connect(_on_kick_pressed.bind(peer_id, panel))
		admin_hbox.add_child(kick_btn)

		# Freeze / Unfreeze toggle.
		var freeze_btn := Button.new()
		freeze_btn.name = "FreezeButton"
		var is_frozen: bool = is_instance_valid(NetworkManager) and NetworkManager.is_peer_frozen(peer_id)
		freeze_btn.text = tr("ui.players.unfreeze") if is_frozen else tr("ui.players.freeze")
		freeze_btn.custom_minimum_size = Vector2(80, 0)
		if is_frozen:
			_style_accent_button(freeze_btn)
		freeze_btn.pressed.connect(_on_freeze_pressed.bind(peer_id, freeze_btn))
		admin_hbox.add_child(freeze_btn)

		hbox.add_child(admin_hbox)

	return panel


func _build_rollback_section() -> void:
	# Separator above the roll-back area.
	var sep := HSeparator.new()
	add_child(sep)

	# Warning label.
	var warning_label := Label.new()
	warning_label.text = tr("ui.players.rollback_warning")
	warning_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	warning_label.add_theme_font_size_override("font_size", 13)
	warning_label.add_theme_color_override("font_color", COLOR_BRICK_WHITE_DIM)
	add_child(warning_label)

	# Roll-back button.
	var rollback_btn := Button.new()
	rollback_btn.name = "RollBackButton"
	rollback_btn.text = tr("ui.players.rollback_action")
	rollback_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_destructive_button(rollback_btn)
	rollback_btn.pressed.connect(_show_rollback_confirm_modal)
	add_child(rollback_btn)


# ─── Signal handlers — peer lifecycle ────────────────────────────────────────

func _on_peer_connected(_peer_id: int) -> void:
	_build_player_list()


func _on_peer_disconnected(_peer_id: int) -> void:
	_build_player_list()


func _on_peer_laggy(peer_id: int, is_laggy: bool) -> void:
	if not _peer_rows.has(peer_id):
		return
	var row: Control = _peer_rows[peer_id]
	var hbox: HBoxContainer = row.get_child(0) if row.get_child_count() > 0 else null
	if hbox == null:
		return
	var laggy_label: Node = hbox.get_node_or_null("LaggyLabel")
	if laggy_label != null:
		laggy_label.visible = is_laggy


func _on_freeze_build_changed(peer_id: int, frozen: bool) -> void:
	if not _peer_rows.has(peer_id):
		return
	var row: Control = _peer_rows[peer_id]
	var hbox: HBoxContainer = row.get_child(0) if row.get_child_count() > 0 else null
	if hbox == null:
		return
	# Update the freeze button text.
	var admin_hbox: Node = hbox.get_node_or_null("HBoxContainer")
	if admin_hbox == null:
		# Try finding by iterating (the admin HBoxContainer has no fixed name).
		for child in hbox.get_children():
			if child is HBoxContainer:
				admin_hbox = child
				break
	if admin_hbox != null:
		var freeze_btn: Node = admin_hbox.get_node_or_null("FreezeButton")
		if freeze_btn != null and freeze_btn is Button:
			(freeze_btn as Button).text = tr("ui.players.unfreeze") if frozen else tr("ui.players.freeze")
			if frozen:
				_style_accent_button(freeze_btn as Button)
			else:
				(freeze_btn as Button).remove_theme_stylebox_override("normal")

	# Update the panel border to show the accent-yellow freeze ring.
	if row is PanelContainer:
		if frozen:
			var style := StyleBoxFlat.new()
			style.bg_color = COLOR_NAVY
			style.border_width_left = 2
			style.border_width_top = 2
			style.border_width_right = 2
			style.border_width_bottom = 2
			style.border_color = COLOR_ACCENT
			style.corner_radius_top_left = 4
			style.corner_radius_top_right = 4
			style.corner_radius_bottom_left = 4
			style.corner_radius_bottom_right = 4
			row.add_theme_stylebox_override("panel", style)
		else:
			row.remove_theme_stylebox_override("panel")


# ─── Kick ─────────────────────────────────────────────────────────────────────

func _on_kick_pressed(peer_id: int, row: Control) -> void:
	# Expand the row to show inline kick confirmation (UI-SPEC: inline expand pattern).
	row.custom_minimum_size = Vector2(0, ROW_HEIGHT_EXPANDED)

	var confirm_vbox := VBoxContainer.new()
	confirm_vbox.name = "ConfirmRow"

	var confirm_label := Label.new()
	var username: String = _peer_username_from_row(row)
	confirm_label.text = tr("ui.players.kick_confirm").replace("{username}", username)
	confirm_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	confirm_label.add_theme_font_size_override("font_size", 13)
	confirm_label.add_theme_color_override("font_color", COLOR_BRICK_WHITE)
	confirm_vbox.add_child(confirm_label)

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 8)

	var confirm_btn := Button.new()
	confirm_btn.text = tr("ui.players.kick_confirm_action")
	_style_destructive_button(confirm_btn)
	confirm_btn.pressed.connect(_on_confirm_kick.bind(peer_id, row, confirm_vbox))
	btn_row.add_child(confirm_btn)

	var cancel_btn := Button.new()
	cancel_btn.text = tr("ui.players.kick_cancel")
	cancel_btn.pressed.connect(_on_cancel_kick.bind(row, confirm_vbox))
	btn_row.add_child(cancel_btn)

	confirm_vbox.add_child(btn_row)
	row.add_child(confirm_vbox)


func _on_confirm_kick(peer_id: int, row: Control, confirm_vbox: Control) -> void:
	confirm_vbox.queue_free()
	row.custom_minimum_size = Vector2(0, ROW_HEIGHT)
	if is_instance_valid(NetworkManager):
		NetworkManager.kick_peer(peer_id)
	player_kicked.emit(peer_id)


func _on_cancel_kick(row: Control, confirm_vbox: Control) -> void:
	confirm_vbox.queue_free()
	row.custom_minimum_size = Vector2(0, ROW_HEIGHT)


# ─── Freeze toggle ────────────────────────────────────────────────────────────

func _on_freeze_pressed(peer_id: int, freeze_btn: Button) -> void:
	var currently_frozen: bool = is_instance_valid(NetworkManager) and NetworkManager.is_peer_frozen(peer_id)
	var new_state: bool = not currently_frozen
	if is_instance_valid(NetworkManager):
		NetworkManager.set_freeze_build(peer_id, new_state)
	player_frozen.emit(peer_id, new_state)


# ─── Invite ───────────────────────────────────────────────────────────────────

func _on_invite_pressed() -> void:
	# Find the session ID and open an InviteModal.
	var session_id: String = ""
	if is_instance_valid(NetworkManager):
		session_id = NetworkManager.get_session_id()
	if session_id == "":
		return

	# Load and open the invite modal.
	var modal_scene: PackedScene = load("res://src/ui/invite_modal.tscn")
	if modal_scene != null:
		var modal: Node = modal_scene.instantiate()
		get_tree().get_root().add_child(modal)
		if modal.has_method("open"):
			modal.open(session_id)


# ─── Roll-back ────────────────────────────────────────────────────────────────

func _show_rollback_confirm_modal() -> void:
	# Create the roll-back confirmation modal (PanelContainer overlay — NOT AcceptDialog).
	if is_instance_valid(_rollback_modal):
		return  # Already showing.

	# Dark overlay.
	var overlay := ColorRect.new()
	overlay.name = "RollbackOverlay"
	overlay.layout_mode = 1
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0.106, 0.173, 0.337, 0.60)
	get_tree().get_root().add_child(overlay)
	_rollback_modal = overlay

	# Centred modal panel.
	var modal := PanelContainer.new()
	modal.custom_minimum_size = Vector2(400, 0)
	# Centre the modal.
	var modal_ctrl := Control.new()
	modal_ctrl.layout_mode = 1
	modal_ctrl.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(modal_ctrl)

	# StyleBox for the modal panel.
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.106, 0.173, 0.337, 0.95)
	style.corner_radius_top_left = 16
	style.corner_radius_top_right = 16
	style.corner_radius_bottom_left = 16
	style.corner_radius_bottom_right = 16
	style.content_margin_left = 24.0
	style.content_margin_top = 24.0
	style.content_margin_right = 24.0
	style.content_margin_bottom = 24.0
	modal.add_theme_stylebox_override("panel", style)
	modal.layout_mode = 1
	modal.anchors_preset = Control.PRESET_CENTER
	modal.anchor_left = 0.5
	modal.anchor_top = 0.5
	modal.anchor_right = 0.5
	modal.anchor_bottom = 0.5
	modal.offset_left = -200.0
	modal.offset_right = 200.0
	modal_ctrl.add_child(modal)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	modal.add_child(vbox)

	# Heading.
	var heading := Label.new()
	heading.text = tr("ui.players.rollback_confirm_title")
	heading.add_theme_font_size_override("font_size", 20)
	heading.add_theme_color_override("font_color", COLOR_BRICK_WHITE)
	vbox.add_child(heading)

	# Body.
	var body := Label.new()
	body.text = tr("ui.players.rollback_confirm_body")
	body.autowrap_mode = TextServer.AUTOWRAP_WORD
	body.add_theme_font_size_override("font_size", 16)
	body.add_theme_color_override("font_color", COLOR_BRICK_WHITE_DIM)
	vbox.add_child(body)

	# Button row.
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 8)
	vbox.add_child(btn_row)

	var confirm_btn := Button.new()
	confirm_btn.text = tr("ui.players.rollback_confirm_action")
	confirm_btn.custom_minimum_size = Vector2(160, 0)
	_style_destructive_button(confirm_btn)
	confirm_btn.pressed.connect(_on_rollback_confirmed.bind(overlay))
	btn_row.add_child(confirm_btn)

	var cancel_btn := Button.new()
	cancel_btn.text = tr("ui.players.rollback_cancel")
	cancel_btn.custom_minimum_size = Vector2(160, 0)
	cancel_btn.pressed.connect(_on_rollback_cancelled.bind(overlay))
	btn_row.add_child(cancel_btn)


func _on_rollback_confirmed(overlay: Control) -> void:
	overlay.queue_free()
	_rollback_modal = null

	# Audit trail.
	push_warning("WorldSave.roll_back by host at %s" % Time.get_datetime_string_from_system(true))

	# Attempt to load the latest snapshot and broadcast to all peers.
	if is_instance_valid(WorldSave) and WorldSave.has_method("load_latest_snapshot"):
		var snapshot: Variant = WorldSave.load_latest_snapshot()
		if snapshot == null or snapshot == {}:
			if is_instance_valid(Toasts):
				Toasts.show("No snapshot available", "error")
			return
		if is_instance_valid(NetworkManager):
			var snapshot_id: String = str(snapshot.get("snapshot_id", "")) if snapshot is Dictionary else ""
			NetworkManager.broadcast_event({"kind": "SNAPSHOT_RESET", "snapshot_id": snapshot_id})
	else:
		# WorldSave not yet wired (Plan 04-10 ships this); broadcast stub.
		if is_instance_valid(NetworkManager):
			NetworkManager.broadcast_event({"kind": "SNAPSHOT_RESET", "snapshot_id": ""})


func _on_rollback_cancelled(overlay: Control) -> void:
	overlay.queue_free()
	_rollback_modal = null


# ─── Style helpers ────────────────────────────────────────────────────────────

func _style_destructive_button(btn: Button) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.106, 0.173, 0.337, 0.85)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = COLOR_DESTRUCTIVE
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.content_margin_left = 12.0
	style.content_margin_top = 8.0
	style.content_margin_right = 12.0
	style.content_margin_bottom = 8.0
	btn.add_theme_stylebox_override("normal", style)
	btn.add_theme_color_override("font_color", COLOR_DESTRUCTIVE)


func _style_accent_button(btn: Button) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.106, 0.173, 0.337, 0.85)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = COLOR_ACCENT
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.content_margin_left = 12.0
	style.content_margin_top = 8.0
	style.content_margin_right = 12.0
	style.content_margin_bottom = 8.0
	btn.add_theme_stylebox_override("normal", style)
	btn.add_theme_color_override("font_color", COLOR_ACCENT)


# ─── Data helpers ─────────────────────────────────────────────────────────────

func _peer_color(peer_id: int, peer_data: Dictionary) -> Color:
	# Use a builder colour from peer_data if available; otherwise derive from peer_id.
	var stored: Variant = peer_data.get("brick_color", null)
	if stored is Color:
		return stored as Color
	# Derive a deterministic hue from peer_id so each player gets a unique colour.
	var hue: float = fmod(float(peer_id) * 0.137, 1.0)
	return Color.from_hsv(hue, 0.7, 0.9, 1.0)


func _peer_username(peer_id: int, peer_data: Dictionary) -> String:
	var name_val: Variant = peer_data.get("username", null)
	if name_val is String and name_val != "":
		return name_val as String
	return "Player %d" % peer_id


func _peer_username_from_row(row: Control) -> String:
	# Walk the row's HBoxContainer to find the Username label.
	var hbox: Control = row.get_child(0) if row.get_child_count() > 0 else null
	if hbox == null:
		return ""
	for child in hbox.get_children():
		if child is Label and child.name == "Username":
			return (child as Label).text
	return ""
