# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# death_screen.gd — Full-screen death overlay: 3-second fade-to-black then respawn dispatch.
#
# Extends ColorRect. Fades from transparent to OVERLAY_ALPHA (0.92) over 3 seconds
# (tween pattern mirrors toast.gd L78-88). After the fade, calls the _respawn_callback
# passed by Builder._on_death.
#
# Added to group "death_screen" so Builder._on_death can find it via
# get_tree().get_first_node_in_group("death_screen").
#
# All user-visible strings use tr() keys (owned by Plan 03-05 locale/en.po):
#   "ui.death.headline"       — "You died"
#   "ui.death.subtitle"       — "Respawning at your bed…"
#   "ui.death.subtitle_spawn" — "Respawning at world spawn…"
#   "ui.death.countdown"      — "Respawning in {n}s"
#
# Per test_death_respawn.gd test 6: DeathScreen must have a "respawn_ready" signal.
# The signal is emitted just before _respawn_callback fires, so test code can
# assert_signal_emitted without waiting 3 real seconds.
#
# References:
#   03-UI-SPEC.md L226-228 — 28px Display semibold at 40% screen height
#   03-CONTEXT.md D-08 — death overlay as part of damage/death feel
#   03-CONTEXT.md D-12 — 3-second fade before respawn
#   03-PATTERNS.md L695-757 — death-screen analog: toast.gd Tween pattern

class_name DeathScreen
extends ColorRect

# ─── Signals ──────────────────────────────────────────────────────────────────

## Emitted just before the respawn callback fires (after the 3 s fade).
## Plan 03-11 and test_death_respawn.gd listen for this.
signal respawn_ready()

# ─── Constants ────────────────────────────────────────────────────────────────

## Duration of the fade-to-black overlay in seconds (D-12).
const FADE_DURATION_S: float = 3.0

## Target alpha of the death overlay after the fade.
const OVERLAY_ALPHA: float = 0.92

## Number of seconds the countdown starts at (matches FADE_DURATION_S).
const COUNTDOWN_START_S: float = 3.0

# ─── Node references ──────────────────────────────────────────────────────────

@onready var _headline_label: Label = $Headline
@onready var _subtitle_label: Label = $Subtitle
@onready var _countdown_label: Label = $Countdown

# ─── State ────────────────────────────────────────────────────────────────────

var _tween: Tween = null
var _respawn_callback: Callable = Callable()
var _countdown_elapsed: float = 0.0

# ─── Lifecycle ────────────────────────────────────────────────────────────────

func _ready() -> void:
	# Navy #1B2C56 at alpha=0 per UI-SPEC L108. Alpha starts transparent.
	color = Color(0.106, 0.173, 0.337, 0.0)
	# Block all clicks during death so the player cannot interact with the world.
	mouse_filter = MOUSE_FILTER_STOP
	# Hidden until start_fade is called.
	visible = false
	# Deferred process (countdown ticker) only active when visible.
	set_process(false)
	# Register so Builder._on_death can find this via get_first_node_in_group.
	add_to_group("death_screen")
	# Set label text now so translations apply immediately.
	if _headline_label != null:
		_headline_label.text = tr("ui.death.headline")


func _process(delta: float) -> void:
	if not visible:
		set_process(false)
		return
	_countdown_elapsed += delta
	var remaining: int = max(0, int(ceil(COUNTDOWN_START_S - _countdown_elapsed)))
	if _countdown_label != null:
		_countdown_label.text = tr("ui.death.countdown").format({"n": str(remaining)})


# ─── Public API ───────────────────────────────────────────────────────────────

## Start the death overlay fade. Called by Builder._on_death.
## @param has_slept_in_bed  Controls which subtitle shows ("bed" vs "spawn" variant).
## @param on_complete       Callable to invoke at the end of the fade (Builder._on_respawn_dispatch).
func start_fade(has_slept_in_bed: bool, on_complete: Callable) -> void:
	_respawn_callback = on_complete
	if _subtitle_label != null:
		_subtitle_label.text = tr("ui.death.subtitle") if has_slept_in_bed else tr("ui.death.subtitle_spawn")
	if _countdown_label != null:
		_countdown_label.text = tr("ui.death.countdown").format({"n": "3"})
	_countdown_elapsed = 0.0
	visible = true
	set_process(true)

	# Cancel any existing tween before starting a new one (e.g. rapid deaths).
	if _tween != null and _tween.is_valid():
		_tween.kill()

	# Fade from transparent to OVERLAY_ALPHA over FADE_DURATION_S (mirror of toast.gd L78-88).
	_tween = create_tween()
	_tween.tween_property(self, "color:a", OVERLAY_ALPHA, FADE_DURATION_S)\
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_tween.tween_callback(_on_fade_complete)


## Also called by test_death_respawn.gd test 6 (legacy API compatibility).
func show_death_screen() -> void:
	start_fade(false, Callable())


# ─── Private helpers ──────────────────────────────────────────────────────────

## Called by the tween when the 3-second fade completes.
## Emits respawn_ready, invokes the callback, then hides and resets the overlay.
func _on_fade_complete() -> void:
	respawn_ready.emit()
	if _respawn_callback.is_valid():
		_respawn_callback.call()
	# Reset for possible reuse (e.g. hardcore mode with multiple deaths).
	visible = false
	color.a = 0.0
	set_process(false)
