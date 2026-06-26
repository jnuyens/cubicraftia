# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# avatar_creator.gd — AvatarCreator CanvasLayer (layer 10).
#
# Surface 2 of 06-UI-SPEC (redesigned, quick task 260622-tkz): builder-card lineup
# (forester / explorer / pathfinder + coming-soon), skin / hairstyle / outfit / accessory
# customiser, SubViewport 3D preview (0.4 rad/s rotation) overlaid on a painted backdrop,
# green "Let's build" CTA + Back. Cards drive the base figure; swatches drive appearance.
#
# Emits:
#   avatar_complete  — Done pressed, user://avatar.cfg written, FriendsClient.save_avatar called.
#   avatar_cancelled — Back pressed, no save.
#
# References:
#   06-UI-SPEC.md Surface 2
#   06-CONTEXT.md Area 2
#   06-04-PLAN.md Task 2

extends CanvasLayer

# ─── Signals ──────────────────────────────────────────────────────────────────

signal avatar_complete()
signal avatar_cancelled()

# ─── Constants — avatar config schema ─────────────────────────────────────────

## Skin colour swatches (5), applied to exposed skin mesh parts.
const SKIN_COLOURS: Array[Color] = [
	Color("#FFD21A"),  # classic builder-figure yellow (default builder head)
	Color("#D4956A"),  # tan
	Color("#A0614A"),  # medium
	Color("#6B3A2A"),  # dark
	Color("#3B1F16"),  # deep
]

## Body / leg colour swatches (10) — a subset of the 18-colour brick palette.
const BODY_COLOURS: Array[Color] = [
	Color("#C91111"),  # red
	Color("#E8890C"),  # orange
	Color("#F5C30D"),  # yellow
	Color("#97C515"),  # lime
	Color("#3DB560"),  # green
	Color("#159195"),  # teal
	Color("#1B72D8"),  # blue
	Color("#7B2DB5"),  # purple
	Color("#D43582"),  # pink
	Color("#F1F0EA"),  # white
]

## Head shape string tokens.
const HEAD_SHAPES: Array[String] = ["square", "round", "tall"]

## Face expression string tokens.
const FACE_EXPRESSIONS: Array[String] = ["neutral", "happy", "cool", "surprised", "sleepy"]

## Body accessory string tokens.
const BODY_ACCESSORIES: Array[String] = ["none", "backpack", "cape"]

## Leg shoes string tokens.
const LEG_SHOES: Array[String] = ["none", "boots", "sneakers"]

## Hand accessory string tokens.
const HAND_ACCESSORIES: Array[String] = ["none", "pickaxe", "lantern", "flower", "blank"]

## Default avatar configuration source. The card redesign retired the 8-preset
## "Snel starten" grid; this single config is the fallback used by _load_avatar_cfg
## when user://avatar.cfg is missing or corrupt (see DEFAULT_CFG / PRESETS[0]).
const PRESETS: Array[Dictionary] = [
	# 0 — Default (light skin, square, neutral, blue body, none/none, none)
	{
		"skin_colour_index": 0,
		"head_shape": "square",
		"face_expression": "neutral",
		"body_colour_index": 6,  # blue
		"body_accessory": "none",
		"leg_colour_index": 6,
		"leg_shoes": "none",
		"hand_accessory": "none",
	},
]

## Path for avatar configuration persistence.
const AVATAR_CFG_PATH: String = "user://avatar.cfg"
## ConfigFile section name for avatar data.
const AVATAR_SECTION: String = "avatar"

## Selectable builder cards (portrait + name + personality subtitle).
## The "id" is written to avatar.cfg "character"; builder.gd loads the matching skin GLB
## (see Builder._AVATAR_SKINS) on spawn. Card order matches the CardRow TextureButton
## order in avatar_creator.tscn (forester / explorer / pathfinder).
const CARDS: Array[Dictionary] = [
	{
		"id": "fem",
		"tex": "res://assets/textures/avatars/creator/card_forester.png",
		"name_key": "ui.avatar.card_forester",
		"sub_key": "ui.avatar.card_forester_sub",
		"body": 4,        # green jacket
		"hair": "round",  # fuller hair
		"skin": 0,
	},
	{
		"id": "builder1",
		"tex": "res://assets/textures/avatars/creator/card_explorer.png",
		"name_key": "ui.avatar.card_explorer",
		"sub_key": "ui.avatar.card_explorer_sub",
		"body": 6,         # blue shirt + satchel signature
		"hair": "square",  # short spiky
		"skin": 0,
	},
	{
		"id": "red",
		"tex": "res://assets/textures/avatars/creator/card_pathfinder.png",
		"name_key": "ui.avatar.card_pathfinder",
		"sub_key": "ui.avatar.card_pathfinder_sub",
		"body": 0,        # red jacket + bandolier signature
		"hair": "tall",   # tall spiky
		"skin": 1,
	},
]
const DEFAULT_CHARACTER: String = "builder1"

