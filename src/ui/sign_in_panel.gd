# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# sign_in_panel.gd — Sign-in / Create account UI controller (Surface 1 / K).
#
# Full-screen CanvasLayer child (layer=10). Gates access to social features.
# Two tabs: "Sign in" and "Create account".
#
# Phase 5 (Plan 05-07): Replaced _age_checkbox with DOB picker row (Surface C/K).
#   Under-13 detection runs fully client-side; only the is_under_13 boolean is
#   passed to FriendsClient.sign_up() — the raw DOB is never sent to any server
#   (GDPR minimum-data principle; T-05-DOB threat mitigation per 05-07-PLAN.md).
#   On successful under-13 sign-up, emits under_13_signup_required so the parent
#   scene can transition to ParentalGatePanel (Surface D).
#
# Phase 5 (Plan 05-10): Added username field + 500ms debounce inline validation.
#   UsernamePol.validate() checks format, reserved prefixes, and profanity locally.
#   Server uniqueness check is deferred to submit to prevent username enumeration
#   (anti-pattern per 05-UI-SPEC.md Surface G; T-05-P-wn mitigation).
#   Inline icons (icon_check/icon_error) shown right of the username field.
#   Submit button disabled until format validation passes.
#
# Security: password field secret=true; credentials never logged; tokens only
# handled by FriendsClient which persists to user://auth.cfg.
# T-04-06-I: error labels use only tr() user-facing strings; HTTP codes not surfaced.
# T-04-06-T: OAuth stubs emit sign_in_failed until Phase 5/6.
# T-05-P-wn: inline validation is format-only; server uniqueness check only on submit.
#
# References:
#   04-UI-SPEC.md Surface 1 — full-screen sign-in panel spec
#   05-UI-SPEC.md Surface C/K — DOB picker spec
#   05-UI-SPEC.md Surface G — username validation error states
#   05-07-PLAN.md Task 1
#   05-10-PLAN.md Task 1

class_name SignInPanel
extends Control

# ─── Constants ────────────────────────────────────────────────────────────────

## Path for auth token persistence (FriendsClient uses same path).
const AUTH_PATH := "user://auth.cfg"

## Panel background: dominant navy #1B2C56 at 0.95α.
const COLOR_NAVY: Color = Color(0.106, 0.173, 0.337, 0.95)
## Accent yellow: #F5C30D — tab underline.
const COLOR_ACCENT: Color = Color(0.96, 0.76, 0.05, 1.0)
## Brick white: #F1F0EA — body text.
const COLOR_WHITE: Color = Color(0.945, 0.941, 0.918, 1.0)
## Destructive red: #D63828 — error label colour.
const COLOR_DESTRUCTIVE: Color = Color(0.839, 0.220, 0.157, 1.0)

## Seconds in 13 years (365.25 days × 13 × 86400).
## COPPA "good faith" approximation — accurate to within < 0.5 day per year.
const THIRTEEN_YEARS_SECONDS: float = 13.0 * 365.25 * 86400.0

# ─── Signals ──────────────────────────────────────────────────────────────────

## Emitted after the user successfully signs in or after account creation confirmation.
signal sign_in_complete()

## Emitted when the sign-in flow is bypassed via "Play offline".
signal play_offline_requested()

## Emitted after a successful under-13 sign-up so the parent scene can show
## ParentalGatePanel. Not emitted for 13+ accounts.
signal under_13_signup_required()

## Emitted when the player presses the "Back to title" button (only present when
## show_back_button is true — i.e. opened from title_scene).
signal back_to_title_requested()

# ─── Node refs (resolved in _ready) ──────────────────────────────────────────

var _panel: PanelContainer = null
var _vbox: VBoxContainer = null
var _tab_row: HBoxContainer = null
var _sign_in_tab: Button = null
var _create_tab: Button = null
var _email_field: LineEdit = null
var _password_field: LineEdit = null

## DOB picker row — visible only on Create account tab.
var _dob_row: HBoxContainer = null
var _dob_day: OptionButton = null
var _dob_month: OptionButton = null
var _dob_year: OptionButton = null

