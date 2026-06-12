# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# hp_bar.gd — heart HP bar HUD (survival mode only).
#
# Shown in survival worlds; hidden in sandbox via Features.is_survival_mode() gate
# (mirrors tool_durability_bar.gd L62 pattern).
#
# Heart icons:
#   heart_full.png / heart_half.png / heart_empty.png from assets/textures/icons/.
#   These are the brick-styled heart sprites cropped label-free from the HUD art
#   sheet. The bar shows the authored sprite colours directly (red brick heart on
#   full, half-red on half, grey outline on empty) — NO flat colour-tint overlay,
#   so the art reads as intended. A subtle framed panel sits behind the row and
#   the whole bar pulses gently when HP is low (<= LOW_HP_THRESHOLD).
#
#   MAX_HP is 10 and there are HEART_COUNT (5) hearts, so each heart represents
#   2 HP: full = 2, half = 1, empty = 0. (Earlier the bar drew 10 one-HP hearts
#   that were flat-colour-tinted, which hid the heart art; 5 two-HP hearts using
#   the half-heart sprite is the classic, more compact read and finally uses the
#   half-heart art that previously shipped unused.)
#
#   If the cropped PNGs are somehow unavailable at runtime, each heart degrades
#   gracefully to a square ColorRect (#D63828 full, grey empty) so the bar is
#   still usable.
#
# Screen-reader: the overall bar Label accessibility string uses tr("ui.hp.bar_sr")
# (owned by Plan 03-05 locale/en.po).
#
# References:
#   03-UI-SPEC.md L72 — top-left anchor, 16px from edge + safe-area inset
#   03-UI-SPEC.md L111 — #D63828 for full hearts (fallback only)
#   03-CONTEXT.md D-08 — HP bar as primary survival HUD element
#   03-PATTERNS.md L695-757 — HP bar analog: hotbar.gd _build_slots

class_name HpBar
extends PanelContainer

# ─── Constants ────────────────────────────────────────────────────────────────

## Number of heart sprites in the bar. Each heart covers 2 HP (full/half/empty),
## so HEART_COUNT * HP_PER_HEART must equal Builder.MAX_HP (10).
const HEART_COUNT: int = 5

## HP each heart represents (full heart = HP_PER_HEART, half = HP_PER_HEART / 2).
const HP_PER_HEART: int = 2

## Heart icon size in pixels.
const HEART_SIZE_PX: int = 28

## Gap between hearts in pixels.
const HEART_GAP_PX: int = 2

## At or below this HP the bar pulses to warn the player.
const LOW_HP_THRESHOLD: int = 4

## Path to the full-heart sprite (label-free brick heart).
const ICON_FULL: String = "res://assets/textures/icons/heart_full.png"

## Path to the half-heart sprite.
const ICON_HALF: String = "res://assets/textures/icons/heart_half.png"

## Path to the empty-heart sprite (grey brick outline).
const ICON_EMPTY: String = "res://assets/textures/icons/heart_empty.png"

## Fallback colours used only if the PNG sprites are unavailable at runtime.
const COLOR_FULL: Color = Color(0.839, 0.220, 0.157, 1.0)   # #D63828 destructive red
const COLOR_EMPTY: Color = Color(0.533, 0.533, 0.533, 0.5)  # mid-grey at 50%

## Framed-panel styling (drawn behind the hearts).
const PANEL_BG: Color = Color(0.106, 0.173, 0.337, 0.55)     # navy at 55% (UI-SPEC surface)
const PANEL_BORDER: Color = Color(0.945, 0.941, 0.914, 0.85) # #F1F0EA parchment border
const PANEL_PAD: int = 6
const PANEL_RADIUS: int = 8

## Low-HP pulse: self.modulate.a oscillates between these over PULSE_PERIOD seconds.
const PULSE_MIN_ALPHA: float = 0.55
const PULSE_MAX_ALPHA: float = 1.0
const PULSE_PERIOD: float = 0.9

# ─── State ────────────────────────────────────────────────────────────────────

## Row container holding the heart nodes.
var _row: HBoxContainer = null

## Array of heart display nodes (TextureRect when PNG available, ColorRect fallback).
var _hearts: Array = []

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

	# Framed panel behind the hearts.
	add_theme_stylebox_override("panel", _make_panel_style())

	# Inner row of hearts.
	_row = HBoxContainer.new()
	_row.name = "HeartRow"
	_row.add_theme_constant_override("separation", HEART_GAP_PX)
	add_child(_row)

	# Build the heart row.
	_build_hearts()

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


## Build the StyleBoxFlat used for the framed panel behind the hearts.
func _make_panel_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL_BG
	sb.set_content_margin_all(PANEL_PAD)
	sb.set_corner_radius_all(PANEL_RADIUS)
	sb.set_border_width_all(2)
	sb.border_color = PANEL_BORDER
	return sb


## Build the heart display nodes. Uses TextureRect with the cropped PNG sprites
## if available, else a square ColorRect as a graceful fallback.
func _build_hearts() -> void:
	_hearts.clear()
	for child in _row.get_children():
		child.queue_free()

	var have_png: bool = ResourceLoader.exists(ICON_FULL, "Texture2D")
	for i: int in range(HEART_COUNT):
		if have_png:
			var tr_node := TextureRect.new()
			tr_node.name = "Heart%d" % (i + 1)
			tr_node.custom_minimum_size = Vector2(HEART_SIZE_PX, HEART_SIZE_PX)
			tr_node.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
			tr_node.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			tr_node.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
			tr_node.texture = load(ICON_FULL)
			_row.add_child(tr_node)
			_hearts.append(tr_node)
		else:
			var cr_node := ColorRect.new()
			cr_node.name = "Heart%d" % (i + 1)
			cr_node.custom_minimum_size = Vector2(HEART_SIZE_PX, HEART_SIZE_PX)
			cr_node.color = COLOR_FULL
			_row.add_child(cr_node)
			_hearts.append(cr_node)


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

## Update the heart display when builder HP changes. Each heart maps to 2 HP:
## full (>=2 remaining for this heart), half (exactly 1), empty (0). The sprites
## carry their own colour, so we do NOT tint full hearts — only dim empties a
## touch so the row still reads left-to-right.
## @param new_hp  New HP value [0..MAX_HP].
func _on_hp_changed(new_hp: int) -> void:
	_current_hp = clampi(new_hp, 0, Builder.MAX_HP)
	for i: int in range(HEART_COUNT):
		# HP that falls within this heart's 2-HP slice.
		var heart_hp: int = clampi(_current_hp - i * HP_PER_HEART, 0, HP_PER_HEART)
		var heart: Node = _hearts[i]
		if heart is TextureRect:
			var tr_heart: TextureRect = heart as TextureRect
			var icon_path: String = ICON_EMPTY
			if heart_hp >= HP_PER_HEART:
				icon_path = ICON_FULL
			elif heart_hp == 1:
				icon_path = ICON_HALF
			if ResourceLoader.exists(icon_path, "Texture2D"):
				tr_heart.texture = load(icon_path)
			# Sprites are pre-coloured; just dim empties slightly for contrast.
			tr_heart.modulate = Color(1, 1, 1, 1) if heart_hp > 0 else Color(1, 1, 1, 0.55)
		elif heart is ColorRect:
			var cr_heart: ColorRect = heart as ColorRect
			cr_heart.color = COLOR_FULL if heart_hp > 0 else COLOR_EMPTY
