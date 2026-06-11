# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# test_telemetry_rotation.gd — Unit tests for OnboardingTelemetry flush/rotation.
#
# Tests cover:
#   - log() appends an event to the in-memory queue
#   - 10,000-event cap: oldest events are dropped when the cap is exceeded
#   - flush writes the queue to the telemetry cfg path
#   - load of existing events on _ready() (via ConfigFile API)
#   - no PII keys appear in logged events
#   - NOTIFICATION_WM_CLOSE_REQUEST triggers _flush_to_disk()
#
# Strategy: instantiate OnboardingTelemetry fresh for each test (add_child /
# remove_child) to avoid inter-test state leakage. The autoload is NOT used
# directly because its Timer state and _queue may be dirty.
#
# Anchors:
#   06-09-PLAN.md Task 1 — activate test_telemetry_rotation stubs
#   06-CONTEXT.md Area 6 — OnboardingTelemetry 10k-event cap

extends GutTest

const Phase6Fixtures = preload("res://tests/conftest_phase6.gd")

const PII_KEYS: Array = ["email", "username", "password", "uid", "user_id", "ip", "token"]

# Script path for fresh instances (avoids depending on the autoload singleton state).
const _TELEMETRY_SCRIPT: String = "res://src/autoload/onboarding_telemetry.gd"

var _sut  # OnboardingTelemetry fresh instance for each test
var _cfg_path: String  # isolated telemetry file path


func before_each() -> void:
	# Instantiate a fresh node so tests are fully isolated from each other.
	_sut = load(_TELEMETRY_SCRIPT).new()
	add_child_autoqfree(_sut)
	_cfg_path = Phase6Fixtures.make_telemetry_cfg_path()


func after_each() -> void:
	# Clean up isolated test file from disk.
	var global := ProjectSettings.globalize_path(_cfg_path)
	if FileAccess.file_exists(_cfg_path):
		DirAccess.remove_absolute(global)


# ─── test_log_event_adds_to_queue ─────────────────────────────────────────────

func test_log_event_adds_to_queue() -> void:
	assert_eq(_sut._queue.size(), 0, "Queue must start empty")
	_sut.log("title_shown")
	assert_eq(_sut._queue.size(), 1, "Queue must have 1 entry after log()")
	var entry: Dictionary = _sut._queue[0]
	assert_eq(entry.get("event"), "title_shown", "Event name must be stored")
	assert_true(entry.has("ts"), "Event must have a ts key")
	assert_typeof(entry.get("ts"), TYPE_INT, "ts must be an int")


# ─── test_events_have_required_format ─────────────────────────────────────────

func test_events_have_required_format() -> void:
	_sut.log("signup_started")
	var entry: Dictionary = _sut._queue[0]
	# Must have exactly 'ts' and 'event' — no extra keys
	assert_true(entry.has("ts"), "Entry must have 'ts' key")
	assert_true(entry.has("event"), "Entry must have 'event' key")
	assert_eq(entry.size(), 2, "Entry must have exactly 2 keys (ts + event, no extras)")


# ─── test_no_pii_in_events ────────────────────────────────────────────────────

func test_no_pii_in_logged_events() -> void:
	_sut.log("signin_complete")
	var entry: Dictionary = _sut._queue[0]
	for key in PII_KEYS:
		assert_false(entry.has(key), "Event must not contain PII key: %s" % key)


# ─── test_flush_writes_to_disk ────────────────────────────────────────────────

func test_flush_writes_to_disk() -> void:
	# Override the flush target by patching the constant via a local flush call.
	# Because _TELEMETRY_PATH is a const, we call _flush_to_disk_at() — but the
	# real implementation uses the const path. We write 5 events, flush, then
	# read back from the default path and verify. Use a workaround: set _queue,
	# then call a modified flush that writes to our isolated path.
	#
	# Since we cannot easily override the const, we instead test the ConfigFile
	# logic directly by calling _flush_to_disk() and inspecting the result file.
	# The test uses the real user:// path but cleans up after itself.
	var real_path: String = _sut._TELEMETRY_PATH

	# Remove any pre-existing telemetry file from a prior run.
	var global_real := ProjectSettings.globalize_path(real_path)
	if FileAccess.file_exists(real_path):
		DirAccess.remove_absolute(global_real)

	_sut.log("title_shown")
	_sut.log("signup_started")
	_sut.log("signup_complete")
	_sut.log("signin_complete")
	_sut.log("world_loaded")

	_sut._flush_to_disk()

	# Queue must be cleared after flush.
	assert_eq(_sut._queue.size(), 0, "Queue must be empty after flush")

	# Verify the file was written with correct content.
	var cfg := ConfigFile.new()
	var err := cfg.load(real_path)
	assert_eq(err, OK, "telemetry.cfg must load without error after flush")

	var count: int = cfg.get_value("meta", "event_count", -1)
	assert_eq(count, 5, "[meta] event_count must be 5")

	var evt0: String = cfg.get_value("event_0", "event", "")
	assert_eq(evt0, "title_shown", "[event_0] event must be 'title_shown'")

	var evt4: String = cfg.get_value("event_4", "event", "")
	assert_eq(evt4, "world_loaded", "[event_4] event must be 'world_loaded'")

	# Cleanup.
	DirAccess.remove_absolute(global_real)


# ─── test_10000_event_cap_drops_oldest ────────────────────────────────────────

