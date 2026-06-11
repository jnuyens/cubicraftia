# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# legal_viewer.gd — In-app viewer for EULA and Privacy Policy (Surface E).
#
# Usage:
#   var viewer: LegalViewer = preload("res://src/ui/legal_viewer.tscn").instantiate()
#   get_tree().root.add_child(viewer)
#   viewer.open("eula")        # or "privacy"
#   viewer.open("eula", true)  # show_agree=true for re-acknowledge flow
#
# Architecture:
#   - CanvasLayer layer 15 (above title screen at 10, below modals at 20).
#   - PanelContainer: 560px desktop, full-width-minus-32px mobile.
#   - Markdown subset: H1, H2, H3, bold (**), italic (*), bullet (- / *),
#     plain paragraphs, inline links (url rendered as text in Phase 5).
#   - Summary section (text between "## Summary" and next "## " heading)
#     wrapped in a PanelContainer with StyleBox_legal_summary.
#   - SHA-256 of the file shown in footer (first 16 hex chars).
#   - "I agree" button visible only when show_agree=true.
#     On press: FriendsClient.store_eula_hash(hash), emit eula_agreed.
#
# Security: T-05-EULA-skip — clearing user://settings.cfg only makes EULA reappear.
#
# References:
#   05-UI-SPEC.md Surface E
#   05-CONTEXT.md Area 4
#   05-RESEARCH.md Pattern 4 (SHA-256 hash)

extends CanvasLayer

# ─── Signals ──────────────────────────────────────────────────────────────────

## Emitted when the user clicks "I agree" and the hash is stored.
signal eula_agreed()

# ─── Constants ────────────────────────────────────────────────────────────────

## CanvasLayer ordering: above title screen (10), below modals (20).
const LAYER: int = 15

## Desktop panel width in pixels.
const PANEL_WIDTH_DESKTOP: float = 560.0

## Horizontal margin subtracted from viewport width on mobile.
const MOBILE_MARGIN: float = 32.0

## Panel height as a fraction of viewport height.
const PANEL_HEIGHT_FRACTION: float = 0.80

## Font sizes.
const FONT_SIZE_H1: int = 20
const FONT_SIZE_H2: int = 16
const FONT_SIZE_BODY: int = 16
const FONT_SIZE_FOOTER: int = 14

## Colors (brick white #F1F0EA).
const COLOR_BRICK_WHITE := Color(0.945, 0.941, 0.918, 1.0)
const COLOR_BRICK_WHITE_70 := Color(0.945, 0.941, 0.918, 0.70)
const COLOR_BRICK_WHITE_40 := Color(0.945, 0.941, 0.918, 0.40)
const COLOR_NAVY := Color(0.106, 0.173, 0.337, 0.95)
const COLOR_ACCENT_YELLOW := Color(0.961, 0.765, 0.051, 1.0)

## Document paths.
const DOC_PATHS := {
	"eula": "res://docs/EULA.md",
	"privacy": "res://docs/PRIVACY.md",
}

# ─── State ────────────────────────────────────────────────────────────────────

## Currently loaded document type ("eula" or "privacy").
var _doc_type: String = ""

## SHA-256 hash (first 16 hex chars) of the currently loaded document.
var _current_hash: String = ""

## Whether to show the "I agree" button.
var _show_agree: bool = false

# ─── UI nodes (built in open()) ──────────────────────────────────────────────

var _overlay: ColorRect = null
var _panel: PanelContainer = null
var _title_label: Label = null
var _close_button: Button = null
var _scroll: ScrollContainer = null
var _content_vbox: VBoxContainer = null
var _footer_hash_label: Label = null
var _agree_button: Button = null

# ─── Lifecycle ────────────────────────────────────────────────────────────────

func _ready() -> void:
	layer = LAYER
	# Build the static UI skeleton once; content is filled by open().
	_build_ui()


# ─── Public API ───────────────────────────────────────────────────────────────

