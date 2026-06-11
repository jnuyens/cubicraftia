# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# report_modal.gd — 2-step Report flow modal (Surface B, Plan 05-08).
#
# CanvasLayer layer=20. Two-step flow:
#   Step 1: Category picker (5 exclusive CheckButton items).
#   Step 2: Free-text reason (max 500 chars) + optional chat context.
#
# Usage:
#   ReportModal.open(uid, username, surface, evidence)
#   surface: "player" | "chat_message" | "build"
#   evidence: Dictionary (optional, e.g. {messages: [...]})
#
# Security:
#   T-05-I1: No notification to reported user; auto-mute is local display filter only.
#   T-05-D1: Submit button enters loading state after first tap.
#   T-05-T1: reporter_uid set from auth.uid() in RLS; JWT used by FriendsClient.
#
# References:
#   05-UI-SPEC.md Surface B — Report Flow
#   05-08-PLAN.md Task 1

extends CanvasLayer

# ─── Colors ──────────────────────────────────────────────────────────────────

const COLOR_NAVY: Color        = Color(0.106, 0.173, 0.337, 0.60)
const COLOR_PANEL: Color       = Color(0.106, 0.173, 0.337, 0.92)
const COLOR_WHITE: Color       = Color(0.945, 0.941, 0.918, 1.0)
const COLOR_DESTRUCTIVE: Color = Color(0.839, 0.220, 0.157, 1.0)
const COLOR_PRIMARY: Color     = Color(0.106, 0.173, 0.337, 1.0)
const COLOR_CONTEXT_BG: Color  = Color(0.106, 0.173, 0.337, 0.50)

# ─── Category constants ───────────────────────────────────────────────────────

const CATEGORIES: Array = [
	{"key": "ui.report.category_harassment", "value": "harassment"},
	{"key": "ui.report.category_spam",       "value": "spam"},
	{"key": "ui.report.category_cheating",   "value": "cheating"},
	{"key": "ui.report.category_csam",       "value": "csam"},
	{"key": "ui.report.category_other",      "value": "other"},
]

const MAX_REASON_CHARS: int = 500
const CHAR_WARN_THRESHOLD: int = 50

# ─── Private state ────────────────────────────────────────────────────────────

var _target_uid: String = ""
var _target_username: String = ""
var _surface: String = "player"
var _evidence: Dictionary = {}
var _selected_category: String = ""
var _current_step: int = 1

# ─── Node refs ───────────────────────────────────────────────────────────────

var _overlay: ColorRect = null
var _panel: PanelContainer = null
var _content_vbox: VBoxContainer = null

# Step 1 nodes.
var _step1_vbox: VBoxContainer = null
var _step1_heading: Label = null
var _btn_group: ButtonGroup = null
var _category_buttons: Array = []
var _next_btn: Button = null
var _step1_cancel_btn: Button = null

# Step 2 nodes.
var _step2_vbox: VBoxContainer = null
var _step2_heading: Label = null
var _context_panel: PanelContainer = null
var _context_label: Label = null
var _reason_edit: TextEdit = null
var _char_counter: Label = null
var _submit_btn: Button = null
var _back_btn: Button = null

# ─── Lifecycle ────────────────────────────────────────────────────────────────

func _ready() -> void:
	layer = 20
	_build_ui()
	visible = false


func _build_ui() -> void:
	# Full-screen overlay (MOUSE_FILTER_STOP blocks outside clicks).
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

	# Outer VBoxContainer.
	_content_vbox = VBoxContainer.new()
	_content_vbox.add_theme_constant_override("separation", 16)
	_panel.add_child(_content_vbox)

	_build_step1()
	_build_step2()


