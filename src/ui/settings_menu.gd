# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# settings_menu.gd - Settings screen controller.
#
# Per UI-SPEC.md §Settings Screen:
#   - Graphics section: 4 preset chips (Auto/Low/Medium/High) + detail rows + Reset button.
#   - Brick Packs section: shows Iap.get_products() or coming_later copy if empty.
#   - About section: version, license, about link.
#   - Done button closes the panel.
#
# Plan 04-07 extension:
#   - Players tab (Surface 6) injected as tab[0] when in-session.
#   - Settings tab holds the existing graphics/brickpacks/about content.
#   - Tab row (PlayersTabBtn + SettingsTabBtn) at the top of the VBox.
#   - Players tab content is hidden in solo sessions (NetworkManager.is_in_session() == false).
#
# Preset application (DOCS.md §7.2 Tier mapping):
#   Low:    render_distance=5, shadows=off, particle_density=low   (Tier-3)
#   Medium: render_distance=7, shadows=on,  particle_density=medium
#   High:   render_distance=9, shadows=on,  particle_density=high
#   Auto:   driven by ThermalProbe (defaults to Medium; adaptive quality in Plan 07)
#
# Plan 02-14 extensions to PRESET_DEFINITIONS (§7.6 adaptive-quality Phase 2 visuals):
#   Added keys per 02-PATTERNS.md §S-6 and 02-CONTEXT.md D-10/D-11/D-12:
#     ghost_preview_mode       — "transparent_mesh" (Tier-1/2) / "outline_only" (Tier-3)
#     palette_3d_previews      — "all" (Tier-1/2) / "on_tap" (Tier-3, D-12 fallback)
#     dynamite_particle_count  — 120 / 30 / 80 / 200 (per tier)
#     biome_ambient_blend_m    — 5.0 / 2.0 (blend distance for biome ambient tint, D-05)
#     rain_particle_density    — "high" / "low" / "medium" (T-14-03 mitigation)
#     sky_mode                 — "procedural" / "panorama" (Tier-3 Pitfall 11 fallback)
#
# _apply_live_settings dispatches all 6 new keys to running subsystems:
#   GhostPreview.set_mode("full"|"outline_only")      — Plan 02-09 setter (contract-guaranteed)
#   BrickPalette.set_previews_mode("3d_realtime"|"on_tap") — Plan 02-12 setter (contract-guaranteed)
#   main.dynamite_particle_count                       — int field on MainScene (Plan 02-14)
#   WorldEnvironment.environment.set_meta(...)         — biome ambient blend dispatch
#   RainParticles.amount                               — adaptive rain density
#   main.set_sky_mode("procedural"|"panorama_low")     — Plan 02-06 setter (contract-guaranteed)
#
# Persistence: user://settings.cfg [graphics] section.
# Live terrain: sets terrain bounds + shadows via scene references.

extends PanelContainer

# ─── Constants ────────────────────────────────────────────────────────────────

const SETTINGS_PATH := "user://settings.cfg"
const SECTION := "graphics"

# Preset tier definitions per DOCS.md §7.2 (Plan 02-14: extended with Phase 2 visual keys)
const PRESET_DEFINITIONS := {
	"auto": {
		"render_distance": 7,
		"shadows": "on",
		"particle_density": "medium",
		# Phase 2 visual subsystems (Plan 02-14, 02-PATTERNS.md §S-6):
		"ghost_preview_mode": "transparent_mesh",
		"palette_3d_previews": "all",
		"dynamite_particle_count": 120,
		"biome_ambient_blend_m": 5.0,
		"rain_particle_density": "high",
		"sky_mode": "procedural",
	},
	"low": {
		# Tier-3 (Motorola-class) — all Phase 2 subsystems fall back to reduced-cost modes.
		"render_distance": 5,
		"shadows": "off",
		"particle_density": "low",
		# D-10 fallback: outline_only shader instead of transparent mesh (Pitfall 10).
		"ghost_preview_mode": "outline_only",
		# D-12 fallback: static 3D preview rendered on tap only (Pitfall 12).
		"palette_3d_previews": "on_tap",
		# D-11 fallback: 30 dynamite particles (vs 120 at Tier-1) per biome budget.
		"dynamite_particle_count": 30,
		# Narrow biome blend zone: 2.0 m (vs 5.0 m at Tier-1) per CONTEXT.md D-05.
		"biome_ambient_blend_m": 2.0,
		# T-14-03 mitigation: only 100 rain particles at Tier-3 (amount set in _apply_live_settings).
		"rain_particle_density": "low",
		# Pitfall 11 mitigation: PanoramaSkyMaterial replaces procedural sky shader.
		"sky_mode": "panorama",
	},
	"medium": {
		"render_distance": 8,
		"shadows": "on",
		"particle_density": "medium",
		"ghost_preview_mode": "transparent_mesh",
		"palette_3d_previews": "all",
		"dynamite_particle_count": 80,
		"biome_ambient_blend_m": 5.0,
		"rain_particle_density": "medium",
		"sky_mode": "procedural",
	},
	"high": {
		"render_distance": 12,
		"shadows": "on",
		"particle_density": "high",
		"ghost_preview_mode": "transparent_mesh",
		"palette_3d_previews": "all",
		"dynamite_particle_count": 200,
		"biome_ambient_blend_m": 5.0,
		"rain_particle_density": "high",
		"sky_mode": "procedural",
	},
}