## Open the viewer with the specified document.
## doc_type: "eula" or "privacy"
## show_agree: true in re-acknowledge flows (shows "I agree" button in footer).
func open(doc_type: String, show_agree: bool = false) -> void:
	_doc_type = doc_type
	_show_agree = show_agree

	var path: String = DOC_PATHS.get(doc_type, DOC_PATHS["eula"])
	var content: String = _read_file(path)

	# Compute hash before building the node tree.
	_current_hash = _compute_hash(path)

	# Set title.
	if _title_label != null:
		if doc_type == "privacy":
			_title_label.text = tr("ui.legal.privacy_link")
		else:
			_title_label.text = tr("ui.legal.terms_link")

	# Build content nodes from Markdown.
	if _content_vbox != null:
		for child in _content_vbox.get_children():
			child.queue_free()
		var nodes := md_to_nodes(content)
		for node in nodes:
			_content_vbox.add_child(node)

	# Update footer hash label.
	if _footer_hash_label != null:
		var version_text: String = tr("ui.legal.footer_version")
		_footer_hash_label.text = version_text.replace("{hash}", _current_hash)

	# Show/hide agree button.
	if _agree_button != null:
		_agree_button.visible = _show_agree

	# Make the layer visible.
	visible = true


# ─── Markdown parser ──────────────────────────────────────────────────────────

## Parse a Markdown string into an array of Control nodes.
## Supported constructs:
##   # H1              → Label (font_size 20, bold)
##   ## H2             → Label (font_size 16, bold)
##   ### H3            → Label (font_size 14, bold + italic via RichTextLabel)
##   - item / * item  → Label with "• " prefix
##   **bold**          → RichTextLabel with bbcode_enabled (for inline bold)
##   *italic*          → RichTextLabel with bbcode_enabled (for inline italic)
##   [link](url)       → text rendered as "link (url)" plain Label (Phase 5: no URL rendering)
##   (empty line)      → 8px gap Control
##   ## Summary section → PanelContainer with StyleBox_legal_summary
##   plain paragraph   → Label (font_size 16, auto-wrap)
static func md_to_nodes(content: String) -> Array[Control]:
	var result: Array[Control] = []
	var lines := content.split("\n")
	var in_summary_section: bool = false
	var summary_vbox: VBoxContainer = null
	var summary_panel: PanelContainer = null

	for raw_line in lines:
		var line: String = raw_line.rstrip(" \t\r")

		# H1
		if line.begins_with("# ") and not line.begins_with("## "):
			if in_summary_section:
				in_summary_section = false
				summary_vbox = null
				summary_panel = null
			var lbl := Label.new()
			lbl.text = line.substr(2)
			lbl.add_theme_font_size_override("font_size", FONT_SIZE_H1)
			lbl.add_theme_color_override("font_color", COLOR_BRICK_WHITE)
			lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			result.append(lbl)
			continue

		# H2 (also detects "## Summary" to start summary section)
		if line.begins_with("## ") and not line.begins_with("### "):
			var heading_text: String = line.substr(3)
			if heading_text.strip_edges() == "Summary":
				in_summary_section = true
				summary_panel = _make_summary_panel()
				summary_vbox = VBoxContainer.new()
				summary_panel.add_child(summary_vbox)
				result.append(summary_panel)
			else:
				in_summary_section = false
				summary_vbox = null
				summary_panel = null
				var lbl := Label.new()
				lbl.text = heading_text
				lbl.add_theme_font_size_override("font_size", FONT_SIZE_H2)
				lbl.add_theme_color_override("font_color", COLOR_BRICK_WHITE)
				lbl.set("theme_override_font_sizes/bold_font_size", FONT_SIZE_H2)
				lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				result.append(lbl)
			continue

		# H3
		if line.begins_with("### "):
			if in_summary_section:
				in_summary_section = false
				summary_vbox = null
				summary_panel = null
			var rtl := RichTextLabel.new()
			rtl.bbcode_enabled = true
			rtl.fit_content = true
			rtl.text = "[b][i]" + line.substr(4) + "[/i][/b]"
			rtl.add_theme_font_size_override("normal_font_size", FONT_SIZE_BODY)
			rtl.add_theme_color_override("default_color", COLOR_BRICK_WHITE)
			rtl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			result.append(rtl)
			continue

		# Bullet list
		if line.begins_with("- ") or line.begins_with("* "):
			var bullet_text: String = line.substr(2)
			var rendered_text: String = "• " + _strip_inline_formatting(bullet_text)
			var node: Control
			if "**" in bullet_text or "*" in bullet_text:
				var rtl := RichTextLabel.new()
				rtl.bbcode_enabled = true
				rtl.fit_content = true
				rtl.text = "• " + _md_inline_to_bbcode(bullet_text)
				rtl.add_theme_font_size_override("normal_font_size", FONT_SIZE_BODY)
				rtl.add_theme_color_override("default_color", COLOR_BRICK_WHITE)
				rtl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				node = rtl
			else:
				var lbl := Label.new()
				lbl.text = rendered_text
				lbl.add_theme_font_size_override("font_size", FONT_SIZE_BODY)
				lbl.add_theme_color_override("font_color", COLOR_BRICK_WHITE)
				lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				node = lbl
			if in_summary_section and is_instance_valid(summary_vbox):
				summary_vbox.add_child(node)
			else:
				result.append(node)
			continue

		# Empty line → 8px gap
		if line.strip_edges() == "":
			var spacer := Control.new()
			spacer.custom_minimum_size = Vector2(0, 8)
			if in_summary_section and is_instance_valid(summary_vbox):
				summary_vbox.add_child(spacer)
			else:
				result.append(spacer)
			continue

		# Plain paragraph (may contain inline **bold** or *italic*)
		var node: Control
		if "**" in line or ("*" in line and not line.begins_with("* ")):
			var rtl := RichTextLabel.new()
			rtl.bbcode_enabled = true
			rtl.fit_content = true
			rtl.text = _md_inline_to_bbcode(line)
			rtl.add_theme_font_size_override("normal_font_size", FONT_SIZE_BODY)
			rtl.add_theme_color_override("default_color", COLOR_BRICK_WHITE)
			rtl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			node = rtl
		else:
			var lbl := Label.new()
			lbl.text = _strip_inline_formatting(line)
			lbl.add_theme_font_size_override("font_size", FONT_SIZE_BODY)
			lbl.add_theme_color_override("font_color", COLOR_BRICK_WHITE)
			lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			node = lbl

		if in_summary_section and is_instance_valid(summary_vbox):
			summary_vbox.add_child(node)
		else:
			result.append(node)

	return result