func test_10000_event_cap_drops_oldest() -> void:
	# Populate the queue with MAX_EVENTS + 1 entries.
	var max_ev: int = _sut.MAX_EVENTS  # 10000
	for i in range(max_ev + 1):
		_sut.log("evt_%d" % i)

	# Queue must have 10001 entries before flush.
	assert_eq(_sut._queue.size(), max_ev + 1, "Queue must have MAX+1 entries before flush")

	var real_path: String = _sut._TELEMETRY_PATH
	var global_real := ProjectSettings.globalize_path(real_path)
	if FileAccess.file_exists(real_path):
		DirAccess.remove_absolute(global_real)

	_sut._flush_to_disk()

	# Load the written file and verify the cap.
	var cfg := ConfigFile.new()
	var err := cfg.load(real_path)
	assert_eq(err, OK, "telemetry.cfg must load after flush")

	var count: int = cfg.get_value("meta", "event_count", -1)
	assert_eq(count, max_ev, "[meta] event_count must equal MAX_EVENTS after rotation")

	# _rotate_oldest RENUMBERS the retained sections contiguously from 0 (so the next
	# flush's append index stays correct and never overwrites the newest row). With 10001
	# logged and a cap of 10000, the oldest (evt_0) is dropped and the survivors are
	# renumbered to event_0..event_9999.
	#
	# event_0 still exists, but now holds the SECOND-oldest event (evt_1) — evt_0 is gone.
	assert_true(cfg.has_section("event_0"), "event_0 must exist (renumbered) after rotation")
	assert_eq(cfg.get_value("event_0", "event", ""), "evt_1",
		"oldest event (evt_0) must have been dropped — event_0 now holds evt_1 after renumbering")

	# The newest event (evt_10000) is retained as the LAST renumbered section, event_9999;
	# event_10000 no longer exists.
	assert_false(cfg.has_section("event_%d" % max_ev),
		"event_%d must NOT exist after renumbering (sections are event_0..event_%d)" % [max_ev, max_ev - 1])
	assert_eq(cfg.get_value("event_%d" % (max_ev - 1), "event", ""), "evt_%d" % max_ev,
		"newest event (evt_%d) must be retained as event_%d after renumbering" % [max_ev, max_ev - 1])

	# Cleanup.
	DirAccess.remove_absolute(global_real)


# ─── test_load_existing_events_on_ready ───────────────────────────────────────

func test_load_existing_events_on_ready() -> void:
	# Pre-populate the telemetry file with 3 events, then log 2 more and flush.
	# Verify total count is 5 (existing + new).
	var real_path: String = _sut._TELEMETRY_PATH
	var global_real := ProjectSettings.globalize_path(real_path)
	if FileAccess.file_exists(real_path):
		DirAccess.remove_absolute(global_real)

	var pre_cfg := ConfigFile.new()
	pre_cfg.set_value("meta", "event_count", 3)
	pre_cfg.set_value("event_0", "ts", 1000)
	pre_cfg.set_value("event_0", "event", "title_shown")
	pre_cfg.set_value("event_1", "ts", 1001)
	pre_cfg.set_value("event_1", "event", "signup_started")
	pre_cfg.set_value("event_2", "ts", 1002)
	pre_cfg.set_value("event_2", "event", "signup_complete")
	pre_cfg.save(real_path)

	# Now log 2 more events and flush — they should append after the existing 3.
	_sut.log("world_select_shown")
	_sut.log("world_loaded")
	_sut._flush_to_disk()

	var cfg := ConfigFile.new()
	var err := cfg.load(real_path)
	assert_eq(err, OK, "telemetry.cfg must load after append flush")

	var count: int = cfg.get_value("meta", "event_count", -1)
	assert_eq(count, 5, "event_count must be 5 (3 existing + 2 new)")

	var evt3: String = cfg.get_value("event_3", "event", "")
	assert_eq(evt3, "world_select_shown", "event_3 must be 'world_select_shown'")

	var evt4: String = cfg.get_value("event_4", "event", "")
	assert_eq(evt4, "world_loaded", "event_4 must be 'world_loaded'")

	# Cleanup.
	DirAccess.remove_absolute(global_real)


# ─── test_close_request_triggers_flush ────────────────────────────────────────

func test_close_request_triggers_flush() -> void:
	var real_path: String = _sut._TELEMETRY_PATH
	var global_real := ProjectSettings.globalize_path(real_path)
	if FileAccess.file_exists(real_path):
		DirAccess.remove_absolute(global_real)

	_sut.log("ftue_complete")
	assert_eq(_sut._queue.size(), 1, "Queue must have 1 event before close notification")

	# Simulate app close — _notification must trigger _flush_to_disk().
	_sut._notification(NOTIFICATION_WM_CLOSE_REQUEST)

	# Queue must be empty (flushed).
	assert_eq(_sut._queue.size(), 0, "Queue must be empty after CLOSE_REQUEST notification")

	# File must exist and contain the event.
	assert_true(FileAccess.file_exists(real_path), "telemetry.cfg must exist after close flush")
	var cfg := ConfigFile.new()
	cfg.load(real_path)
	assert_eq(cfg.get_value("meta", "event_count", 0), 1, "event_count must be 1 after close flush")

	# Cleanup.
	DirAccess.remove_absolute(global_real)