## Card frame (PanelContainer) node names, parallel to CARDS by index. The selection
## glow StyleBox is toggled on the matching frame in _refresh_card_selection.
const CARD_FRAMES: Array[String] = [
	"CardForesterFrame",
	"CardExplorerFrame",
	"CardPathfinderFrame",
]

## TextureButton node names inside CardRow, parallel to CARDS by index.
const CARD_BUTTONS: Array[String] = [
	"CardForesterButton",
	"CardExplorerButton",
	"CardPathfinderButton",
]

## SubViewport builder rotation speed in radians per second.
const PREVIEW_ROT_SPEED: float = 0.4

# ─── Node references (set in _ready via NodePath or create programmatically) ──

## SubViewport builder preview node (set in _ready from the tscn).
var _preview_builder: Node3D = null

## Current avatar config dictionary.
var _cfg: Dictionary = {}

## Swatch Button arrays — populated in _ready from the scene tree.
var _skin_buttons: Array[Button] = []
var _head_shape_buttons: Array[Button] = []
var _face_expr_buttons: Array[Button] = []
var _body_colour_buttons: Array[Button] = []
var _body_acc_buttons: Array[Button] = []
var _leg_colour_buttons: Array[Button] = []
var _leg_shoe_buttons: Array[Button] = []
var _hand_acc_buttons: Array[Button] = []
## Card TextureButtons (CardRow), parallel to CARDS by index. Resolved in _ready.
var _card_buttons: Array[TextureButton] = []

# ─── Lifecycle ────────────────────────────────────────────────────────────────

func _ready() -> void:
	# Telemetry: avatar picker shown.
	OnboardingTelemetry.log(OnboardingTelemetry.AVATAR_PICKER_SHOWN)

	# Load existing avatar config from disk if present (re-customisation case).
	_cfg = _load_avatar_cfg()

	# Cache scene node references.
	_preview_builder = _find_preview_builder()

	# Build swatch / button arrays from named container nodes.
	_skin_buttons       = _collect_buttons("SkinRow")
	_head_shape_buttons = _collect_buttons("HeadShapeRow")
	_face_expr_buttons  = _collect_buttons("FaceExprRow")
	_body_colour_buttons = _collect_buttons("BodyColourRow")
	_body_acc_buttons   = _collect_buttons("BodyAccRow")
	_leg_colour_buttons = _collect_buttons("LegColourRow")
	_leg_shoe_buttons   = _collect_buttons("LegShoeRow")
	_hand_acc_buttons   = _collect_buttons("HandAccRow")

	# Wire swatch buttons.
	for i: int in _skin_buttons.size():
		var btn: Button = _skin_buttons[i]
		btn.pressed.connect(func() -> void: _on_skin_pressed(i))
	for i: int in _head_shape_buttons.size():
		var btn: Button = _head_shape_buttons[i]
		btn.pressed.connect(func() -> void: _on_head_shape_pressed(i))
	for i: int in _face_expr_buttons.size():
		var btn: Button = _face_expr_buttons[i]
		btn.pressed.connect(func() -> void: _on_face_expr_pressed(i))
	for i: int in _body_colour_buttons.size():
		var btn: Button = _body_colour_buttons[i]
		btn.pressed.connect(func() -> void: _on_body_colour_pressed(i))
	for i: int in _body_acc_buttons.size():
		var btn: Button = _body_acc_buttons[i]
		btn.pressed.connect(func() -> void: _on_body_acc_pressed(i))
	for i: int in _leg_colour_buttons.size():
		var btn: Button = _leg_colour_buttons[i]
		btn.pressed.connect(func() -> void: _on_leg_colour_pressed(i))
	for i: int in _leg_shoe_buttons.size():
		var btn: Button = _leg_shoe_buttons[i]
		btn.pressed.connect(func() -> void: _on_leg_shoe_pressed(i))
	for i: int in _hand_acc_buttons.size():
		var btn: Button = _hand_acc_buttons[i]
		btn.pressed.connect(func() -> void: _on_hand_acc_pressed(i))

	# Wire the builder cards (CardRow TextureButtons) to the character selector.
	_wire_cards()

	# Wire action buttons.
	var done_btn: Button = _find_node("DoneButton")
	if done_btn:
		done_btn.pressed.connect(_on_done_pressed)
	var back_btn: Button = _find_node("BackButton")
	if back_btn:
		back_btn.pressed.connect(_on_back_pressed)

	# Decorate section headers + accessory buttons with sliced artwork icons.
	_wire_artwork_icons()

	# Apply initial config to UI controls and preview.
	_refresh_ui_selection()
	_apply_config_to_preview(_cfg)