const COLOR_DESTRUCTIVE: Color = Color(0.839, 0.220, 0.157, 1.0)

## Accent yellow for the active tab underline indicator.
const COLOR_ACCENT: Color = Color(0.96, 0.76, 0.05, 1.0)

# ─── Node refs ────────────────────────────────────────────────────────────────

@onready var _chips_container: HBoxContainer = $VBox/SettingsContent/GraphicsSection/ChipsRow
@onready var _iap_label: Label = $VBox/SettingsContent/BrickPacksSection/ComingLaterLabel
@onready var _done_button: Button = $VBox/DoneButton
@onready var _reset_button: Button = $VBox/SettingsContent/GraphicsSection/ResetButton
@onready var _title_label: Label = $VBox/TitleLabel
@onready var _graphics_label: Label = $VBox/SettingsContent/GraphicsSection/GraphicsLabel
@onready var _brick_packs_label: Label = $VBox/SettingsContent/BrickPacksSection/BrickPacksLabel
@onready var _about_label: Label = $VBox/SettingsContent/AboutSection/AboutLabel
@onready var _about_button: Button = $VBox/SettingsContent/AboutSection/AboutButton

# Tab row buttons (Plan 04-07).
@onready var _players_tab_btn: Button = $VBox/TabRow/PlayersTabBtn
@onready var _settings_tab_btn: Button = $VBox/TabRow/SettingsTabBtn

# Tab content containers (Plan 04-07).
@onready var _players_content: VBoxContainer = $VBox/PlayersContent
@onready var _settings_content: VBoxContainer = $VBox/SettingsContent

# ─── State ────────────────────────────────────────────────────────────────────

var _active_preset: StringName = &"auto"
var _chips: Array = []

## Currently active tab: "players" or "settings".
var _active_tab: String = "settings"

# ─── Plan 05-09: Legal + Account section state ────────────────────────────────

## Username label in the Account section (updated after username change).
var _username_value_label: Label = null

## Inline username change form container (hidden when not editing).
var _username_form: VBoxContainer = null

## Username change form input.
var _username_line_edit: LineEdit = null

## Username change save button.
var _username_save_btn: Button = null

## Username validation timer (500ms debounce).
var _username_debounce_timer: Timer = null

## Account deletion pending label.
var _deletion_pending_label: Label = null

## Cancel deletion button.
var _cancel_deletion_btn: Button = null

## Whether the inline username form is expanded.
var _username_form_expanded: bool = false

## Tween for username form expand/collapse animation.
var _username_tween: Tween = null

# ─── Lifecycle ────────────────────────────────────────────────────────────────

func _ready() -> void:
	_setup_labels()
	_build_preset_chips()
	_update_iap_section()
	_setup_buttons()
	_load_saved_preset()
	_setup_tab_row()
	_inject_players_tab()
	_setup_language_section()
	_load_locale_pref()
	_setup_legal_section()
	_setup_account_section()


func _setup_labels() -> void:
	# Section headings are category names (Title-Cased per UI-SPEC Copywriting Contract tone)
	# populated at runtime so .tscn has no hardcoded English strings.
	_title_label.text = "Settings"
	_graphics_label.text = "Graphics"
	_brick_packs_label.text = tr("ui.settings.iap.title")
	_about_label.text = "About"
	if _about_button != null:
		_about_button.text = tr("ui.about.title")
		_about_button.pressed.connect(_on_about_pressed)


func _build_preset_chips() -> void:
	var preset_ids := ["auto", "low", "medium", "high"]
	var chip_scene := load("res://src/ui/preset_chip.tscn")
	for pid in preset_ids:
		var chip: Node
		if chip_scene != null:
			chip = chip_scene.instantiate()
		else:
			chip = Button.new()
		chip.name = (pid as String).capitalize()
		if "preset_id" in chip:
			chip.preset_id = pid
		if chip.has_method("set_active"):
			chip.set_active(pid == _active_preset)
		_chips_container.add_child(chip)
		_chips.append(chip)


func _update_iap_section() -> void:
	# DOC-00: show coming_later copy when IAP unavailable (Phase 1 always)
	if not Iap.is_available():
		_iap_label.text = tr("ui.settings.iap.coming_later")
	else:
		var products := Iap.get_products()
		if products.is_empty():
			_iap_label.text = tr("ui.settings.iap.coming_later")
		else:
			_iap_label.text = tr("ui.settings.iap.title")


func _setup_buttons() -> void:
	_done_button.text = tr("ui.common.done")
	_done_button.pressed.connect(_on_done_pressed)

	# Destructive styling for Reset button
	_reset_button.text = tr("ui.settings.graphics.reset")
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
	style.content_margin_left = 16.0
	style.content_margin_top = 10.0
	style.content_margin_right = 16.0
	style.content_margin_bottom = 10.0
	_reset_button.add_theme_stylebox_override("normal", style)
	_reset_button.add_theme_color_override("font_color", COLOR_DESTRUCTIVE)
	_reset_button.pressed.connect(_on_reset_pressed)


func _load_saved_preset() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		var saved: String = cfg.get_value(SECTION, "preset", "auto")
		_set_active_preset(saved as StringName)


# ─── Public API ──────────────────────────────────────────────────────────────

