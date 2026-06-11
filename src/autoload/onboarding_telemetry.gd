# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# onboarding_telemetry.gd — OnboardingTelemetry autoload
#
# Local-only anonymous event log for playtesting funnel analysis.
# No data is ever transmitted remotely in v1 (T-06-I1 mitigation).
#
# Events stored: unix timestamp (int) + event name (String) ONLY.
# No user IDs, no emails, no world IDs, no positions — zero PII.
#
# Storage: user://telemetry.cfg (ConfigFile).
#   [meta] section: event_count (int) — total events written to disk.
#   [event_N] sections: ts (int), event (String).
#   Cap: 10,000 events. When exceeded, oldest events are dropped (T-06-D1 mitigation).
#
# Flush strategy:
#   - Every FLUSH_INTERVAL_SEC seconds via a Timer node.
#   - On NOTIFICATION_WM_CLOSE_REQUEST (app close / home button on mobile).
#   - In-memory queue is appended to the file; existing file events are preserved.
#
# Usage (from any script):
#   OnboardingTelemetry.log("title_shown")
#
# Registered as autoload "OnboardingTelemetry" in project.godot (last in the list —
# must not block startup of earlier autoloads).
#
# Locked event names (Phase 6 — exhaustive list from 06-CONTEXT.md Area 6):
#   TITLE_SHOWN, DEEP_LINK_RECEIVED, SIGNUP_STARTED, SIGNUP_COMPLETE,
#   SIGNIN_COMPLETE, AVATAR_PICKER_SHOWN, AVATAR_COMPLETE, WORLD_SELECT_SHOWN,
#   WORLD_CREATED, WORLD_LOADED, FTUE_STEP_1_COMPLETE, FTUE_STEP_2_COMPLETE,
#   FTUE_STEP_3_COMPLETE, FTUE_COMPLETE, INVITE_JOINED.

extends Node

# ─── Event name constants ─────────────────────────────────────────────────────

const TITLE_SHOWN:         String = "title_shown"
const DEEP_LINK_RECEIVED:  String = "deep_link_received"
const SIGNUP_STARTED:      String = "signup_started"
const SIGNUP_COMPLETE:     String = "signup_complete"
const SIGNIN_COMPLETE:     String = "signin_complete"
const AVATAR_PICKER_SHOWN: String = "avatar_picker_shown"
const AVATAR_COMPLETE:     String = "avatar_complete"
const WORLD_SELECT_SHOWN:  String = "world_select_shown"
const WORLD_CREATED:       String = "world_created"
const WORLD_LOADED:        String = "world_loaded"
const FTUE_STEP_1_COMPLETE: String = "ftue_step_1_complete"
const FTUE_STEP_2_COMPLETE: String = "ftue_step_2_complete"
const FTUE_STEP_3_COMPLETE: String = "ftue_step_3_complete"
const FTUE_COMPLETE:       String = "ftue_complete"
const INVITE_JOINED:       String = "invite_joined"

# ─── Configuration ────────────────────────────────────────────────────────────

## Maximum number of events to retain in the telemetry file (T-06-D1 mitigation).
## When exceeded, the oldest events are dropped until the count is at or below this cap.
const MAX_EVENTS: int = 10_000

## Interval in seconds between automatic flush-to-disk operations.
const FLUSH_INTERVAL_SEC: float = 60.0

## Path of the telemetry ConfigFile on disk.
const _TELEMETRY_PATH: String = "user://telemetry.cfg"

## Section name for file-level metadata (event_count).
const _META_SECTION: String = "meta"

## Key within [meta] that stores the total number of events written to disk.
const _COUNT_KEY: String = "event_count"

# ─── State ────────────────────────────────────────────────────────────────────

## In-memory queue of events not yet written to disk.
## Each entry is {"ts": int, "event": String}.
var _queue: Array[Dictionary] = []


# ─── Lifecycle ────────────────────────────────────────────────────────────────

func _ready() -> void:
	# Create and start the auto-flush timer.
	var timer: Timer = Timer.new()
	timer.name = "FlushTimer"
	timer.wait_time = FLUSH_INTERVAL_SEC
	timer.autostart = true
	timer.one_shot = false
	timer.timeout.connect(_flush_to_disk)
	add_child(timer)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_flush_to_disk()