## Prepend a small artwork icon beside each section label, and put the option icons
## on the accessory buttons. All icons are sliced from the concept art.
func _wire_artwork_icons() -> void:
	const ICON_DIR := "res://assets/textures/avatars/creator/"
	_add_section_icon("SkinLabel", ICON_DIR + "ic_skin.png")
	_add_section_icon("HairstyleLabel", ICON_DIR + "ic_hair.png")
	_add_section_icon("OutfitLabel", ICON_DIR + "ic_outfit.png")
	_add_section_icon("AccessoryLabel", ICON_DIR + "ic_accessory.png")
	var acc_icons: Array[String] = [ICON_DIR + "ic_none.png", ICON_DIR + "ic_backpack.png", ICON_DIR + "ic_cape.png"]
	for i: int in mini(_body_acc_buttons.size(), acc_icons.size()):
		var tex: Texture2D = load(acc_icons[i]) as Texture2D
		if tex != null:
			_body_acc_buttons[i].icon = tex
			_body_acc_buttons[i].expand_icon = true


## Wrap a section's label in an HBox with a 26px icon to its left.
func _add_section_icon(label_name: String, icon_path: String) -> void:
	var label: Node = _find_node(label_name)
	if label == null or not (label is Label):
		return
	var tex: Texture2D = load(icon_path) as Texture2D
	if tex == null:
		return
	var section: Node = label.get_parent()
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	section.add_child(hbox)
	section.move_child(hbox, label.get_index())
	var icon := TextureRect.new()
	icon.texture = tex
	icon.custom_minimum_size = Vector2(26, 26)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hbox.add_child(icon)
	section.remove_child(label)
	hbox.add_child(label)


func _process(delta: float) -> void:
	# Rotate the SubViewport preview builder.
	if is_instance_valid(_preview_builder):
		_preview_builder.rotation.y += PREVIEW_ROT_SPEED * delta


# ─── Public helpers ───────────────────────────────────────────────────────────

## Return a snapshot of the current avatar config.
func _current_config() -> Dictionary:
	return _cfg.duplicate()


# ─── Part change handlers ─────────────────────────────────────────────────────

func _on_skin_pressed(index: int) -> void:
	_cfg["skin_colour_index"] = index
	_refresh_ui_selection()
	_apply_config_to_preview(_cfg)


func _on_head_shape_pressed(index: int) -> void:
	_cfg["head_shape"] = HEAD_SHAPES[index]
	_refresh_ui_selection()
	_apply_config_to_preview(_cfg)


func _on_face_expr_pressed(index: int) -> void:
	_cfg["face_expression"] = FACE_EXPRESSIONS[index]
	_refresh_ui_selection()
	_apply_config_to_preview(_cfg)


func _on_body_colour_pressed(index: int) -> void:
	_cfg["body_colour_index"] = index
	_refresh_ui_selection()
	_apply_config_to_preview(_cfg)


func _on_body_acc_pressed(index: int) -> void:
	_cfg["body_accessory"] = BODY_ACCESSORIES[index]
	_refresh_ui_selection()
	_apply_config_to_preview(_cfg)