## Apply the given preset by name. Called by tests and by preset chip press.
## Writes to user://settings.cfg and applies live if terrain is reachable.
func apply_preset(preset_name: String) -> void:
	if not preset_name in PRESET_DEFINITIONS:
		push_warning("settings_menu: unknown preset '%s'" % preset_name)
		return

	var def: Dictionary = PRESET_DEFINITIONS[preset_name]
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)  # Load existing or start fresh
	cfg.set_value(SECTION, "preset", preset_name)
	cfg.set_value(SECTION, "render_distance", def["render_distance"])
	cfg.set_value(SECTION, "shadows", def["shadows"])
	cfg.set_value(SECTION, "particle_density", def["particle_density"])
	# Plan 02-14: persist Phase 2 visual subsystem values.
	cfg.set_value(SECTION, "ghost_preview_mode", def.get("ghost_preview_mode", "transparent_mesh"))
	cfg.set_value(SECTION, "palette_3d_previews", def.get("palette_3d_previews", "all"))
	cfg.set_value(SECTION, "dynamite_particle_count", def.get("dynamite_particle_count", 120))
	cfg.set_value(SECTION, "biome_ambient_blend_m", def.get("biome_ambient_blend_m", 5.0))
	cfg.set_value(SECTION, "rain_particle_density", def.get("rain_particle_density", "high"))
	cfg.set_value(SECTION, "sky_mode", def.get("sky_mode", "procedural"))
	cfg.save(SETTINGS_PATH)

	_set_active_preset(preset_name)
	_apply_live_settings(def)


# ─── Chip press handler ───────────────────────────────────────────────────────

func _on_preset_chip_pressed(preset_id: StringName) -> void:
	apply_preset(preset_id)


func _set_active_preset(preset_name: StringName) -> void:
	_active_preset = preset_name
	for chip in _chips:
		if chip.has_method("set_active") and "preset_id" in chip:
			chip.set_active(chip.preset_id == preset_name)


func _apply_live_settings(def: Dictionary) -> void:
	# Apply shadows to the DirectionalLight3D in main_scene if reachable
	var main := get_tree().get_root().get_node_or_null("Main")
	if main != null:
		var sun := main.get_node_or_null("Sun")
		if sun != null and sun is DirectionalLight3D:
			(sun as DirectionalLight3D).shadow_enabled = (def["shadows"] == "on")

		# Apply render distance to VoxelViewer
		var builder := main.get_node_or_null("Builder")
		if builder != null:
			var viewer := builder.get_node_or_null("VoxelViewer")
			if viewer != null:
				viewer.view_distance = def["render_distance"] * 16

		# ── Plan 02-14: Phase 2 visual subsystem dispatches ─────────────────────

		# (a) Ghost preview mode.
		# GhostPreview.set_mode("full"|"outline_only") — Plan 02-09 contract-guaranteed setter.
		# "full" = transparent mesh (transparent_mesh preset value); "outline_only" = Tier-3 fallback.
		var gp := main.get_node_or_null("GhostPreview")
		if gp != null:
			var ghost_mode: String = "outline_only" if def.get("ghost_preview_mode", "transparent_mesh") == "outline_only" else "full"
			gp.set_mode(ghost_mode)

		# (b) Palette 3D previews.
		# BrickPalette.set_previews_mode("3d_realtime"|"on_tap") — Plan 02-12 contract-guaranteed setter.
		var palette: Node = main.get_node_or_null("UI/BrickPaletteSidebar")
		if palette == null:
			palette = main.get_node_or_null("UI/BrickPaletteBottomsheet")
		if palette != null:
			var previews_mode: String = "on_tap" if def.get("palette_3d_previews", "all") == "on_tap" else "3d_realtime"
			palette.set_previews_mode(previews_mode)

		# (c) Dynamite particle count.
		# main.dynamite_particle_count is a public int that DynamiteHandler reads at light_fuse().
		main.set("dynamite_particle_count", def.get("dynamite_particle_count", 120))

		# (d) Biome ambient blend distance.
		# Store as metadata on WorldEnvironment.environment for the biome ambient shader to read.
		# The visual is bounded by Plan 15 acceptance; this dispatch ships the data (non-no-op: meta is set).
		var we := main.get_node_or_null("WorldEnvironment")
		if we != null and we.has_method("get") and we.environment != null:
			we.environment.set_meta("biome_ambient_blend_m", def.get("biome_ambient_blend_m", 5.0))

		# (e) Rain particle density.
		# RainParticles.amount drives the particle count; dict maps density string to amount.
		var rp: Node = main.get_node_or_null("Builder/Camera3D/RainParticles")
		if rp == null:
			rp = main.get_node_or_null("Builder/CameraPivot/SpringArm3D/ChaseCamera/RainParticles")
		if rp != null:
			var density_map: Dictionary = {"high": 500, "medium": 300, "low": 100}
			rp.set("amount", density_map.get(def.get("rain_particle_density", "medium"), 300))

		# (f) Sky mode.
		# main.set_sky_mode("procedural"|"panorama_low") — Plan 02-06 contract-guaranteed setter.
		# "panorama" preset value maps to "panorama_low" (Tier-3 PanoramaSkyMaterial).
		var sky_mode_val: String = def.get("sky_mode", "procedural")
		var sky_call_arg: String = "panorama_low" if sky_mode_val == "panorama" else "procedural"
		if main.has_method("set_sky_mode"):
			main.set_sky_mode(sky_call_arg)

		# Note: ui.settings.graphics_adjusted toast fires only when ThermalProbe triggers
		# adaptive quality demotion (via main_scene._on_thermal_throttled → Toasts.show).
		# It does NOT fire on every manual preset application — that would be noisy.
		# The toast key exists in en.po (Plan 02-14 Task 1) for completeness.


