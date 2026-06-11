# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# world_select_screen.gd — World Select / Home Screen controller (Surface 3 + 4).
#
# Shown after every sign-in (or after "Continue offline" from title_scene).
# Reads world list from user://worlds/index.cfg on _ready(), renders up to 5 world
# cards, and provides a "New world" modal (Surface 4) inline.
#
# Index schema (user://worlds/index.cfg):
#   Each section is a world_id string. Keys per section:
#     name            String  — display name (24-char max, profanity-validated)
#     seed            int     — procedural generation seed
#     mode            String  — "survival" or "creative"
#     created_unix    int     — Unix timestamp of creation
#     last_played_unix int    — Unix timestamp of last play session
#
# Security:
#   T-06-S2: world name validated by ProfanityFilter.filter_reject() on the client (UI
#            shows error label); WorldSave.create_world() validates again server-side
#            (defence in depth). Error label never echoes the rejected string.
#   T-06-D1-thumbnail: at most 5 worlds → at most 125 KB of thumbnail storage.
#
# Telemetry events: WORLD_SELECT_SHOWN (on _ready), WORLD_CREATED (on create), WORLD_LOADED (on open).
#
# References:
#   06-UI-SPEC.md Surface 3 + Surface 4
#   06-CONTEXT.md Area 4
#   06-05-PLAN.md Task 2

class_name WorldSelectScreen
extends CanvasLayer

# ─── Constants ────────────────────────────────────────────────────────────────

## Path to the world index ConfigFile.
const _INDEX_PATH: String = "user://worlds/index.cfg"
## Absolute path used for DirAccess checks (ConfigFile uses user:// directly).
const _WORLDS_DIR: String = "user://worlds"
## Maximum number of worlds permitted (hard cap v1).
const MAX_WORLDS: int = 5
## Minimum visible height (px) for the world-card list. Prevents the EXPAND_FILL
## scroll from collapsing to 0 px (which hid all world cards and made the
## MAX_WORLDS cap a dead-end). Regression-guarded by test_world_select_list.gd.
const _WORLD_LIST_MIN_HEIGHT: float = 260.0
## Long-press duration in seconds before context menu appears.
const LONG_PRESS_DURATION: float = 0.5
## Hover tween duration (0.22s — standard panel transition token).
const HOVER_TWEEN_S: float = 0.22
## World card minimum height in pixels.
const CARD_MIN_HEIGHT: int = 96

## Colours (verbatim from UI-SPEC §Color).
const COLOR_NAVY:        Color = Color(0.106, 0.173, 0.337, 0.92)
const COLOR_NAVY_CARD:   Color = Color(0.106, 0.173, 0.337, 0.85)
const COLOR_NAVY_HOVER:  Color = Color(0.150, 0.220, 0.400, 0.90)
const COLOR_WHITE:       Color = Color(0.945, 0.941, 0.918, 1.0)
const COLOR_WHITE_DIM:   Color = Color(0.945, 0.941, 0.918, 0.6)
const COLOR_DESTRUCTIVE: Color = Color(0.839, 0.220, 0.157, 1.0)
const COLOR_BADGE_NAVY:  Color = Color(0.106, 0.173, 0.337, 1.0)
const COLOR_CREATIVE:    Color = Color(0.239, 0.710, 0.376, 1.0)
const COLOR_SURVIVAL:    Color = Color(0.910, 0.537, 0.047, 1.0)

# ─── Exported properties ──────────────────────────────────────────────────────

## When true, the "Friends" button is hidden (offline / guest mode).
@export var offline_mode: bool = false

# ─── Node refs ────────────────────────────────────────────────────────────────

var _panel: PanelContainer = null
var _header_hbox: HBoxContainer = null
var _title_label: Label = null
var _friends_button: Button = null
var _settings_button: Button = null
var _new_world_button: Button = null
var _scroll_container: ScrollContainer = null
var _world_list_container: VBoxContainer = null
var _empty_state: VBoxContainer = null

## New world modal overlay elements.
var _modal_overlay: ColorRect = null
var _modal_panel: PanelContainer = null
var _modal_name_field: LineEdit = null
var _modal_name_counter: Label = null
var _modal_name_error: Label = null
var _modal_survival_button: Button = null
var _modal_creative_button: Button = null
var _modal_create_button: Button = null

## Delete confirmation modal.
var _delete_overlay: ColorRect = null
var _delete_panel: PanelContainer = null
var _delete_world_id: String = ""

## Rename dialog (AcceptDialog reuse).
var _rename_dialog: AcceptDialog = null
var _rename_field: LineEdit = null
var _rename_world_id: String = ""

## Long-press timer (one shared instance).
var _long_press_timer: Timer = null
var _long_press_world_id: String = ""

# ─── State ────────────────────────────────────────────────────────────────────

## Cached list of world Dictionaries loaded from index.cfg.
var _worlds: Array[Dictionary] = []
## Currently selected mode in the new-world modal.
var _selected_mode: String = "survival"

# ─── Lifecycle ────────────────────────────────────────────────────────────────

func _ready() -> void:
	OnboardingTelemetry.log(OnboardingTelemetry.WORLD_SELECT_SHOWN)
	_build_ui()
	_hide_friends_button_if_offline()
	_rebuild_world_list()

	# Escape closes any open modal.
	set_process_unhandled_key_input(true)


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if _modal_overlay != null and _modal_overlay.visible:
			_hide_new_world_modal()
			get_viewport().set_input_as_handled()
		elif _delete_overlay != null and _delete_overlay.visible:
			_delete_overlay.visible = false
			_delete_panel.visible = false
			get_viewport().set_input_as_handled()
	# Enter / Return submits the new-world modal even when the LineEdit
	# text_submitted signal doesn't fire (focus drift, IME, etc.).
	elif _modal_overlay != null and _modal_overlay.visible and event is InputEventKey:
		var key_event := event as InputEventKey
		if key_event.pressed and not key_event.echo and key_event.keycode in [KEY_ENTER, KEY_KP_ENTER]:
			_on_create_world_pressed()
			get_viewport().set_input_as_handled()

