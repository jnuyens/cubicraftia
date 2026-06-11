# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# eula_acknowledge_modal.gd — EULA re-acknowledge gate modal.
#
# Shown on app launch when FriendsClient.check_eula_acknowledgement() returns false
# (bundled EULA hash differs from the stored hash in user://settings.cfg).
#
# Cannot be dismissed without choosing "Review Terms" (which leads to LegalViewer
# with show_agree=true) or "Sign out". No tap-outside or Escape dismissal.
#
# Architecture:
#   - CanvasLayer layer 20 (same as other modals — blocks all interaction below).
#   - PanelContainer 400px, centred, navy overlay.
#   - "Review Terms" → opens LegalViewer(eula, show_agree=true).
#     Connects to LegalViewer.eula_agreed → dismisses this modal.
#   - "Sign out" → FriendsClient.sign_out(), dismisses modal.
#
# References:
#   05-UI-SPEC.md Surface E (EULA re-acknowledge flow)
#   05-CONTEXT.md Area 4

extends CanvasLayer

# ─── Constants ────────────────────────────────────────────────────────────────

const LAYER: int = 20
const PANEL_WIDTH: float = 400.0

const COLOR_NAVY_OVERLAY := Color(0.106, 0.173, 0.337, 0.92)
const COLOR_BRICK_WHITE := Color(0.945, 0.941, 0.918, 1.0)
const COLOR_BRICK_WHITE_80 := Color(0.945, 0.941, 0.918, 0.80)

# ─── Lifecycle ────────────────────────────────────────────────────────────────

func _ready() -> void:
	layer = LAYER
	visible = false
	_build_ui()


# ─── Public API ───────────────────────────────────────────────────────────────

## Show the EULA re-acknowledge modal.
## Call this when FriendsClient.check_eula_acknowledgement() returns false.
func show() -> void:
	visible = true


# ─── Input handling ──────────────────────────────────────────────────────────

## Consume all unhandled input to prevent tap-outside or Escape dismissal.
func _input(event: InputEvent) -> void:
	if not visible:
		return
	# Swallow keyboard escape so the modal cannot be dismissed.
	if event is InputEventKey and (event as InputEventKey).keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()


# ─── UI construction ──────────────────────────────────────────────────────────

func _build_ui() -> void:
	# Full-screen navy overlay (blocks interaction below).
	var overlay := ColorRect.new()
	overlay.color = COLOR_NAVY_OVERLAY
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP  # blocks clicks below
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)

	# Anchor container for centering the panel.
	var anchor := Control.new()
	anchor.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(anchor)

	# Modal panel.
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.106, 0.173, 0.337, 0.97)
	panel_style.corner_radius_top_left = 16
	panel_style.corner_radius_top_right = 16
	panel_style.corner_radius_bottom_left = 16
	panel_style.corner_radius_bottom_right = 16
	panel.add_theme_stylebox_override("panel", panel_style)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	anchor.add_child(panel)

	# Content VBox.
	var vbox := VBoxContainer.new()
	panel.add_child(vbox)

	# Spacer at top.
	var top_spacer := Control.new()
	top_spacer.custom_minimum_size = Vector2(0, 24)
	vbox.add_child(top_spacer)

	# Heading.
	var heading := Label.new()
	heading.text = tr("ui.legal.reack_title")
	heading.add_theme_font_size_override("font_size", 20)
	heading.add_theme_color_override("font_color", COLOR_BRICK_WHITE)
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(heading)

	# Gap.
	var gap1 := Control.new()
	gap1.custom_minimum_size = Vector2(0, 16)
	vbox.add_child(gap1)

	# Body.
	var body := Label.new()
	body.text = tr("ui.legal.reack_body")
	body.add_theme_font_size_override("font_size", 16)
	body.add_theme_color_override("font_color", COLOR_BRICK_WHITE_80)
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(body)

	# Gap.
	var gap2 := Control.new()
	gap2.custom_minimum_size = Vector2(0, 24)
	vbox.add_child(gap2)

	# "Review Terms" button (primary, full-width).
	var review_btn := Button.new()
	review_btn.text = tr("ui.legal.reack_review")
	review_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	review_btn.pressed.connect(_on_review_pressed)
	vbox.add_child(review_btn)

	# Gap between buttons.
	var gap3 := Control.new()
	gap3.custom_minimum_size = Vector2(0, 8)
	vbox.add_child(gap3)

	# "Sign out" button (secondary, full-width).
	var signout_btn := Button.new()
	signout_btn.text = tr("ui.legal.reack_signout")
	signout_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	signout_btn.pressed.connect(_on_signout_pressed)
	vbox.add_child(signout_btn)

	# Spacer at bottom.
	var bottom_spacer := Control.new()
	bottom_spacer.custom_minimum_size = Vector2(0, 24)
	vbox.add_child(bottom_spacer)


# ─── Button handlers ──────────────────────────────────────────────────────────

func _on_review_pressed() -> void:
	# Instantiate and show LegalViewer with show_agree=true.
	var viewer_scene: PackedScene = load("res://src/ui/legal_viewer.tscn")
	if viewer_scene == null:
		push_warning("EulaAcknowledgeModal: could not load legal_viewer.tscn")
		return
	var viewer: Node = viewer_scene.instantiate()
	# Add to the same parent (root) so it appears above this modal's layer.
	get_tree().root.add_child(viewer)
	# Connect eula_agreed signal to dismiss this modal.
	if viewer.has_signal("eula_agreed"):
		viewer.eula_agreed.connect(_on_eula_agreed)
	# Open the EULA with agree button visible.
	if viewer.has_method("open"):
		viewer.open("eula", true)


func _on_eula_agreed() -> void:
	# User agreed in the LegalViewer — dismiss this modal.
	visible = false
	queue_free()


func _on_signout_pressed() -> void:
	# Sign out the user and dismiss the modal.
	var fc: Node = get_node_or_null("/root/FriendsClient")
	if fc != null and fc.has_method("sign_out"):
		fc.sign_out()
	visible = false
	queue_free()