func _build_step1() -> void:
	_step1_vbox = VBoxContainer.new()
	_step1_vbox.name = "Step1"
	_step1_vbox.add_theme_constant_override("separation", 8)
	_content_vbox.add_child(_step1_vbox)

	# Heading.
	_step1_heading = Label.new()
	_step1_heading.name = "Heading"
	_step1_heading.add_theme_color_override("font_color", COLOR_WHITE)
	_step1_heading.add_theme_font_size_override("font_size", 20)
	_step1_heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_step1_vbox.add_child(_step1_heading)

	# Subheading.
	var subheading := Label.new()
	subheading.text = tr("ui.report.subtitle_category")
	subheading.add_theme_color_override("font_color", Color(COLOR_WHITE.r, COLOR_WHITE.g, COLOR_WHITE.b, 0.70))
	subheading.add_theme_font_size_override("font_size", 14)
	_step1_vbox.add_child(subheading)

	# Button group for exclusive CheckButton selection.
	_btn_group = ButtonGroup.new()
	_btn_group.allow_unpress = false

	# Category rows.
	var cat_vbox := VBoxContainer.new()
	cat_vbox.add_theme_constant_override("separation", 8)
	_step1_vbox.add_child(cat_vbox)

	_category_buttons.clear()
	for cat in CATEGORIES:
		var row_btn := CheckButton.new()
		row_btn.text = tr(cat.key)
		row_btn.custom_minimum_size = Vector2(0, 48)
		row_btn.button_group = _btn_group
		row_btn.add_theme_color_override("font_color", COLOR_WHITE)
		row_btn.add_theme_font_size_override("font_size", 16)
		row_btn.pressed.connect(_on_category_selected.bind(cat.value))
		cat_vbox.add_child(row_btn)
		_category_buttons.append(row_btn)

	# "Next" button (primary style, full-width, disabled until selection).
	_next_btn = Button.new()
	_next_btn.name = "NextButton"
	_next_btn.text = tr("ui.report.next")
	_next_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_next_btn.disabled = true
	var next_style := StyleBoxFlat.new()
	next_style.bg_color = Color(0.239, 0.463, 0.824, 1.0)
	next_style.corner_radius_top_left = 6
	next_style.corner_radius_top_right = 6
	next_style.corner_radius_bottom_left = 6
	next_style.corner_radius_bottom_right = 6
	_next_btn.add_theme_stylebox_override("normal", next_style)
	_next_btn.add_theme_color_override("font_color", COLOR_WHITE)
	_next_btn.pressed.connect(_go_to_step2)
	_step1_vbox.add_child(_next_btn)

	# Cancel link-style button.
	_step1_cancel_btn = Button.new()
	_step1_cancel_btn.name = "CancelButton"
	_step1_cancel_btn.text = tr("ui.report.cancel")
	_step1_cancel_btn.flat = true
	_step1_cancel_btn.add_theme_color_override("font_color", Color(COLOR_WHITE.r, COLOR_WHITE.g, COLOR_WHITE.b, 0.60))
	_step1_cancel_btn.add_theme_font_size_override("font_size", 14)
	_step1_cancel_btn.pressed.connect(_on_cancel)
	_step1_vbox.add_child(_step1_cancel_btn)