# ─── UI Construction ──────────────────────────────────────────────────────────

func _build_ui() -> void:
	layer = 0

	# Background TextureRect — same title_bg pan shader as title_scene for visual continuity.
	var bg_rect := TextureRect.new()
	bg_rect.name = "BgRect"
	bg_rect.layout_mode = 1
	bg_rect.anchors_preset = 15   # PRESET_FULL_RECT
	bg_rect.anchor_right = 1.0
	bg_rect.anchor_bottom = 1.0
	bg_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	# COVERED, not TILE: the non-tileable hero image was tiling vertically and showing a seam
	# (QA: "band" at top/bottom). Cover fills the full rect from a single copy, no seam.
	bg_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Use the same hero vista as title_scene for visual continuity between title and world-select.
	var bg_tex_path := "res://assets/textures/icons/title_bg.png"
	if ResourceLoader.exists(bg_tex_path):
		bg_rect.texture = load(bg_tex_path)
	var shader_path := "res://src/shaders/title_bg_pan.gdshader"
	if ResourceLoader.exists(shader_path):
		var shader: Shader = load(shader_path)
		var mat := ShaderMaterial.new()
		mat.shader = shader
		mat.set_shader_parameter("uv_offset", Vector2(0.0, 0.0))
		bg_rect.material = mat
	add_child(bg_rect)

	# Navy overlay for readability.
	var overlay := ColorRect.new()
	overlay.name = "Overlay"
	overlay.layout_mode = 1
	overlay.anchors_preset = 15
	overlay.anchor_right = 1.0
	overlay.anchor_bottom = 1.0
	overlay.color = Color(0.106, 0.173, 0.337, 0.72)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(overlay)

	# Main panel: 640px wide, centred, full height with 32px top/bottom margin.
	var margin_container := CenterContainer.new()
	margin_container.name = "MarginContainer"
	margin_container.layout_mode = 1
	margin_container.anchor_right = 1.0
	margin_container.anchor_bottom = 1.0
	margin_container.anchors_preset = 15
	add_child(margin_container)

	_panel = PanelContainer.new()
	_panel.name = "Panel"
	_panel.custom_minimum_size = Vector2(640, 0)
	_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = COLOR_NAVY
	panel_style.corner_radius_top_left = 16
	panel_style.corner_radius_top_right = 16
	panel_style.corner_radius_bottom_left = 16
	panel_style.corner_radius_bottom_right = 16
	panel_style.content_margin_left = 16.0
	panel_style.content_margin_top = 16.0
	panel_style.content_margin_right = 16.0
	panel_style.content_margin_bottom = 16.0
	_panel.add_theme_stylebox_override("panel", panel_style)
	margin_container.add_child(_panel)

	var inner_vbox := VBoxContainer.new()
	inner_vbox.name = "InnerVBox"
	inner_vbox.add_theme_constant_override("separation", 16)
	_panel.add_child(inner_vbox)

	# Header bar.
	_header_hbox = HBoxContainer.new()
	_header_hbox.name = "HeaderHBox"
	_header_hbox.add_theme_constant_override("separation", 8)
	_header_hbox.custom_minimum_size = Vector2(0, 48)
	inner_vbox.add_child(_header_hbox)

	_title_label = Label.new()
	_title_label.name = "TitleLabel"
	_title_label.text = tr("ui.world_select.title")
	_title_label.add_theme_font_size_override("font_size", 20)
	_title_label.add_theme_color_override("font_color", COLOR_WHITE)
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_header_hbox.add_child(_title_label)

	_friends_button = Button.new()
	_friends_button.name = "FriendsButton"
	_friends_button.text = tr("ui.world_select.friends")
	_friends_button.custom_minimum_size = Vector2(120, 0)
	_friends_button.pressed.connect(_on_friends_pressed)
	_header_hbox.add_child(_friends_button)

	_settings_button = Button.new()
	_settings_button.name = "SettingsButton"
	_settings_button.text = tr("ui.world_select.settings_tooltip")
	_settings_button.tooltip_text = tr("ui.world_select.settings_tooltip")
	_settings_button.custom_minimum_size = Vector2(48, 48)
	_settings_button.pressed.connect(_on_settings_pressed)
	_header_hbox.add_child(_settings_button)

	# New world button (primary CTA, full-width).
	_new_world_button = Button.new()
	_new_world_button.name = "NewWorldButton"
	_new_world_button.text = tr("ui.world_select.new_world")
	_new_world_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_new_world_button.custom_minimum_size = Vector2(0, 48)
	_new_world_button.pressed.connect(_on_new_world_pressed)
	inner_vbox.add_child(_new_world_button)

	# Empty state (hidden initially).
	_empty_state = VBoxContainer.new()
	_empty_state.name = "EmptyState"
	_empty_state.alignment = BoxContainer.ALIGNMENT_CENTER
	_empty_state.visible = false
	_empty_state.add_theme_constant_override("separation", 8)
	inner_vbox.add_child(_empty_state)

	var empty_heading := Label.new()
	empty_heading.text = tr("ui.world_select.empty_heading")
	empty_heading.add_theme_font_size_override("font_size", 20)
	empty_heading.add_theme_color_override("font_color", COLOR_WHITE)
	empty_heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty_state.add_child(empty_heading)

	var empty_body := Label.new()
	empty_body.text = tr("ui.world_select.empty_body")
	empty_body.add_theme_font_size_override("font_size", 16)
	empty_body.add_theme_color_override("font_color", COLOR_WHITE_DIM)
	empty_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	empty_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_empty_state.add_child(empty_body)

	# ScrollContainer for world cards.
	_scroll_container = ScrollContainer.new()
	_scroll_container.name = "ScrollContainer"
	_scroll_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# Guarantee a visible height for the world list. Without this the panel sizes
	# to content and the EXPAND_FILL scroll collapses to 0 px — world cards become
	# invisible, so once the MAX_WORLDS cap disables "New world" the screen is a
	# dead-end (no card to select/delete). MIN keeps the list reachable. See
	# tests/unit/test_world_select_list.gd (regression guard).
	_scroll_container.custom_minimum_size = Vector2(0, _WORLD_LIST_MIN_HEIGHT)
	inner_vbox.add_child(_scroll_container)

	_world_list_container = VBoxContainer.new()
	_world_list_container.name = "WorldListContainer"
	_world_list_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_world_list_container.add_theme_constant_override("separation", 8)
	_scroll_container.add_child(_world_list_container)

	# Long-press timer (shared for all cards).
	_long_press_timer = Timer.new()
	_long_press_timer.name = "LongPressTimer"
	_long_press_timer.wait_time = LONG_PRESS_DURATION
	_long_press_timer.one_shot = true
	_long_press_timer.timeout.connect(_on_long_press_timeout)
	add_child(_long_press_timer)

	# Build new-world modal (hidden).
	_build_new_world_modal()

	# Build delete confirmation modal (hidden).
	_build_delete_modal()


