# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# android_thermal.gd — Layered Android thermal probe wrapper (Plan 07).
#
# Registered as autoload "AndroidThermal" in project.godot (Android builds only).
#
# On _ready(), detects which probe path is available and records it in _path.
# The layered probe (RESEARCH.md Pitfall 2):
#   1. getThermalHeadroom  — API 30+ (Android 11+)
#   2. currentThermalStatus — API 29+ (Android 10+)
#   3. sysfs_zone           — /sys/class/thermal/thermal_zone0/temp
#   4. unavailable          — none of the above worked
#
# Public API:
#   get_probe_path() -> String  — one of: "getThermalHeadroom", "currentThermalStatus",
#                                "sysfs_zone", "unavailable"
#   read_headroom() -> float    — NaN if path != getThermalHeadroom; cached per 10s (Pitfall 3)
#   read_status() -> int        — -1 if path != currentThermalStatus
#   read_sysfs_millidegrees() -> float — NaN if path != sysfs_zone
#
# Poll throttle (RESEARCH.md Pitfall 3):
#   Android's documented contract is ≤ 1 call per 10 seconds to getThermalHeadroom.
#   This wrapper caches the last headroom value and the timestamp of the last real
#   API call. If read_headroom() is invoked within 10 seconds of the last call,
#   it returns the cached value without hitting the plugin again.
#
# On non-Android builds, get_path() returns "unavailable" and all reads return NaN / -1.
# This makes the autoload safe to instantiate on desktop for testing.
#
# Thread safety: not thread-safe; call only from the main thread.
#
# Integration with ThermalProbe:
#   thermal_probe.gd's _ready() calls ThermalProbe.set_thermal_provider(AndroidThermal)
#   when OS.has_feature("android") is true. ThermalProbe then calls
#   get_thermal_headroom() and get_thermal_status() through the provider interface.

extends Node

# ─── Constants ────────────────────────────────────────────────────────────────

## Minimum interval between real getThermalHeadroom API calls (seconds).
## Android's documented contract: ≤ 1 call per 10 seconds (RESEARCH.md Pitfall 3).
## T-07-03 mitigation: applies to sysfs reads too (file-handle exhaustion guard).
const POLL_INTERVAL_S: float = 10.0

## THERMAL_STATUS_* enum values (Android API 29+).
## Matches PowerManager.THERMAL_STATUS_* constants.
const THERMAL_STATUS_NONE:      int = 0
const THERMAL_STATUS_LIGHT:     int = 1
const THERMAL_STATUS_MODERATE:  int = 2
const THERMAL_STATUS_SEVERE:    int = 3
const THERMAL_STATUS_CRITICAL:  int = 4
const THERMAL_STATUS_EMERGENCY: int = 5
const THERMAL_STATUS_SHUTDOWN:  int = 6

# ─── Private state ────────────────────────────────────────────────────────────

## Which probe layer is active on this device.
var _path: String = "unavailable"

## Cached plugin singleton (or null on non-Android builds).
var _plugin: Object = null

## Cached thermal headroom value from the last real API call.
var _cached_headroom: float = NAN

## Monotonic time of the last real getThermalHeadroom (or sysfs) API call.
var _last_call_time: float = -1000.0

# ─── Lifecycle ────────────────────────────────────────────────────────────────

func _ready() -> void:
	if not OS.has_feature("android"):
		_path = "unavailable"
		return

	# Attempt to get the Kotlin plugin singleton.
	if Engine.has_singleton("CubicraftiaThermal"):
		_plugin = Engine.get_singleton("CubicraftiaThermal")
	else:
		_plugin = null

	# Detect the best available probe path.
	_path = _detect_path()


## Detect which probe layer works on this device.
## Called once in _ready(); may also be called again after plugin hot-reload in
## editor environments (not expected in production).
func _detect_path() -> String:
	# Layer 1: try getThermalHeadroom (API 30+)
	if _plugin != null and _plugin.has_method("getThermalHeadroom"):
		var h: float = _plugin.getThermalHeadroom(0)
		if not is_nan(h):
			return "getThermalHeadroom"

	# Layer 2: try getCurrentThermalStatus (API 29+)
	if _plugin != null and _plugin.has_method("getCurrentThermalStatus"):
		var s: int = _plugin.getCurrentThermalStatus()
		if s >= 0:
			return "currentThermalStatus"

	# Layer 3: try sysfs
	if _plugin != null and _plugin.has_method("readSysfsZone"):
		var temp: float = _plugin.readSysfsZone()
		if not is_nan(temp):
			return "sysfs_zone"

	return "unavailable"

# ─── Public API ──────────────────────────────────────────────────────────────

## Returns the probe path detected on _ready().
## One of: "getThermalHeadroom", "currentThermalStatus", "sysfs_zone", "unavailable"
func get_probe_path() -> String:
	return _path


## Returns the thermal headroom as a float [0.0, 1.0].
## Returns NaN if path is not "getThermalHeadroom".
## Cached: real API calls are throttled to at most once per POLL_INTERVAL_S seconds
## (RESEARCH.md Pitfall 3 — Android returns NaN if called more frequently).
func read_headroom() -> float:
	if _path != "getThermalHeadroom":
		return NAN
	if _plugin == null:
		return NAN

	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_call_time < POLL_INTERVAL_S:
		# Return cached value — do NOT call the plugin again.
		return _cached_headroom

	_last_call_time = now
	_cached_headroom = _plugin.getThermalHeadroom(0)
	return _cached_headroom


## Returns the discrete thermal status integer (THERMAL_STATUS_* enum).
## Returns -1 if path is not "currentThermalStatus".
func read_status() -> int:
	if _path != "currentThermalStatus":
		return -1
	if _plugin == null:
		return -1
	return _plugin.getCurrentThermalStatus()


## Returns the raw sysfs temperature in millidegrees Celsius.
## Returns NaN if path is not "sysfs_zone".
## T-07-03: sysfs reads are also throttled to at most once per POLL_INTERVAL_S.
func read_sysfs_millidegrees() -> float:
	if _path != "sysfs_zone":
		return NAN
	if _plugin == null:
		return NAN

	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_call_time < POLL_INTERVAL_S:
		return _cached_headroom  # reuse cache slot (NaN if first call didn't work)

	_last_call_time = now
	var temp: float = _plugin.readSysfsZone()
	_cached_headroom = temp  # reuse cache slot
	return temp


# ─── ThermalProbe provider interface ─────────────────────────────────────────
# These methods are called by thermal_probe.gd's provider abstraction.
# The naming matches the provider contract expected by _on_sample_timer_timeout().

## Returns thermal headroom (0.0–1.0) or NaN.
## Delegates to read_headroom() with caching.
func get_thermal_headroom() -> float:
	return read_headroom()


## Returns thermal status int or -1.
## Delegates to read_status().
func get_thermal_status() -> int:
	return read_status()
