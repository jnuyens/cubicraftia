# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# world_clock.gd — Cubicraftia day timer (Cubicraftia day = 15 real min: 10 day / 5 night).
#
# Registered as autoload "WorldClock" in project.godot (after WorldSave, before Weather
# per the Plan 02-05 load-order contract — Weather subscribes to day_boundary).
#
# Drives the day/night cycle (DOCS.md §2.3): sun/moon rotation, ambient tint blend,
# day_boundary signal that Weather + rain-dance quota consume.
#
# Persistence: clock_state serialised to world_meta via WorldSave.set_world_meta on every
# day boundary crossing.
#
# Pitfall 3 mitigation: _process uses Time.get_unix_time_from_system() (wall-clock) rather
# than the frame delta. This ensures the clock advances correctly when the game is
# backgrounded on mobile (the OS pauses _process but real time keeps passing). On resume,
# a single _process tick catches up — wall_delta is capped at SECONDS_PER_DAY to prevent
# day_boundary from firing more than once per _process tick.
#
# References:
#   DOCS.md §2.3 — Cubicraftia day = ~15 real minutes (10 day / 5 night)
#   02-RESEARCH.md §"Pattern 6: Day/night clock" (lines 832–867)
#   02-RESEARCH.md §"Pitfall 3" (background-tick survival on mobile)
#   02-PATTERNS.md §"src/autoload/world_clock.gd" (analog: thermal_probe.gd)

extends Node

# ─── Constants ───────────────────────────────────────────────────────────────

## Cubicraftia day length in real seconds (15 min per DOCS §2.3).
const SECONDS_PER_DAY: float = 900.0

## Fraction of the day that is daytime (10 of 15 min = 0.666…).
const DAY_FRACTION: float = 600.0 / 900.0

## Fraction of the day that is night (5 of 15 min = 0.333…).
const NIGHT_FRACTION: float = 300.0 / 900.0

# ─── Phase enum ──────────────────────────────────────────────────────────────

## Day/night phase. Progress thresholds:
##   DAWN  [0.00, 0.05)
##   DAY   [0.05, 0.65)
##   DUSK  [0.65, 0.70)
##   NIGHT [0.70, 1.00)
enum Phase { DAWN, DAY, DUSK, NIGHT }

# ─── Signals ─────────────────────────────────────────────────────────────────

## Emitted when the day/night phase changes (e.g. DAWN → DAY).
## @param new_phase      The new Phase enum value.
## @param day_progress   Normalised position in the day [0.0, 1.0).
signal phase_changed(new_phase: Phase, day_progress: float)

## Emitted exactly once per Cubicraftia day (at the day rollover point).
## Also triggers WorldSave persistence and Weather's Markov roll.
## @param cubicraftia_day_index  Zero-based day counter since the world was created.
signal day_boundary(cubicraftia_day_index: int)

## Emitted when a sleep lapse ends (at dawn, on manual cancel, or on unsafe cancellation).
## @param reason  One of: "woke_at_dawn" | "cancelled_unsafe" | "cancelled_by_caller"
## Plan 03-04 Builder.sleep_interact listens for this to restore HP + close the lapse UI.
signal sleep_lapse_ended(reason: String)

# ─── State ───────────────────────────────────────────────────────────────────

## Total elapsed seconds since the world was created (across all sessions).
var elapsed_seconds: float = 0.0

## Current Cubicraftia day index (0 = first day, increments each day boundary).
var current_day_index: int = 0

## Current phase of the day.
var current_phase: Phase = Phase.DAWN

## Wall-clock anchor (Unix timestamp) captured on start()/resume().
## Used for Pitfall 3: computing the real elapsed time even across background pauses.
var _last_wall_unix: float = 0.0

## Whether the clock is currently ticking.
var _running: bool = false

## Sleep-lapse multiplier. 1.0 = normal; 10.0 = 10× acceleration during bed sleep.
## Reset to 1.0 by cancel_sleep_lapse(). Never persisted — multiplier is session-only
## per DOCS §5.5 ("sleep is per-session") and T-03-03-SPN-04 mitigation.
var _sleep_multiplier: float = 1.0

## Day-progress threshold at which the sleep lapse auto-wakes the builder.
## -1.0 means no active lapse. Set to 0.05 (DAWN threshold) by start_sleep_lapse().
var _sleep_target_progress: float = -1.0

# ─── Lifecycle ────────────────────────────────────────────────────────────────

## Autoload _ready: clock does not start until start() is called (e.g. by main_scene
## or a test fixture after opening a world).
func _ready() -> void:
	pass