var _error_label: Label = null
var _submit_button: Button = null
var _apple_button: Button = null
var _google_button: Button = null
var _verification_notice: Label = null
var _spinner: Control = null

## Username field on the Create account tab (Surface G — username gating).
var _username_field: LineEdit = null

## Inline validation label positioned below the username field.
var _username_error_label: Label = null

## TextureRect showing a green check icon (valid username).
var _username_icon_check: TextureRect = null

## TextureRect showing a red error icon (invalid username).
var _username_icon_error: TextureRect = null

## 500ms debounce Timer: restarted on each username keystroke.
var _username_validation_timer: Timer = null

# ─── State ────────────────────────────────────────────────────────────────────

## When true, a "Back to title" button is shown in the panel footer.
## Set by the caller (title_scene) after instantiation, before adding to tree.
@export var show_back_button: bool = false

## Active tab: "signin" | "create"
var _active_tab: String = "signin"

## Cached under-13 status from the most recent create-account submission.
var _last_signup_is_under_13: bool = false

## True when the username passes local format/reserved/profanity validation.
## Server uniqueness is only checked on submit (T-05-P-wn: anti-enumeration).
var _username_valid: bool = false

# ─── Lifecycle ────────────────────────────────────────────────────────────────

func _ready() -> void:
	_build_ui()
	_build_dob_ui()
	_build_username_field_ui()
	_setup_connections()
	_apply_tab_style_both(true)  # Sign in tab active by default
	# Add "Back to title" button when opened from title_scene.
	if show_back_button:
		_add_back_button()


## Build the full UI tree programmatically (no .tscn dependency for child nodes).
func _build_ui() -> void:
	# PanelContainer centred, 480px wide.
	_panel = PanelContainer.new()
	_panel.name = "Panel"
	_panel.anchor_left = 0.5
	_panel.anchor_top = 0.5
	_panel.anchor_right = 0.5
	_panel.anchor_bottom = 0.5
	_panel.offset_left = -240.0
	_panel.offset_top = -260.0
	_panel.offset_right = 240.0
	_panel.offset_bottom = 260.0
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = COLOR_NAVY
	panel_style.corner_radius_top_left = 16
	panel_style.corner_radius_top_right = 16
	panel_style.corner_radius_bottom_left = 16
	panel_style.corner_radius_bottom_right = 16
	_panel.add_theme_stylebox_override("panel", panel_style)
	add_child(_panel)

	# VBoxContainer with 24px padding.
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	_panel.add_child(margin)

	_vbox = VBoxContainer.new()
	_vbox.add_theme_constant_override("separation", 16)
	margin.add_child(_vbox)

	# Title label.
	var title_label := Label.new()
	title_label.text = tr("ui.signin.title")
	title_label.add_theme_color_override("font_color", COLOR_WHITE)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_vbox.add_child(title_label)

	# Tab row.
	_tab_row = HBoxContainer.new()
	_tab_row.name = "TabRow"
	_tab_row.add_theme_constant_override("separation", 0)
	_vbox.add_child(_tab_row)

	_sign_in_tab = Button.new()
	_sign_in_tab.name = "SignInTab"
	_sign_in_tab.text = tr("ui.signin.tab.signin")
	_sign_in_tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sign_in_tab.focus_mode = Control.FOCUS_NONE
	_tab_row.add_child(_sign_in_tab)

	_create_tab = Button.new()
	_create_tab.name = "CreateTab"
	_create_tab.text = tr("ui.signin.tab.create")
	_create_tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_create_tab.focus_mode = Control.FOCUS_NONE
	_tab_row.add_child(_create_tab)

	# Email field.
	_email_field = LineEdit.new()
	_email_field.name = "EmailField"
	_email_field.placeholder_text = tr("ui.signin.email_placeholder")
	_email_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_vbox.add_child(_email_field)

	# Password field (secret=true — T-04-06-I: credentials never logged).
	_password_field = LineEdit.new()
	_password_field.name = "PasswordField"
	_password_field.placeholder_text = tr("ui.signin.password_placeholder")
	_password_field.secret = true
	_password_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_vbox.add_child(_password_field)

	# Username field (Surface G) — visible only on Create account tab.
	# Built and connected in _build_username_field_ui() and _setup_connections().
	# Placeholder container added here to keep VBox order stable.
	# The actual LineEdit + icons + validation label are added in _build_username_field_ui().

	# DOB row (Surface C/K) — built and populated in _build_dob_ui(); visible
	# only on the Create account tab.
	_dob_row = HBoxContainer.new()
	_dob_row.name = "DobRow"
	_dob_row.add_theme_constant_override("separation", 8)  # sm token
	_dob_row.custom_minimum_size = Vector2(0, 44)           # mobile touch target
	_dob_row.visible = false
	_vbox.add_child(_dob_row)

	# Error label (hidden by default).
	_error_label = Label.new()
	_error_label.name = "ErrorLabel"
	_error_label.visible = false
	_error_label.add_theme_color_override("font_color", COLOR_DESTRUCTIVE)
	_error_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_vbox.add_child(_error_label)

	# Submit button (primary).
	_submit_button = Button.new()
	_submit_button.name = "SubmitButton"
	_submit_button.text = tr("ui.signin.submit_signin")
	_submit_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_vbox.add_child(_submit_button)

	# Separator.
	var sep := HSeparator.new()
	_vbox.add_child(sep)

	# OAuth container.
	var oauth_container := VBoxContainer.new()
	oauth_container.name = "OAuthContainer"
	oauth_container.add_theme_constant_override("separation", 8)
	_vbox.add_child(oauth_container)

	_apple_button = Button.new()
	_apple_button.name = "AppleButton"
	_apple_button.text = tr("ui.signin.apple")
	_apple_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	oauth_container.add_child(_apple_button)

	_google_button = Button.new()
	_google_button.name = "GoogleButton"
	_google_button.text = tr("ui.signin.google")
	_google_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	oauth_container.add_child(_google_button)

	# Verification notice (shown after account creation).
	_verification_notice = Label.new()
	_verification_notice.name = "VerificationNotice"
	_verification_notice.visible = false
	_verification_notice.text = tr("ui.signin.verification_notice")
	_verification_notice.add_theme_color_override("font_color",
		Color(COLOR_WHITE.r, COLOR_WHITE.g, COLOR_WHITE.b, 0.7))
	_verification_notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_vbox.add_child(_verification_notice)