## Convert Markdown inline syntax to BBCode.
## Handles **bold**, *italic*, [link](url).
static func _md_inline_to_bbcode(text: String) -> String:
	var out: String = text
	# Strip inline links: [text](url) → text (Phase 5: no URL rendering)
	var link_re := RegEx.new()
	link_re.compile("\\[([^\\]]+)\\]\\([^)]+\\)")
	out = link_re.sub(out, "$1", true)
	# **bold** → [b]bold[/b]
	var bold_re := RegEx.new()
	bold_re.compile("\\*\\*([^*]+)\\*\\*")
	out = bold_re.sub(out, "[b]$1[/b]", true)
	# *italic* (single asterisk, not inside bold) → [i]italic[/i]
	var italic_re := RegEx.new()
	italic_re.compile("(?<![*])\\*([^*]+)\\*(?![*])")
	out = italic_re.sub(out, "[i]$1[/i]", true)
	return out


## Strip Markdown inline syntax to plain text.
static func _strip_inline_formatting(text: String) -> String:
	var out: String = text
	# Strip inline links
	var link_re := RegEx.new()
	link_re.compile("\\[([^\\]]+)\\]\\([^)]+\\)")
	out = link_re.sub(out, "$1", true)
	# Strip **bold** markers
	var bold_re := RegEx.new()
	bold_re.compile("\\*\\*([^*]+)\\*\\*")
	out = bold_re.sub(out, "$1", true)
	# Strip *italic* markers
	var italic_re := RegEx.new()
	italic_re.compile("(?<![*])\\*([^*]+)\\*(?![*])")
	out = italic_re.sub(out, "$1", true)
	return out


## Build a PanelContainer styled as StyleBox_legal_summary.
## Transparent background, 2px accent-yellow left border, 8px padding.
static func _make_summary_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.0, 0.0, 0.0)
	style.border_width_left = 2
	style.border_width_top = 0
	style.border_width_right = 0
	style.border_width_bottom = 0
	style.border_color = Color(0.961, 0.765, 0.051, 1.0)  # accent yellow
	style.content_margin_left = 8.0
	style.content_margin_top = 8.0
	style.content_margin_right = 8.0
	style.content_margin_bottom = 8.0
	panel.add_theme_stylebox_override("panel", style)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return panel


# ─── File I/O ─────────────────────────────────────────────────────────────────

## Read a resource file and return its content as a String.
## Returns "" if the file cannot be opened.
static func _read_file(path: String) -> String:
	if not FileAccess.file_exists(path):
		push_warning("LegalViewer._read_file: file not found: %s" % path)
		return ""
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("LegalViewer._read_file: could not open: %s" % path)
		return ""
	var text := file.get_as_text()
	file.close()
	return text


