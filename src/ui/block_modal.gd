# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# block_modal.gd — Block Confirmation Modal (Surface A, Plan 05-08).
#
# CanvasLayer layer=20. Full-screen navy overlay with centred PanelContainer.
# Cannot be dismissed by tapping outside or pressing Escape — only via buttons.
#
# Usage:
#   BlockModal.open(uid, username)
#
# Security:
#   T-05-I1: No notification to blocked user. Client-side display filter only.
#   T-05-D1: Submit button enters loading state after first tap.
#
# References:
#   05-UI-SPEC.md Surface A — Block Confirmation Modal
#   05-08-PLAN.md Task 1

extends CanvasLayer

# ─── Colors ──────────────────────────────────────────────────────────────────

const COLOR_NAVY: Color      = Color(0.106, 0.173, 0.337, 0.60)   # 60% alpha overlay
const COLOR_PANEL: Color     = Color(0.106, 0.173, 0.337, 0.92)   # panel background
const COLOR_WHITE: Color     = Color(0.945, 0.941, 0.918, 1.0)    # brick white
const COLOR_DESTRUCTIVE: Color = Color(0.839, 0.220, 0.157, 1.0) # brick red

# ─── Signals ─────────────────────────────────────────────────────────────────

## Emitted after the user confirms blocking.
signal user_blocked(uid: String)

# ─── Private state ────────────────────────────────────────────────────────────

var _target_uid: String = ""
var _target_username: String = ""

# ─── Node refs ───────────────────────────────────────────────────────────────

var _overlay: ColorRect = null
var _panel: PanelContainer = null
var _heading: Label = null
var _body_label: Label = null
var _block_btn: Button = null
var _cancel_btn: Button = null

# ─── Lifecycle ────────────────────────────────────────────────────────────────

func _ready() -> void:
	layer = 20
	_build_ui()
	visible = false


func _build_ui() -> void:
	# Full-screen overlay — MOUSE_FILTER_STOP blocks clicks from passing through.
	_overlay = ColorRect.new()
	_overlay.name = "Overlay"
	_overlay.color = COLOR_NAVY
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_overlay)

	# Centred PanelContainer.
	_panel = PanelContainer.new()
	_panel.name = "ModalPanel"
	_panel.custom_minimum_size = Vector2(400, 0)
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = COLOR_PANEL
	panel_style.corner_radius_top_left = 12
	panel_style.corner_radius_top_right = 12
	panel_style.corner_radius_bottom_left = 12
	panel_style.corner_radius_bottom_right = 12
	panel_style.content_margin_left = 16.0
	panel_style.content_margin_top = 16.0
	panel_style.content_margin_right = 16.0
	panel_style.content_margin_bottom = 24.0
	_panel.add_theme_stylebox_override("panel", panel_style)
	_overlay.add_child(_panel)

	# Inner VBoxContainer.
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	_panel.add_child(vbox)

	# Heading label.
	_heading = Label.new()
	_heading.name = "Heading"
	_heading.add_theme_color_override("font_color", COLOR_WHITE)
	_heading.add_theme_font_size_override("font_size", 20)
	_heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_heading)

	# Body label.
	_body_label = Label.new()
	_body_label.name = "Body"
	_body_label.text = tr("ui.block.body")
	_body_label.add_theme_color_override("font_color", Color(COLOR_WHITE.r, COLOR_WHITE.g, COLOR_WHITE.b, 0.80))
	_body_label.add_theme_font_size_override("font_size", 16)
	_body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_body_label)

	# Button row.
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 8)
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(btn_row)

	# Block (destructive) button.
	_block_btn = Button.new()
	_block_btn.name = "BlockButton"
	_block_btn.custom_minimum_size = Vector2(160, 0)
	var block_style := StyleBoxFlat.new()
	block_style.bg_color = COLOR_DESTRUCTIVE
	block_style.corner_radius_top_left = 6
	block_style.corner_radius_top_right = 6
	block_style.corner_radius_bottom_left = 6
	block_style.corner_radius_bottom_right = 6
	_block_btn.add_theme_stylebox_override("normal", block_style)
	var block_hover := block_style.duplicate() as StyleBoxFlat
	block_hover.bg_color = Color(COLOR_DESTRUCTIVE.r + 0.08, COLOR_DESTRUCTIVE.g, COLOR_DESTRUCTIVE.b, 1.0)
	_block_btn.add_theme_stylebox_override("hover", block_hover)
	_block_btn.add_theme_color_override("font_color", COLOR_WHITE)
	_block_btn.add_theme_color_override("font_hover_color", COLOR_WHITE)
	_block_btn.pressed.connect(_on_block_pressed)
	btn_row.add_child(_block_btn)

	# Cancel (secondary) button.
	_cancel_btn = Button.new()
	_cancel_btn.name = "CancelButton"
	_cancel_btn.text = tr("ui.block.cancel")
	_cancel_btn.custom_minimum_size = Vector2(160, 0)
	var cancel_style := StyleBoxFlat.new()
	cancel_style.bg_color = Color(0, 0, 0, 0)
	cancel_style.border_width_left = 1
	cancel_style.border_width_top = 1
	cancel_style.border_width_right = 1
	cancel_style.border_width_bottom = 1
	cancel_style.border_color = COLOR_WHITE
	cancel_style.corner_radius_top_left = 6
	cancel_style.corner_radius_top_right = 6
	cancel_style.corner_radius_bottom_left = 6
	cancel_style.corner_radius_bottom_right = 6
	_cancel_btn.add_theme_stylebox_override("normal", cancel_style)
	_cancel_btn.add_theme_color_override("font_color", COLOR_WHITE)
	_cancel_btn.pressed.connect(_on_cancel_pressed)
	btn_row.add_child(_cancel_btn)