# ─── Tab row (Plan 04-07) ────────────────────────────────────────────────────

## Set up tab row buttons and wire their pressed signals.
## Players tab is visible only when NetworkManager.is_in_session() is true.
func _setup_tab_row() -> void:
	if _players_tab_btn == null or _settings_tab_btn == null:
		return

	_players_tab_btn.text = tr("ui.players.tab_label")
	_settings_tab_btn.text = tr("ui.players.settings_tab_label")

	_players_tab_btn.pressed.connect(_set_active_tab.bind("players"))
	_settings_tab_btn.pressed.connect(_set_active_tab.bind("settings"))

	# Determine which tab to show on open.
	var in_session: bool = is_instance_valid(NetworkManager) and NetworkManager.is_in_session()
	_players_tab_btn.visible = in_session

	if in_session:
		_set_active_tab("players")
	else:
		_set_active_tab("settings")


## Switch the visible tab. Applies accent-yellow underline to the active tab button.
func _set_active_tab(tab: String) -> void:
	_active_tab = tab
	_apply_tab_style(_players_tab_btn, tab == "players")
	_apply_tab_style(_settings_tab_btn, tab == "settings")

	var show_players: bool = (tab == "players")
	if _players_content != null:
		_players_content.visible = show_players
	if _settings_content != null:
		_settings_content.visible = not show_players


## Apply or remove the active-tab accent underline style on a tab button.
func _apply_tab_style(btn: Button, is_active: bool) -> void:
	if btn == null:
		return
	if is_active:
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.0, 0.0, 0.0, 0.0)  # transparent background
		style.border_width_bottom = 2
		style.border_color = COLOR_ACCENT
		btn.add_theme_stylebox_override("normal", style)
		btn.add_theme_color_override("font_color", COLOR_ACCENT)
	else:
		btn.remove_theme_stylebox_override("normal")
		btn.remove_theme_color_override("font_color")


## Instantiate PlayersTab and add it to the PlayersContent container.
func _inject_players_tab() -> void:
	if _players_content == null:
		return
	var players_tab_script: Script = load("res://src/ui/players_tab.gd")
	if players_tab_script == null:
		return
	var players_tab := VBoxContainer.new()
	players_tab.set_script(players_tab_script)
	players_tab.name = "PlayersTabInstance"
	_players_content.add_child(players_tab)
	_add_nameplate_toggle()


## Add "Show player names" checkbox to the settings content (Plan 04-08, Surface 8).
## Persists to user://settings.cfg [multiplayer] show_nameplates.
## Also propagates the change to all active remote nameplates via group lookup.
func _add_nameplate_toggle() -> void:
	if _settings_content == null:
		return
	var check := CheckBox.new()
	check.name = "ShowNameplatesCheck"
	check.text = tr("ui.settings.show_nameplates")
	# Load current preference (default true).
	var cfg := ConfigFile.new()
	var show: bool = true
	if cfg.load(SETTINGS_PATH) == OK:
		show = cfg.get_value("multiplayer", "show_nameplates", true)
	check.button_pressed = show
	check.toggled.connect(_on_nameplate_toggle)
	_settings_content.add_child(check)


func _on_nameplate_toggle(show: bool) -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("multiplayer", "show_nameplates", show)
	cfg.save(SETTINGS_PATH)
	# Apply to all active remote nameplates (group: "remote_nameplate").
	if is_instance_valid(get_tree()):
		for node: Node in get_tree().get_nodes_in_group("remote_nameplate"):
			node.visible = show


# ─── Plan 06-10: Language section ────────────────────────────────────────────

## Active locale button references so we can update the accent border on switch.
var _locale_btn_en: Button = null
var _locale_btn_nl: Button = null


## Add a "Language" section before the Legal section in SettingsContent.
## Two locale buttons (English / Nederlands) with accent-yellow border on active.
func _setup_language_section() -> void:
	if _settings_content == null:
		return

	# Separator above Language section.
	var sep := HSeparator.new()
	sep.name = "LangSep"
	_settings_content.add_child(sep)

	# Language section container.
	var section := VBoxContainer.new()
	section.name = "LanguageSection"
	_settings_content.add_child(section)

	# Section heading label.
	var heading := Label.new()
	heading.text = tr("ui.settings.language_label")
	heading.add_theme_font_size_override("font_size", 14)
	heading.add_theme_color_override("font_color", Color(0.945, 0.941, 0.918, 0.70))
	section.add_child(heading)

	# Button row.
	var btn_row := HBoxContainer.new()
	section.add_child(btn_row)

	# English button.
	_locale_btn_en = Button.new()
	_locale_btn_en.name = "LocaleEnBtn"
	_locale_btn_en.text = tr("ui.settings.locale_en")
	_locale_btn_en.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_locale_btn_en.pressed.connect(_on_locale_btn_pressed.bind("en"))
	btn_row.add_child(_locale_btn_en)

	# Nederlands button.
	_locale_btn_nl = Button.new()
	_locale_btn_nl.name = "LocaleNlBtn"
	_locale_btn_nl.text = tr("ui.settings.locale_nl")
	_locale_btn_nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_locale_btn_nl.pressed.connect(_on_locale_btn_pressed.bind("nl"))
	btn_row.add_child(_locale_btn_nl)