func _build_new_world_modal() -> void:
	# Full-screen semi-transparent overlay.
	_modal_overlay = ColorRect.new()
	_modal_overlay.name = "ModalOverlay"
	_modal_overlay.layout_mode = 1
	_modal_overlay.anchors_preset = 15
	_modal_overlay.anchor_right = 1.0
	_modal_overlay.anchor_bottom = 1.0
	_modal_overlay.color = Color(0.106, 0.173, 0.337, 0.60)
	_modal_overlay.mouse_filter = Control.MOUSE_FILTER_PASS
	_modal_overlay.visible = false
	_modal_overlay.gui_input.connect(_on_modal_overlay_input)
	add_child(_modal_overlay)

	# Centred modal panel (400px wide, auto-height).
	var modal_center := CenterContainer.new()
	modal_center.name = "ModalCenter"
	modal_center.layout_mode = 1
	modal_center.anchors_preset = 15
	modal_center.anchor_right = 1.0
	modal_center.anchor_bottom = 1.0
	modal_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_modal_overlay.add_child(modal_center)

	_modal_panel = PanelContainer.new()
	_modal_panel.name = "ModalPanel"
	# Cap modal height at 90% of viewport so the Create button is always reachable
	# even on short windows. ScrollContainer inside handles overflow.
	var viewport_h: float = get_viewport().get_visible_rect().size.y
	_modal_panel.custom_minimum_size = Vector2(400, 0)
	_modal_panel.set_meta("max_h", maxf(540.0, viewport_h * 0.90))
	_modal_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var modal_style := StyleBoxFlat.new()
	modal_style.bg_color = COLOR_NAVY
	modal_style.corner_radius_top_left = 16
	modal_style.corner_radius_top_right = 16
	modal_style.corner_radius_bottom_left = 16
	modal_style.corner_radius_bottom_right = 16
	modal_style.content_margin_left = 16.0
	modal_style.content_margin_top = 16.0
	modal_style.content_margin_right = 16.0
	modal_style.content_margin_bottom = 16.0
	_modal_panel.add_theme_stylebox_override("panel", modal_style)
	modal_center.add_child(_modal_panel)

	# ScrollContainer keeps Create button reachable when modal content > viewport height.
	var scroll := ScrollContainer.new()
	scroll.name = "ModalScroll"
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, minf(540.0, viewport_h * 0.85))
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_modal_panel.add_child(scroll)

	var modal_vbox := VBoxContainer.new()
	modal_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	modal_vbox.add_theme_constant_override("separation", 12)
	scroll.add_child(modal_vbox)

	# Modal title.
	var modal_title := Label.new()
	modal_title.text = tr("ui.new_world.title")
	modal_title.add_theme_font_size_override("font_size", 20)
	modal_title.add_theme_color_override("font_color", COLOR_WHITE)
	modal_vbox.add_child(modal_title)

	# World name label + field.
	var name_label := Label.new()
	name_label.text = tr("ui.new_world.name_label")
	name_label.add_theme_font_size_override("font_size", 14)
	name_label.add_theme_color_override("font_color", COLOR_WHITE)
	modal_vbox.add_child(name_label)

	_modal_name_field = LineEdit.new()
	_modal_name_field.placeholder_text = tr("ui.new_world.name_placeholder")
	_modal_name_field.text = tr("ui.new_world.name_placeholder")
	_modal_name_field.max_length = 24
	_modal_name_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_modal_name_field.custom_minimum_size = Vector2(0, 40)
	_modal_name_field.text_changed.connect(_on_modal_name_changed)
	# Enter submits the modal — saves the user from scrolling to find Create on short windows.
	_modal_name_field.text_submitted.connect(_on_modal_field_submitted)
	modal_vbox.add_child(_modal_name_field)

	# Character counter.
	_modal_name_counter = Label.new()
	_modal_name_counter.text = "%d/24" % _modal_name_field.text.length()
	_modal_name_counter.add_theme_font_size_override("font_size", 14)
	_modal_name_counter.add_theme_color_override("font_color",
		Color(COLOR_WHITE.r, COLOR_WHITE.g, COLOR_WHITE.b, 0.50))
	_modal_name_counter.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	modal_vbox.add_child(_modal_name_counter)

	# Profanity error label (hidden initially).
	_modal_name_error = Label.new()
	_modal_name_error.text = tr("ui.new_world.name_error_profanity")
	_modal_name_error.add_theme_font_size_override("font_size", 14)
	_modal_name_error.add_theme_color_override("font_color", COLOR_DESTRUCTIVE)
	_modal_name_error.visible = false
	modal_vbox.add_child(_modal_name_error)

	# Seed input removed (v1.1 QA): a youth game should not ask for a procedural seed.
	# Every new world silently uses a fresh random seed (see _on_modal_create_pressed).

	# Mode toggle.
	var mode_label := Label.new()
	mode_label.text = tr("ui.new_world.mode_label")
	mode_label.add_theme_font_size_override("font_size", 14)
	mode_label.add_theme_color_override("font_color", COLOR_WHITE)
	modal_vbox.add_child(mode_label)

	var mode_hbox := HBoxContainer.new()
	mode_hbox.add_theme_constant_override("separation", 4)
	modal_vbox.add_child(mode_hbox)

	_modal_survival_button = Button.new()
	_modal_survival_button.text = tr("ui.new_world.mode_survival")
	_modal_survival_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_modal_survival_button.pressed.connect(_on_mode_survival_pressed)
	mode_hbox.add_child(_modal_survival_button)

	_modal_creative_button = Button.new()
	_modal_creative_button.text = tr("ui.new_world.mode_creative")
	_modal_creative_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_modal_creative_button.pressed.connect(_on_mode_creative_pressed)
	mode_hbox.add_child(_modal_creative_button)

	_update_mode_buttons()

	# Create + Cancel buttons.
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 8)
	modal_vbox.add_child(btn_row)

	_modal_create_button = Button.new()
	_modal_create_button.text = tr("ui.new_world.create")
	_modal_create_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_modal_create_button.pressed.connect(_on_create_world_pressed)
	btn_row.add_child(_modal_create_button)

	var cancel_button := Button.new()
	cancel_button.text = tr("ui.new_world.cancel")
	cancel_button.custom_minimum_size = Vector2(120, 0)
	cancel_button.pressed.connect(_hide_new_world_modal)
	btn_row.add_child(cancel_button)


