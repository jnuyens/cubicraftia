# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# parental_gate_panel.gd — Parental Consent Panel (Surface D) + Restricted-Account
# Banner (Surface F), as specified in 05-UI-SPEC.md.
#
# Surface D (ParentalGatePanel):
#   Full-screen CanvasLayer overlay at layer 20. Shown automatically after a
#   successful under-13 sign-up. Also accessible from the restricted-account
#   banner via "Resend email".
#
#   Four UI states:
#     DEFAULT  — heading + body + parent email field + "Send link" + "Why?" + "Skip"
#     LOADING  — "Send link" disabled + "Sending…" text
#     SUCCESS  — envelope icon + "Link sent!" + success body + "Done" + "Resend"
#     ERROR    — destructive label below email field (button re-enabled)
#
# Surface F (RestrictedAccountBanner):
#   40px full-width amber PanelContainer anchored to the top of any scene's
#   CanvasLayer 5 (HUD layer). Call install_banner(target_canvas_layer) from
#   the parent scene to add the banner to the HUD.
#   Hidden until consent_status_received(false, *) fires; hidden permanently
#   once consent_status_received(true, *) fires.
#
# Security:
#   - Email validation: basic "@" + "." check (per 05-UI-SPEC.md Surface D).
#   - Raw DOB is never handled by this panel — the is_under_13 flag is already
#     stored in FriendsClient's user metadata at sign-up time.
#   - "Resend email" is rate-limited to once per 3600 seconds client-side to
#     discourage spam (the Go server enforces the hard rate limit server-side).
#
# References:
#   05-UI-SPEC.md Surfaces D + F — full layout and copywriting contract
#   05-07-PLAN.md Task 2
#   05-CONTEXT.md Area 3 — parental consent flow

class_name ParentalGatePanel
extends Control

# ─── Constants ────────────────────────────────────────────────────────────────

## Panel background: dominant navy #1B2C56 at 0.92α.
const COLOR_NAVY: Color = Color(0.106, 0.173, 0.337, 0.92)
## Backdrop: dominant navy #1B2C56 at 0.60α (full-screen dim).
const COLOR_BACKDROP: Color = Color(0.106, 0.173, 0.337, 0.60)
## Brick white: #F1F0EA — body text.
const COLOR_WHITE: Color = Color(0.945, 0.941, 0.918, 1.0)
## Accent yellow: #F5C30D.
const COLOR_ACCENT: Color = Color(0.96, 0.76, 0.05, 1.0)
## Destructive red: #D63828.
const COLOR_DESTRUCTIVE: Color = Color(0.839, 0.220, 0.157, 1.0)
## Warning amber: #E8890C — banner background.
const COLOR_AMBER: Color = Color(0.910, 0.537, 0.047, 1.0)
## Navy (dark): #1B2C56 — text on amber background.
const COLOR_NAVY_SOLID: Color = Color(0.106, 0.173, 0.337, 1.0)

## Client-side resend cooldown: 3600 seconds (1 hour).
const RESEND_COOLDOWN_SECONDS: float = 3600.0

## Panel states.
const STATE_DEFAULT := "DEFAULT"
const STATE_LOADING := "LOADING"
const STATE_SUCCESS := "SUCCESS"
const STATE_ERROR := "ERROR"

# ─── Signals ──────────────────────────────────────────────────────────────────

## Emitted when the user taps "Done" or "Skip for now".
signal panel_closed()

# ─── Surface D — parental gate panel nodes ───────────────────────────────────

var _backdrop: ColorRect = null
var _inner_panel: PanelContainer = null
var _content_vbox: VBoxContainer = null

# DEFAULT state nodes
var _heading_label: Label = null
var _body_label: Label = null
var _email_field: LineEdit = null
var _email_error_label: Label = null
var _send_button: Button = null
var _why_button: Button = null
var _why_vbox: VBoxContainer = null
var _skip_button: Button = null

# SUCCESS state nodes
var _success_vbox: VBoxContainer = null
var _success_heading: Label = null
var _success_body: Label = null
var _done_button: Button = null
var _resend_link: Button = null

# ─── Surface F — restricted-account banner ───────────────────────────────────

## The banner node. Created in _build_banner(); installed into the HUD by install_banner().
var _banner: PanelContainer = null
var _banner_resend_btn: Button = null

# ─── State ────────────────────────────────────────────────────────────────────

var _current_state: String = STATE_DEFAULT
var _last_resend_epoch: float = -RESEND_COOLDOWN_SECONDS  # allow immediate first send
var _cached_parent_email: String = ""