## Called when a locale button is pressed.
func _on_locale_btn_pressed(locale_code: String) -> void:
	_on_locale_changed(locale_code)
	_save_locale_pref(locale_code)


## Apply the new locale, update button styles, and propagate to all nodes.
func _on_locale_changed(locale_code: String) -> void:
	TranslationServer.set_locale(locale_code)
	_update_locale_btn_styles(locale_code)
	# Force all visible nodes to re-evaluate their tr() strings immediately.
	if is_instance_valid(get_tree()):
		get_tree().root.propagate_notification(NOTIFICATION_TRANSLATION_CHANGED)


## Update the accent-yellow border on the active locale button.
func _update_locale_btn_styles(active_locale: String) -> void:
	_apply_locale_btn_style(_locale_btn_en, active_locale == "en")
	_apply_locale_btn_style(_locale_btn_nl, active_locale == "nl")


## Apply or remove the active locale button accent border.
func _apply_locale_btn_style(btn: Button, is_active: bool) -> void:
	if btn == null:
		return
	if is_active:
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.0, 0.0, 0.0, 0.0)  # transparent
		style.border_width_left = 2
		style.border_width_top = 2
		style.border_width_right = 2
		style.border_width_bottom = 2
		style.border_color = COLOR_ACCENT
		style.corner_radius_top_left = 8
		style.corner_radius_top_right = 8
		style.corner_radius_bottom_left = 8
		style.corner_radius_bottom_right = 8
		btn.add_theme_stylebox_override("normal", style)
		btn.add_theme_color_override("font_color", COLOR_ACCENT)
	else:
		btn.remove_theme_stylebox_override("normal")
		btn.remove_theme_color_override("font_color")


## Save the locale preference to user://settings.cfg [settings] locale.
func _save_locale_pref(locale_code: String) -> void:
	# T-06-L1: validate locale code before persisting.
	if locale_code != "en" and locale_code != "nl":
		push_warning("settings_menu._save_locale_pref: invalid locale_code '%s'; ignoring." % locale_code)
		return
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)  # Load existing or start fresh.
	cfg.set_value("settings", "locale", locale_code)
	cfg.save(SETTINGS_PATH)


## Load the locale preference from user://settings.cfg and apply it.
## Called in _ready() so the button highlight reflects the current locale on open.
func _load_locale_pref() -> void:
	var cfg := ConfigFile.new()
	var saved_locale: String = "en"
	if cfg.load(SETTINGS_PATH) == OK:
		var raw: String = cfg.get_value("settings", "locale", "en")
		# T-06-L1: accept only "en" or "nl"; fall back to "en" for any other value.
		if raw == "en" or raw == "nl":
			saved_locale = raw
	_update_locale_btn_styles(saved_locale)


# ─── Plan 05-09: Legal section ───────────────────────────────────────────────

## Add a "Legal" section below the About section in SettingsContent.
## Two buttons: Terms of Use and Privacy Policy, both opening LegalViewer.
func _setup_legal_section() -> void:
	if _settings_content == null:
		return
	# Separator above Legal section.
	var sep := HSeparator.new()
	sep.name = "LegalSep"
	_settings_content.add_child(sep)

	# Legal section container.
	var section := VBoxContainer.new()
	section.name = "LegalSection"
	_settings_content.add_child(section)

	# Section heading label.
	var heading := Label.new()
	heading.text = tr("ui.settings.legal_section_title")
	heading.add_theme_font_size_override("font_size", 14)
	heading.add_theme_color_override("font_color", Color(0.945, 0.941, 0.918, 0.70))
	section.add_child(heading)

	# Terms of Use button.
	var terms_btn := Button.new()
	terms_btn.text = tr("ui.settings.terms_button")
	terms_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	terms_btn.pressed.connect(_on_terms_pressed)
	section.add_child(terms_btn)

	# Privacy Policy button.
	var privacy_btn := Button.new()
	privacy_btn.text = tr("ui.settings.privacy_button")
	privacy_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	privacy_btn.pressed.connect(_on_privacy_pressed)
	section.add_child(privacy_btn)


## Open the LegalViewer with the EULA document.
func _on_terms_pressed() -> void:
	_open_legal_viewer("eula")


## Open the LegalViewer with the Privacy Policy document.
func _on_privacy_pressed() -> void:
	_open_legal_viewer("privacy")


## Instantiate and show the LegalViewer for the given document type.
func _open_legal_viewer(doc_type: String) -> void:
	var viewer_scene: PackedScene = load("res://src/ui/legal_viewer.tscn")
	if viewer_scene == null:
		push_warning("settings_menu._open_legal_viewer: could not load legal_viewer.tscn")
		return
	var viewer: Node = viewer_scene.instantiate()
	get_tree().root.add_child(viewer)
	if viewer.has_method("open"):
		viewer.open(doc_type)


# ─── Plan 05-09: Account section ─────────────────────────────────────────────