## Populate the DOB picker row: Day (1-31), Month (localised names), Year
## (current_year-100 to current_year, descending). Called once from _ready()
## so the ~100 year items are only created once — not on every panel open.
## Per 05-UI-SPEC.md Performance Constraints: "Populate once on first _ready".
func _build_dob_ui() -> void:
	if _dob_row == null:
		return

	# Day OptionButton (72px, values 1-31).
	_dob_day = OptionButton.new()
	_dob_day.name = "DobDay"
	_dob_day.custom_minimum_size = Vector2(72, 44)
	# Placeholder item at index 0 (selected = 0 means "not chosen").
	_dob_day.add_item(tr("ui.signin.dob_day_placeholder"), 0)
	for d: int in range(1, 32):
		_dob_day.add_item(str(d), d)
	_dob_row.add_child(_dob_day)

	# Month OptionButton (120px, 12 localised month names).
	_dob_month = OptionButton.new()
	_dob_month.name = "DobMonth"
	_dob_month.custom_minimum_size = Vector2(120, 44)
	_dob_month.add_item(tr("ui.signin.dob_month_placeholder"), 0)
	var month_keys: Array[String] = [
		"ui.signin.dob_month_jan", "ui.signin.dob_month_feb",
		"ui.signin.dob_month_mar", "ui.signin.dob_month_apr",
		"ui.signin.dob_month_may", "ui.signin.dob_month_jun",
		"ui.signin.dob_month_jul", "ui.signin.dob_month_aug",
		"ui.signin.dob_month_sep", "ui.signin.dob_month_oct",
		"ui.signin.dob_month_nov", "ui.signin.dob_month_dec",
	]
	for i: int in range(month_keys.size()):
		_dob_month.add_item(tr(month_keys[i]), i + 1)
	_dob_row.add_child(_dob_month)

	# Year OptionButton (96px, current_year-100 to current_year, descending).
	_dob_year = OptionButton.new()
	_dob_year.name = "DobYear"
	_dob_year.custom_minimum_size = Vector2(96, 44)
	_dob_year.add_item(tr("ui.signin.dob_year_placeholder"), 0)
	var today_dict: Dictionary = Time.get_date_dict_from_system()
	var current_year: int = int(today_dict["year"])
	# Descending: most-recently born years first (more natural for age-gate use).
	for y: int in range(current_year, current_year - 101, -1):
		_dob_year.add_item(str(y), y)
	_dob_row.add_child(_dob_year)