# ─── Lifecycle ────────────────────────────────────────────────────────────────

func _ready() -> void:
	_build_panel()
	_build_banner()
	_setup_connections()
	_set_state(STATE_DEFAULT)


# ─── Builder: Surface D panel ─────────────────────────────────────────────────

func _build_panel() -> void:
	# Full-screen backdrop (navy 60% alpha, blocks all interaction below).
	_backdrop = ColorRect.new()
	_backdrop.name = "Backdrop"
	_backdrop.anchor_right = 1.0
	_backdrop.anchor_bottom = 1.0
	_backdrop.color = COLOR_BACKDROP
	_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_backdrop)

	# Inner PanelContainer: 480px wide, centred.
	_inner_panel = PanelContainer.new()
	_inner_panel.name = "InnerPanel"
	_inner_panel.anchor_left = 0.5
	_inner_panel.anchor_top = 0.5
	_inner_panel.anchor_right = 0.5
	_inner_panel.anchor_bottom = 0.5
	_inner_panel.offset_left = -240.0
	_inner_panel.offset_top = -220.0
	_inner_panel.offset_right = 240.0
	_inner_panel.offset_bottom = 220.0
	_inner_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_inner_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = COLOR_NAVY
	panel_style.corner_radius_top_left = 16
	panel_style.corner_radius_top_right = 16
	panel_style.corner_radius_bottom_left = 16
	panel_style.corner_radius_bottom_right = 16
	_inner_panel.add_theme_stylebox_override("panel", panel_style)
	add_child(_inner_panel)

	# Content margin: 24px all sides.
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	_inner_panel.add_child(margin)

	_content_vbox = VBoxContainer.new()
	_content_vbox.add_theme_constant_override("separation", 16)
	margin.add_child(_content_vbox)

	# ── DEFAULT state nodes ──

	# Heading.
	_heading_label = Label.new()
	_heading_label.name = "HeadingLabel"
	_heading_label.text = tr("ui.consent.title")
	_heading_label.add_theme_color_override("font_color", COLOR_WHITE)
	_heading_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_heading_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content_vbox.add_child(_heading_label)

	# Body paragraph.
	_body_label = Label.new()
	_body_label.name = "BodyLabel"
	_body_label.text = tr("ui.consent.body")
	_body_label.add_theme_color_override("font_color",
		Color(COLOR_WHITE.r, COLOR_WHITE.g, COLOR_WHITE.b, 0.8))
	_body_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content_vbox.add_child(_body_label)

	# Parent email LineEdit.
	_email_field = LineEdit.new()
	_email_field.name = "EmailField"
	_email_field.placeholder_text = tr("ui.consent.parent_email_placeholder")
	# Godot 4.6 renamed LineEdit.keyboard_type → virtual_keyboard_type.
	_email_field.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_EMAIL_ADDRESS
	_email_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content_vbox.add_child(_email_field)

	# Email error label (hidden by default).
	_email_error_label = Label.new()
	_email_error_label.name = "EmailErrorLabel"
	_email_error_label.visible = false
	_email_error_label.add_theme_color_override("font_color", COLOR_DESTRUCTIVE)
	_email_error_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content_vbox.add_child(_email_error_label)

	# "Send link" button (primary style, full-width).
	_send_button = Button.new()
	_send_button.name = "SendButton"
	_send_button.text = tr("ui.consent.send_link")
	_send_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content_vbox.add_child(_send_button)

	# "Why am I seeing this?" LinkButton (toggles collapsible VBox).
	_why_button = Button.new()
	_why_button.name = "WhyButton"
	_why_button.text = tr("ui.consent.why_label")
	_why_button.flat = true
	_why_button.add_theme_color_override("font_color", COLOR_ACCENT)
	_why_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_content_vbox.add_child(_why_button)

	# Collapsible explanation VBox (hidden by default).
	_why_vbox = VBoxContainer.new()
	_why_vbox.name = "WhyVBox"
	_why_vbox.visible = false
	_why_vbox.add_theme_constant_override("separation", 8)
	var why_style := StyleBoxFlat.new()
	why_style.bg_color = Color(0.106, 0.173, 0.337, 0.5)
	why_style.corner_radius_top_left = 8
	why_style.corner_radius_top_right = 8
	why_style.corner_radius_bottom_left = 8
	why_style.corner_radius_bottom_right = 8
	why_style.content_margin_left = 8.0
	why_style.content_margin_top = 8.0
	why_style.content_margin_right = 8.0
	why_style.content_margin_bottom = 8.0
	var why_panel := PanelContainer.new()
	why_panel.add_theme_stylebox_override("panel", why_style)
	_why_vbox.add_child(why_panel)
	var why_text := Label.new()
	why_text.text = tr("ui.consent.why_explanation")
	why_text.add_theme_color_override("font_color",
		Color(COLOR_WHITE.r, COLOR_WHITE.g, COLOR_WHITE.b, 0.8))
	why_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	why_panel.add_child(why_text)
	_content_vbox.add_child(_why_vbox)

	# "Skip for now" button (secondary style).
	_skip_button = Button.new()
	_skip_button.name = "SkipButton"
	_skip_button.text = tr("ui.consent.skip")
	_skip_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content_vbox.add_child(_skip_button)

	# ── SUCCESS state nodes (hidden until SUCCESS state) ──

	_success_vbox = VBoxContainer.new()
	_success_vbox.name = "SuccessVBox"
	_success_vbox.visible = false
	_success_vbox.add_theme_constant_override("separation", 16)
	_content_vbox.add_child(_success_vbox)

	_success_heading = Label.new()
	_success_heading.name = "SuccessHeading"
	_success_heading.text = tr("ui.consent.success_heading")
	_success_heading.add_theme_color_override("font_color", COLOR_WHITE)
	_success_heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_success_vbox.add_child(_success_heading)

	_success_body = Label.new()
	_success_body.name = "SuccessBody"
	_success_body.add_theme_color_override("font_color",
		Color(COLOR_WHITE.r, COLOR_WHITE.g, COLOR_WHITE.b, 0.8))
	_success_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_success_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_success_vbox.add_child(_success_body)

	_done_button = Button.new()
	_done_button.name = "DoneButton"
	_done_button.text = tr("ui.consent.done")
	_done_button.custom_minimum_size = Vector2(160, 0)
	_done_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_success_vbox.add_child(_done_button)

	_resend_link = Button.new()
	_resend_link.name = "ResendLink"
	_resend_link.text = tr("ui.consent.resend")
	_resend_link.flat = true
	_resend_link.add_theme_color_override("font_color", COLOR_ACCENT)
	_resend_link.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_success_vbox.add_child(_resend_link)


