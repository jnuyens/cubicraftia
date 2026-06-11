# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# weather.gd — Weather autoload: infrequent short rain bursts with a rain-dance quota.
#
# Registered as autoload "Weather" in project.godot (after WorldClock, before BrickRegistry
# per the Plan 02-05 load-order contract).
#
# Rain model (QA-tuned): each Cubicraftia day boundary rolls whether a dry day turns rainy
# (_RAIN_CHANCE_PER_DAY ~1/7 → roughly once per in-game week, with long dry spells). When
# rain starts it is a SHORT bounded burst (_RAIN_MIN/MAX_SECONDS, 2-5 min) that _process
# auto-clears off WorldClock game-time — NOT a multi-day downpour. The RNG is seeded from
# the world's world_seed XOR'd with a salt so the weather stream is decorrelated from
# terrain generation (02-RESEARCH.md §Pattern 1 line 473) and stays deterministic per seed.
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

## WorldClock.elapsed_seconds at which the current rain burst auto-clears.
## -1.0 means no active rain burst. Rain is a SHORT, bounded sub-day event (a few
## minutes), NOT a multi-day Markov state — so the day-boundary roll only decides
## WHETHER it rains that day; this timestamp ends the burst within the day.
## Persisted to WorldSave so a reload mid-rain resumes the same end time.
var _rain_until_elapsed: float = -1.0

## Chance, per Cubicraftia day boundary, that a dry day turns rainy. A Cubicraftia
## day is 15 real minutes (WorldClock.SECONDS_PER_DAY), so ~1/7 makes rain begin
## roughly once per in-game week, with long dry spells in between (QA: "rain at most
## a few minutes at a time, infrequently, with dry spells").
const _RAIN_CHANCE_PER_DAY: float = 1.0 / 7.0

## Bounded rain-burst duration in real seconds (2-5 min). Capped well under one
## Cubicraftia day (900 s) so a burst never stretches into a multi-day downpour.
const _RAIN_MIN_SECONDS: float = 120.0
const _RAIN_MAX_SECONDS: float = 300.0

# ─── Lifecycle ────────────────────────────────────────────────────────────────

## Autoload _ready: RNG is created but not seeded yet — seed is applied lazily in
## attach_world() because the world is not open at autoload _ready time.
func _ready() -> void:
	_rng = RandomNumberGenerator.new()


## Per-frame: end the current rain burst once WorldClock has passed its scheduled end
## time. Rain is a short bounded event (a few minutes), so this is what actually stops
## it — the day-boundary roll only ever STARTS rain. Driven by WorldClock.elapsed_seconds
## (game time, sleep-lapse aware) rather than wall-clock or frame delta so it stays
## consistent with the day/night clock and survives mobile backgrounding.
func _process(_delta: float) -> void:
	if state != State.RAIN:
		return
	if _rain_until_elapsed < 0.0:
		return
	if WorldClock.elapsed_seconds >= _rain_until_elapsed:
		state = State.CLEAR
		_rain_until_elapsed = -1.0
		state_changed.emit(state)
		_persist_to_world_save()


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

	# Accept: start a bounded rain burst immediately (same short duration as a natural
	# burst, so a summoned rain still clears after a few minutes rather than lasting forever).
	_start_rain()

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
		# Resume the in-progress rain burst's end time (so a mid-rain reload clears on
		# schedule rather than raining forever). Older saves lack this key → default -1.
		_rain_until_elapsed = float(d.get("rain_until_elapsed", -1.0))

	var quota_variant: Variant = WorldSave.get_world_meta("rain_dance_quota")
	if quota_variant != null and quota_variant is Dictionary:
		_rain_dance_used = quota_variant as Dictionary


# ─── Private helpers ──────────────────────────────────────────────────────────

## WorldClock.day_boundary handler: decide whether a NEW rain burst starts today.
## Rain is infrequent and short (QA: "at most a few minutes at a time, infrequently,
## with dry spells"): a dry day turns rainy with probability _RAIN_CHANCE_PER_DAY
## (~1/7, i.e. roughly once per in-game week). When rain starts, _start_rain schedules
## a bounded 2-5 minute burst that _process auto-clears; the burst is NOT re-rolled or
## extended on later day boundaries, so it never becomes a multi-day downpour.
func _on_day_boundary(_new_day_index: int) -> void:
	var roll: float = _rng.randf()
	if state == State.CLEAR and roll < _RAIN_CHANCE_PER_DAY:
		_start_rain()
	# A burst already in progress is left alone — _process ends it on schedule.
	_persist_to_world_save()


## Begin a bounded rain burst: switch to RAIN and schedule its end a few minutes out
## (via WorldClock game-time so it stays in sync with the day/night clock). Shared by
## the day-boundary roll and the rain-dance trigger so summoned rain is also bounded.
func _start_rain() -> void:
	state = State.RAIN
	var duration: float = _rng.randf_range(_RAIN_MIN_SECONDS, _RAIN_MAX_SECONDS)
	_rain_until_elapsed = WorldClock.elapsed_seconds + duration
	state_changed.emit(state)


## Persist weather state and rain-dance quota to WorldSave.
func _persist_to_world_save() -> void:
	if not WorldSave.is_open():
		return
	WorldSave.set_world_meta("weather_state", {
		"state": state,
		"rain_until_elapsed": _rain_until_elapsed,
	})
	WorldSave.set_world_meta("rain_dance_quota", _rain_dance_used.duplicate())
