# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# tool_wear.gd — ToolWear autoload: per-tool-instance durability tracking.
#
# Registered as autoload "ToolWear" in project.godot (after Weather, before BrickRegistry).
#
# DOCS.md §3.4 "Tool wear":
#   - Survival mode: durability decrements by 1 on each tool use.
#   - Sandbox mode: tools NEVER wear; decrement_on_use() is a no-op returning true.
#   - Lantern (max_durability=0): exempt from wear entirely regardless of mode.
#   - Dynamite (max_durability=1): one use depletes it; worn_out fires; consumed from hotbar.
#
# Instance IDs:
#   Phase 2 uses slot-based instance IDs: "slot_0".."slot_7" matching hotbar slot indices.
#   Phase 3 inventory system can extend this with uuid-based IDs without API changes.
#
# Persistence:
#   Durability map is saved/loaded via WorldSave.get_world_meta / set_world_meta.
#   Key: "tool_durability" → var_to_bytes(_durability_map).
#   Save is triggered by WorldClock.day_boundary signal (subscribed in _ready).
#   Restore is triggered by attach_world() called from main_scene after open_world().
#
# Mode detection:
#   Uses Features.is_survival_mode() which reads WorldSave.get_world_meta("mode").
#   Sandbox/survival is locked at world-creation time (DOCS §5.1); no mid-session flip.
#
# Type annotations note (Rule 2 — correctness):
#   ToolDefinition parameters use Resource type hint (not the class_name ToolDefinition)
#   because this script is parsed as an autoload before the global class registry
#   fully resolves class_name types. Pattern from WorldSave (uses Object for SQLite).
#   Callers still pass ToolDefinition resources; the cast is done at call-site via `as Resource`.
#
# References:
#   DOCS.md §3.4
#   02-PATTERNS.md §"src/autoload/tool_wear.gd" (autoload pattern from thermal_probe.gd)
#   02-RESEARCH.md §"Tool System"
#   02-CONTEXT.md D-12

extends Node

# ─── Signals ──────────────────────────────────────────────────────────────────

## Emitted when a tool's durability changes.
## @param tool_id      The tool type ID (e.g. "pickaxe_wood").
## @param instance_id  The slot-based instance ID (e.g. "slot_0").
## @param new_pct      New durability as a 0.0..1.0 fraction.
signal durability_changed(tool_id: String, instance_id: String, new_pct: float)

## Emitted when a tool is fully worn out (durability reaches 0).
## @param tool_id      The tool type ID.
## @param instance_id  The slot-based instance ID.
signal worn_out(tool_id: String, instance_id: String)

# ─── Private state ────────────────────────────────────────────────────────────

## Per-instance durability map. Key = instance_id (String), value = current durability (int).
## Entries are only created when a tool is first used or explicitly set.
## If an instance_id is absent, it is assumed to be at max_durability.
var _durability_map: Dictionary = {}

## Test-only mode override: if non-empty, overrides Features.is_survival_mode().
## Set by _test_set_mode_override(); never used outside unit tests.
## "" = use Features.is_survival_mode() normally.
var _test_mode_override: String = ""

# ─── Lifecycle ────────────────────────────────────────────────────────────────

func _ready() -> void:
	# Subscribe to WorldClock.day_boundary to persist durability on each in-game day.
	# WorldClock is registered before ToolWear (see autoload order in project.godot).
	if Engine.has_singleton("WorldClock"):
		var world_clock = Engine.get_singleton("WorldClock")
		if world_clock.has_signal("day_boundary"):
			world_clock.day_boundary.connect(_on_day_boundary)


# ─── Public API ───────────────────────────────────────────────────────────────

## Get the current durability of a tool instance.
## Returns max_durability if the instance has never been used (absent from map).
## @param instance_id   Slot-based ID ("slot_0".."slot_7").
## @param tool          The ToolDefinition Resource for this instance (used as fallback max).
##                      Pass as Resource to avoid class_name resolution issues in autoloads.
## @return              Current durability (0..max_durability).
func get_durability(instance_id: String, tool: Resource = null) -> int:
	if _durability_map.has(instance_id):
		return _durability_map[instance_id]
	if tool != null and tool.has_method("get") and "max_durability" in tool:
		return tool.get("max_durability")
	return 0