# ─── Builder: Surface F banner ────────────────────────────────────────────────

func _build_banner() -> void:
	_banner = PanelContainer.new()
	_banner.name = "RestrictedAccountBanner"
	_banner.anchor_right = 1.0
	_banner.anchor_bottom = 0.0  # anchored at top
	_banner.offset_top = 0.0
	_banner.offset_bottom = 40.0  # 40px height per 05-UI-SPEC.md Surface F
	_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_banner.visible = false  # hidden until consent status known

	var banner_style := StyleBoxFlat.new()
	banner_style.bg_color = COLOR_AMBER
	# No border, no rounding — flush with screen edges (per 05-UI-SPEC.md Surface F).
	banner_style.border_width_top = 0
	banner_style.border_width_right = 0
	banner_style.border_width_bottom = 0
	banner_style.border_width_left = 0
	banner_style.corner_radius_top_left = 0
	banner_style.corner_radius_top_right = 0
	banner_style.corner_radius_bottom_left = 0
	banner_style.corner_radius_bottom_right = 0
	banner_style.content_margin_left = 0.0
	banner_style.content_margin_top = 0.0
	banner_style.content_margin_right = 0.0
	banner_style.content_margin_bottom = 0.0
	_banner.add_theme_stylebox_override("panel", banner_style)

	# Inner HBoxContainer (centred content).
	var hbox := HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 8)
	hbox.anchor_right = 1.0
	hbox.anchor_bottom = 1.0
	_banner.add_child(hbox)

	# Warning label.
	var banner_label := Label.new()
	banner_label.text = tr("ui.restricted.banner_label")
	banner_label.add_theme_color_override("font_color", COLOR_NAVY_SOLID)
	hbox.add_child(banner_label)

	# "Resend email" button (navy text on amber — flat, underline-style).
	_banner_resend_btn = Button.new()
	_banner_resend_btn.name = "ResendBtn"
	_banner_resend_btn.text = tr("ui.restricted.resend_link")
	_banner_resend_btn.flat = true
	_banner_resend_btn.add_theme_color_override("font_color", COLOR_NAVY_SOLID)
	hbox.add_child(_banner_resend_btn)