# ─── Public API ───────────────────────────────────────────────────────────────

## Append an event to the in-memory queue.
## No disk I/O — the flush timer and close notification handle persistence.
##
## @param event_name  One of the locked event name constants above.
func log(event_name: String) -> void:
	_queue.append({"ts": int(Time.get_unix_time_from_system()), "event": event_name})


# ─── Private helpers ──────────────────────────────────────────────────────────

## Write the in-memory queue to user://telemetry.cfg.
## Appends to the existing file; enforces the MAX_EVENTS cap by dropping oldest.
## Clears _queue on success.
func _flush_to_disk() -> void:
	if _queue.is_empty():
		return

	var cfg := ConfigFile.new()
	# Load existing data (ignore error — file may not exist yet on first flush).
	cfg.load(_TELEMETRY_PATH)

	# Read the current event count from [meta].
	var base_count: int = 0
	if cfg.has_section_key(_META_SECTION, _COUNT_KEY):
		base_count = int(cfg.get_value(_META_SECTION, _COUNT_KEY, 0))

	# Append each queued event as a new [event_N] section.
	for entry: Dictionary in _queue:
		var section: String = "event_%d" % base_count
		cfg.set_value(section, "ts", entry.get("ts", 0))
		cfg.set_value(section, "event", entry.get("event", ""))
		base_count += 1

	# Update the [meta] event_count to reflect all events written so far.
	cfg.set_value(_META_SECTION, _COUNT_KEY, base_count)

	# Enforce the 10,000-event cap: drop oldest events if we are over the limit.
	var excess: int = base_count - MAX_EVENTS
	if excess > 0:
		# _rotate_oldest erases excess sections, renumbers retained ones, and
		# updates [meta] event_count to retained.size().  Reflect that here so
		# base_count stays consistent with the renumbered file state.
		_rotate_oldest(cfg, excess)
		base_count -= excess

	cfg.save(_TELEMETRY_PATH)
	_queue.clear()


## Remove the oldest `drop_count` event sections from the ConfigFile and renumber
## remaining sections so the next flush continues from the correct base index.
## Sections are named [event_N] where N is an ascending integer; the lowest
## N values are the oldest. We collect, sort, erase the first drop_count, and
## renumber retained sections starting from 0 so base_count stays accurate.
##
## @param cfg         The ConfigFile to mutate in-place.
## @param drop_count  Number of oldest event sections to erase.
func _rotate_oldest(cfg: ConfigFile, drop_count: int) -> void:
	if drop_count <= 0:
		return

	# Collect all event_N section names (exclude [meta]).
	var sections: PackedStringArray = cfg.get_sections()
	var event_sections: Array[String] = []
	for section: String in sections:
		if section.begins_with("event_"):
			event_sections.append(section)

	# Sort by the numeric suffix to identify oldest events.
	event_sections.sort_custom(func(a: String, b: String) -> bool:
		var na: int = int(a.substr("event_".length()))
		var nb: int = int(b.substr("event_".length()))
		return na < nb
	)

	# Erase the oldest drop_count sections.
	var to_drop: int = mini(drop_count, event_sections.size())
	for i: int in to_drop:
		cfg.erase_section(event_sections[i])

	# Renumber the retained sections so the next flush writes event_N starting
	# from 0 rather than from the old high-water mark.  Without renumbering,
	# the next flush would compute base_count = MAX_EVENTS and write event_10000,
	# overwriting a retained row.
	var retained: Array[String] = event_sections.slice(to_drop)
	for new_idx: int in retained.size():
		var old_section: String = retained[new_idx]
		var new_section: String = "event_%d" % new_idx
		if old_section != new_section:
			var ts_val: Variant    = cfg.get_value(old_section, "ts", 0)
			var event_val: Variant = cfg.get_value(old_section, "event", "")
			cfg.erase_section(old_section)
			cfg.set_value(new_section, "ts", ts_val)
			cfg.set_value(new_section, "event", event_val)

	# Update [meta] event_count to match the new contiguous section count so
	# _flush_to_disk starts appending from the right index on the next call.
	cfg.set_value(_META_SECTION, _COUNT_KEY, retained.size())