func _build_step2() -> void:
	_step2_vbox = VBoxContainer.new()
	_step2_vbox.name = "Step2"
	_step2_vbox.add_theme_constant_override("separation", 8)
	_step2_vbox.visible = false
	_content_vbox.add_child(_step2_vbox)

	# Heading.
	_step2_heading = Label.new()
	_step2_heading.name = "Heading"
	_step2_heading.text = tr("ui.report.reason_placeholder")
	_step2_heading.add_theme_color_override("font_color", COLOR_WHITE)
	_step2_heading.add_theme_font_size_override("font_size", 20)
	_step2_heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_step2_vbox.add_child(_step2_heading)

	# Context panel (chat_message surface only — initially hidden).
	_context_panel = PanelContainer.new()
	_context_panel.name = "ContextPanel"
	_context_panel.visible = false
	_context_panel.custom_minimum_size = Vector2(0, 0)
	var ctx_style := StyleBoxFlat.new()
	ctx_style.bg_color = COLOR_CONTEXT_BG
	ctx_style.corner_radius_top_left = 6
	ctx_style.corner_radius_top_right = 6
	ctx_style.corner_radius_bottom_left = 6
	ctx_style.corner_radius_bottom_right = 6
	ctx_style.content_margin_left = 8.0
	ctx_style.content_margin_top = 8.0
	ctx_style.content_margin_right = 8.0
	ctx_style.content_margin_bottom = 8.0
	_context_panel.add_theme_stylebox_override("panel", ctx_style)
	_step2_vbox.add_child(_context_panel)

	var ctx_scroll := ScrollContainer.new()
	ctx_scroll.custom_minimum_size = Vector2(0, 0)
	ctx_scroll.custom_minimum_size.y = 0
	_context_panel.add_child(ctx_scroll)

	_context_label = Label.new()
	_context_label.name = "ContextLabel"
	_context_label.add_theme_color_override("font_color", Color(COLOR_WHITE.r, COLOR_WHITE.g, COLOR_WHITE.b, 0.70))
	_context_label.add_theme_font_size_override("font_size", 14)
	_context_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ctx_scroll.add_child(_context_label)

	# Free-text reason TextEdit.
	_reason_edit = TextEdit.new()
	_reason_edit.name = "ReasonEdit"
	_reason_edit.placeholder_text = "Describe what happened…"
	_reason_edit.custom_minimum_size = Vector2(0, 96)
	_reason_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_reason_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_reason_edit.add_theme_color_override("font_color", COLOR_WHITE)
	_reason_edit.text_changed.connect(_on_reason_changed)
	_step2_vbox.add_child(_reason_edit)

	# Character counter.
	_char_counter = Label.new()
	_char_counter.name = "CharCounter"
	_char_counter.text = "%d/%d" % [MAX_REASON_CHARS, MAX_REASON_CHARS]
	_char_counter.add_theme_color_override("font_color", Color(COLOR_WHITE.r, COLOR_WHITE.g, COLOR_WHITE.b, 0.50))
	_char_counter.add_theme_font_size_override("font_size", 14)
	_char_counter.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_step2_vbox.add_child(_char_counter)

	# Button row (Submit + Back).
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 8)
	_step2_vbox.add_child(btn_row)

	# Submit button.
	_submit_btn = Button.new()
	_submit_btn.name = "SubmitButton"
	_submit_btn.text = tr("ui.report.submit")
	_submit_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var submit_style := StyleBoxFlat.new()
	submit_style.bg_color = Color(0.239, 0.463, 0.824, 1.0)
	submit_style.corner_radius_top_left = 6
	submit_style.corner_radius_top_right = 6
	submit_style.corner_radius_bottom_left = 6
	submit_style.corner_radius_bottom_right = 6
	_submit_btn.add_theme_stylebox_override("normal", submit_style)
	_submit_btn.add_theme_color_override("font_color", COLOR_WHITE)
	_submit_btn.pressed.connect(_on_submit_pressed)
	btn_row.add_child(_submit_btn)

	# Back button.
	_back_btn = Button.new()
	_back_btn.name = "BackButton"
	_back_btn.text = tr("ui.report.back")
	_back_btn.custom_minimum_size = Vector2(120, 0)
	var back_style := StyleBoxFlat.new()
	back_style.bg_color = Color(0, 0, 0, 0)
	back_style.border_width_left = 1
	back_style.border_width_top = 1
	back_style.border_width_right = 1
	back_style.border_width_bottom = 1
	back_style.border_color = COLOR_WHITE
	back_style.corner_radius_top_left = 6
	back_style.corner_radius_top_right = 6
	back_style.corner_radius_bottom_left = 6
	back_style.corner_radius_bottom_right = 6
	_back_btn.add_theme_stylebox_override("normal", back_style)
	_back_btn.add_theme_color_override("font_color", COLOR_WHITE)
	_back_btn.pressed.connect(_go_to_step1)
	btn_row.add_child(_back_btn)


# ─── Public API ──────────────────────────────────────────────────────────────

## Open the report modal.
## @param uid      Target user's UID.
## @param username Target user's display name.
## @param surface  "player" | "chat_message" | "build"
## @param evidence Optional context dict (e.g. {messages: [...]}).
func open(uid: String, username: String, surface: String, evidence: Dictionary = {}) -> void:
	_target_uid = uid
	_target_username = username
	_surface = surface
	_evidence = evidence
	_selected_category = ""

	# Reset step 1.
	if _surface == "chat_message":
		_step1_heading.text = tr("ui.report.title_message")
	else:
		_step1_heading.text = tr("ui.report.title_player").format({"username": username})

	# Deselect all category buttons.
	for btn in _category_buttons:
		(btn as CheckButton).set_pressed_no_signal(false)
	_next_btn.disabled = true

	# Reset step 2.
	if _reason_edit != null:
		_reason_edit.text = ""
	_update_char_counter(MAX_REASON_CHARS)

	# Show chat context if applicable.
	_context_panel.visible = (_surface == "chat_message" and not _evidence.is_empty())
	if _context_panel.visible:
		var messages: Variant = _evidence.get("messages", [])
		if messages is Array:
			var lines: PackedStringArray = PackedStringArray()
			for m in messages:
				if m is Dictionary:
					var uname: String = (m as Dictionary).get("username", "")
					var txt: String = (m as Dictionary).get("text", "")
					lines.append(uname + ": " + txt)
			_context_label.text = "\n".join(lines)

	# Start at step 1.
	_go_to_step1()

	visible = true
	await get_tree().process_frame
	_centre_panel()