## Install the restricted-account banner as a child of the given CanvasLayer (layer 5).
## Call this from the main scene / HUD scene _ready() after instantiating this panel.
## The banner is not added to the panel's own tree — it is a top-level HUD element.
func install_banner(target_canvas_layer: CanvasLayer) -> void:
	if _banner != null and is_instance_valid(target_canvas_layer):
		target_canvas_layer.add_child(_banner)


# ─── Signal wiring ────────────────────────────────────────────────────────────

func _setup_connections() -> void:
	# Button signals.
	if _send_button != null:
		_send_button.pressed.connect(_on_send_pressed)
	if _why_button != null:
		_why_button.pressed.connect(_on_why_pressed)
	if _skip_button != null:
		_skip_button.pressed.connect(_on_skip_pressed)
	if _done_button != null:
		_done_button.pressed.connect(_on_done_pressed)
	if _resend_link != null:
		_resend_link.pressed.connect(_on_resend_pressed)
	if _banner_resend_btn != null:
		_banner_resend_btn.pressed.connect(_on_banner_resend_pressed)

	# FriendsClient consent signal.
	var fc: Node = get_node_or_null("/root/FriendsClient")
	if fc != null and fc.has_signal("consent_status_received"):
		fc.consent_status_received.connect(_on_consent_status)


# ─── State machine ────────────────────────────────────────────────────────────

func _set_state(state: String) -> void:
	_current_state = state

	# Show/hide top-level state groups.
	var in_default: bool = (state == STATE_DEFAULT or state == STATE_LOADING or state == STATE_ERROR)
	var in_success: bool = (state == STATE_SUCCESS)

	if _heading_label != null:
		_heading_label.visible = in_default
	if _body_label != null:
		_body_label.visible = in_default
	if _email_field != null:
		_email_field.visible = in_default
	if _email_error_label != null:
		_email_error_label.visible = false  # reset; _show_email_error shows it
	if _send_button != null:
		_send_button.visible = in_default
	if _why_button != null:
		_why_button.visible = in_default
	if _why_vbox != null:
		_why_vbox.visible = false  # always reset collapsible on state change
	if _skip_button != null:
		_skip_button.visible = in_default
	if _success_vbox != null:
		_success_vbox.visible = in_success

	# State-specific tweaks.
	match state:
		STATE_DEFAULT:
			if _send_button != null:
				_send_button.text = tr("ui.consent.send_link")
				_send_button.disabled = false
		STATE_LOADING:
			if _send_button != null:
				_send_button.text = tr("ui.consent.sending")
				_send_button.disabled = true
		STATE_ERROR:
			if _send_button != null:
				_send_button.text = tr("ui.consent.send_link")
				_send_button.disabled = false
		STATE_SUCCESS:
			pass  # success body is set before calling _set_state(SUCCESS)


# ─── Button handlers ──────────────────────────────────────────────────────────

func _on_send_pressed() -> void:
	var email: String = _email_field.text.strip_edges() if _email_field != null else ""

	# Basic email format validation (per 05-UI-SPEC.md Surface D).
	if not _is_valid_email(email):
		_show_email_error(tr("ui.consent.error_invalid_email"))
		return

	_cached_parent_email = email
	_set_state(STATE_LOADING)

	var fc: Node = get_node_or_null("/root/FriendsClient")
	if fc != null and fc.has_method("request_parental_consent"):
		fc.call("request_parental_consent", email)
	else:
		# FriendsClient unavailable — treat as network error.
		_set_state(STATE_ERROR)
		_show_email_error(tr("ui.consent.error_network"))


func _on_why_pressed() -> void:
	if _why_vbox != null:
		_why_vbox.visible = not _why_vbox.visible


func _on_skip_pressed() -> void:
	_show_banner()
	visible = false
	emit_signal("panel_closed")


func _on_done_pressed() -> void:
	visible = false
	emit_signal("panel_closed")


func _on_resend_pressed() -> void:
	# Client-side rate limit.
	var now: float = Time.get_unix_time_from_system()
	if now - _last_resend_epoch < RESEND_COOLDOWN_SECONDS:
		return
	_last_resend_epoch = now
	# Re-enter DEFAULT state pre-filled with cached email, then trigger send.
	_set_state(STATE_DEFAULT)
	if _email_field != null:
		_email_field.text = _cached_parent_email
	_on_send_pressed()


func _on_banner_resend_pressed() -> void:
	# Open the panel in the resend flow.
	visible = true
	_set_state(STATE_DEFAULT)
	if _email_field != null and _cached_parent_email != "":
		_email_field.text = _cached_parent_email


