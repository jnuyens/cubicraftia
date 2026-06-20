# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# title_scene.gd — Title screen controller (Surface 1 + Surface 6).
#
# This is the run/main_scene registered in project.godot (Phase 6, Plan 06-03).
# It is the first screen a player sees on every launch.
#
# Responsibilities:
#   1. Record telemetry "title_shown" event on every launch.
#   2. Connect to DeepLinkHandler.invite_token_received BEFORE reading
#      get_pending_token() to avoid the race where the signal already fired.
#   3. Show "Continue as {username}" when FriendsClient.is_signed_in() is true.
#   4. Open sign_in_panel.tscn (with back button) for Sign in / Create account.
#   5. Transition to world_select_screen for offline play or post-sign-in play.
#   6. Open settings_menu.tscn and legal_viewer.tscn from footer buttons.
#   7. Animate logo alpha-in over 2 seconds (TRANS_SINE ease-in-out).
#   8. Drive UV-pan shader on background TextureRect each frame.
#   9. Handle deep-link invite tokens: signed-in path and abbreviated sign-in path.
#  10. Write user://ftue.cfg markers for invite joiners (joined_via_invite, pending_ftue_complete).
#  11. Log telemetry events: title_shown, deep_link_received, signup_started,
#      signup_complete, signin_complete, invite_joined.
#
# Security:
#   T-06-T1: deep-link token delegated to DeepLinkHandler for length check;
#             redemption enforced server-side by FriendsClient.redeem_invite().
#   T-06-S2: username shown from FriendsClient._cached_username (JWT-validated).
#   T-06-T2: pending_ftue_complete applied only after peer_connected fires
#            (world belongs to the host who accepted the invite).
#
# References:
#   06-UI-SPEC.md Surface 1 + Surface 6
#   06-03-PLAN.md Task 2
#   06-08-PLAN.md Task 1

class_name TitleScene
extends CanvasLayer

# ─── Node refs (resolved at runtime from scene tree) ─────────────────────────

## TextureRect with title_bg_pan ShaderMaterial — driven by _process.
var _bg_rect: TextureRect = null

## ShaderMaterial instance from _bg_rect. Cached to avoid re-fetch each frame.
var _bg_material: ShaderMaterial = null

## Logo label — alpha tweened from 0 → 1 on open.
var _logo_label: Control = null   # Either a Label (legacy fallback) or a TextureRect (designed wordmark) — both Control subclasses so the modulate.a fade-in works on either.

## Tagline label beneath the logo.
var _tagline_label: Label = null

## VBoxContainer holding all action buttons.
var _button_stack: VBoxContainer = null

## "Continue as {username}" — only visible when signed in.
var _continue_button: Button = null

## "Sign in" button.
var _sign_in_button: Button = null

## "Create account" button.
var _create_account_button: Button = null

## "Continue offline" button.
var _continue_offline_button: Button = null

## "Settings" button.
var _settings_button: Button = null

## "Customize builder" button — re-opens the avatar creator so returning players (who
## already have an avatar.cfg and skip the first-launch creator) can change their skin/parts.
var _customize_button: Button = null

## Content column (logo + buttons). Hidden during deep-link handling.
var _content_column: VBoxContainer = null

## "Joining…" label shown when a deep-link token is received.
var _joining_label: Label = null

## Legal footer HBox.
var _footer_hbox: HBoxContainer = null

## Version label.
var _version_label: Label = null

## AudioStreamPlayer for title music (stream=null; autoplay when OGG is placed).
var _music_player: AudioStreamPlayer = null

## Currently open overlay (sign_in_panel, settings, legal_viewer). Kept to allow
## back-navigation and to prevent duplicate opens.
var _open_overlay: Node = null

## Stored pending invite token — preserved across the inline sign-in flow so
## _on_inline_sign_in_complete() can pick it up after sign-in finishes.
var _pending_invite_token: String = ""

## Inline sign-in overlay used in the abbreviated (invite-joiner) sign-in path.
## Separate from _open_overlay so the deep-link and normal sign-in paths don't
## conflict when both code paths try to set _open_overlay.
var _inline_sign_in_overlay: Node = null

# ─── Path constants ───────────────────────────────────────────────────────────

## Path to the per-user FTUE / invite state config file.
const _FTUE_CFG_PATH: String = "user://ftue.cfg"

## ConfigFile section for FTUE and invite state flags.
const _FTUE_SECTION: String = "state"

# ─── Lifecycle ────────────────────────────────────────────────────────────────