# ─── Step navigation ──────────────────────────────────────────────────────────

func _go_to_step1() -> void:
	_current_step = 1
	_step1_vbox.visible = true
	_step2_vbox.visible = false


func _go_to_step2() -> void:
	if _selected_category.is_empty():
		return
	_current_step = 2
	_step1_vbox.visible = false
	_step2_vbox.visible = true
	_centre_panel()


# ─── Signal handlers ──────────────────────────────────────────────────────────

func _on_category_selected(value: String) -> void:
	_selected_category = value
	_next_btn.disabled = false


func _on_reason_changed() -> void:
	var text: String = _reason_edit.text
	if text.length() > MAX_REASON_CHARS:
		# Truncate to enforce the limit.
		_reason_edit.text = text.left(MAX_REASON_CHARS)
		_reason_edit.set_caret_column(MAX_REASON_CHARS)
	var remaining: int = MAX_REASON_CHARS - min(_reason_edit.text.length(), MAX_REASON_CHARS)
	_update_char_counter(remaining)


func _update_char_counter(remaining: int) -> void:
	_char_counter.text = tr("ui.report.char_counter").format({"n": str(remaining)})
	if remaining < CHAR_WARN_THRESHOLD:
		_char_counter.add_theme_color_override("font_color", COLOR_DESTRUCTIVE)
	else:
		_char_counter.add_theme_color_override("font_color",
			Color(COLOR_WHITE.r, COLOR_WHITE.g, COLOR_WHITE.b, 0.50))


func _on_submit_pressed() -> void:
	# Prevent double-submission (T-05-D1).
	_submit_btn.disabled = true

	var reason: String = _reason_edit.text.strip_edges()
	var fc: Node = get_node_or_null("/root/FriendsClient")
	if fc != null and fc.has_method("submit_report"):
		fc.call("submit_report", _target_uid, _surface, _selected_category, reason, _evidence)
		if fc.has_signal("report_submitted"):
			if not fc.report_submitted.is_connected(_on_report_submitted):
				fc.report_submitted.connect(_on_report_submitted, CONNECT_ONE_SHOT)

	# Auto-mute: local display filter for reported user — not a real block.
	_auto_mute_reported_user()

	visible = false
	_submit_btn.disabled = false

	if is_instance_valid(Toasts):
		Toasts.show("ui.report.toast_submitted", "info")


func _on_report_submitted() -> void:
	# Server confirmed — no additional client action needed.
	pass


func _on_cancel() -> void:
	visible = false


# ─── Auto-mute ───────────────────────────────────────────────────────────────

## Locally suppress messages from the reported user for this session.
## This is a display filter, not a real block — T-05-I1.
func _auto_mute_reported_user() -> void:
	if _target_uid.is_empty():
		return
	# Mute in NetworkManager first (filters at RPC delivery layer — WR-05).
	var nm: Node = get_node_or_null("/root/NetworkManager")
	if nm != null and nm.has_method("mute_session_uid"):
		nm.call("mute_session_uid", _target_uid)
	# Also mute in ChatOverlay for the display layer.
	if is_inside_tree():
		var chat: Node = get_tree().get_root().find_child("ChatOverlay", true, false)
		if chat == null:
			var group_nodes := get_tree().get_nodes_in_group("chat_overlay")
			if not group_nodes.is_empty():
				chat = group_nodes[0]
		if chat != null and chat.has_method("mute_by_uid"):
			chat.call("mute_by_uid", _target_uid)


# ─── Helpers ──────────────────────────────────────────────────────────────────

func _centre_panel() -> void:
	var vp := get_viewport()
	if vp == null:
		return
	var vp_size := vp.get_visible_rect().size
	var panel_size := _panel.size
	_panel.position = Vector2(
		(vp_size.x - panel_size.x) * 0.5,
		(vp_size.y - panel_size.y) * 0.5
	)