## Add an "Account" section below the Legal section in SettingsContent.
## Shows username with change form (inline, animated), and delete account button.
## Only visible when FriendsClient.is_signed_in() is true.
func _setup_account_section() -> void:
	if _settings_content == null:
		return
	# Only show Account section when signed in.
	var fc: Node = get_node_or_null("/root/FriendsClient")
	if fc == null or not fc.has_method("is_signed_in") or not fc.is_signed_in():
		return

	# Separator above Account section.
	var sep := HSeparator.new()
	sep.name = "AccountSep"
	_settings_content.add_child(sep)

	# Account section container.
	var section := VBoxContainer.new()
	section.name = "AccountSection"
	_settings_content.add_child(section)

	# Section heading label.
	var heading := Label.new()
	heading.text = tr("ui.settings.account_section_title")
	heading.add_theme_font_size_override("font_size", 14)
	heading.add_theme_color_override("font_color", Color(0.945, 0.941, 0.918, 0.70))
	section.add_child(heading)

	# Username display label.
	_username_value_label = Label.new()
	var current_username: String = ""
	if fc.has_method("get_username"):
		current_username = fc.get_username()
	var username_template: String = tr("ui.settings.account_username_label")
	_username_value_label.text = username_template.replace("{current}", current_username)
	_username_value_label.add_theme_font_size_override("font_size", 16)
	_username_value_label.add_theme_color_override("font_color", Color(0.945, 0.941, 0.918, 1.0))
	_username_value_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	section.add_child(_username_value_label)

	# Determine change cooldown.
	var change_btn := Button.new()
	change_btn.name = "ChangeUsernameBtn"
	change_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# Check cooldown (UsernamePol.days_until_change_allowed — needs last_changed_at_unix).
	# For v1: check is disabled (0 days cooldown) since we don't yet cache the timestamp locally.
	# The server-side trigger is the hard gate.
	change_btn.text = tr("ui.settings.account_change_username")
	change_btn.pressed.connect(_toggle_username_form)
	section.add_child(change_btn)

	# Inline username change form (collapsed by default).
	_username_form = VBoxContainer.new()
	_username_form.name = "UsernameForm"
	_username_form.visible = false
	_username_form.custom_minimum_size = Vector2(0, 0)
	section.add_child(_username_form)

	_username_line_edit = LineEdit.new()
	_username_line_edit.placeholder_text = tr("ui.settings.account_change_username")
	_username_line_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_username_form.add_child(_username_line_edit)

	# Validation error label (hidden until there is an error).
	var validation_label := Label.new()
	validation_label.name = "ValidationLabel"
	validation_label.text = ""
	validation_label.add_theme_font_size_override("font_size", 14)
	validation_label.add_theme_color_override("font_color", COLOR_DESTRUCTIVE)
	validation_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	validation_label.visible = false
	_username_form.add_child(validation_label)

	# Debounce timer for 500ms inline validation.
	_username_debounce_timer = Timer.new()
	_username_debounce_timer.one_shot = true
	_username_debounce_timer.wait_time = 0.5
	_username_form.add_child(_username_debounce_timer)
	_username_debounce_timer.timeout.connect(_on_username_debounce_done.bind(validation_label))
	_username_line_edit.text_changed.connect(_on_username_text_changed)

	# Button row for Save / Cancel.
	var form_btns := HBoxContainer.new()
	_username_form.add_child(form_btns)

	_username_save_btn = Button.new()
	_username_save_btn.text = tr("ui.settings.account_change_save")
	_username_save_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_username_save_btn.disabled = true
	_username_save_btn.pressed.connect(_on_username_save_pressed.bind(validation_label))
	form_btns.add_child(_username_save_btn)

	var cancel_btn := Button.new()
	cancel_btn.text = tr("ui.settings.account_change_cancel")
	cancel_btn.custom_minimum_size = Vector2(120, 0)
	cancel_btn.pressed.connect(_toggle_username_form)
	form_btns.add_child(cancel_btn)

	# Connect FriendsClient username signals.
	if fc.has_signal("username_changed"):
		fc.username_changed.connect(_on_username_changed_ok)
	if fc.has_signal("username_change_failed"):
		fc.username_change_failed.connect(_on_username_change_failed.bind(validation_label))

	# Deletion pending state (shown if deletion was previously requested).
	_deletion_pending_label = Label.new()
	_deletion_pending_label.name = "DeletionPendingLabel"
	_deletion_pending_label.text = ""
	_deletion_pending_label.add_theme_font_size_override("font_size", 14)
	_deletion_pending_label.add_theme_color_override("font_color", Color(0.910, 0.537, 0.047, 1.0))  # warning amber
	_deletion_pending_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_deletion_pending_label.visible = false
	section.add_child(_deletion_pending_label)

	_cancel_deletion_btn = Button.new()
	_cancel_deletion_btn.name = "CancelDeletionBtn"
	_cancel_deletion_btn.text = tr("ui.settings.account_delete_cancel_action")
	_cancel_deletion_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cancel_deletion_btn.visible = false
	_cancel_deletion_btn.pressed.connect(_on_cancel_deletion_pressed)
	section.add_child(_cancel_deletion_btn)

	# Connect FriendsClient account deletion signals.
	if fc.has_signal("account_deletion_requested"):
		fc.account_deletion_requested.connect(_on_account_deletion_requested)
	if fc.has_signal("account_deletion_cancelled"):
		fc.account_deletion_cancelled.connect(_on_account_deletion_cancelled)

	# Delete account button (destructive).
	var delete_sep := HSeparator.new()
	section.add_child(delete_sep)

	var delete_btn := Button.new()
	delete_btn.name = "DeleteAccountBtn"
	delete_btn.text = tr("ui.settings.account_delete_button")
	delete_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Destructive styling: red fill.
	var del_style := StyleBoxFlat.new()
	del_style.bg_color = Color(0.839, 0.220, 0.157, 1.0)  # brick red
	del_style.corner_radius_top_left = 8
	del_style.corner_radius_top_right = 8
	del_style.corner_radius_bottom_left = 8
	del_style.corner_radius_bottom_right = 8
	del_style.content_margin_left = 16.0
	del_style.content_margin_top = 10.0
	del_style.content_margin_right = 16.0
	del_style.content_margin_bottom = 10.0
	delete_btn.add_theme_stylebox_override("normal", del_style)
	delete_btn.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))
	delete_btn.pressed.connect(_on_delete_account_pressed)
	section.add_child(delete_btn)