## Build the username field UI for the Create account tab (Surface G).
## Adds a LineEdit, inline check/error icons (16×16 TextureRects), a validation
## label, and a 500ms debounce Timer. All nodes are inserted into _vbox just
## before _dob_row so the Create tab layout is: email → password → username → dob → error → submit.
## Visible = false by default (shown only on Create tab via _on_tab_pressed).
func _build_username_field_ui() -> void:
	# Container: HBox holds the LineEdit + icons side by side.
	var username_row := HBoxContainer.new()
	username_row.name = "UsernameRow"
	username_row.visible = false
	username_row.add_theme_constant_override("separation", 4)
	# Insert before _dob_row in the VBox children.
	_vbox.add_child(username_row)
	_vbox.move_child(username_row, _dob_row.get_index())

	_username_field = LineEdit.new()
	_username_field.name = "UsernameField"
	_username_field.placeholder_text = tr("ui.signin.username_placeholder")
	_username_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	username_row.add_child(_username_field)

	# Green check icon (valid) — 16×16 TextureRect.
	# Texture loaded at runtime; if the asset is missing, the rect stays empty (graceful).
	_username_icon_check = TextureRect.new()
	_username_icon_check.name = "UsernameIconCheck"
	_username_icon_check.custom_minimum_size = Vector2(16, 16)
	_username_icon_check.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_username_icon_check.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_username_icon_check.modulate = Color(0.239, 0.710, 0.376, 1.0)  # #3DB560 green
	_username_icon_check.visible = false
	var check_tex: Texture2D = load("res://assets/textures/icons/icon_check.png") if ResourceLoader.exists("res://assets/textures/icons/icon_check.png") else null
	if check_tex != null:
		_username_icon_check.texture = check_tex
	username_row.add_child(_username_icon_check)

	# Red error icon (invalid) — 16×16 TextureRect.
	_username_icon_error = TextureRect.new()
	_username_icon_error.name = "UsernameIconError"
	_username_icon_error.custom_minimum_size = Vector2(16, 16)
	_username_icon_error.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_username_icon_error.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_username_icon_error.modulate = COLOR_DESTRUCTIVE
	_username_icon_error.visible = false
	var error_tex: Texture2D = load("res://assets/textures/icons/icon_error.png") if ResourceLoader.exists("res://assets/textures/icons/icon_error.png") else null
	if error_tex != null:
		_username_icon_error.texture = error_tex
	username_row.add_child(_username_icon_error)

	# Username-specific validation label (separate from the form-level _error_label).
	_username_error_label = Label.new()
	_username_error_label.name = "UsernameErrorLabel"
	_username_error_label.visible = false
	_username_error_label.add_theme_color_override("font_color", COLOR_DESTRUCTIVE)
	_username_error_label.add_theme_font_size_override("font_size", 13)
	_username_error_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_vbox.add_child(_username_error_label)
	_vbox.move_child(_username_error_label, username_row.get_index() + 1)

	# 500ms debounce timer — one_shot so it fires once per typing pause.
	_username_validation_timer = Timer.new()
	_username_validation_timer.name = "UsernameValidationTimer"
	_username_validation_timer.one_shot = true
	_username_validation_timer.wait_time = 0.5
	add_child(_username_validation_timer)
	_username_validation_timer.timeout.connect(_validate_username_inline)
	_username_field.text_changed.connect(_on_username_field_text_changed)