func _on_leg_colour_pressed(index: int) -> void:
	_cfg["leg_colour_index"] = index
	_refresh_ui_selection()
	_apply_config_to_preview(_cfg)


func _on_leg_shoe_pressed(index: int) -> void:
	_cfg["leg_shoes"] = LEG_SHOES[index]
	_refresh_ui_selection()
	_apply_config_to_preview(_cfg)


func _on_hand_acc_pressed(index: int) -> void:
	_cfg["hand_accessory"] = HAND_ACCESSORIES[index]
	_refresh_ui_selection()
	_apply_config_to_preview(_cfg)


## Wire the CardRow TextureButtons (one per CARDS entry, by index) to the character
## selector. The chosen id is persisted to avatar.cfg "character" and loaded by builder.gd
## on spawn.
func _wire_cards() -> void:
	_card_buttons.clear()
	for i: int in CARD_BUTTONS.size():
		var node: Node = _find_node(CARD_BUTTONS[i])
		if node is TextureButton:
			var btn: TextureButton = node as TextureButton
			btn.pressed.connect(func() -> void: _on_character_pressed(i))
			_card_buttons.append(btn)


## Select a builder card: persist immediately (force-quit resilient) and re-render.
func _on_character_pressed(index: int) -> void:
	if index < 0 or index >= CARDS.size():
		return
	_cfg["character"] = str(CARDS[index].get("id", DEFAULT_CHARACTER))
	# Apply the card's signature look so each builder is visibly distinct (outfit colour,
	# hairstyle, skin + the satchel/bandolier driven by character). Players can override after.
	if CARDS[index].has("body"):
		_cfg["body_colour_index"] = int(CARDS[index]["body"])
	if CARDS[index].has("hair"):
		_cfg["head_shape"] = str(CARDS[index]["hair"])
	if CARDS[index].has("skin"):
		_cfg["skin_colour_index"] = int(CARDS[index]["skin"])
	_refresh_ui_selection()
	_write_avatar_cfg_silent()
	_apply_config_to_preview(_cfg)  # re-render the preview on base-figure change


# ─── Action handlers ──────────────────────────────────────────────────────────

## Done: write config to disk, push to Supabase (fire-and-forget), emit avatar_complete.
func _on_done_pressed() -> void:
	_write_avatar_cfg_silent()
	if is_instance_valid(FriendsClient):
		FriendsClient.save_avatar(_cfg)
	OnboardingTelemetry.log(OnboardingTelemetry.AVATAR_COMPLETE)
	avatar_complete.emit()
	_return_to_caller()


## Back: emit avatar_cancelled without saving.
func _on_back_pressed() -> void:
	avatar_cancelled.emit()
	_return_to_caller()


## Navigate back after Done/Back. The creator is loaded as a full scene (first launch and
## the title-screen "Customize Builder" button), so it must change scene itself — nothing
## else listens to avatar_complete/avatar_cancelled. Returns to the title screen.
func _return_to_caller() -> void:
	var title_path := "res://src/ui/title_scene.tscn"
	if ResourceLoader.exists(title_path):
		get_tree().change_scene_to_file(title_path)


# ─── Persistence ──────────────────────────────────────────────────────────────

## Write the current _cfg to user://avatar.cfg without emitting avatar_complete.
## Called on card tap for force-quit resilience.
func _write_avatar_cfg_silent() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value(AVATAR_SECTION, "character",         _cfg.get("character", DEFAULT_CHARACTER))
	cfg.set_value(AVATAR_SECTION, "skin_colour_index", _cfg.get("skin_colour_index", 0))
	cfg.set_value(AVATAR_SECTION, "head_shape",        _cfg.get("head_shape", "square"))
	cfg.set_value(AVATAR_SECTION, "face_expression",   _cfg.get("face_expression", "neutral"))
	cfg.set_value(AVATAR_SECTION, "body_colour_index", _cfg.get("body_colour_index", 6))
	cfg.set_value(AVATAR_SECTION, "body_accessory",    _cfg.get("body_accessory", "none"))
	cfg.set_value(AVATAR_SECTION, "leg_colour_index",  _cfg.get("leg_colour_index", 6))
	cfg.set_value(AVATAR_SECTION, "leg_shoes",         _cfg.get("leg_shoes", "none"))
	cfg.set_value(AVATAR_SECTION, "hand_accessory",    _cfg.get("hand_accessory", "none"))
	cfg.save(AVATAR_CFG_PATH)