# ─── Public API ──────────────────────────────────────────────────────────────

## Open the block confirmation modal for the given user.
## @param uid       Target user's UID.
## @param username  Target user's display name (injected into heading/button).
func open(uid: String, username: String) -> void:
	_target_uid = uid
	_target_username = username

	# Inject username into heading and block button.
	_heading.text = tr("ui.block.title").format({"username": username})
	_block_btn.text = tr("ui.block.confirm_action").format({"username": username})

	visible = true
	# Ensure panel is centred on current viewport.
	await get_tree().process_frame
	var vp := get_viewport()
	if vp != null:
		var vp_size := vp.get_visible_rect().size
		var panel_size := _panel.size
		_panel.position = Vector2(
			(vp_size.x - panel_size.x) * 0.5,
			(vp_size.y - panel_size.y) * 0.5
		)


# ─── Button handlers ──────────────────────────────────────────────────────────

func _on_block_pressed() -> void:
	# Disable to prevent double-submission (T-05-D1).
	_block_btn.disabled = true

	var fc: Node = get_node_or_null("/root/FriendsClient")
	if fc != null and fc.has_method("block_user"):
		fc.call("block_user", _target_uid)
		# Connect to server confirmation signal (one-shot).
		# user_blocked is emitted only after the server confirms — see _on_fc_user_blocked.
		if fc.has_signal("user_blocked"):
			if not fc.user_blocked.is_connected(_on_fc_user_blocked):
				fc.user_blocked.connect(_on_fc_user_blocked, CONNECT_ONE_SHOT)

	# Close modal immediately; button stays disabled until server confirms (CR-06).
	visible = false


func _on_cancel_pressed() -> void:
	visible = false


func _on_fc_user_blocked(uid: String) -> void:
	# Server confirmed the block — now it is safe to emit and update UI.
	user_blocked.emit(uid)
	_block_btn.disabled = false
	if is_instance_valid(Toasts):
		Toasts.show("ui.block.toast_blocked", "error")
	# B3 fix: refresh blocks cache so NetworkManager._is_blocked_locally sees the new
	# block in the current session (without this, _blocks_cache stays stale until
	# next launch and the blocked peer's nameplate keeps rendering).
	var fc: Node = get_node_or_null("/root/FriendsClient")
	if fc != null and fc.has_method("get_blocks"):
		fc.call("get_blocks")