func _build_delete_modal() -> void:
	_delete_overlay = ColorRect.new()
	_delete_overlay.name = "DeleteOverlay"
	_delete_overlay.layout_mode = 1
	_delete_overlay.anchors_preset = 15
	_delete_overlay.anchor_right = 1.0
	_delete_overlay.anchor_bottom = 1.0
	_delete_overlay.color = Color(0.106, 0.173, 0.337, 0.60)
	_delete_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_delete_overlay.visible = false
	add_child(_delete_overlay)

	var center := CenterContainer.new()
	center.layout_mode = 1
	center.anchors_preset = 15
	center.anchor_right = 1.0
	center.anchor_bottom = 1.0
	_delete_overlay.add_child(center)

	_delete_panel = PanelContainer.new()
	_delete_panel.name = "DeletePanel"
	_delete_panel.custom_minimum_size = Vector2(400, 0)
	var del_style := StyleBoxFlat.new()
	del_style.bg_color = COLOR_NAVY
	del_style.corner_radius_top_left = 16
	del_style.corner_radius_top_right = 16
	del_style.corner_radius_bottom_left = 16
	del_style.corner_radius_bottom_right = 16
	del_style.content_margin_left = 16.0
	del_style.content_margin_top = 16.0
	del_style.content_margin_right = 16.0
	del_style.content_margin_bottom = 16.0
	_delete_panel.add_theme_stylebox_override("panel", del_style)
	center.add_child(_delete_panel)

	var del_vbox := VBoxContainer.new()
	del_vbox.add_theme_constant_override("separation", 16)
	_delete_panel.add_child(del_vbox)

	var del_title := Label.new()
	del_title.text = tr("ui.world_select.delete_title")
	del_title.add_theme_font_size_override("font_size", 20)
	del_title.add_theme_color_override("font_color", COLOR_WHITE)
	del_vbox.add_child(del_title)

	var del_body := Label.new()
	del_body.text = tr("ui.world_select.delete_body")
	del_body.add_theme_font_size_override("font_size", 16)
	del_body.add_theme_color_override("font_color", COLOR_WHITE_DIM)
	del_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	del_vbox.add_child(del_body)

	var del_btn_row := HBoxContainer.new()
	del_btn_row.add_theme_constant_override("separation", 8)
	del_vbox.add_child(del_btn_row)

	var confirm_btn := Button.new()
	confirm_btn.name = "ConfirmDeleteButton"
	confirm_btn.text = tr("ui.world_select.delete_confirm")
	confirm_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var dest_style := StyleBoxFlat.new()
	dest_style.bg_color = COLOR_DESTRUCTIVE
	dest_style.corner_radius_top_left = 8
	dest_style.corner_radius_top_right = 8
	dest_style.corner_radius_bottom_left = 8
	dest_style.corner_radius_bottom_right = 8
	dest_style.content_margin_left = 16.0
	dest_style.content_margin_top = 10.0
	dest_style.content_margin_right = 16.0
	dest_style.content_margin_bottom = 10.0
	confirm_btn.add_theme_stylebox_override("normal", dest_style)
	confirm_btn.pressed.connect(_on_delete_confirmed)
	del_btn_row.add_child(confirm_btn)

	var cancel_del_btn := Button.new()
	cancel_del_btn.text = tr("ui.world_select.delete_cancel")
	cancel_del_btn.custom_minimum_size = Vector2(120, 0)
	cancel_del_btn.pressed.connect(func(): _delete_overlay.visible = false)
	del_btn_row.add_child(cancel_del_btn)

# ─── World list ───────────────────────────────────────────────────────────────

## Rebuild the world list from user://worlds/index.cfg. Handles missing dir gracefully.
func _rebuild_world_list() -> void:
	# Clear old cards.
	for child in _world_list_container.get_children():
		child.queue_free()
	_worlds.clear()

	# Guard: worlds directory may not exist yet (first launch).
	if not DirAccess.dir_exists_absolute(
			ProjectSettings.globalize_path(_WORLDS_DIR)):
		_show_empty_state(true)
		return

	var cfg := ConfigFile.new()
	var load_err := cfg.load(_INDEX_PATH)
	if load_err != OK:
		# Index doesn't exist yet — show empty state without error.
		_show_empty_state(true)
		return

	var sections := cfg.get_sections()
	if sections.is_empty():
		_show_empty_state(true)
		return

	_show_empty_state(false)

	for world_id: String in sections:
		var entry := {
			"world_id":       world_id,
			"name":           str(cfg.get_value(world_id, "name", world_id)),
			"seed":           int(cfg.get_value(world_id, "seed", 0)),
			"mode":           str(cfg.get_value(world_id, "mode", "survival")),
			"created_unix":   int(cfg.get_value(world_id, "created_unix", 0)),
			"last_played_unix": int(cfg.get_value(world_id, "last_played_unix", 0)),
		}
		_worlds.append(entry)
		var card := _build_world_card(entry)
		_world_list_container.add_child(card)

	# Cap enforcement: disable New World button when at the limit.
	if _worlds.size() >= MAX_WORLDS:
		_new_world_button.disabled = true
		_new_world_button.tooltip_text = tr("ui.world_select.worlds_cap_error")
	else:
		_new_world_button.disabled = false
		_new_world_button.tooltip_text = ""