func _ready() -> void:
	# 1. Telemetry — must happen before any early-return.
	OnboardingTelemetry.log(OnboardingTelemetry.TITLE_SHOWN)

	# 2. Build UI programmatically (no child nodes in .tscn root — all in script).
	_build_ui()

	# 3. Deep-link wiring: connect FIRST, then consume to handle race condition
	#    where DeepLinkHandler._ready() fired before our _ready() connected.
	DeepLinkHandler.invite_token_received.connect(_handle_invite_deep_link)
	var pending: String = DeepLinkHandler.consume_pending_token()
	if not pending.is_empty():
		# Token already waiting — skip normal title flow.
		_handle_invite_deep_link(pending)
		return

	# 4. Wire FriendsClient telemetry signals (signup_complete, signin_complete).
	var fc: Node = get_node_or_null("/root/FriendsClient")
	if fc != null:
		if fc.has_signal("sign_up_ok") and not fc.sign_up_ok.is_connected(_on_sign_up_ok_telemetry):
			fc.sign_up_ok.connect(_on_sign_up_ok_telemetry)
		if fc.has_signal("signed_in") and not fc.signed_in.is_connected(_on_signed_in_telemetry):
			fc.signed_in.connect(_on_signed_in_telemetry)

	# 5. Invite-joiner return-visit shortcut: if joined_via_invite=true AND signed in,
	#    skip title animations and go directly to world_select_screen.
	if _check_ftue_marker_on_ready():
		return

	# 6. Session restore: show "Continue as {username}" when signed in.
	if FriendsClient.is_signed_in():
		if _continue_button != null:
			_continue_button.visible = true
			var username: String = FriendsClient.get_username()
			_continue_button.text = tr("ui.title.continue").format({"username": username})

	# 7. Logo + button-stack alpha-in tween.
	if _logo_label != null:
		_logo_label.modulate.a = 0.0
	if _button_stack != null:
		_button_stack.modulate.a = 0.0

	var tw := create_tween()
	tw.tween_property(_logo_label, "modulate:a", 1.0, 2.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_interval(0.5)
	tw.tween_property(_button_stack, "modulate:a", 1.0, 0.5)


func _process(delta: float) -> void:
	# Animate UV-pan shader on background TextureRect.
	if _bg_material != null:
		var current: Vector2 = _bg_material.get_shader_parameter("uv_offset")
		_bg_material.set_shader_parameter("uv_offset", current + Vector2(0.002, 0.0) * delta)


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if _open_overlay != null:
			_close_overlay()
			get_viewport().set_input_as_handled()
		elif OS.has_feature("pc"):
			# Godot 4 API: get_tree().quit(). OS.request_quit() does not exist.
			get_tree().quit()
			get_viewport().set_input_as_handled()

# ─── UI construction ──────────────────────────────────────────────────────────

func _build_ui() -> void:
	# Background TextureRect with UV-pan shader.
	_bg_rect = TextureRect.new()
	_bg_rect.name = "BgRect"
	_bg_rect.layout_mode = 1
	_bg_rect.anchors_preset = 15
	_bg_rect.anchor_right = 1.0
	_bg_rect.anchor_bottom = 1.0
	_bg_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_bg_rect.stretch_mode = TextureRect.STRETCH_TILE
	_bg_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Load title brick-vista background.
	for bg_tex_path: String in [
		"res://assets/textures/icons/title_bg.png",          # hero composition art
	]:
		if ResourceLoader.exists(bg_tex_path):
			_bg_rect.texture = load(bg_tex_path)
			# The hero vista is composed art (not seamlessly tileable) — use
			# KEEP_ASPECT_CENTERED so the painting reads correctly; the shader
			# pan still gives subtle motion across the unmasked edges.
			_bg_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
			break

	# Attach UV-pan shader material.
	var shader_path := "res://src/shaders/title_bg_pan.gdshader"
	if ResourceLoader.exists(shader_path):
		var shader: Shader = load(shader_path)
		_bg_material = ShaderMaterial.new()
		_bg_material.shader = shader
		_bg_material.set_shader_parameter("uv_offset", Vector2(0.0, 0.0))
		_bg_rect.material = _bg_material
	add_child(_bg_rect)

	# Semi-transparent navy overlay to ensure text readability over the brick texture.
	var overlay := ColorRect.new()
	overlay.name = "Overlay"
	overlay.layout_mode = 1
	overlay.anchors_preset = 15
	overlay.anchor_right = 1.0
	overlay.anchor_bottom = 1.0
	overlay.color = Color(0.106, 0.173, 0.337, 0.72)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(overlay)

	# Content column: centred, max 480px wide, positioned at ~20% from top.
	_content_column = VBoxContainer.new()
	_content_column.name = "ContentColumn"
	_content_column.layout_mode = 1
	_content_column.anchor_left = 0.5
	_content_column.anchor_right = 0.5
	_content_column.anchor_top = 0.18
	_content_column.anchor_bottom = 0.85
	_content_column.offset_left = -240.0
	_content_column.offset_right = 240.0
	_content_column.add_theme_constant_override("separation", 24)
	add_child(_content_column)

	# Logo — prefer the designed wordmark texture if present, else fall back
	# to the 96 px Label (UI-SPEC Surface 1 exception size).
	var wordmark_path := "res://assets/textures/icons/cubicraftia_wordmark.png"
	if ResourceLoader.exists(wordmark_path):
		var wordmark_rect := TextureRect.new()
		wordmark_rect.name = "WordmarkRect"
		wordmark_rect.texture = load(wordmark_path)
		wordmark_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		wordmark_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		wordmark_rect.custom_minimum_size = Vector2(420, 210)
		wordmark_rect.modulate.a = 0.0
		_logo_label = wordmark_rect as Control   # kept for the fade-in tween reference
		_content_column.add_child(wordmark_rect)
	else:
		_logo_label = Label.new()
		_logo_label.name = "LogoLabel"
		(_logo_label as Label).text = "Cubicraftia"
		(_logo_label as Label).add_theme_font_size_override("font_size", 96)
		(_logo_label as Label).add_theme_color_override("font_color", Color(0.961, 0.765, 0.051, 1.0))
		(_logo_label as Label).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_logo_label.modulate.a = 0.0
		_content_column.add_child(_logo_label)

	# Hero portrait — pinned to the right edge of the screen as a decorative
	# overlay. Falls through if the asset isn't present.
	var hero_path := "res://assets/textures/icons/title_character.png"
	if ResourceLoader.exists(hero_path):
		var hero_rect := TextureRect.new()
		hero_rect.name = "HeroPortrait"
		hero_rect.texture = load(hero_path)
		hero_rect.expand_mode = TextureRect.EXPAND_FIT_HEIGHT_PROPORTIONAL
		hero_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		hero_rect.layout_mode = 1
		hero_rect.anchor_left = 0.72
		hero_rect.anchor_top = 0.18
		hero_rect.anchor_right = 1.0
		hero_rect.anchor_bottom = 0.98
		hero_rect.offset_right = -16
		hero_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(hero_rect)

	# Tagline label.
	_tagline_label = Label.new()
	_tagline_label.name = "TaglineLabel"
	_tagline_label.text = tr("ui.title.tagline")
	_tagline_label.add_theme_font_size_override("font_size", 20)
	_tagline_label.add_theme_color_override("font_color", Color(0.945, 0.941, 0.918, 0.85))
	_tagline_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_content_column.add_child(_tagline_label)

	# Button stack.
	_button_stack = VBoxContainer.new()
	_button_stack.name = "ButtonStack"
	_button_stack.add_theme_constant_override("separation", 16)
	_button_stack.modulate.a = 0.0
	_content_column.add_child(_button_stack)

	# "Continue as {username}" — hidden by default; shown when signed in.
	_continue_button = Button.new()
	_continue_button.name = "ContinueButton"
	_continue_button.text = tr("ui.title.continue").format({"username": ""})
	_continue_button.visible = false
	_continue_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var continue_style := StyleBoxFlat.new()
	continue_style.bg_color = Color(0.961, 0.765, 0.051, 1.0)
	continue_style.corner_radius_top_left = 8
	continue_style.corner_radius_top_right = 8
	continue_style.corner_radius_bottom_left = 8
	continue_style.corner_radius_bottom_right = 8
	continue_style.content_margin_left = 16.0
	continue_style.content_margin_top = 10.0
	continue_style.content_margin_right = 16.0
	continue_style.content_margin_bottom = 10.0
	_continue_button.add_theme_stylebox_override("normal", continue_style)
	_continue_button.add_theme_color_override("font_color", Color(0.106, 0.173, 0.337, 1.0))
	_button_stack.add_child(_continue_button)

	# "Sign in" button.
	_sign_in_button = Button.new()
	_sign_in_button.name = "SignInButton"
	_sign_in_button.text = tr("ui.title.sign_in")
	_sign_in_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_button_stack.add_child(_sign_in_button)

	# "Create account" button.
	_create_account_button = Button.new()
	_create_account_button.name = "CreateAccountButton"
	_create_account_button.text = tr("ui.title.create_account")
	_create_account_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_button_stack.add_child(_create_account_button)

	# "Continue offline" button — secondary style.
	_continue_offline_button = Button.new()
	_continue_offline_button.name = "ContinueOfflineButton"
	_continue_offline_button.text = tr("ui.title.continue_offline")
	_continue_offline_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var secondary_style := StyleBoxFlat.new()
	secondary_style.bg_color = Color(0, 0, 0, 0)
	secondary_style.border_width_left = 1
	secondary_style.border_width_top = 1
	secondary_style.border_width_right = 1
	secondary_style.border_width_bottom = 1
	secondary_style.border_color = Color(0.945, 0.941, 0.918, 0.80)
	secondary_style.corner_radius_top_left = 8
	secondary_style.corner_radius_top_right = 8
	secondary_style.corner_radius_bottom_left = 8
	secondary_style.corner_radius_bottom_right = 8
	secondary_style.content_margin_left = 16.0
	secondary_style.content_margin_top = 10.0
	secondary_style.content_margin_right = 16.0
	secondary_style.content_margin_bottom = 10.0
	_continue_offline_button.add_theme_stylebox_override("normal", secondary_style)
	_button_stack.add_child(_continue_offline_button)

	# "Settings" button — secondary style.
	_settings_button = Button.new()
	_settings_button.name = "SettingsButton"
	_settings_button.text = tr("ui.title.settings")
	_settings_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_settings_button.add_theme_stylebox_override("normal", secondary_style)
	_button_stack.add_child(_settings_button)

	# "Customize builder" — secondary style. Always available so returning players can
	# re-open the avatar creator (otherwise it only appears on first launch).
	_customize_button = Button.new()
	_customize_button.name = "CustomizeButton"
	_customize_button.text = tr("ui.title.customize")
	_customize_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_customize_button.add_theme_stylebox_override("normal", secondary_style)
	_button_stack.add_child(_customize_button)

	# "Joining…" label — hidden initially; shown during deep-link handling.
	_joining_label = Label.new()
	_joining_label.name = "JoiningLabel"
	_joining_label.text = tr("ui.title.joining")
	_joining_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_joining_label.add_theme_font_size_override("font_size", 20)
	_joining_label.add_theme_color_override("font_color", Color(0.945, 0.941, 0.918, 1.0))
	_joining_label.visible = false
	add_child(_joining_label)

	# Legal footer — anchored to bottom-left.
	_footer_hbox = HBoxContainer.new()
	_footer_hbox.name = "FooterHBox"
	_footer_hbox.layout_mode = 1
	_footer_hbox.anchor_left = 0.0
	_footer_hbox.anchor_top = 1.0
	_footer_hbox.anchor_right = 0.5
	_footer_hbox.anchor_bottom = 1.0
	_footer_hbox.offset_top = -40.0
	_footer_hbox.add_theme_constant_override("separation", 12)
	add_child(_footer_hbox)

	var eula_button := Button.new()
	eula_button.name = "EulaButton"
	eula_button.text = tr("ui.title.eula")
	eula_button.flat = true
	eula_button.add_theme_font_size_override("font_size", 12)
	eula_button.add_theme_color_override("font_color", Color(0.945, 0.941, 0.918, 0.6))
	eula_button.pressed.connect(_on_eula_pressed)
	_footer_hbox.add_child(eula_button)

	var privacy_button := Button.new()
	privacy_button.name = "PrivacyButton"
	privacy_button.text = tr("ui.title.privacy")
	privacy_button.flat = true
	privacy_button.add_theme_font_size_override("font_size", 12)
	privacy_button.add_theme_color_override("font_color", Color(0.945, 0.941, 0.918, 0.6))
	privacy_button.pressed.connect(_on_privacy_pressed)
	_footer_hbox.add_child(privacy_button)

	# Version label — anchored to bottom-right.
	_version_label = Label.new()
	_version_label.name = "VersionLabel"
	# Show the real build identifier on the opening screen (and console via BuildInfo)
	# so it is always clear which build is running. A clean version string ("v1.0")
	# is shown only for a tagged major release.
	_version_label.text = "v1.0" if BuildInfo.IS_MAJOR_RELEASE else "build " + BuildInfo.version_string()
	_version_label.layout_mode = 1
	_version_label.anchor_left = 1.0
	_version_label.anchor_top = 1.0
	_version_label.anchor_right = 1.0
	_version_label.anchor_bottom = 1.0
	_version_label.offset_left = -240.0
	_version_label.offset_top = -36.0
	_version_label.add_theme_font_size_override("font_size", 12)
	_version_label.add_theme_color_override("font_color", Color(0.945, 0.941, 0.918, 0.5))
	_version_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(_version_label)

	# Music player — stream=null avoids crash when OGG not yet in project.
	_music_player = AudioStreamPlayer.new()
	_music_player.name = "MusicPlayer"
	_music_player.volume_db = -6.0
	_music_player.autoplay = true
	var music_path := "res://assets/audio/title_loop.ogg"
	if ResourceLoader.exists(music_path):
		var music_stream: AudioStream = load(music_path)
		# Loop the title track (OGG import may default loop off).
		if music_stream is AudioStreamOggVorbis:
			(music_stream as AudioStreamOggVorbis).loop = true
		_music_player.stream = music_stream
	add_child(_music_player)

	# Wire button signals.
	_continue_button.pressed.connect(_on_continue_pressed)
	_sign_in_button.pressed.connect(_on_sign_in_pressed.bind(false))
	_create_account_button.pressed.connect(_on_sign_in_pressed.bind(true))
	_continue_offline_button.pressed.connect(_on_continue_offline_pressed)
	_settings_button.pressed.connect(_on_settings_pressed)
	_customize_button.pressed.connect(_show_avatar_creator)

# ─── Button handlers ──────────────────────────────────────────────────────────

## "Continue as {username}" — player is already signed in; go to avatar check.
func _on_continue_pressed() -> void:
	_check_avatar_then_world_select()


## "Sign in" (create_account_mode=false) or "Create account" (create_account_mode=true).
func _on_sign_in_pressed(create_account_mode: bool) -> void:
	if _open_overlay != null:
		return  # Prevent duplicate open.

	# Telemetry: log signup_started when the user explicitly opens Create Account.
	if create_account_mode:
		OnboardingTelemetry.log(OnboardingTelemetry.SIGNUP_STARTED)

	var panel_scene: PackedScene = load("res://src/ui/sign_in_panel.tscn")
	if panel_scene == null:
		push_warning("title_scene: could not load sign_in_panel.tscn")
		return

	var panel: Node = panel_scene.instantiate()

	# Set back button and tab pre-selection via the properties added in this plan.
	if panel.has_method("set") and "show_back_button" in panel:
		panel.show_back_button = true
	if create_account_mode and panel.has_method("set_create_account_mode"):
		panel.set_create_account_mode(true)

	# Wire signals.
	if panel.has_signal("sign_in_complete"):
		panel.sign_in_complete.connect(_on_sign_in_panel_complete)
	if panel.has_signal("back_to_title_requested"):
		panel.back_to_title_requested.connect(_on_sign_in_panel_back_to_title)
	if panel.has_signal("under_13_signup_required"):
		panel.under_13_signup_required.connect(_on_under_13_signup_required)

	# Open on a higher CanvasLayer so it covers the title.
	var overlay_layer := CanvasLayer.new()
	overlay_layer.name = "SignInOverlay"
	overlay_layer.layer = 10
	overlay_layer.add_child(panel)
	add_child(overlay_layer)
	_open_overlay = overlay_layer


## "Continue offline" — go to world_select_screen without signing in.
func _on_continue_offline_pressed() -> void:
	_show_world_select(true)


## "Settings" — open settings_menu.tscn above title.
func _on_settings_pressed() -> void:
	if _open_overlay != null:
		return
	var settings_scene: PackedScene = load("res://src/ui/settings_menu.tscn")
	if settings_scene == null:
		push_warning("title_scene: could not load settings_menu.tscn")
		return
	var settings: Node = settings_scene.instantiate()
	var overlay_layer := CanvasLayer.new()
	overlay_layer.name = "SettingsOverlay"
	overlay_layer.layer = 10
	overlay_layer.add_child(settings)
	add_child(overlay_layer)
	_open_overlay = overlay_layer
	# If settings_menu emits a close/back signal, connect it.
	if settings.has_signal("close_requested"):
		settings.close_requested.connect(_close_overlay)


## Legal EULA link.
func _on_eula_pressed() -> void:
	_open_legal_viewer("eula")


## Legal privacy link.
func _on_privacy_pressed() -> void:
	_open_legal_viewer("privacy")

# ─── Sign-in panel signal handlers ───────────────────────────────────────────

## sign_in_panel emitted sign_in_complete — check avatar, then go to world_select.
func _on_sign_in_panel_complete() -> void:
	_close_overlay()
	_check_avatar_then_world_select()


## sign_in_panel emitted back_to_title_requested — remove the overlay.
func _on_sign_in_panel_back_to_title() -> void:
	_close_overlay()


## Under-13 signup: sign_in_panel delegates to parental_gate_panel (Plan 05-03).
func _on_under_13_signup_required() -> void:
	_close_overlay()
	var pg_scene: PackedScene = load("res://src/ui/parental_gate_panel.tscn")
	if pg_scene == null:
		return
	var pg: Node = pg_scene.instantiate()
	var overlay_layer := CanvasLayer.new()
	overlay_layer.name = "ParentalGateOverlay"
	overlay_layer.layer = 10
	overlay_layer.add_child(pg)
	add_child(overlay_layer)
	_open_overlay = overlay_layer

# ─── Deep-link handling (Surface 6) ──────────────────────────────────────────

## Called when DeepLinkHandler emits invite_token_received, or immediately in
## _ready() if consume_pending_token() returned a non-empty string (race fix).
##
## Flow (06-CONTEXT.md Area 5):
##   - Hides title UI, shows brief "Connecting..." toast.
##   - If signed in  → _redeem_invite_and_join(token) immediately.
##   - If not signed → show abbreviated sign-in (email+password+DOB only).
##     On sign-in complete → _redeem_invite_and_join(token).
func _handle_invite_deep_link(token: String) -> void:
	OnboardingTelemetry.log(OnboardingTelemetry.DEEP_LINK_RECEIVED)
	_pending_invite_token = token

	if _content_column != null:
		_content_column.visible = false
	if _joining_label != null:
		_joining_label.visible = true

	# Brief "Connecting..." feedback so the screen is never blank.
	var toasts: Node = get_node_or_null("/root/Toasts")
	if toasts != null and toasts.has_method("show"):
		toasts.call("show", tr("ui.deeplink.connecting"), 2.0)

	if FriendsClient.is_signed_in():
		_redeem_invite_and_join(token)
	else:
		_show_inline_sign_in_for_invite(token)


## Show a compact abbreviated sign-in panel for invite joiners.
## Uses set_abbreviated_mode(true) to hide the tab bar and extra fields.
## On sign-in complete, resumes _redeem_invite_and_join(token).
func _show_inline_sign_in_for_invite(token: String) -> void:
	var panel_scene: PackedScene = load("res://src/ui/sign_in_panel.tscn")
	if panel_scene == null:
		push_warning("title_scene: could not load sign_in_panel.tscn for inline invite sign-in")
		return

	var panel: Node = panel_scene.instantiate()

	# Abbreviated mode: email + password + DOB only; no full tab bar.
	if panel.has_method("set_abbreviated_mode"):
		panel.call("set_abbreviated_mode", true)

	# Show back-to-title button so the user can escape the flow.
	if "show_back_button" in panel:
		panel.set("show_back_button", true)

	# Wire signals.
	if panel.has_signal("sign_in_complete"):
		panel.sign_in_complete.connect(_on_inline_sign_in_complete.bind(token), CONNECT_ONE_SHOT)
	if panel.has_signal("back_to_title_requested"):
		panel.back_to_title_requested.connect(_on_escape_from_deep_link, CONNECT_ONE_SHOT)

	var overlay_layer := CanvasLayer.new()
	overlay_layer.name = "InlineSignInOverlay"
	overlay_layer.layer = 10
	overlay_layer.add_child(panel)
	add_child(overlay_layer)
	_inline_sign_in_overlay = overlay_layer


## Called when the abbreviated sign-in panel completes sign-in.
## Resumes the invite flow with the stored token.
func _on_inline_sign_in_complete(token: String) -> void:
	if _inline_sign_in_overlay != null and is_instance_valid(_inline_sign_in_overlay):
		_inline_sign_in_overlay.queue_free()
	_inline_sign_in_overlay = null
	_redeem_invite_and_join(token)


## Called when the user cancels out of the abbreviated sign-in prompt.
## Restores the normal title UI.
func _on_escape_from_deep_link() -> void:
	if _inline_sign_in_overlay != null and is_instance_valid(_inline_sign_in_overlay):
		_inline_sign_in_overlay.queue_free()
	_inline_sign_in_overlay = null
	_pending_invite_token = ""
	if _content_column != null:
		_content_column.visible = true
	if _joining_label != null:
		_joining_label.visible = false


## Step 2 of the invite flow: call FriendsClient.redeem_invite(token).
## Connects one-shot signals to friendship_created and invite_creation_failed.
func _redeem_invite_and_join(token: String) -> void:
	var fc: Node = get_node_or_null("/root/FriendsClient")
	if fc == null:
		push_warning("title_scene._redeem_invite_and_join: FriendsClient not available")
		return

	if fc.has_signal("friendship_created"):
		fc.friendship_created.connect(_on_friendship_created.bind(token), CONNECT_ONE_SHOT)
	if fc.has_signal("invite_creation_failed"):
		fc.invite_creation_failed.connect(_on_invite_creation_failed, CONNECT_ONE_SHOT)

	if fc.has_method("redeem_invite"):
		fc.call("redeem_invite", token)
	else:
		push_warning("title_scene._redeem_invite_and_join: FriendsClient.redeem_invite() not found")


## Step 3: friendship_created(host_uid) — initiate join_session.
## Write pending_ftue_complete marker before main_scene loads so FTUE overlay
## never appears for invite joiners (T-06-T2: applied only after join initiated).
func _on_friendship_created(host_uid: String, _token: String) -> void:
	# Pre-set pending_ftue_complete so main_scene reads and applies it before the
	# FTUE overlay would trigger.
	_write_pending_ftue_complete()

	# Start the session join. NetworkManager.join_session is the spec API;
	# in the current implementation use start_peer via the signaling flow.
	# The Go signaling server returns a peer_id for this session; for now
	# we call join_session if it exists, otherwise use start_peer fallback.
	var nm: Node = get_node_or_null("/root/NetworkManager")
	if nm != null:
		if nm.has_method("join_session"):
			nm.call("join_session", host_uid)
		elif nm.has_method("start_peer"):
			# Fallback: use host_uid as session_id with peer_id assigned by signaling.
			# Actual peer_id will be 0 here — the signaling server will assign a real one.
			nm.call("start_peer", host_uid, 0)

		# Connect to peer_connected (equivalent to spec peer_joined) ONE_SHOT.
		if nm.has_signal("peer_connected"):
			nm.peer_connected.connect(_on_self_joined.bind(host_uid), CONNECT_ONE_SHOT)

	# Transition to main_scene (world is loading; host has the world).
	var main_scene_path := "res://src/world/main_scene.tscn"
	if ResourceLoader.exists(main_scene_path):
		get_tree().change_scene_to_file(main_scene_path)
	else:
		push_warning("title_scene._on_friendship_created: main_scene.tscn not found")


## Step 4: peer_connected fires (we are now in the host's session).
## Write joined_via_invite=true and log INVITE_JOINED telemetry.
## Then show the joiner tip toast after world_ready fires.
func _on_self_joined(peer_id: int, host_uid: String) -> void:
	if peer_id == 0:
		# Peer_id=0 is the local host; skip — we're waiting for our own join.
		return
	OnboardingTelemetry.log(OnboardingTelemetry.INVITE_JOINED)
	_write_joined_via_invite_marker()

	# Resolve host username for the joiner tip toast.
	var host_username: String = host_uid  # Fallback: show UID if username unknown.
	var fc: Node = get_node_or_null("/root/FriendsClient")
	if fc != null and fc.has_method("get_username"):
		var cached: String = fc.call("get_username")
		if not cached.is_empty():
			host_username = cached

	# Show joiner tip after world_ready fires.
	var main_node: Node = get_tree().get_root().get_node_or_null("MainScene")
	if main_node != null and main_node.has_signal("world_ready"):
		main_node.world_ready.connect(
			func() -> void:
				var toasts: Node = get_node_or_null("/root/Toasts")
				if toasts != null and toasts.has_method("show"):
					toasts.call("show",
						tr("ui.deeplink.joiner_tip").format({"friend": host_username}),
						8.0),
			CONNECT_ONE_SHOT)


## Called when FriendsClient.invite_creation_failed fires during redemption.
func _on_invite_creation_failed(reason: String) -> void:
	push_warning("title_scene._on_invite_creation_failed: " + reason)
	# Show title UI again so the user isn't stuck on a blank screen.
	if _content_column != null:
		_content_column.visible = true
	if _joining_label != null:
		_joining_label.visible = false
	_pending_invite_token = ""

# ─── FTUE marker helpers ──────────────────────────────────────────────────────

## Write user://ftue.cfg [state] pending_ftue_complete=true.
## main_scene reads this flag before the FTUE overlay triggers and pre-sets
## ftue_complete on the world meta so the FTUE overlay never appears.
## T-06-T2: only written once the join flow has been initiated (host verified).
func _write_pending_ftue_complete() -> void:
	var cfg := ConfigFile.new()
	cfg.load(_FTUE_CFG_PATH)
	cfg.set_value(_FTUE_SECTION, "pending_ftue_complete", true)
	cfg.save(_FTUE_CFG_PATH)


## Write user://ftue.cfg [state] joined_via_invite=true.
## Causes subsequent title_scene launches to skip to world_select_screen
## so invite joiners never see "first launch" title animations again.
func _write_joined_via_invite_marker() -> void:
	var cfg := ConfigFile.new()
	cfg.load(_FTUE_CFG_PATH)
	cfg.set_value(_FTUE_SECTION, "joined_via_invite", true)
	# Clear pending_ftue_complete now that the join is confirmed.
	cfg.set_value(_FTUE_SECTION, "pending_ftue_complete", false)
	cfg.save(_FTUE_CFG_PATH)


## Called from _ready() to check for the invite-joiner return-visit fast-path.
## Returns true if we handled the fast-path (caller should return from _ready()).
func _check_ftue_marker_on_ready() -> bool:
	var cfg := ConfigFile.new()
	if cfg.load(_FTUE_CFG_PATH) != OK:
		return false
	var joined_via_invite: bool = cfg.get_value(_FTUE_SECTION, "joined_via_invite", false)
	if joined_via_invite and FriendsClient.is_signed_in():
		# Skip title UI entirely; go directly to world_select_screen.
		_show_world_select(false)
		return true
	return false

# ─── Telemetry signal handlers ────────────────────────────────────────────────

## FriendsClient.sign_up_ok — log signup_complete telemetry.
## Connected in _ready() so this fires for any sign-up path (normal or abbreviated).
func _on_sign_up_ok_telemetry(_user_id: String) -> void:
	OnboardingTelemetry.log(OnboardingTelemetry.SIGNUP_COMPLETE)


## FriendsClient.signed_in — log signin_complete telemetry.
## Covers both explicit sign-in and session restore (token restore path).
func _on_signed_in_telemetry(_user_id: String) -> void:
	OnboardingTelemetry.log(OnboardingTelemetry.SIGNIN_COMPLETE)

# ─── Navigation helpers ───────────────────────────────────────────────────────

## Check for avatar config; route to world_select_screen or avatar_creator.
func _check_avatar_then_world_select() -> void:
	if FileAccess.file_exists("user://avatar.cfg"):
		_show_world_select(false)
	else:
		_show_avatar_creator()


## Transition to world_select_screen.tscn.
## offline_mode=true skips social features (no sign-in required).
func _show_world_select(_offline_mode: bool = false) -> void:
	var world_select_path := "res://src/ui/world_select_screen.tscn"
	if ResourceLoader.exists(world_select_path):
		get_tree().change_scene_to_file(world_select_path)
	else:
		# world_select_screen will be created in a later plan — warn and stay on title.
		push_warning("title_scene: world_select_screen.tscn not yet available (expected in Phase 6)")


## Transition to avatar_creator.tscn (Plan 06-05).
func _show_avatar_creator() -> void:
	var avatar_path := "res://src/ui/avatar_creator.tscn"
	if ResourceLoader.exists(avatar_path):
		get_tree().change_scene_to_file(avatar_path)
	else:
		push_warning("title_scene: avatar_creator.tscn not yet available (expected in Phase 6)")
		_show_world_select(false)


## Open legal_viewer.tscn with the given document type ("eula" or "privacy").
func _open_legal_viewer(doc_type: String) -> void:
	var viewer_path := "res://src/ui/legal_viewer.tscn"
	if not ResourceLoader.exists(viewer_path):
		return
	var viewer: Node = load(viewer_path).instantiate()
	if viewer.has_method("set") and "document_type" in viewer:
		viewer.set("document_type", doc_type)
	var overlay_layer := CanvasLayer.new()
	overlay_layer.name = "LegalViewerOverlay"
	overlay_layer.layer = 10
	overlay_layer.add_child(viewer)
	add_child(overlay_layer)
	# legal_viewer typically has a close button — no overlay tracking needed for footer links.


## Remove and free the current open overlay.
func _close_overlay() -> void:
	if _open_overlay != null and is_instance_valid(_open_overlay):
		_open_overlay.queue_free()
	_open_overlay = null