## Wire all signals after UI tree is built.
func _setup_connections() -> void:
	# Tab buttons.
	if _sign_in_tab != null and _sign_in_tab.has_signal("pressed"):
		_sign_in_tab.pressed.connect(_on_tab_pressed.bind("signin"))
	if _create_tab != null and _create_tab.has_signal("pressed"):
		_create_tab.pressed.connect(_on_tab_pressed.bind("create"))

	# Submit + OAuth.
	if _submit_button != null and _submit_button.has_signal("pressed"):
		_submit_button.pressed.connect(_on_submit)
	if _apple_button != null and _apple_button.has_signal("pressed"):
		_apple_button.pressed.connect(_on_apple_sign_in)
	if _google_button != null and _google_button.has_signal("pressed"):
		_google_button.pressed.connect(_on_google_sign_in)

	# FriendsClient signals.
	var fc: Node = get_node_or_null("/root/FriendsClient")
	if fc != null:
		if fc.has_signal("signed_in"):
			fc.signed_in.connect(_on_signed_in)
		if fc.has_signal("sign_in_failed"):
			fc.sign_in_failed.connect(_on_sign_in_failed)
		if fc.has_signal("sign_up_ok"):
			fc.sign_up_ok.connect(_on_sign_up_ok)
		if fc.has_signal("sign_up_failed"):
			fc.sign_up_failed.connect(_on_sign_in_failed)

# ─── Tab handling ─────────────────────────────────────────────────────────────

## Switch between Sign in and Create account tabs.
func _on_tab_pressed(tab: String) -> void:
	_active_tab = tab
	_error_label.visible = false
	if tab == "signin":
		_dob_row.visible = false
		# Hide username field + validation nodes on sign-in tab.
		var urow: Node = _vbox.get_node_or_null("UsernameRow")
		if urow != null:
			urow.visible = false
		if _username_error_label != null:
			_username_error_label.visible = false
		# Reset validation state so the user doesn't carry over inline errors.
		_username_valid = false
		_submit_button.disabled = false
		_submit_button.text = tr("ui.signin.submit_signin")
		_apply_tab_style_both(true)
	else:
		_dob_row.visible = true
		# Show username field on create tab.
		var urow2: Node = _vbox.get_node_or_null("UsernameRow")
		if urow2 != null:
			urow2.visible = true
		# Disable submit until username validates.
		_username_valid = false
		_submit_button.disabled = true
		_submit_button.text = tr("ui.signin.submit_create")
		_apply_tab_style_both(false)


## Apply active/inactive style to both tab buttons.
## signin_active=true → Sign In tab is active; false → Create tab is active.
func _apply_tab_style_both(signin_active: bool) -> void:
	if _sign_in_tab != null:
		_apply_tab_style(_sign_in_tab, signin_active)
	if _create_tab != null:
		_apply_tab_style(_create_tab, not signin_active)


## Apply active/inactive style to a tab button (verbatim from inventory_slide_in.gd).
func _apply_tab_style(btn: Button, active: bool) -> void:
	if active:
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.106, 0.173, 0.337, 1.0)
		style.border_width_bottom = 2
		style.border_color = COLOR_ACCENT
		style.content_margin_left = 12.0
		style.content_margin_top = 8.0
		style.content_margin_right = 12.0
		style.content_margin_bottom = 6.0
		style.corner_radius_top_left = 8
		style.corner_radius_top_right = 8
		btn.add_theme_stylebox_override("normal", style)
		btn.add_theme_stylebox_override("hover", style)
		btn.add_theme_stylebox_override("pressed", style)
		btn.add_theme_color_override("font_color", COLOR_ACCENT)
	else:
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.0, 0.0, 0.0, 0.0)
		style.content_margin_left = 12.0
		style.content_margin_top = 8.0
		style.content_margin_right = 12.0
		style.content_margin_bottom = 8.0
		style.corner_radius_top_left = 8
		style.corner_radius_top_right = 8
		style.corner_radius_bottom_left = 8
		style.corner_radius_bottom_right = 8
		btn.add_theme_stylebox_override("normal", style)
		btn.add_theme_color_override("font_color",
			Color(COLOR_WHITE.r, COLOR_WHITE.g, COLOR_WHITE.b, 0.7))

# ─── Username validation (Surface G, Plan 05-10) ──────────────────────────────