## Compute SHA-256 of a resource file (chunked 4096 bytes per 05-RESEARCH.md Pattern 4).
## Returns the first 16 hex characters, or "" on failure.
static func _compute_hash(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var ctx := HashingContext.new()
	if ctx.start(HashingContext.HASH_SHA256) != OK:
		return ""
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var chunk_size: int = 4096
	while not file.eof_reached():
		var chunk: PackedByteArray = file.get_buffer(chunk_size)
		if chunk.size() > 0:
			ctx.update(chunk)
	file.close()
	return ctx.finish().hex_encode()  # Full SHA-256 hex (64 chars) — WR-07


# ─── UI construction ──────────────────────────────────────────────────────────

## Build the static UI skeleton.
## Content is filled dynamically by open().
func _build_ui() -> void:
	visible = false

	# Full-screen darkening overlay.
	_overlay = ColorRect.new()
	_overlay.color = Color(0.0, 0.0, 0.0, 0.4)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_overlay)

	# Panel anchor container (centred, sized to viewport).
	var anchor := Control.new()
	anchor.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(anchor)

	# Main panel.
	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = COLOR_NAVY
	panel_style.corner_radius_top_left = 16
	panel_style.corner_radius_top_right = 16
	panel_style.corner_radius_bottom_left = 16
	panel_style.corner_radius_bottom_right = 16
	_panel.add_theme_stylebox_override("panel", panel_style)
	anchor.add_child(_panel)

	# Size and centre the panel based on viewport.
	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_update_panel_size()

	# Outer VBox inside the panel.
	var outer_vbox := VBoxContainer.new()
	outer_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_panel.add_child(outer_vbox)

	# Header bar (48px, HBoxContainer).
	var header := HBoxContainer.new()
	header.custom_minimum_size = Vector2(0, 48)
	outer_vbox.add_child(header)

	_title_label = Label.new()
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_label.add_theme_font_size_override("font_size", FONT_SIZE_H1)
	_title_label.add_theme_color_override("font_color", COLOR_BRICK_WHITE)
	_title_label.text = ""
	header.add_child(_title_label)

	_close_button = Button.new()
	_close_button.text = tr("ui.legal.viewer_close")
	_close_button.custom_minimum_size = Vector2(80, 0)
	_close_button.pressed.connect(_on_close_pressed)
	header.add_child(_close_button)

	# ScrollContainer (fills remaining height).
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer_vbox.add_child(_scroll)

	_content_vbox = VBoxContainer.new()
	_content_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_content_vbox)

	# Footer bar (40px, HBoxContainer, top border).
	var footer := HBoxContainer.new()
	footer.custom_minimum_size = Vector2(0, 40)
	outer_vbox.add_child(footer)

	_footer_hash_label = Label.new()
	_footer_hash_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_footer_hash_label.add_theme_font_size_override("font_size", FONT_SIZE_FOOTER)
	_footer_hash_label.add_theme_color_override("font_color", COLOR_BRICK_WHITE_40)
	_footer_hash_label.text = ""
	footer.add_child(_footer_hash_label)

	_agree_button = Button.new()
	_agree_button.text = tr("ui.legal.agree_button")
	_agree_button.custom_minimum_size = Vector2(160, 0)
	_agree_button.visible = false
	_agree_button.pressed.connect(_on_agree_pressed)
	footer.add_child(_agree_button)


## Adjust panel width and height to match the current viewport size.
func _update_panel_size() -> void:
	if _panel == null:
		return
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var panel_width: float
	if viewport_size.x <= 600.0:
		# Mobile: full width minus 32px margin.
		panel_width = viewport_size.x - MOBILE_MARGIN
	else:
		panel_width = PANEL_WIDTH_DESKTOP
	var panel_height: float = viewport_size.y * PANEL_HEIGHT_FRACTION
	_panel.custom_minimum_size = Vector2(panel_width, panel_height)


# ─── Button handlers ──────────────────────────────────────────────────────────

func _on_close_pressed() -> void:
	visible = false


func _on_agree_pressed() -> void:
	# Store the hash via FriendsClient.
	var fc: Node = get_node_or_null("/root/FriendsClient")
	if fc != null and fc.has_method("store_eula_hash"):
		fc.store_eula_hash(_current_hash)
	# Hide the agree button (accepted this version).
	if _agree_button != null:
		_agree_button.visible = false
	# Emit signal so EulaAcknowledgeModal can dismiss itself.
	eula_agreed.emit()
	# Close the viewer.
	visible = false