## Load avatar config from user://avatar.cfg. Returns the default config if missing or corrupt.
func _load_avatar_cfg() -> Dictionary:
	var default: Dictionary = PRESETS[0].duplicate()
	var cfg := ConfigFile.new()
	if cfg.load(AVATAR_CFG_PATH) != OK:
		return default
	var loaded: Dictionary = {
		"character":         cfg.get_value(AVATAR_SECTION, "character", DEFAULT_CHARACTER),
		"skin_colour_index": cfg.get_value(AVATAR_SECTION, "skin_colour_index", 0),
		"head_shape":        cfg.get_value(AVATAR_SECTION, "head_shape", "square"),
		"face_expression":   cfg.get_value(AVATAR_SECTION, "face_expression", "neutral"),
		"body_colour_index": cfg.get_value(AVATAR_SECTION, "body_colour_index", 6),
		"body_accessory":    cfg.get_value(AVATAR_SECTION, "body_accessory", "none"),
		"leg_colour_index":  cfg.get_value(AVATAR_SECTION, "leg_colour_index", 6),
		"leg_shoes":         cfg.get_value(AVATAR_SECTION, "leg_shoes", "none"),
		"hand_accessory":    cfg.get_value(AVATAR_SECTION, "hand_accessory", "none"),
	}
	return loaded


# ─── 3D Preview ───────────────────────────────────────────────────────────────

## Apply avatar config to the SubViewport builder preview.
## Pre-06-07 compatibility path: directly sets the albedo colour of the primary
## MeshInstance3D nodes named "Body" and "Legs". Plan 06-07 upgrades this to
## Builder.apply_avatar_config() with full multi-part rendering.
func _apply_config_to_preview(cfg: Dictionary) -> void:
	if not is_instance_valid(_preview_builder):
		return
	var body_idx: int = int(cfg.get("body_colour_index", 6))
	var leg_idx: int  = int(cfg.get("leg_colour_index", 6))
	var skin_idx: int = int(cfg.get("skin_colour_index", 0))

	var body_colour: Color = BODY_COLOURS[clampi(body_idx, 0, BODY_COLOURS.size() - 1)]
	var leg_colour:  Color = BODY_COLOURS[clampi(leg_idx, 0, BODY_COLOURS.size() - 1)]
	var skin_colour: Color = SKIN_COLOURS[clampi(skin_idx, 0, SKIN_COLOURS.size() - 1)]

	# Prefer Builder.apply_avatar_config if available (Plan 06-07+).
	if _preview_builder.has_method("apply_avatar_config"):
		_preview_builder.apply_avatar_config(cfg)
		return

	# Pre-06-07 fallback: manipulate named MeshInstance3D children directly.
	_set_mesh_colour(_preview_builder, "Body", body_colour)
	_set_mesh_colour(_preview_builder, "Legs", leg_colour)
	_set_mesh_colour(_preview_builder, "Head", skin_colour)


## Set the albedo colour of a MeshInstance3D child of `parent` named `node_name`.
## Creates a local material override so the base resource is not mutated.
func _set_mesh_colour(parent: Node3D, node_name: String, colour: Color) -> void:
	var mesh_node: Node = parent.get_node_or_null(node_name)
	if not mesh_node is MeshInstance3D:
		return
	var mi: MeshInstance3D = mesh_node as MeshInstance3D
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = colour
	mi.material_override = mat


# ─── UI selection refresh ─────────────────────────────────────────────────────

## Sync all button selection highlights to the current _cfg values.
## Uses a 2px border override to show the active selection (accent yellow per UI-SPEC).
const COLOR_ACCENT: Color = Color("#F5C30D")
const BORDER_NONE:  int = 0
const BORDER_ACTIVE: int = 2