## Called whenever the username field text changes.
## Restarts the 500ms debounce timer on each keystroke; also disables submit
## immediately so the user cannot submit mid-typing.
func _on_username_field_text_changed(_new_text: String) -> void:
	_username_valid = false
	if _active_tab == "create" and _submit_button != null:
		_submit_button.disabled = true
	if _username_validation_timer != null:
		_username_validation_timer.start()
	# Clear icons while typing to avoid flickering stale state.
	if _username_icon_check != null:
		_username_icon_check.visible = false
	if _username_icon_error != null:
		_username_icon_error.visible = false
	if _username_error_label != null:
		_username_error_label.visible = false


## Called after 500ms typing pause. Runs format/reserved/profanity validation via
## UsernamePol.validate(). Updates icons and error label. Does NOT hit the server
## (no uniqueness check inline — T-05-P-wn anti-enumeration guard).
func _validate_username_inline() -> void:
	if _username_field == null:
		return
	var text: String = _username_field.text
	if text.is_empty():
		# Blank — hide icons, disable submit, show no error (user hasn't started yet).
		if _username_icon_check != null:
			_username_icon_check.visible = false
		if _username_icon_error != null:
			_username_icon_error.visible = false
		if _username_error_label != null:
			_username_error_label.visible = false
		_username_valid = false
		if _active_tab == "create" and _submit_button != null:
			_submit_button.disabled = true
		return

	# Run client-side validation (format + reserved + profanity). No HTTP call.
	var result: Dictionary = UsernamePol.validate(text)
	var is_valid: bool = result.get("valid", false)
	var error_key: String = result.get("error_key", "")

	_username_valid = is_valid

	if is_valid:
		if _username_icon_check != null:
			_username_icon_check.visible = true
		if _username_icon_error != null:
			_username_icon_error.visible = false
		if _username_error_label != null:
			_username_error_label.visible = false
		# Enable submit only when username is locally valid.
		if _active_tab == "create" and _submit_button != null:
			_submit_button.disabled = false
	else:
		if _username_icon_check != null:
			_username_icon_check.visible = false
		if _username_icon_error != null:
			_username_icon_error.visible = true
		if _username_error_label != null and not error_key.is_empty():
			# T-05-P-wn: never echo the rejected input — show only the i18n error key.
			_username_error_label.text = tr(error_key)
			_username_error_label.visible = true
		if _active_tab == "create" and _submit_button != null:
			_submit_button.disabled = true


# ─── Form submission ──────────────────────────────────────────────────────────

## Validate and dispatch sign-in or create-account to FriendsClient.
func _on_submit() -> void:
	# Clear previous error.
	_error_label.visible = false

	var email: String = _email_field.text.strip_edges() if _email_field != null else ""
	var password: String = _password_field.text if _password_field != null else ""

	if email.is_empty() or password.is_empty():
		_show_error(tr("ui.signin.error_invalid_credentials"))
		return

	var fc: Node = get_node_or_null("/root/FriendsClient")
	if fc == null:
		_show_error(tr("ui.signin.error_network"))
		return

	if _active_tab == "signin":
		if fc.has_method("sign_in"):
			fc.call("sign_in", email, password)
	else:
		_on_submit_create_account(email, password, fc)