func _show_empty_state(show: bool) -> void:
	_empty_state.visible = show
	_scroll_container.visible = not show


## Build a single world card PanelContainer for the given world entry dictionary.
func _build_world_card(entry: Dictionary) -> PanelContainer:
	var world_id: String = entry.get("world_id", "")
	var world_name: String = entry.get("name", world_id)
	var mode: String = entry.get("mode", "survival")
	var last_played: int = entry.get("last_played_unix", 0)

	var card := PanelContainer.new()
	card.name = "Card_%s" % world_id
	card.custom_minimum_size = Vector2(0, CARD_MIN_HEIGHT)

	# StyleBox: world card navy.
	var card_style := StyleBoxFlat.new()
	card_style.bg_color = COLOR_NAVY_CARD
	card_style.border_width_left = 1
	card_style.border_width_top = 1
	card_style.border_width_right = 1
	card_style.border_width_bottom = 1
	card_style.border_color = Color(0.945, 0.941, 0.918, 0.15)
	card_style.corner_radius_top_left = 12
	card_style.corner_radius_top_right = 12
	card_style.corner_radius_bottom_left = 12
	card_style.corner_radius_bottom_right = 12
	card_style.content_margin_left = 16.0
	card_style.content_margin_top = 12.0
	card_style.content_margin_right = 16.0
	card_style.content_margin_bottom = 12.0
	card.add_theme_stylebox_override("panel", card_style)

	# Hover effect via mouse_entered / mouse_exited.
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.mouse_entered.connect(_on_card_hover_enter.bind(card, card_style))
	card.mouse_exited.connect(_on_card_hover_exit.bind(card, card_style))

	# Inner HBox: thumbnail | info vbox | play button.
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 12)
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_child(hbox)

	# Thumbnail (128×72 display, scaled from 256×144 source).
	var thumb := TextureRect.new()
	thumb.name = "Thumbnail"
	thumb.custom_minimum_size = Vector2(128, 72)
	thumb.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	thumb.texture = _load_thumbnail(world_id)
	thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(thumb)

	# Centre column: name + last-played + mode badge.
	var info_vbox := VBoxContainer.new()
	info_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_vbox.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	info_vbox.add_theme_constant_override("separation", 4)
	hbox.add_child(info_vbox)

	var name_label := Label.new()
	# Truncate at 24 chars with ellipsis.
	var display_name: String = world_name if world_name.length() <= 24 else world_name.substr(0, 23) + "…"
	name_label.text = display_name
	name_label.add_theme_font_size_override("font_size", 16)
	name_label.add_theme_color_override("font_color", COLOR_WHITE)
	name_label.clip_text = true
	info_vbox.add_child(name_label)

	# Last-played + mode badge row.
	var meta_hbox := HBoxContainer.new()
	meta_hbox.add_theme_constant_override("separation", 8)
	info_vbox.add_child(meta_hbox)

	var date_label := Label.new()
	date_label.text = _relative_time(last_played)
	date_label.add_theme_font_size_override("font_size", 14)
	date_label.add_theme_color_override("font_color", COLOR_WHITE_DIM)
	meta_hbox.add_child(date_label)

	# Mode badge PanelContainer.
	var badge_panel := PanelContainer.new()
	var badge_style := StyleBoxFlat.new()
	badge_style.corner_radius_top_left = 12
	badge_style.corner_radius_top_right = 12
	badge_style.corner_radius_bottom_left = 12
	badge_style.corner_radius_bottom_right = 12
	badge_style.content_margin_left = 6.0
	badge_style.content_margin_top = 3.0
	badge_style.content_margin_right = 6.0
	badge_style.content_margin_bottom = 3.0
	badge_style.border_width_left = 0
	badge_style.border_width_top = 0
	badge_style.border_width_right = 0
	badge_style.border_width_bottom = 0
	if mode == "creative":
		badge_style.bg_color = COLOR_CREATIVE
		var badge_label := Label.new()
		badge_label.text = tr("ui.world_select.mode_creative")
		badge_label.add_theme_font_size_override("font_size", 14)
		badge_label.add_theme_color_override("font_color", COLOR_BADGE_NAVY)
		badge_panel.add_theme_stylebox_override("panel", badge_style)
		badge_panel.add_child(badge_label)
	else:
		badge_style.bg_color = COLOR_SURVIVAL
		var badge_label := Label.new()
		badge_label.text = tr("ui.world_select.mode_survival")
		badge_label.add_theme_font_size_override("font_size", 14)
		badge_label.add_theme_color_override("font_color", COLOR_BADGE_NAVY)
		badge_panel.add_theme_stylebox_override("panel", badge_style)
		badge_panel.add_child(badge_label)
	badge_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	meta_hbox.add_child(badge_panel)

	# Play button (right side).
	var play_button := Button.new()
	play_button.name = "PlayButton"
	play_button.text = tr("ui.world_select.play")
	play_button.custom_minimum_size = Vector2(80, 40)
	play_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	play_button.pressed.connect(_on_play_pressed.bind(entry))
	hbox.add_child(play_button)

	# Long-press / right-click for context menu.
	card.gui_input.connect(_on_card_input.bind(world_id))

	return card


