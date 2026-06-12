# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# hp_bar.gd — horizontal HP bar HUD (survival mode only).
#
# Shown in survival worlds; hidden in sandbox via Features.is_survival_mode() gate
# (mirrors tool_durability_bar.gd L62 pattern).
#
# Art:
#   The bar uses the authored HUD gauge sprite xp_bar_fill.png (the green-yellow-red
#   segmented brick gauge cropped label-free from art-hud.png). It is shown as the
#   "progress" texture of a TextureProgressBar in FILL_LEFT_TO_RIGHT mode, so the
#   visible fill width tracks the HP fraction: full HP shows the whole gauge, half HP
#   reveals the left half, etc. A thin framed panel (navy + parchment border) sits
#   behind the gauge so the empty (un-filled) portion still reads as a bar.
#
#   Driven by Builder.hp_changed (HP in [0, Builder.MAX_HP], MAX_HP = 10). The bar
#   pulses gently when HP is low (<= LOW_HP_THRESHOLD).
#
#   If the gauge PNG is unavailable at runtime, the bar degrades gracefully to a flat
#   coloured ProgressBar-style fill (#D63828 red over a grey track) drawn via a
#   StyleBoxFlat fallback, so the bar is still usable.
#
# Screen-reader: the bar's accessibility string uses tr("ui.hp.bar_sr")
# (owned by Plan 03-05 locale/en.po).
#
# References:
#   03-UI-SPEC.md L72 — top-left anchor, 16px from edge + safe-area inset
#   03-UI-SPEC.md L111 — #D63828 for the fallback fill
#   03-CONTEXT.md D-08 — HP bar as primary survival HUD element
#   tool_durability_bar.gd — sibling survival-gated HUD bar pattern

class_name HpBar
extends PanelContainer

# ─── Constants ────────────────────────────────────────────────────────────────

## On-screen size of the gauge in pixels (width x height). The authored gauge is a
## wide, short strip; these proportions keep its segmented brick read.
const BAR_WIDTH_PX: int = 180
const BAR_HEIGHT_PX: int = 18

## At or below this HP the bar pulses to warn the player.
const LOW_HP_THRESHOLD: int = 4

## Path to the horizontal gauge sprite (label-free, cropped from art-hud.png).
const ICON_GAUGE: String = "res://assets/textures/icons/xp_bar_fill.png"

## Fallback colours used only if the gauge PNG is unavailable at runtime.
const COLOR_FILL: Color = Color(0.839, 0.220, 0.157, 1.0)    # #D63828 destructive red
const COLOR_TRACK: Color = Color(0.533, 0.533, 0.533, 0.5)   # mid-grey at 50%

## Framed-panel styling (drawn behind the gauge).
const PANEL_BG: Color = Color(0.106, 0.173, 0.337, 0.55)     # navy at 55% (UI-SPEC surface)
const PANEL_BORDER: Color = Color(0.945, 0.941, 0.914, 0.85) # #F1F0EA parchment border
const PANEL_PAD: int = 6
const PANEL_RADIUS: int = 8

## Empty-track styling drawn behind the fill so the un-filled portion reads.
const TRACK_BG: Color = Color(0.04, 0.07, 0.14, 0.85)        # near-black navy
const TRACK_RADIUS: int = 4

## Low-HP pulse: self.modulate.a oscillates between these over PULSE_PERIOD seconds.
const PULSE_MIN_ALPHA: float = 0.55
const PULSE_MAX_ALPHA: float = 1.0
const PULSE_PERIOD: float = 0.9

# ─── State ────────────────────────────────────────────────────────────────────

## The progress bar showing the gauge fill (TextureProgressBar when the PNG is
## available, ProgressBar fallback otherwise). Typed loosely as Range so both work.
var _bar: Range = null

## Cached reference to the builder node (wired in _ready).
var _builder: Builder = null

## Last HP value received, so _process can drive the low-HP pulse without re-querying.
var _current_hp: int = Builder.MAX_HP

## Elapsed time accumulator for the pulse animation (seconds).
var _pulse_t: float = 0.0

# ─── Lifecycle ────────────────────────────────────────────────────────────────