## Validate username + DOB and dispatch create-account to FriendsClient.
## Raw DOB is NEVER sent to the server — only the is_under_13 boolean.
## Per T-05-DOB: GDPR minimum-data principle.
## Per T-05-P-wn: server uniqueness check only on submit, not inline.
func _on_submit_create_account(email: String, password: String, fc: Node) -> void:
	# ── Username validation (synchronous on submit — Surface G) ──
	var username: String = ""
	if _username_field != null:
		username = _username_field.text.strip_edges()
	if username.is_empty():
		_show_error(tr("ui.signin.error_username_required"))
		return
	# Synchronous client-side check (format + reserved + profanity).
	# Server uniqueness check happens on submit return (409 conflict) — not inline.
	var username_result: Dictionary = UsernamePol.validate(username)
	if not username_result.get("valid", false):
		var uk: String = username_result.get("error_key", "ui.username.error_format")
		_show_error(tr(uk))
		return

	# ── DOB validation ──
	var day: int = _get_dob_selected_id(_dob_day)
	var month: int = _get_dob_selected_id(_dob_month)
	var year: int = _get_dob_selected_id(_dob_year)

	# Check all three fields are filled (placeholder = id 0).
	if day == 0 or month == 0 or year == 0:
		_show_error(tr("ui.signin.error_dob_incomplete"))
		return

	# Validate date using Time; returns -1 for impossible dates (e.g. Feb 31).
	var date_dict := {"year": year, "month": month, "day": day}
	var birth_unix: float = Time.get_unix_time_from_datetime_dict(date_dict)
	if birth_unix <= 0.0:
		_show_error(tr("ui.signin.error_dob_invalid"))
		return

	# Under-13 detection (client-side only — COPPA "good faith" standard).
	# Raw DOB is computed here and immediately discarded after boolean evaluation.
	var today_unix: float = Time.get_unix_time_from_system()
	var is_under_13: bool = (today_unix - birth_unix) < THIRTEEN_YEARS_SECONDS

	# Cache the under-13 status for use in _on_sign_up_ok.
	_last_signup_is_under_13 = is_under_13

	# Call sign_up with is_under_13 context via the DOB params so FriendsClient
	# computes the same boolean server-side (raw DOB never reaches the server).
	# We pass the DOB fields so FriendsClient can re-derive is_under_13; it will
	# NOT include day/month/year in the HTTP body (see friends_client.gd sign_up).
	if fc.has_method("sign_up"):
		fc.call("sign_up", email, password, username, year, month, day)


## Get the item id (not index) of the selected item in an OptionButton.
## Returns 0 if the OptionButton is null or the placeholder is selected.
func _get_dob_selected_id(opt: OptionButton) -> int:
	if opt == null:
		return 0
	var idx: int = opt.selected
	if idx < 0:
		return 0
	return opt.get_item_id(idx)


## Show an error message below the submit button.
func _show_error(message: String) -> void:
	if _error_label == null:
		return
	# T-04-06-I: only tr() user-facing strings — never raw HTTP codes or server messages.
	_error_label.text = message
	_error_label.visible = true

# ─── FriendsClient signal handlers ───────────────────────────────────────────

## Called when FriendsClient.signed_in fires — hide panel, emit sign_in_complete.
func _on_signed_in(_user_id: String) -> void:
	visible = false
	emit_signal("sign_in_complete")


## Called when sign_in_failed or sign_up_failed fires.
## For sign-up: if reason is "taken" (Supabase 409 conflict), show the canonical
## "That name is taken" error (Surface G). Never echo the attempted username
## in the error message (T-05-P-wn anti-enumeration).
func _on_sign_in_failed(reason: String) -> void:
	match reason:
		"taken":
			_show_error(tr("ui.username.error_taken"))
		"reserved":
			_show_error(tr("ui.username.error_reserved"))
		"cooldown":
			_show_error(tr("ui.username.error_cooldown"))
		"format":
			_show_error(tr("ui.username.error_format"))
		_:
			# Unknown or not-yet-implemented reason (e.g. "not_implemented_phase_5",
			# raw server text, etc.): show generic network error rather than raw server text.
			_show_error(tr("ui.signin.error_network"))
	_last_signup_is_under_13 = false


## Called when sign_up_ok fires.
## For under-13 accounts: emit under_13_signup_required so the parent scene
## can show ParentalGatePanel (Surface D). Do not emit sign_in_complete yet.
## For 13+ accounts: show verification notice, hide after 2s, then sign_in_complete.
func _on_sign_up_ok(_user_id: String) -> void:
	if _last_signup_is_under_13:
		_last_signup_is_under_13 = false
		# Under-13 post-signup: transition to parental gate panel via parent scene.
		# Do not show normal verification notice — the parental gate panel handles messaging.
		visible = false
		emit_signal("under_13_signup_required")
		return

	# 13+ path: show verification notice, then proceed to game.
	if _verification_notice != null:
		_verification_notice.visible = true
	if _error_label != null:
		_error_label.visible = false
	# Auto-hide after 2 seconds, then emit sign_in_complete (account exists, can play).
	var t := Timer.new()
	t.one_shot = true
	t.wait_time = 2.0
	add_child(t)
	t.timeout.connect(_on_verification_timer_done.bind(t))
	t.start()


