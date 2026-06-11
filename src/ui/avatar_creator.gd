# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# avatar_creator.gd — AvatarCreator CanvasLayer (layer 10).
#
# Surface 2 of 06-UI-SPEC: 5-part customiser, 8 presets, Randomise,
# SubViewport 3D preview (256×256, 0.4 rad/s rotation), Done / Back buttons.
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

## 8 diverse preset configurations.
## Coverage: all 5 skin tones appear (0,1,2,3,4); varied head shapes, expressions, accessories.
const PRESETS: Array[Dictionary] = [
	# 0 — Classic (light skin, square, neutral, blue body, none/none, none)
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
	# 1 — Explorer (tan skin, round, happy, green body, backpack, brown legs, boots, pickaxe)
	{
		"skin_colour_index": 1,
		"head_shape": "round",
		"face_expression": "happy",
		"body_colour_index": 4,  # green
		"body_accessory": "backpack",
		"leg_colour_index": 0,  # red-brown substitute — red for now
		"leg_shoes": "boots",
		"hand_accessory": "pickaxe",
	},
	# 2 — Knight (medium skin, square, cool, red body, cape, red legs, boots, none)
	{
		"skin_colour_index": 2,
		"head_shape": "square",
		"face_expression": "cool",
		"body_colour_index": 0,  # red
		"body_accessory": "cape",
		"leg_colour_index": 0,
		"leg_shoes": "boots",
		"hand_accessory": "none",
	},
	# 3 — Ninja (dark skin, tall, cool, purple body, none, purple legs, sneakers, blank)
	{
		"skin_colour_index": 3,
		"head_shape": "tall",
		"face_expression": "cool",
		"body_colour_index": 7,  # purple
		"body_accessory": "none",
		"leg_colour_index": 7,
		"leg_shoes": "sneakers",
		"hand_accessory": "blank",
	},
	# 4 — Astronaut (deep skin, round, surprised, white body, backpack, white legs, none, none)
	{
		"skin_colour_index": 4,
		"head_shape": "round",
		"face_expression": "surprised",
		"body_colour_index": 9,  # white
		"body_accessory": "backpack",
		"leg_colour_index": 9,
		"leg_shoes": "none",
		"hand_accessory": "none",
	},
	# 5 — Rainbow (light skin, tall, happy, yellow body, none, lime legs, sneakers, flower)
	{
		"skin_colour_index": 0,
		"head_shape": "tall",
		"face_expression": "happy",
		"body_colour_index": 3,  # lime
		"body_accessory": "none",
		"leg_colour_index": 2,  # yellow
		"leg_shoes": "sneakers",
		"hand_accessory": "flower",
	},
	# 6 — Pirate (tan skin, square, surprised, orange body, cape, red legs, boots, pickaxe)
	{
		"skin_colour_index": 1,
		"head_shape": "square",
		"face_expression": "surprised",
		"body_colour_index": 1,  # orange
		"body_accessory": "cape",
		"leg_colour_index": 0,
		"leg_shoes": "boots",
		"hand_accessory": "pickaxe",
	},
	# 7 — Winter (medium skin, round, sleepy, teal body, none, teal legs, boots, lantern)
	{
		"skin_colour_index": 2,
		"head_shape": "round",
		"face_expression": "sleepy",
		"body_colour_index": 5,  # teal
		"body_accessory": "none",
		"leg_colour_index": 5,
		"leg_shoes": "boots",
		"hand_accessory": "lantern",
	},
]

## Path for avatar configuration persistence.
const AVATAR_CFG_PATH: String = "user://avatar.cfg"
## ConfigFile section name for avatar data.
const AVATAR_SECTION: String = "avatar"

## Selectable builder figures (the textured 3D base mesh + rig the world avatar uses).
## The "id" is written to avatar.cfg "character"; builder.gd loads the matching skin GLB
## (see Builder._AVATAR_SKINS) on spawn. Default is "builder1".
const CHARACTERS: Array[Dictionary] = [
	{"id": "builder1", "label": "Builder"},
	{"id": "red", "label": "Adventurer"},
	{"id": "fem", "label": "Explorer"},
]
const DEFAULT_CHARACTER: String = "builder1"

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
var _preset_buttons: Array[Button] = []
## Character (base figure) buttons — built programmatically in _ready.
var _character_buttons: Array[Button] = []

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
	_preset_buttons     = _collect_buttons("PresetGrid")

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
	for i: int in _preset_buttons.size():
		var btn: Button = _preset_buttons[i]
		btn.pressed.connect(func() -> void: _on_preset_pressed(i))

	# Build the Character (base figure) selector programmatically and insert it at the top
	# of the parts column so the chosen skin GLB is the first thing the player picks.
	_build_character_section()

	# Wire action buttons.
	var done_btn: Button = _find_node("DoneButton")
	if done_btn:
		done_btn.pressed.connect(_on_done_pressed)
	var back_btn: Button = _find_node("BackButton")
	if back_btn:
		back_btn.pressed.connect(_on_back_pressed)
	var rand_btn: Button = _find_node("RandomiseButton")
	if rand_btn:
		rand_btn.pressed.connect(_on_randomise_pressed)

	# Apply initial config to UI controls and preview.
	_refresh_ui_selection()
	_apply_config_to_preview(_cfg)


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