func _refresh_ui_selection() -> void:
	_refresh_card_selection(_character_index(str(_cfg.get("character", DEFAULT_CHARACTER))))
	_set_selected_index(_skin_buttons, int(_cfg.get("skin_colour_index", 0)))
	_set_selected_index(_head_shape_buttons, HEAD_SHAPES.find(str(_cfg.get("head_shape", "square"))))
	_set_selected_index(_face_expr_buttons, FACE_EXPRESSIONS.find(str(_cfg.get("face_expression", "neutral"))))
	_set_selected_index(_body_colour_buttons, int(_cfg.get("body_colour_index", 6)))
	_set_selected_index(_body_acc_buttons, BODY_ACCESSORIES.find(str(_cfg.get("body_accessory", "none"))))
	_set_selected_index(_leg_colour_buttons, int(_cfg.get("leg_colour_index", 6)))
	_set_selected_index(_leg_shoe_buttons, LEG_SHOES.find(str(_cfg.get("leg_shoes", "none"))))
	_set_selected_index(_hand_acc_buttons, HAND_ACCESSORIES.find(str(_cfg.get("hand_accessory", "none"))))


## Add a 2px accent-yellow border to the button at `active_index`, clear others.
func _set_selected_index(buttons: Array[Button], active_index: int) -> void:
	for i: int in buttons.size():
		var btn: Button = buttons[i]
		if i == active_index:
			btn.add_theme_color_override("font_outline_color", COLOR_ACCENT)
			btn.add_theme_constant_override("outline_size", BORDER_ACTIVE)
		else:
			btn.remove_theme_color_override("font_outline_color")
			btn.remove_theme_constant_override("outline_size")


## Build (once) a yellow accent glow StyleBox for the selected card frame.
func _card_glow_stylebox() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.137255, 0.211765, 0.345098, 1.0)  # matches SB_Card fill
	sb.border_width_left = 3
	sb.border_width_top = 3
	sb.border_width_right = 3
	sb.border_width_bottom = 3
	sb.border_color = COLOR_ACCENT
	sb.corner_radius_top_left = 10
	sb.corner_radius_top_right = 10
	sb.corner_radius_bottom_right = 10
	sb.corner_radius_bottom_left = 10
	return sb


## Toggle the yellow glow StyleBox on the card frame at `active_index`; clear others.
## The glow is drawn in-engine (never baked into the portrait texture) so it tracks selection.
func _refresh_card_selection(active_index: int) -> void:
	for i: int in CARD_FRAMES.size():
		var node: Node = _find_node(CARD_FRAMES[i])
		if not (node is PanelContainer):
			continue
		var frame: PanelContainer = node as PanelContainer
		if i == active_index:
			frame.add_theme_stylebox_override("panel", _card_glow_stylebox())
		else:
			frame.remove_theme_stylebox_override("panel")


## Index of the character id within CARDS (0 = default if unknown).
func _character_index(char_id: String) -> int:
	for i: int in CARDS.size():
		if str(CARDS[i].get("id", "")) == char_id:
			return i
	return 0


# ─── Private helpers ──────────────────────────────────────────────────────────

## Find the preview builder Node3D inside the SubViewport.
func _find_preview_builder() -> Node3D:
	var viewport: SubViewport = _find_node("AvatarSubViewport") as SubViewport
	if viewport == null:
		return null
	# Prefer the builder preview by name. NEVER return the first Node3D child — the
	# SubViewport also holds a DirectionalLight3D and Camera3D (both Node3D), and
	# grabbing the light here is what stopped the preview rotating / updating.
	var named: Node = viewport.get_node_or_null("BuilderPreview")
	if named is Node3D:
		return named as Node3D
	# Fallback: the node that actually exposes the avatar API.
	for child: Node in viewport.get_children():
		if child is Node3D and child.has_method("apply_avatar_config"):
			return child as Node3D
	return null


## Collect all Button children of a container node named `container_name`,
## searched recursively from the CanvasLayer root.
func _collect_buttons(container_name: String) -> Array[Button]:
	var result: Array[Button] = []
	var container: Node = _find_node(container_name)
	if container == null:
		return result
	for child: Node in container.get_children():
		if child is Button:
			result.append(child as Button)
	return result


## Find a node by name anywhere in the CanvasLayer subtree (BFS).
func _find_node(node_name: String) -> Node:
	return _find_node_recursive(self, node_name)


func _find_node_recursive(parent: Node, node_name: String) -> Node:
	for child: Node in parent.get_children():
		if child.name == node_name:
			return child
		var found: Node = _find_node_recursive(child, node_name)
		if found != null:
			return found
	return null