func _on_verification_timer_done(t: Timer) -> void:
	t.queue_free()
	visible = false
	emit_signal("sign_in_complete")

# ─── OAuth stubs (Phase 5/6) ─────────────────────────────────────────────────

## Programmatically select the "Create account" tab.
## Called by title_scene when the "Create account" button is pressed.
func set_create_account_mode(active: bool) -> void:
	if active:
		_on_tab_pressed("create")


## Enable or disable abbreviated (compact) mode for invite-joiner sign-in.
##
## When enabled:
##   - Hides the tab bar (both Sign in and Create account tabs hidden).
##   - Shows only email, password, and DOB fields.
##   - Hides OAuth buttons, the separator, and extra links.
##   - "Create account" flow uses abbreviated sign-up (DOB required but no tab navigation).
##
## When disabled (default):
##   - Restores the normal two-tab layout.
##
## Called by title_scene after instantiating sign_in_panel.tscn for the
## inline invite-joiner sign-in prompt (Surface 6 compact form).
##
## References: 06-08-PLAN.md Task 1; 06-CONTEXT.md Area 5.
func set_abbreviated_mode(enabled: bool) -> void:
	# Tab bar: hide both tabs so the user sees a single-mode form.
	if _tab_row != null:
		_tab_row.visible = not enabled

	if enabled:
		# Show the email, password, and DOB fields for the abbreviated sign-up path.
		# DOB is required in abbreviated mode because the account-creation path needs it.
		if _dob_row != null:
			_dob_row.visible = true
		# Show the username row as well — abbreviated sign-up still needs a username.
		var urow: Node = _vbox.get_node_or_null("UsernameRow") if _vbox != null else null
		if urow != null:
			urow.visible = true
		# Switch the submit button to "Create account" label (abbreviated default is sign-up).
		if _submit_button != null:
			_submit_button.text = tr("ui.signin.submit_create")
			# Submit should be enabled once username validates; start disabled.
			_submit_button.disabled = true
		_active_tab = "create"
		_username_valid = false

		# Hide OAuth separator and buttons — abbreviated mode is email-only.
		var oauth_container: Node = _vbox.get_node_or_null("OAuthContainer") if _vbox != null else null
		if oauth_container != null:
			oauth_container.visible = false
		# Hide the separator above OAuth.
		for child: Node in _vbox.get_children() if _vbox != null else []:
			if child is HSeparator:
				child.visible = false
				break
	else:
		# Restore normal mode: sign-in tab active by default.
		_on_tab_pressed("signin")
		var oauth_container: Node = _vbox.get_node_or_null("OAuthContainer") if _vbox != null else null
		if oauth_container != null:
			oauth_container.visible = true
		for child: Node in _vbox.get_children() if _vbox != null else []:
			if child is HSeparator:
				child.visible = true
				break


## Add a "Back to title" flat button at the bottom of the panel VBox.
## Only called from _ready() when show_back_button is true.
func _add_back_button() -> void:
	if _vbox == null:
		return
	var sep := HSeparator.new()
	_vbox.add_child(sep)
	var back_btn := Button.new()
	back_btn.name = "BackToTitleButton"
	back_btn.text = tr("ui.signin.back_to_title")
	back_btn.flat = true
	back_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	back_btn.add_theme_color_override("font_color",
		Color(0.945, 0.941, 0.918, 0.7))
	back_btn.pressed.connect(_on_back_to_title_pressed)
	_vbox.add_child(back_btn)


## Emits back_to_title_requested so title_scene can remove this panel.
func _on_back_to_title_pressed() -> void:
	emit_signal("back_to_title_requested")


## Apple sign-in stub — Phase 5/6 will implement actual SIWA flow.
## T-04-06-T: stub emits sign_in_failed so no false authentication is possible.
func _on_apple_sign_in() -> void:
	_show_error(tr("ui.signin.error_network"))


## Google sign-in stub — Phase 5/6 will implement actual OAuth flow.
## T-04-06-T: stub emits sign_in_failed so no false authentication is possible.
func _on_google_sign_in() -> void:
	_show_error(tr("ui.signin.error_network"))
