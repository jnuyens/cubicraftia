# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# handover_screen.gd — Host failover overlay (Surface 9).
#
# Displays a full-screen semi-transparent overlay while host failover is in progress.
# Appears automatically when NetworkManager emits host_failover_started and dismisses
# (0.22 s fade-out + queue_free) on host_failover_complete. Not dismissible by the player.
#
# After SLOW_THRESHOLD_S (8 s) without a completion signal, the subtitle updates to
# tr("ui.handover.subtitle_slow") tinted COLOR_RELAY_AMBER — a visual cue that the
# failover is taking longer than expected (T-04-09-D mitigation).
#
# CanvasLayer layer=100 (above all UI except critical system dialogs).
#
# Threat mitigations:
#   T-04-09-D: 8-second slow threshold updates subtitle; network-level timeout handled by
#              NetworkManager (5-minute reconnect window → emits host_failover_failed).
#
# References:
#   04-09-PLAN.md Task 1
#   04-UI-SPEC.md Surface 9 — Handover overlay
#   04-PATTERNS.md lines 588-618 — signal subscription + fade-out pattern

class_name HandoverScreen
extends CanvasLayer

# ─── Constants ────────────────────────────────────────────────────────────────

## Fade-out duration in seconds (matches panel animation duration across all surfaces).
const FADE_DURATION_S := 0.22

## After this many seconds without host_failover_complete, update subtitle to slow variant.
const SLOW_THRESHOLD_S := 8.0

## Relay amber colour for the slow-subtitle warning (UI-SPEC accent for relay/TURN path).
const COLOR_RELAY_AMBER := Color(0.910, 0.537, 0.047, 1.0)

## Navy background colour with 0.88 alpha (dominant navy per UI-SPEC Surface 9).
const COLOR_BACKGROUND := Color(0.106, 0.173, 0.337, 0.88)

# ─── Node refs ────────────────────────────────────────────────────────────────

# CanvasLayer has no `modulate` (that is a CanvasItem property), so all fade/alpha
# operations target the Background ColorRect, which is the visible CanvasItem.
@onready var _background: ColorRect = $Background
@onready var _heading_label: Label = $Background/Content/Heading
@onready var _subtitle_label: Label = $Background/Content/Subtitle
@onready var _spinner: AnimatedSprite2D = $Background/Content/Spinner

# ─── Private state ────────────────────────────────────────────────────────────

## Active fade-out tween (killed before creating a new one — tween-kill pattern).
var _tween: Tween = null

## One-shot timer: fires SLOW_THRESHOLD_S after failover starts → slow subtitle.
var _slow_subtitle_timer: Timer = null

# ─── Lifecycle ────────────────────────────────────────────────────────────────

func _ready() -> void:
	# Start hidden — shown only on host_failover_started.
	visible = false
	_background.modulate.a = 1.0

	# Create the slow-subtitle one-shot timer.
	_slow_subtitle_timer = Timer.new()
	_slow_subtitle_timer.one_shot = true
	_slow_subtitle_timer.wait_time = SLOW_THRESHOLD_S
	_slow_subtitle_timer.timeout.connect(_on_slow_threshold)
	add_child(_slow_subtitle_timer)

	# Subscribe to NetworkManager failover signals.
	if is_instance_valid(NetworkManager):
		NetworkManager.host_failover_started.connect(_on_failover_started)
		NetworkManager.host_failover_complete.connect(_on_failover_complete)


# ─── Signal handlers ──────────────────────────────────────────────────────────

## Show the overlay when host failover begins.
func _on_failover_started() -> void:
	visible = true
	_background.modulate.a = 1.0
	# Set heading and subtitle via tr() — defaults in .tscn are empty.
	_heading_label.text = tr("ui.handover.heading")
	_subtitle_label.text = tr("ui.handover.subtitle")
	_subtitle_label.modulate = Color.WHITE
	_slow_subtitle_timer.start()


## Fade out and free the overlay when failover completes successfully.
func _on_failover_complete(_new_host_peer_id: int) -> void:
	_slow_subtitle_timer.stop()
	# Kill any running tween before creating a new one (04-PATTERNS.md lines 986-994).
	if _tween != null and _tween.is_running():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(_background, "modulate:a", 0.0, FADE_DURATION_S) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_tween.tween_callback(queue_free)


## Update subtitle to slow-warning copy after SLOW_THRESHOLD_S elapses.
func _on_slow_threshold() -> void:
	_subtitle_label.text = tr("ui.handover.subtitle_slow")
	_subtitle_label.modulate = COLOR_RELAY_AMBER