## Compute relative time string for a Unix timestamp.
func _relative_time(last_played_unix: int) -> String:
	if last_played_unix == 0:
		return tr("ui.world_select.last_played_today")
	var delta: int = int(Time.get_unix_time_from_system()) - last_played_unix
	if delta < 86400:
		return tr("ui.world_select.last_played_today")
	elif delta < 172800:
		return tr("ui.world_select.last_played_yesterday")
	else:
		var days: int = int(delta / 86400)
		return tr("ui.world_select.last_played_n_days_ago").replace("{n}", str(days))


## Load world thumbnail or fall back to placeholder.
func _load_thumbnail(p_world_id: String) -> Texture2D:
	var thumb_path := "user://worlds/%s/thumbnail.jpg" % p_world_id
	var abs_path := ProjectSettings.globalize_path(thumb_path)
	if FileAccess.file_exists(abs_path):
		var img := Image.load_from_file(abs_path)
		if img != null and not img.is_empty():
			return ImageTexture.create_from_image(img)
	# Fall back to placeholder texture.
	var placeholder_path := "res://assets/textures/ui/world_thumb_placeholder.png"
	if ResourceLoader.exists(placeholder_path):
		return load(placeholder_path)
	return null

# ─── World index helpers ──────────────────────────────────────────────────────

## Write or update an entry in user://worlds/index.cfg.
func _write_index_entry(p_world_id: String, p_name: String,
                         p_seed: int, p_mode: String,
                         p_last_played: int = 0) -> void:
	var cfg := ConfigFile.new()
	cfg.load(_INDEX_PATH)   # Silently fails if file does not exist — that's fine.

	cfg.set_value(p_world_id, "name", p_name)
	cfg.set_value(p_world_id, "seed", p_seed)
	cfg.set_value(p_world_id, "mode", p_mode)

	if not cfg.has_section_key(p_world_id, "created_unix"):
		cfg.set_value(p_world_id, "created_unix", int(Time.get_unix_time_from_system()))

	var ts: int = p_last_played if p_last_played > 0 else int(Time.get_unix_time_from_system())
	cfg.set_value(p_world_id, "last_played_unix", ts)

	cfg.save(_INDEX_PATH)


## Remove a world entry from the index and soft-delete its directory.
func _delete_world_entry(p_world_id: String) -> void:
	var cfg := ConfigFile.new()
	cfg.load(_INDEX_PATH)
	if cfg.has_section(p_world_id):
		cfg.erase_section(p_world_id)
		cfg.save(_INDEX_PATH)

	# Soft delete: move world directory to user://worlds/_deleted/{world_id}.
	var src_dir := ProjectSettings.globalize_path("user://worlds/%s" % p_world_id)
	var del_base := ProjectSettings.globalize_path("user://worlds/_deleted")
	DirAccess.make_dir_recursive_absolute(del_base)
	var dst_dir := del_base + "/%s" % p_world_id
	if DirAccess.dir_exists_absolute(src_dir):
		DirAccess.rename_absolute(src_dir, dst_dir)

# ─── Navigation helpers ───────────────────────────────────────────────────────

## Open a world: update last_played timestamp, open in WorldSave, change scene.
func _load_world(entry: Dictionary) -> void:
	var p_world_id: String  = entry.get("world_id", "")
	var p_seed: int         = entry.get("seed", 0)
	var p_mode: String      = entry.get("mode", "survival")
	var p_name: String      = entry.get("name", p_world_id)

	# Update last_played in the index.
	_write_index_entry(p_world_id, p_name, p_seed, p_mode,
		int(Time.get_unix_time_from_system()))

	if not WorldSave.open_world(p_world_id, p_seed, p_mode):
		push_error("world_select_screen._load_world: WorldSave.open_world failed for '%s' — aborting scene change." % p_world_id)
		return
	# W2 fix: WORLD_LOADED is emitted by main_scene._on_world_ready_telemetry() once
	# the world has actually loaded. Emitting here would double-fire the event and
	# distort the onboarding funnel.
	get_tree().change_scene_to_file("res://src/world/main_scene.tscn")

# ─── Signal handlers ──────────────────────────────────────────────────────────

func _on_friends_pressed() -> void:
	var panel_path := "res://src/ui/friends_panel.tscn"
	if not ResourceLoader.exists(panel_path):
		push_warning("world_select_screen: friends_panel.tscn not found")
		return
	var panel: Node = load(panel_path).instantiate()
	# Set standalone_mode so admin controls are hidden.
	if "standalone_mode" in panel:
		panel.set("standalone_mode", true)
	var overlay_layer := CanvasLayer.new()
	overlay_layer.name = "FriendsPanelOverlay"
	overlay_layer.layer = 10
	overlay_layer.add_child(panel)
	add_child(overlay_layer)
	if panel.has_method("open"):
		panel.call("open")


func _on_settings_pressed() -> void:
	var settings_path := "res://src/ui/settings_menu.tscn"
	if not ResourceLoader.exists(settings_path):
		return
	var settings: Node = load(settings_path).instantiate()
	var overlay_layer := CanvasLayer.new()
	overlay_layer.name = "SettingsOverlay"
	overlay_layer.layer = 10
	overlay_layer.add_child(settings)
	add_child(overlay_layer)
	if settings.has_signal("close_requested"):
		settings.close_requested.connect(func(): overlay_layer.queue_free())


func _on_new_world_pressed() -> void:
	# Reset modal state.
	if _modal_name_field != null:
		_modal_name_field.text = tr("ui.new_world.name_placeholder")
		_modal_name_counter.text = "%d/24" % _modal_name_field.text.length()
	if _modal_name_error != null:
		_modal_name_error.visible = false
	_selected_mode = "survival"
	_update_mode_buttons()
	if _modal_create_button != null:
		_modal_create_button.text = tr("ui.new_world.create")
		_modal_create_button.disabled = false
	_show_new_world_modal()


func _show_new_world_modal() -> void:
	if _modal_overlay != null:
		_modal_overlay.visible = true
	if _modal_name_field != null:
		_modal_name_field.grab_focus()


func _hide_new_world_modal() -> void:
	if _modal_overlay != null:
		_modal_overlay.visible = false