## Build the Character (base figure) selector section and insert it at the top of the
## parts column (VBoxParts). One button per CHARACTERS entry; the chosen id is persisted
## to avatar.cfg "character" and loaded by builder.gd on spawn.
func _build_character_section() -> void:
	var parts: Node = _find_node("VBoxParts")
	if parts == null:
		return
	var section := VBoxContainer.new()
	section.name = "CharacterSection"
	var label := Label.new()
	label.text = "Character"
	section.add_child(label)
	var row := HBoxContainer.new()
	row.name = "CharacterRow"
	section.add_child(row)
	for i: int in CHARACTERS.size():
		var btn := Button.new()
		btn.text = str(CHARACTERS[i].get("label", "?"))
		btn.custom_minimum_size = Vector2(96, 36)
		btn.pressed.connect(func() -> void: _on_character_pressed(i))
		row.add_child(btn)
		_character_buttons.append(btn)
	parts.add_child(section)
	parts.move_child(section, 0)  # top of the parts column


## Select a base figure: persist immediately (force-quit resilient) and highlight it.
func _on_character_pressed(index: int) -> void:
	if index < 0 or index >= CHARACTERS.size():
		return
	_cfg["character"] = str(CHARACTERS[index].get("id", DEFAULT_CHARACTER))
	_refresh_ui_selection()
	_write_avatar_cfg_silent()


# ─── Preset / Randomise ───────────────────────────────────────────────────────

## Apply preset configuration by index. Writes to disk immediately (fire-and-forget)
## so progress survives a force-quit.
func _on_preset_pressed(idx: int) -> void:
	if idx < 0 or idx >= PRESETS.size():
		return
	var keep_character: String = str(_cfg.get("character", DEFAULT_CHARACTER))
	_cfg = PRESETS[idx].duplicate()
	_cfg["character"] = keep_character  # presets style the appearance, not the base figure
	_refresh_ui_selection()
	_apply_config_to_preview(_cfg)
	_write_avatar_cfg_silent()


## Generate a random valid avatar configuration.
func _on_randomise_pressed() -> void:
	_cfg = {
		"character":         str(CHARACTERS[randi_range(0, CHARACTERS.size() - 1)].get("id", DEFAULT_CHARACTER)),
		"skin_colour_index": randi_range(0, SKIN_COLOURS.size() - 1),
		"head_shape":        HEAD_SHAPES[randi_range(0, HEAD_SHAPES.size() - 1)],
		"face_expression":   FACE_EXPRESSIONS[randi_range(0, FACE_EXPRESSIONS.size() - 1)],
		"body_colour_index": randi_range(0, BODY_COLOURS.size() - 1),
		"body_accessory":    BODY_ACCESSORIES[randi_range(0, BODY_ACCESSORIES.size() - 1)],
		"leg_colour_index":  randi_range(0, BODY_COLOURS.size() - 1),
		"leg_shoes":         LEG_SHOES[randi_range(0, LEG_SHOES.size() - 1)],
		"hand_accessory":    HAND_ACCESSORIES[randi_range(0, HAND_ACCESSORIES.size() - 1)],
	}
	_refresh_ui_selection()
	_apply_config_to_preview(_cfg)


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
## Called on preset tap for force-quit resilience.
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
	_set_selected_index(_character_buttons, _character_index(str(_cfg.get("character", DEFAULT_CHARACTER))))
	_set_selected_index(_skin_buttons, int(_cfg.get("skin_colour_index", 0)))
	_set_selected_index(_head_shape_buttons, HEAD_SHAPES.find(str(_cfg.get("head_shape", "square"))))
	_set_selected_index(_face_expr_buttons, FACE_EXPRESSIONS.find(str(_cfg.get("face_expression", "neutral"))))
	_set_selected_index(_body_colour_buttons, int(_cfg.get("body_colour_index", 6)))
	_set_selected_index(_body_acc_buttons, BODY_ACCESSORIES.find(str(_cfg.get("body_accessory", "none"))))
	_set_selected_index(_leg_colour_buttons, int(_cfg.get("leg_colour_index", 6)))
	_set_selected_index(_leg_shoe_buttons, LEG_SHOES.find(str(_cfg.get("leg_shoes", "none"))))
	_set_selected_index(_hand_acc_buttons, HAND_ACCESSORIES.find(str(_cfg.get("hand_accessory", "none"))))
	# Preset grid: highlight if current config matches any preset exactly.
	var active_preset: int = _find_matching_preset()
	_set_selected_index(_preset_buttons, active_preset)


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


## Index of the character id within CHARACTERS (0 = default if unknown).
func _character_index(char_id: String) -> int:
	for i: int in CHARACTERS.size():
		if str(CHARACTERS[i].get("id", "")) == char_id:
			return i
	return 0


## Return the index of the preset that matches _cfg exactly, or -1 if none matches.
func _find_matching_preset() -> int:
	for i: int in PRESETS.size():
		var p: Dictionary = PRESETS[i]
		var matches: bool = true
		for key: String in p.keys():
			if _cfg.get(key) != p.get(key):
				matches = false
				break
		if matches:
			return i
	return -1


# ─── Private helpers ──────────────────────────────────────────────────────────

## Find the preview builder Node3D inside the SubViewport.
func _find_preview_builder() -> Node3D:
	var viewport: SubViewport = _find_node("AvatarSubViewport") as SubViewport
	if viewport == null:
		return null
	# The first Node3D child that is the builder instance.
	for child: Node in viewport.get_children():
		if child is Node3D:
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