## Per-frame update. Uses wall-clock delta (not the Godot frame delta) so the clock
## survives mobile backgrounding (Pitfall 3).
func _process(_delta: float) -> void:
	if not _running:
		return

	var now: float = Time.get_unix_time_from_system()
	# Apply the sleep-lapse multiplier to wall_delta per RESEARCH Code Examples L493.
	# _sleep_multiplier is 1.0 normally; 10.0 during a sleep lapse (start_sleep_lapse).
	# Pitfall 3 mitigation (mobile backgrounding) remains intact: the SECONDS_PER_DAY
	# cap below still acts as the absolute backstop regardless of the multiplier.
	var wall_delta: float = (now - _last_wall_unix) * _sleep_multiplier
	_last_wall_unix = now

	# Cap wall_delta to one day maximum. If the app was backgrounded for multiple
	# Cubicraftia days, we advance by at most one day — preventing a burst of
	# day_boundary signals in a single _process tick (Pitfall 3 debounce).
	if wall_delta > SECONDS_PER_DAY:
		wall_delta = SECONDS_PER_DAY

	elapsed_seconds += wall_delta

	var new_day: int = int(elapsed_seconds / SECONDS_PER_DAY)
	var day_progress: float = fmod(elapsed_seconds, SECONDS_PER_DAY) / SECONDS_PER_DAY
	var new_phase: Phase = _phase_from_progress(day_progress)

	if new_phase != current_phase:
		current_phase = new_phase
		phase_changed.emit(new_phase, day_progress)

	if new_day != current_day_index:
		current_day_index = new_day
		day_boundary.emit(new_day)
		_persist_to_world_save()

	# Wake-target check: auto-cancel the sleep lapse when day_progress crosses the
	# DAWN threshold (progress <= 0.05 + 0.01 tolerance per RESEARCH Code Examples L500).
	# The `progress >= 0.0` guard prevents spurious mid-day wakes (progress wraps from
	# ~0.99 at night back down to <0.05 at dawn; mid-day progress is always > 0.05).
	if _sleep_target_progress >= 0.0:
		var progress: float = current_day_progress()
		# Detect dawn wrap-around: progress drops from night (~0.7-0.99) back to dawn (<0.05).
		if progress <= _sleep_target_progress + 0.01 and progress >= 0.0:
			cancel_sleep_lapse("woke_at_dawn")


# ─── Public API ───────────────────────────────────────────────────────────────

## Start the clock. Call after WorldSave.open_world() (or load_from_world_save()).
## @param initial_elapsed_s  Resume from this many seconds (restored from world save).
func start(initial_elapsed_s: float = 0.0) -> void:
	elapsed_seconds = initial_elapsed_s
	current_day_index = int(elapsed_seconds / SECONDS_PER_DAY)
	var day_progress: float = fmod(elapsed_seconds, SECONDS_PER_DAY) / SECONDS_PER_DAY
	current_phase = _phase_from_progress(day_progress)
	_last_wall_unix = Time.get_unix_time_from_system()
	_running = true


## Pause the clock (e.g. when a menu is open or the app is about to background).
func pause() -> void:
	_running = false


## Resume the clock after pause(). Re-anchors _last_wall_unix to now so the pause
## duration does not count as game time.
func resume() -> void:
	_last_wall_unix = Time.get_unix_time_from_system()
	_running = true


## Returns true if the current phase is night.
func is_night() -> bool:
	return current_phase == Phase.NIGHT


## Returns true if a world position is in "deep dark" — ambient light below the
## v1 threshold (0.1). Used by hostile-spawn gating per DOCS §2.3.
## Phase 3 may revisit the 0.1 constant; Phase 2 ships it as canonical.
## @param world_pos      3D world position (unused in v1 — future proximity-to-light calc).
## @param ambient_light  Normalised ambient light level [0.0, 1.0].
func is_deep_dark(_world_pos: Vector3, ambient_light: float) -> bool:
	return ambient_light < 0.1


## Derived getter: day progress normalised [0.0, 1.0). Consumed by Plan 06's sky shader.
func current_day_progress() -> float:
	return fmod(elapsed_seconds, SECONDS_PER_DAY) / SECONDS_PER_DAY


## Begin a sleep lapse: multiply wall_delta by `multiplier` (default 10×) each tick.
## The lapse auto-cancels when day_progress crosses the DAWN threshold (0.05).
## Call cancel_sleep_lapse() explicitly to stop before dawn (e.g. on hostile detection).
##
## Per 03-CONTEXT.md D-12: solo sleep = accelerated 10× time-lapse.
## Per RESEARCH Code Examples L479-483.
##
## @param multiplier    Acceleration factor (default 10.0 per D-12).
## @param target_phase  Target wake phase (default DAWN — day_progress 0.05 threshold).
func start_sleep_lapse(multiplier: float = 10.0, target_phase: Phase = Phase.DAWN) -> void:
	_sleep_multiplier = multiplier
	# DAWN threshold per _phase_from_progress(): progress < 0.05.
	# target_phase is stored for future callers that may pass other phases;
	# in v1 the wake target is always fixed at DAWN (0.05).
	_sleep_target_progress = 0.05
	# Suppress "unused parameter" GDScript lint — target_phase forwarded in future.
	if target_phase != Phase.DAWN:
		# Non-DAWN targets would require computing per-phase thresholds;
		# v1 only supports DAWN wake-up per D-12.
		push_warning("WorldClock.start_sleep_lapse: target_phase %d is not yet supported; defaulting to DAWN." % target_phase)