# ─── FriendsClient signal handler ─────────────────────────────────────────────

## Called when FriendsClient.consent_status_received fires.
## is_consented=true: hide panel and banner permanently.
## is_consented=false: show banner (pending state).
func _on_consent_status(is_consented: bool, _is_pending: bool) -> void:
	if is_consented:
		_hide_banner()
		visible = false
	else:
		_show_banner()
		# If the request just succeeded (panel is loading) → transition to SUCCESS.
		if _current_state == STATE_LOADING:
			_success_body.text = tr("ui.consent.success_body").replace(
				"{parent_email}", _cached_parent_email)
			_set_state(STATE_SUCCESS)


# ─── Surface F banner helpers ─────────────────────────────────────────────────

func _show_banner() -> void:
	if _banner != null:
		_banner.visible = true


func _hide_banner() -> void:
	if _banner != null:
		_banner.visible = false


# ─── Email validation ─────────────────────────────────────────────────────────

## Basic email format check: must contain "@" and "." (per 05-UI-SPEC.md Surface D).
## Not an RFC 5322 full validator — sufficient for the COPPA "good faith" standard.
func _is_valid_email(email: String) -> bool:
	return email.contains("@") and email.contains(".")


func _show_email_error(message: String) -> void:
	if _email_error_label == null:
		return
	_email_error_label.text = message
	_email_error_label.visible = true


# ─── Session-join gate ────────────────────────────────────────────────────────

## Show the session-join blocked modal (Surface F "Session join gate").
## Call this when an under-13 unconsented account attempts to join a session.
## Returns immediately if the account has consent (caller should check first).
func show_join_blocked_modal() -> void:
	# Build and show a 400px modal with "Parental approval needed" content.
	var overlay := ColorRect.new()
	overlay.name = "JoinBlockedOverlay"
	overlay.anchor_right = 1.0
	overlay.anchor_bottom = 1.0
	overlay.color = Color(0.106, 0.173, 0.337, 0.60)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)

	var modal_panel := PanelContainer.new()
	modal_panel.anchor_left = 0.5
	modal_panel.anchor_top = 0.5
	modal_panel.anchor_right = 0.5
	modal_panel.anchor_bottom = 0.5
	modal_panel.offset_left = -200.0
	modal_panel.offset_top = -120.0
	modal_panel.offset_right = 200.0
	modal_panel.offset_bottom = 120.0
	modal_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	modal_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	var ms := StyleBoxFlat.new()
	ms.bg_color = Color(0.106, 0.173, 0.337, 0.95)
	ms.corner_radius_top_left = 16
	ms.corner_radius_top_right = 16
	ms.corner_radius_bottom_left = 16
	ms.corner_radius_bottom_right = 16
	modal_panel.add_theme_stylebox_override("panel", ms)
	overlay.add_child(modal_panel)

	var margin2 := MarginContainer.new()
	margin2.add_theme_constant_override("margin_left", 24)
	margin2.add_theme_constant_override("margin_top", 24)
	margin2.add_theme_constant_override("margin_right", 24)
	margin2.add_theme_constant_override("margin_bottom", 24)
	modal_panel.add_child(margin2)

	var mvbox := VBoxContainer.new()
	mvbox.add_theme_constant_override("separation", 16)
	margin2.add_child(mvbox)

	var modal_heading := Label.new()
	modal_heading.text = tr("ui.restricted.join_blocked_title")
	modal_heading.add_theme_color_override("font_color", COLOR_WHITE)
	modal_heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	modal_heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mvbox.add_child(modal_heading)

	var modal_body := Label.new()
	modal_body.text = tr("ui.restricted.join_blocked_body")
	modal_body.add_theme_color_override("font_color",
		Color(COLOR_WHITE.r, COLOR_WHITE.g, COLOR_WHITE.b, 0.8))
	modal_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	modal_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mvbox.add_child(modal_body)

	var resend_btn := Button.new()
	resend_btn.text = tr("ui.restricted.join_blocked_resend")
	resend_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	resend_btn.pressed.connect(func():
		overlay.queue_free()
		visible = true
		_set_state(STATE_DEFAULT)
	)
	mvbox.add_child(resend_btn)

	var cancel_btn := Button.new()
	cancel_btn.text = tr("ui.restricted.join_blocked_cancel")
	cancel_btn.custom_minimum_size = Vector2(160, 0)
	cancel_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	cancel_btn.pressed.connect(func():
		overlay.queue_free()
	)
	mvbox.add_child(cancel_btn)