# ─── Username change form ─────────────────────────────────────────────────────

## Toggle the inline username change form open or closed (0.22s tween).
func _toggle_username_form() -> void:
	if _username_form == null:
		return
	_username_form_expanded = not _username_form_expanded
	# Kill any active tween before starting a new one.
	if _username_tween != null and _username_tween.is_valid():
		_username_tween.kill()
	_username_tween = create_tween()
	if _username_form_expanded:
		_username_form.visible = true
		_username_tween.tween_property(_username_form, "modulate:a", 1.0, 0.22).from(0.0)
		if _username_line_edit != null:
			_username_line_edit.grab_focus()
	else:
		_username_tween.tween_property(_username_form, "modulate:a", 0.0, 0.22)
		_username_tween.tween_callback(func() -> void:
			_username_form.visible = false
			if _username_line_edit != null:
				_username_line_edit.text = ""
			if _username_save_btn != null:
				_username_save_btn.disabled = true
		)


## Called when the username text changes — restart debounce timer.
func _on_username_text_changed(_new_text: String) -> void:
	if _username_debounce_timer != null:
		_username_debounce_timer.start()
	if _username_save_btn != null:
		_username_save_btn.disabled = true


## Called after 500ms debounce — validate format client-side.
func _on_username_debounce_done(validation_label: Label) -> void:
	if _username_line_edit == null:
		return
	var text: String = _username_line_edit.text
	# Use UsernamePol if available (class_name based access).
	var result: Dictionary = {}
	if ClassDB.class_exists("UsernamePol") or ResourceLoader.exists("res://src/autoload/username_policy.gd"):
		var policy_script: Script = load("res://src/autoload/username_policy.gd")
		if policy_script != null and policy_script.has_method("validate"):
			result = policy_script.call("validate", text)
	else:
		# Fallback: simple format check.
		var re := RegEx.new()
		re.compile("^[a-zA-Z0-9_]{3,20}$")
		result = {"valid": re.search(text) != null, "error_key": "ui.username.error_format"}

	var is_valid: bool = result.get("valid", false)
	if is_valid:
		if validation_label != null:
			validation_label.text = ""
			validation_label.visible = false
		if _username_save_btn != null:
			_username_save_btn.disabled = false
	else:
		var error_key: String = result.get("error_key", "ui.username.error_format")
		if validation_label != null:
			validation_label.text = tr(error_key)
			validation_label.visible = true
		if _username_save_btn != null:
			_username_save_btn.disabled = true


## Called when the Save button is pressed in the username change form.
func _on_username_save_pressed(validation_label: Label) -> void:
	if _username_line_edit == null:
		return
	var new_username: String = _username_line_edit.text.strip_edges()
	if new_username.is_empty():
		return
	# Disable save button while the request is in-flight.
	if _username_save_btn != null:
		_username_save_btn.disabled = true
	var fc: Node = get_node_or_null("/root/FriendsClient")
	if fc != null and fc.has_method("change_username"):
		fc.change_username(new_username)
	else:
		if validation_label != null:
			validation_label.text = tr("ui.signin.error_network")
			validation_label.visible = true


## Called when FriendsClient.username_changed fires (success).
func _on_username_changed_ok(new_username: String) -> void:
	# Update the displayed username label.
	if _username_value_label != null:
		var template: String = tr("ui.settings.account_username_label")
		_username_value_label.text = template.replace("{current}", new_username)
	# Collapse the form.
	_username_form_expanded = true  # so toggle goes to collapsed state
	_toggle_username_form()


## Called when FriendsClient.username_change_failed fires.
func _on_username_change_failed(reason: String, validation_label: Label) -> void:
	if _username_save_btn != null:
		_username_save_btn.disabled = false
	if validation_label == null:
		return
	match reason:
		"taken":
			validation_label.text = tr("ui.username.error_taken")
		"reserved":
			validation_label.text = tr("ui.username.error_reserved")
		"cooldown":
			validation_label.text = tr("ui.username.error_cooldown").replace("{n}", "30")
		"format":
			validation_label.text = tr("ui.username.error_format")
		_:
			validation_label.text = tr("ui.signin.error_network")
	validation_label.visible = true


# ─── Account deletion flow ────────────────────────────────────────────────────

## Show the "Delete your account?" confirmation modal on button press.
func _on_delete_account_pressed() -> void:
	_show_delete_account_modal()