func _on_modal_overlay_input(event: InputEvent) -> void:
	# Tapping outside the modal panel (on the overlay ColorRect) dismisses the modal.
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			# Check if the click landed outside _modal_panel.
			if _modal_panel != null:
				var panel_rect := _modal_panel.get_global_rect()
				if not panel_rect.has_point(mb.global_position):
					_hide_new_world_modal()


func _on_modal_name_changed(new_text: String) -> void:
	if _modal_name_counter != null:
		_modal_name_counter.text = "%d/24" % new_text.length()
	if _modal_name_error != null:
		_modal_name_error.visible = false


func _on_mode_survival_pressed() -> void:
	_selected_mode = "survival"
	_update_mode_buttons()


func _on_mode_creative_pressed() -> void:
	_selected_mode = "creative"
	_update_mode_buttons()


func _update_mode_buttons() -> void:
	if _modal_survival_button == null or _modal_creative_button == null:
		return
	# Survival selected: solid navy border on survival button; dim on creative.
	var active_style := StyleBoxFlat.new()
	active_style.bg_color = Color(0.106, 0.173, 0.337, 0.85)
	active_style.border_width_left = 2
	active_style.border_width_top = 2
	active_style.border_width_right = 2
	active_style.border_width_bottom = 2
	active_style.border_color = Color(0.961, 0.765, 0.051, 1.0)   # accent yellow
	active_style.corner_radius_top_left = 8
	active_style.corner_radius_top_right = 8
	active_style.corner_radius_bottom_left = 8
	active_style.corner_radius_bottom_right = 8
	active_style.content_margin_left = 16.0
	active_style.content_margin_top = 10.0
	active_style.content_margin_right = 16.0
	active_style.content_margin_bottom = 10.0

	if _selected_mode == "survival":
		_modal_survival_button.add_theme_stylebox_override("normal", active_style)
		_modal_creative_button.remove_theme_stylebox_override("normal")
	else:
		_modal_creative_button.add_theme_stylebox_override("normal", active_style)
		_modal_survival_button.remove_theme_stylebox_override("normal")


## Shared handler for text_submitted on both name and seed LineEdits.
func _on_modal_field_submitted(_text: String) -> void:
	print("[world_select] modal field submitted (Enter) — invoking create")
	_on_create_world_pressed()


func _on_create_world_pressed() -> void:
	print("[world_select] _on_create_world_pressed entered")
	if _modal_name_field == null:
		print("[world_select] guard: _modal_name_field is null — abort")
		return

	var world_name: String = _modal_name_field.text.strip_edges()
	print("[world_select] world_name='", world_name, "' length=", world_name.length())

	# Empty name guard.
	if world_name.is_empty():
		print("[world_select] reject: empty name")
		if _modal_name_error != null:
			_modal_name_error.text = tr("ui.new_world.name_error_empty")
			_modal_name_error.visible = true
		return

	# Profanity filter (T-06-S2: client-side check; WorldSave.create_world() also checks).
	var ProfanityFilter = load("res://src/networking/profanity_filter.gd")
	if ProfanityFilter != null and ProfanityFilter.filter_reject(world_name):
		print("[world_select] reject: profanity matched")
		if _modal_name_error != null:
			_modal_name_error.visible = true
		return

	# Seed: always a fresh random seed (the seed prompt was removed for v1.1 — youth game).
	var world_seed: int = randi()
	print("[world_select] seed=", world_seed, " mode=", _selected_mode)

	# Loading state.
	if _modal_create_button != null:
		_modal_create_button.text = tr("ui.new_world.creating")
		_modal_create_button.disabled = true

	# Create via WorldSave.
	print("[world_select] calling WorldSave.create_world …")
	var ok: bool = WorldSave.create_world(world_name, world_seed, _selected_mode)
	print("[world_select] WorldSave.create_world returned ok=", ok, " world_id=", WorldSave.world_id)
	if not ok:
		# WorldSave.create_world() rejected the name (profanity double-check or collision).
		if _modal_name_error != null:
			_modal_name_error.visible = true
		if _modal_create_button != null:
			_modal_create_button.text = tr("ui.new_world.create")
			_modal_create_button.disabled = false
		return

	# WorldSave.create_world calls open_world internally — world_id is now set.
	var new_world_id: String = WorldSave.world_id

	# Write to index.cfg so the world appears in the list on next open.
	_write_index_entry(new_world_id, world_name, world_seed, _selected_mode,
		int(Time.get_unix_time_from_system()))

	OnboardingTelemetry.log(OnboardingTelemetry.WORLD_CREATED)
	# W2 fix: WORLD_LOADED is emitted by main_scene._on_world_ready_telemetry().

	_hide_new_world_modal()
	get_tree().change_scene_to_file("res://src/world/main_scene.tscn")


func _on_play_pressed(entry: Dictionary) -> void:
	_load_world(entry)


func _hide_friends_button_if_offline() -> void:
	if offline_mode and _friends_button != null:
		_friends_button.visible = false

# ─── Card hover effect ────────────────────────────────────────────────────────

func _on_card_hover_enter(card: PanelContainer, card_style: StyleBoxFlat) -> void:
	var tw := card.create_tween()
	tw.tween_method(
		func(c: Color): card_style.bg_color = c,
		COLOR_NAVY_CARD,
		COLOR_NAVY_HOVER,
		HOVER_TWEEN_S
	)


func _on_card_hover_exit(card: PanelContainer, card_style: StyleBoxFlat) -> void:
	var tw := card.create_tween()
	tw.tween_method(
		func(c: Color): card_style.bg_color = c,
		COLOR_NAVY_HOVER,
		COLOR_NAVY_CARD,
		HOVER_TWEEN_S
	)

# ─── Long-press / right-click context menu ────────────────────────────────────

func _on_card_input(event: InputEvent, p_world_id: String) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			_show_world_context_menu(p_world_id, mb.global_position)
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_long_press_world_id = p_world_id
				_long_press_timer.start()
			else:
				_long_press_timer.stop()
	elif event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			_long_press_world_id = p_world_id
			_long_press_timer.start()
		else:
			_long_press_timer.stop()