## Set the durability of a tool instance directly.
## Clamped to [0, tool.max_durability] if tool is provided.
## @param instance_id  Slot-based ID.
## @param value        New durability value.
## @param tool         Optional ToolDefinition Resource for clamping; null = no clamp.
func set_durability(instance_id: String, value: int, tool: Resource = null) -> void:
	var clamped: int = value
	if tool != null and "max_durability" in tool:
		var max_dur: int = tool.get("max_durability")
		if max_dur > 0:
			clamped = clampi(value, 0, max_dur)
	_durability_map[instance_id] = clamped


## Unit-test helper: override the survival/sandbox mode without a live WorldSave.
## Only call from test scripts. Pass "" to restore normal Features.is_survival_mode() behaviour.
## @param mode  "survival", "sandbox", or "" (restore normal).
func _test_set_mode_override(mode: String) -> void:
	_test_mode_override = mode


## Returns the effective survival-mode state, honoring the test override if set.
func _is_survival_mode() -> bool:
	if _test_mode_override != "":
		return _test_mode_override == "survival"
	return Features.is_survival_mode()


## Decrement a tool instance's durability by 1 on use.
##
## Gate conditions (no decrement):
##   1. Sandbox mode: _is_survival_mode() == false → no-op; return true.
##   2. Lantern: tool.max_durability == 0 → never wears out; return true.
##
## If durability reaches 0 or below:
##   - Emits worn_out(tool.tool_id, instance_id).
##   - Returns false (tool is no longer usable).
##
## @param tool         The ToolDefinition Resource being used.
## @param instance_id  The slot-based instance ID.
## @return             true if the tool can still be used; false if worn out.
func decrement_on_use(tool: Resource, instance_id: String) -> bool:
	# Gate 1: sandbox mode → no wear ever.
	if not _is_survival_mode():
		return true

	# Retrieve max_durability from the ToolDefinition resource.
	var max_dur: int = 0
	if "max_durability" in tool:
		max_dur = tool.get("max_durability")

	# Gate 2: lantern (and anything with max_durability == 0) never wears out.
	if max_dur == 0:
		return true

	# Retrieve current durability (default to max if never used).
	var cur: int = _durability_map.get(instance_id, max_dur)

	# Decrement.
	cur -= 1
	_durability_map[instance_id] = cur

	# Retrieve tool_id for signal payload.
	var tool_id: String = ""
	if "tool_id" in tool:
		tool_id = tool.get("tool_id")

	# Compute percentage for UI signal.
	var pct: float = float(cur) / float(max_dur)

	# Emit durability_changed every time.
	durability_changed.emit(tool_id, instance_id, maxf(pct, 0.0))

	# Check worn out.
	if cur <= 0:
		worn_out.emit(tool_id, instance_id)
		return false

	return true


## Returns true if the tool instance has 0 durability remaining.
## A tool that has never been used is NOT worn out (assumed full).
## @param instance_id  The slot-based instance ID.
func is_worn_out(instance_id: String) -> bool:
	if not _durability_map.has(instance_id):
		return false
	return _durability_map[instance_id] <= 0


## Attach the current world's persisted durability state.
## Called by main_scene after WorldSave.open_world() succeeds.
## Loads previously-saved durability values so tools persist across sessions.
func attach_world() -> void:
	if not WorldSave.is_open():
		return
	var raw: Variant = WorldSave.get_world_meta("tool_durability")
	if raw == null:
		return
	if raw is PackedByteArray:
		var decoded: Variant = bytes_to_var(raw as PackedByteArray)
		if decoded is Dictionary:
			_durability_map = decoded as Dictionary
	elif raw is Dictionary:
		# Already decoded (fallback — some driver versions return decoded values).
		_durability_map = raw as Dictionary


## Detach world state (clear map on world close).
## Called by main_scene before WorldSave.close_world().
func detach_world() -> void:
	_persist_to_save()
	_durability_map.clear()


# ─── Private helpers ──────────────────────────────────────────────────────────

## Persist the current durability map to WorldSave.
## Uses WorldSave.set_world_meta("tool_durability", var_to_bytes(_durability_map)).
func _persist_to_save() -> void:
	if not WorldSave.is_open():
		return
	WorldSave.set_world_meta("tool_durability", var_to_bytes(_durability_map))


# ─── Signal handlers ──────────────────────────────────────────────────────────

## Called on each in-game day boundary to persist durability.
func _on_day_boundary(_day_index: int) -> void:
	_persist_to_save()
