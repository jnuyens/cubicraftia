# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# weather.gd — Weather autoload: Clear ↔ Rain Markov state machine with rain-dance quota.
#
# Registered as autoload "Weather" in project.godot (after WorldClock, before BrickRegistry
# per the Plan 02-05 load-order contract).
#
# Weather state transitions are driven by WorldClock.day_boundary — one Markov roll per
# Cubicraftia day. The RNG is seeded from the world's world_seed XOR'd with a salt so the
# weather stream is decorrelated from terrain generation (02-RESEARCH.md §Pattern 1 line 473).
#
# Rain-dance API (DOCS §2.4):
#   A builder (identified by stable UUID — Pitfall 8) can trigger rain at most once per
#   Cubicraftia day. Second attempt returns {"accepted": false, "message_key":
#   "ui.weather.sky_wont_listen_again_today"}. Quota persists across sessions via WorldSave.
#
# Pitfall 8 mitigation: quota keyed on builder_id (UUID string), NOT on username.
#   Phase 4 multiplayer will pass the account_id; Phase 2 uses a local UUID stored in
#   user://settings.cfg. This ensures quota survives Phase 4 username changes.
#
# Persistence:
#   weather_state → WorldSave.set_world_meta("weather_state", ...)
#   rain_dance_quota → WorldSave.set_world_meta("rain_dance_quota", ...)
#
# References:
#   DOCS.md §2.4 — rain dance ≤ 1/Cubicraftia-day/builder
#   02-RESEARCH.md §"Pattern 6: Day/night clock + weather" (lines 869–899)
#   02-RESEARCH.md §"Pitfall 8" (rain dance keyed on stable UUID)
#   02-PATTERNS.md §"src/autoload/weather.gd" (analog: features.gd + thermal_probe.gd)

extends Node

# ─── State enum ──────────────────────────────────────────────────────────────

enum State { CLEAR = 0, RAIN = 1 }

# ─── Signals ─────────────────────────────────────────────────────────────────

## Emitted when the weather state changes (e.g. after a day boundary Markov roll
## or after a successful rain dance).
signal state_changed(new_state: State)

# ─── Public state ─────────────────────────────────────────────────────────────

## Current weather state.
var state: State = State.CLEAR

# ─── Private state ────────────────────────────────────────────────────────────

## RNG for Markov transitions — seeded from world_seed XOR salt on attach_world().
var _rng: RandomNumberGenerator = null

## Quota map: builder_id (UUID string) → Cubicraftia day index when last used.
## Value is an int (the day index), not a bool — so the quota resets automatically
## when WorldClock.current_day_index advances.
## Persisted to WorldSave as "rain_dance_quota".
var _rain_dance_used: Dictionary = {}

## XOR salt to decorrelate weather RNG from terrain/biome RNG streams.
## (02-RESEARCH.md §Pattern 1 line 473 names this pattern.)
const _WEATHER_SEED_SALT: int = 0x7EA7E5

# ─── Lifecycle ────────────────────────────────────────────────────────────────

## Autoload _ready: RNG is created but not seeded yet — seed is applied lazily in
## attach_world() because the world is not open at autoload _ready time.
func _ready() -> void:
	_rng = RandomNumberGenerator.new()


# ─── Public API ───────────────────────────────────────────────────────────────

## Attach to an open world: seed the RNG from world_seed, restore persisted state,
## and connect to WorldClock.day_boundary.
##
## Call after WorldSave.open_world() (main_scene or test fixture).
## Safe to call multiple times; reconnects cleanly.
func attach_world() -> void:
	if not WorldSave.is_open():
		push_warning("Weather.attach_world: WorldSave is not open — cannot seed RNG.")
		return

	var world_seed_variant: Variant = WorldSave.get_world_meta("world_seed")
	var world_seed: int = 1234  # safe fallback if not set yet
	if world_seed_variant != null and world_seed_variant is int:
		world_seed = int(world_seed_variant)

	_rng.seed = world_seed ^ _WEATHER_SEED_SALT

	# Restore persisted state before connecting signals (avoids spurious emissions).
	load_from_world_save()

	# Connect to WorldClock.day_boundary (safe double-connect guard).
	if not WorldClock.day_boundary.is_connected(_on_day_boundary):
		WorldClock.day_boundary.connect(_on_day_boundary)


## Returns true if the builder is allowed to trigger the rain dance today
## (i.e. they have not already used it during the current Cubicraftia day).
## @param builder_id  Stable UUID string for the builder (Pitfall 8).
func can_rain_dance(builder_id: String) -> bool:
	var last_used_day: int = _rain_dance_used.get(builder_id, -1)
	return last_used_day != WorldClock.current_day_index


## Attempt to trigger the rain dance for a builder.
## Returns {"accepted": bool, "message_key": String}.
## @param builder_id  Stable UUID string for the builder (Pitfall 8).
func trigger_rain_dance(builder_id: String) -> Dictionary:
	if not can_rain_dance(builder_id):
		return {
			"accepted": false,
			"message_key": "ui.weather.sky_wont_listen_again_today"
		}

	# Accept: switch to rain immediately.
	state = State.RAIN
	state_changed.emit(state)

	# Record quota usage for this builder today.
	record_rain_dance(builder_id)

	return {
		"accepted": true,
		"message_key": "ui.weather.rain_dance_summoned"
	}


## Record that a builder has used their rain dance quota for the current day.
## Exposed separately so Plan 14's rain-dance action handler can call it if needed.
## @param builder_id  Stable UUID string for the builder (Pitfall 8).
func record_rain_dance(builder_id: String) -> void:
	_rain_dance_used[builder_id] = WorldClock.current_day_index
	_persist_to_world_save()


## Restore weather state and rain-dance quota from WorldSave.
## Called by attach_world() and (in tests) directly.
func load_from_world_save() -> void:
	if not WorldSave.is_open():
		return

	var weather_variant: Variant = WorldSave.get_world_meta("weather_state")
	if weather_variant != null and weather_variant is Dictionary:
		var d: Dictionary = weather_variant as Dictionary
		if d.has("state"):
			state = d.get("state", State.CLEAR) as State

	var quota_variant: Variant = WorldSave.get_world_meta("rain_dance_quota")
	if quota_variant != null and quota_variant is Dictionary:
		_rain_dance_used = quota_variant as Dictionary


# ─── Private helpers ──────────────────────────────────────────────────────────

## WorldClock.day_boundary handler: roll the Markov state machine.
## CLEAR → RAIN with probability 0.30.
## RAIN → CLEAR with probability 0.50.
## (Values from DOCS §2.4 "rain alternates over Cubicraftia days".)
func _on_day_boundary(_new_day_index: int) -> void:
	var roll: float = _rng.randf()
	if state == State.CLEAR and roll < 0.30:
		state = State.RAIN
	elif state == State.RAIN and roll < 0.50:
		state = State.CLEAR
	state_changed.emit(state)
	_persist_to_world_save()


## Persist weather state and rain-dance quota to WorldSave.
func _persist_to_world_save() -> void:
	if not WorldSave.is_open():
		return
	WorldSave.set_world_meta("weather_state", {
		"state": state,
	})
	WorldSave.set_world_meta("rain_dance_quota", _rain_dance_used.duplicate())