## Build and show the delete account confirmation modal.
func _show_delete_account_modal() -> void:
	# Use a simple confirmation dialog with destructive styling.
	var overlay := ColorRect.new()
	overlay.color = Color(0.106, 0.173, 0.337, 0.70)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var cl := CanvasLayer.new()
	cl.layer = 25
	cl.add_child(overlay)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(400, 0)
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.106, 0.173, 0.337, 0.97)
	panel_style.corner_radius_top_left = 16
	panel_style.corner_radius_top_right = 16
	panel_style.corner_radius_bottom_left = 16
	panel_style.corner_radius_bottom_right = 16
	panel.add_theme_stylebox_override("panel", panel_style)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	overlay.add_child(panel)

	var vbox := VBoxContainer.new()
	panel.add_child(vbox)

	var top := Control.new()
	top.custom_minimum_size = Vector2(0, 24)
	vbox.add_child(top)

	var title := Label.new()
	title.text = tr("ui.settings.account_delete_title")
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", COLOR_DESTRUCTIVE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(title)

	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 16)
	vbox.add_child(gap)

	var body := Label.new()
	body.text = tr("ui.settings.account_delete_body")
	body.add_theme_font_size_override("font_size", 16)
	body.add_theme_color_override("font_color", Color(0.945, 0.941, 0.918, 0.80))
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(body)

	var gap2 := Control.new()
	gap2.custom_minimum_size = Vector2(0, 24)
	vbox.add_child(gap2)

	# Button row.
	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(btn_row)

	var confirm_btn := Button.new()
	confirm_btn.text = tr("ui.settings.account_delete_confirm")
	confirm_btn.custom_minimum_size = Vector2(200, 0)
	var c_style := StyleBoxFlat.new()
	c_style.bg_color = COLOR_DESTRUCTIVE
	c_style.corner_radius_top_left = 8
	c_style.corner_radius_top_right = 8
	c_style.corner_radius_bottom_left = 8
	c_style.corner_radius_bottom_right = 8
	c_style.content_margin_left = 16.0
	c_style.content_margin_top = 10.0
	c_style.content_margin_right = 16.0
	c_style.content_margin_bottom = 10.0
	confirm_btn.add_theme_stylebox_override("normal", c_style)
	confirm_btn.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	confirm_btn.pressed.connect(func() -> void:
		cl.queue_free()
		_do_request_account_deletion()
	)
	btn_row.add_child(confirm_btn)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(8, 0)
	btn_row.add_child(spacer)

	var cancel_btn := Button.new()
	cancel_btn.text = tr("ui.settings.account_delete_cancel")
	cancel_btn.custom_minimum_size = Vector2(200, 0)
	cancel_btn.pressed.connect(func() -> void:
		cl.queue_free()
	)
	btn_row.add_child(cancel_btn)

	var bottom := Control.new()
	bottom.custom_minimum_size = Vector2(0, 24)
	vbox.add_child(bottom)

	get_tree().root.add_child(cl)


## Call FriendsClient.request_account_deletion() and show pending state.
func _do_request_account_deletion() -> void:
	var fc: Node = get_node_or_null("/root/FriendsClient")
	if fc != null and fc.has_method("request_account_deletion"):
		fc.request_account_deletion()


## Called when FriendsClient.account_deletion_requested fires.
func _on_account_deletion_requested() -> void:
	# Show the pending deletion state with a cancellation option.
	if _deletion_pending_label != null:
		# Build a rough "cancels on {date}" string (now + 7 days).
		var cancel_unix: int = int(Time.get_unix_time_from_system()) + 7 * 86400
		var cancel_date: String = Time.get_date_string_from_unix_time(cancel_unix)
		var template: String = tr("ui.settings.account_delete_pending")
		_deletion_pending_label.text = template.replace("{date}", cancel_date)
		_deletion_pending_label.visible = true
	if _cancel_deletion_btn != null:
		_cancel_deletion_btn.visible = true


## Called when the "Cancel deletion" button is pressed.
func _on_cancel_deletion_pressed() -> void:
	var fc: Node = get_node_or_null("/root/FriendsClient")
	if fc != null and fc.has_method("cancel_account_deletion"):
		fc.cancel_account_deletion()


## Called when FriendsClient.account_deletion_cancelled fires.
func _on_account_deletion_cancelled() -> void:
	if _deletion_pending_label != null:
		_deletion_pending_label.visible = false
	if _cancel_deletion_btn != null:
		_cancel_deletion_btn.visible = false


# ─── Done button ─────────────────────────────────────────────────────────────

func _on_done_pressed() -> void:
	queue_free()


func _on_about_pressed() -> void:
	var about_scene: PackedScene = load("res://src/ui/about.tscn")
	if about_scene != null:
		var about: Node = about_scene.instantiate()
		get_parent().add_child(about)


# ─── Reset button ─────────────────────────────────────────────────────────────

func _on_reset_pressed() -> void:
	_show_reset_confirmation()


func _show_reset_confirmation() -> void:
	var dialog := AcceptDialog.new()
	dialog.title = tr("ui.settings.graphics.reset")
	dialog.dialog_text = tr("ui.settings.graphics.reset.confirm")
	dialog.ok_button_text = tr("ui.settings.graphics.reset.do")
	dialog.get_ok_button().add_theme_color_override("font_color", COLOR_DESTRUCTIVE)
	dialog.confirmed.connect(_on_reset_confirmed)
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered()


func _on_reset_confirmed() -> void:
	apply_preset("auto")