func _ready() -> void:
	# Survival-mode visibility gate (mirrors tool_durability_bar.gd L62).
	visible = Features.is_survival_mode()

	# Framed panel behind the bar.
	add_theme_stylebox_override("panel", _make_panel_style())

	# Build the progress bar (textured when art is available, flat fallback otherwise).
	_build_bar()

	# Accessibility label for screen readers.
	tooltip_text = tr("ui.hp.bar_sr")

	# Wire to the Builder hp_changed signal.
	var b: Node = get_tree().get_first_node_in_group("builder")
	if b != null and b.has_signal("hp_changed"):
		b.hp_changed.connect(_on_hp_changed)
		_builder = b as Builder
		# Sync current HP immediately.
		var start_hp: int = Builder.MAX_HP
		if b.get("hp") != null:
			start_hp = int(b.get("hp"))
		_on_hp_changed(start_hp)
	else:
		_on_hp_changed(_current_hp)

	# Only run _process while the bar is visible (pulse is the only per-frame work).
	# main_scene.gd may force visible=true after our _ready (it opens WorldSave and
	# re-checks survival mode), so keep _process in sync with actual visibility via
	# NOTIFICATION_VISIBILITY_CHANGED rather than freezing it to the _ready value.
	set_process(visible)


## Keep per-frame processing tied to actual visibility. The bar starts hidden in
## sandbox; main_scene re-shows it in survival after WorldSave opens. Without this,
## the low-HP pulse would stay frozen because _process was disabled at _ready time.
func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED:
		set_process(visible)


## Build the StyleBoxFlat used for the framed panel behind the bar.
func _make_panel_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL_BG
	sb.set_content_margin_all(PANEL_PAD)
	sb.set_corner_radius_all(PANEL_RADIUS)
	sb.set_border_width_all(2)
	sb.border_color = PANEL_BORDER
	return sb


## Build the progress bar. Prefers a TextureProgressBar driven by the authored gauge
## sprite (FILL_LEFT_TO_RIGHT). Falls back to a flat-styled ProgressBar if the PNG is
## unavailable so the bar still renders and tracks HP.
func _build_bar() -> void:
	if _bar != null and is_instance_valid(_bar):
		_bar.queue_free()
		_bar = null

	if ResourceLoader.exists(ICON_GAUGE, "Texture2D"):
		var tpb := TextureProgressBar.new()
		tpb.name = "Gauge"
		tpb.custom_minimum_size = Vector2(BAR_WIDTH_PX, BAR_HEIGHT_PX)
		tpb.min_value = 0.0
		tpb.max_value = float(Builder.MAX_HP)
		tpb.value = float(_current_hp)
		tpb.step = 0.0
		tpb.nine_patch_stretch = true
		tpb.fill_mode = TextureProgressBar.FILL_LEFT_TO_RIGHT
		tpb.texture_progress = load(ICON_GAUGE)
		# Empty-track background so the un-filled portion reads as a bar.
		tpb.add_theme_stylebox_override("background", _make_track_style())
		_bar = tpb
	else:
		var pb := ProgressBar.new()
		pb.name = "Gauge"
		pb.custom_minimum_size = Vector2(BAR_WIDTH_PX, BAR_HEIGHT_PX)
		pb.min_value = 0.0
		pb.max_value = float(Builder.MAX_HP)
		pb.value = float(_current_hp)
		pb.step = 0.0
		pb.show_percentage = false
		pb.add_theme_stylebox_override("background", _make_track_style())
		pb.add_theme_stylebox_override("fill", _make_fill_style())
		_bar = pb

	add_child(_bar)


## Empty-track StyleBoxFlat (the bar background behind the fill).
func _make_track_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = TRACK_BG
	sb.set_corner_radius_all(TRACK_RADIUS)
	return sb


## Flat-fill StyleBoxFlat used only by the ProgressBar fallback.
func _make_fill_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = COLOR_FILL
	sb.set_corner_radius_all(TRACK_RADIUS)
	return sb


# ─── Per-frame ────────────────────────────────────────────────────────────────

## Drive the low-HP pulse. Cheap: only mutates self.modulate.a when HP is low,
## and settles it back once on recovery. No allocations.
func _process(delta: float) -> void:
	if _current_hp <= LOW_HP_THRESHOLD and _current_hp > 0:
		_pulse_t += delta
		var phase: float = sin(_pulse_t * TAU / PULSE_PERIOD) * 0.5 + 0.5  # 0..1
		modulate.a = lerpf(PULSE_MIN_ALPHA, PULSE_MAX_ALPHA, phase)
	elif modulate.a != 1.0:
		# Recovered (or dead) — settle back to fully opaque.
		_pulse_t = 0.0
		modulate.a = 1.0


# ─── Signal handler ───────────────────────────────────────────────────────────

## Update the bar fill when builder HP changes. The visible fill width tracks the
## HP fraction directly (value = new_hp over [0, MAX_HP]).
## @param new_hp  New HP value [0..MAX_HP].
func _on_hp_changed(new_hp: int) -> void:
	_current_hp = clampi(new_hp, 0, Builder.MAX_HP)
	if _bar != null and is_instance_valid(_bar):
		_bar.value = float(_current_hp)