func _on_long_press_timeout() -> void:
	if _long_press_world_id.is_empty():
		return
	_show_world_context_menu(_long_press_world_id, get_viewport().get_mouse_position())


func _show_world_context_menu(p_world_id: String, screen_pos: Vector2) -> void:
	var items: Array = [
		{
			"label": tr("ui.world_select.ctx_rename"),
			"action": func(): _show_rename_dialog(p_world_id),
		},
		{
			"label": tr("ui.world_select.ctx_duplicate"),
			"action": func(): _duplicate_world(p_world_id),
		},
		{
			"label": tr("ui.world_select.ctx_export"),
			"action": func(): _export_world(p_world_id),
		},
		{
			"label": tr("ui.world_select.ctx_delete"),
			"color": COLOR_DESTRUCTIVE,
			"action": func(): _confirm_delete(p_world_id),
		},
	]

	var ctx_menu: Node = get_node_or_null("/root/ContextMenu")
	if ctx_menu != null and ctx_menu.has_method("show_menu"):
		ctx_menu.call("show_menu", items, screen_pos)
	else:
		# Fallback: show a simple popup menu if ContextMenu autoload is unavailable.
		_show_fallback_context_menu(p_world_id, screen_pos)


func _show_fallback_context_menu(p_world_id: String, _screen_pos: Vector2) -> void:
	# Minimal fallback: just confirm delete, since ContextMenu autoload may not be wired.
	push_warning("world_select_screen: ContextMenu autoload not found — using inline fallback for world '%s'" % p_world_id)
	_confirm_delete(p_world_id)

# ─── World management actions ─────────────────────────────────────────────────

## Show a rename dialog for the given world_id.
func _show_rename_dialog(p_world_id: String) -> void:
	_rename_world_id = p_world_id

	if _rename_dialog == null:
		_rename_dialog = AcceptDialog.new()
		_rename_dialog.title = tr("ui.world_select.ctx_rename")
		_rename_field = LineEdit.new()
		_rename_field.max_length = 24
		_rename_dialog.add_child(_rename_field)
		_rename_dialog.confirmed.connect(_on_rename_confirmed)
		add_child(_rename_dialog)

	# Pre-fill with current name.
	var cfg := ConfigFile.new()
	if cfg.load(_INDEX_PATH) == OK and cfg.has_section(p_world_id):
		_rename_field.text = str(cfg.get_value(p_world_id, "name", p_world_id))

	_rename_dialog.popup_centered()


func _on_rename_confirmed() -> void:
	if _rename_world_id.is_empty() or _rename_field == null:
		return
	var new_name: String = _rename_field.text.strip_edges()
	if new_name.is_empty():
		return
	# Validate via WorldSave.rename_world() (profanity check).
	if not WorldSave.rename_world(new_name):
		push_warning("world_select_screen: rename rejected by profanity filter")
		return

	var cfg := ConfigFile.new()
	cfg.load(_INDEX_PATH)
	if cfg.has_section(_rename_world_id):
		cfg.set_value(_rename_world_id, "name", new_name)
		cfg.save(_INDEX_PATH)
	_rebuild_world_list()


func _duplicate_world(p_world_id: String) -> void:
	# Read source entry from index.
	var cfg := ConfigFile.new()
	if cfg.load(_INDEX_PATH) != OK:
		return
	if not cfg.has_section(p_world_id):
		return

	var src_name: String = str(cfg.get_value(p_world_id, "name", p_world_id))
	var src_seed: int    = int(cfg.get_value(p_world_id, "seed", 0))
	var src_mode: String = str(cfg.get_value(p_world_id, "mode", "survival"))

	# Generate new world_id.
	var new_id: String = p_world_id + "_copy_" + str(int(Time.get_unix_time_from_system()))

	# Copy world directory contents.
	var src_dir := ProjectSettings.globalize_path("user://worlds/%s" % p_world_id)
	var dst_dir := ProjectSettings.globalize_path("user://worlds/%s" % new_id)
	if DirAccess.dir_exists_absolute(src_dir):
		DirAccess.make_dir_recursive_absolute(dst_dir)
		var dir := DirAccess.open(src_dir)
		if dir != null:
			dir.list_dir_begin()
			var file_name: String = dir.get_next()
			while not file_name.is_empty():
				if not dir.current_is_dir():
					var src_file: String = src_dir + "/" + file_name
					var dst_file: String = dst_dir + "/" + file_name
					# Copy file via FileAccess read/write.
					var src_fa := FileAccess.open(src_file, FileAccess.READ)
					var dst_fa := FileAccess.open(dst_file, FileAccess.WRITE)
					if src_fa != null and dst_fa != null:
						const CHUNK_SZ: int = 65536
						while not src_fa.eof_reached():
							var buf := src_fa.get_buffer(CHUNK_SZ)
							if buf.size() > 0:
								dst_fa.store_buffer(buf)
						src_fa.close()
						dst_fa.flush()
						dst_fa.close()
					elif src_fa != null:
						src_fa.close()
				file_name = dir.get_next()
			dir.list_dir_end()

	var new_name: String = src_name + " (copy)"
	_write_index_entry(new_id, new_name, src_seed, src_mode)
	_rebuild_world_list()


func _export_world(p_world_id: String) -> void:
	# Opens the world directory in the system file manager.
	var world_dir := ProjectSettings.globalize_path("user://worlds/%s" % p_world_id)
	if DirAccess.dir_exists_absolute(world_dir):
		OS.shell_open(world_dir)
	else:
		push_warning("world_select_screen: cannot export — world dir not found: %s" % world_dir)


func _confirm_delete(p_world_id: String) -> void:
	_delete_world_id = p_world_id
	if _delete_overlay != null:
		_delete_overlay.visible = true


func _on_delete_confirmed() -> void:
	if _delete_world_id.is_empty():
		return
	_delete_world_entry(_delete_world_id)
	_delete_world_id = ""
	if _delete_overlay != null:
		_delete_overlay.visible = false
	_rebuild_world_list()