## Cancel an active sleep lapse, restoring normal (1×) time flow.
## Emits sleep_lapse_ended(reason) so Plan 03-04 Builder.sleep_interact can:
##   - restore HP (bed-rest heals to full per D-12)
##   - close the lapse UI
##   - show the "unsafe" toast if reason == "cancelled_unsafe"
##
## @param reason  One of: "woke_at_dawn" | "cancelled_unsafe" | "cancelled_by_caller"
func cancel_sleep_lapse(reason: String = "cancelled_by_caller") -> void:
	_sleep_multiplier = 1.0
	_sleep_target_progress = -1.0
	sleep_lapse_ended.emit(reason)


## Cancel the sleep lapse with a specific unsafe reason.
## Convenience wrapper used by test_sleep_lapse.gd and Plan 03-04 when a hostile
## is detected inside the bed bubble (RESEARCH Pitfall 9).
## Also shows the toast key "ui.sleep.cancelled_unsafe" via the Toasts autoload.
func cancel_sleep_lapse_with_reason(_reason: String) -> void:
	cancel_sleep_lapse("cancelled_unsafe")
	# Show the "unsafe cancellation" toast (Toasts is always available as an autoload).
	# Toasts.show() emits "toast_requested" which the Phase 6 overlay scene connects to.
	if Toasts.has_method("show"):
		Toasts.show("ui.sleep.cancelled_unsafe", "warning")


## Instantly jump the clock to the next morning (used by the bed sleep cutscene, which
## fades to black, calls this, despawns night creatures, then fades back into day).
## Unlike start_sleep_lapse (a 10× time-lapse), this is a hard skip so the fade hides it.
## Emits phase_changed (so the sky/ambient update to day) and sleep_lapse_ended("woke_at_dawn")
## (so the builder restores HP), matching the lapse contract.
func skip_to_morning() -> void:
	var day_start: float = floor(elapsed_seconds / SECONDS_PER_DAY) * SECONDS_PER_DAY
	# Next day, ~12% in — comfortably into DAY (past the 0.05 DAWN threshold).
	elapsed_seconds = day_start + SECONDS_PER_DAY + 0.12 * SECONDS_PER_DAY
	current_day_index = int(elapsed_seconds / SECONDS_PER_DAY)
	var dp: float = fmod(elapsed_seconds, SECONDS_PER_DAY) / SECONDS_PER_DAY
	current_phase = _phase_from_progress(dp)
	_sleep_multiplier = 1.0
	_sleep_target_progress = -1.0
	phase_changed.emit(current_phase, dp)
	sleep_lapse_ended.emit("woke_at_dawn")


## Restore clock state from WorldSave (called by main_scene after open_world()).
func load_from_world_save() -> void:
	if not WorldSave.is_open():
		return
	var blob: Variant = WorldSave.get_world_meta("clock_state")
	if blob == null:
		return
	if not blob is Dictionary:
		return
	var d: Dictionary = blob as Dictionary
	if d.has("elapsed_seconds"):
		elapsed_seconds = float(d.get("elapsed_seconds", 0.0))
	if d.has("current_day_index"):
		current_day_index = int(d.get("current_day_index", 0))
	if d.has("current_phase"):
		current_phase = d.get("current_phase", Phase.DAWN) as Phase


# ─── Test helpers ─────────────────────────────────────────────────────────────

## Test hook: directly set elapsed_seconds and recompute derived state.
## Bypasses Time.get_unix_time_from_system() for deterministic unit tests (Pitfall 3).
## NOT for production use.
func _set_elapsed_for_test(seconds: float) -> void:
	elapsed_seconds = seconds
	current_day_index = int(elapsed_seconds / SECONDS_PER_DAY)
	var day_progress: float = fmod(elapsed_seconds, SECONDS_PER_DAY) / SECONDS_PER_DAY
	current_phase = _phase_from_progress(day_progress)


# ─── Private helpers ──────────────────────────────────────────────────────────

## Map normalised day progress [0.0, 1.0) to a Phase enum value.
func _phase_from_progress(p: float) -> Phase:
	# v1.1 QA: night was too long — pushed DUSK/NIGHT later (night 0.70→0.78 start, ~22% of
	# the day vs 30%) so days are longer and hostile-spawn time (is_night) is shorter.
	if p < 0.05:
		return Phase.DAWN
	if p < 0.73:
		return Phase.DAY
	if p < 0.78:
		return Phase.DUSK
	return Phase.NIGHT


## Persist the current clock state to WorldSave. Called on every day boundary.
func _persist_to_world_save() -> void:
	if not WorldSave.is_open():
		return
	WorldSave.set_world_meta("clock_state", {
		"elapsed_seconds": elapsed_seconds,
		"current_day_index": current_day_index,
		"current_phase": current_phase,
	})
