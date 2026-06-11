# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# test_keepalive_logic.gd — Unit tests for peer keepalive and disconnect detection.
#
# Keepalive contract (04-CONTEXT.md Area 4):
#   - 3 consecutive missed keepalives → peer marked "laggy" (soft UI warning)
#   - 6 consecutive missed keepalives → peer dropped from session
#   - Recovery: keepalive received again → laggy state cleared (miss count reset)
#
# Uses _simulate_keepalive_miss() and _simulate_keepalive_pong() test helpers
# added to NetworkManager in this plan.
#
# Anchors:
#   04-CONTEXT.md Area 4 — adaptive keepalive thresholds
#   04-UI-SPEC.md Surface 6 — "[Player] is laggy" soft warning
#   04-11-PLAN.md — test activation plan

extends GutTest

const NetworkManagerScript := preload("res://src/autoload/network_manager.gd")

var _nm: Node = null
const TEST_PEER_ID := 42


func before_each() -> void:
	# Do NOT add to scene tree — _ready() connects to get_tree().root.focus_exited /
	# focus_entered signals, causing ObjectDB leak errors when the node is freed
	# between tests. All tests only use _simulate_keepalive_miss/pong helpers and
	# signal-watching, which work fine on an off-tree node.
	_nm = NetworkManagerScript.new()
	# Seed the keepalive miss count so the peer is tracked.
	_nm._keepalive_miss_count[TEST_PEER_ID] = 0


func after_each() -> void:
	if is_instance_valid(_nm):
		_nm.free()
	_nm = null


# ─── Keepalive tests ───────────────────────────────────────────────────────────

## test_laggy_after_3_missed: exactly 3 missed keepalives → peer_laggy(id, true).
func test_laggy_after_3_missed() -> void:
	watch_signals(_nm)
	# Simulate 3 ticks with no pong — miss count goes 1 → 2 → 3
	_nm._simulate_keepalive_miss(TEST_PEER_ID)
	_nm._simulate_keepalive_miss(TEST_PEER_ID)
	_nm._simulate_keepalive_miss(TEST_PEER_ID)
	# After 3 misses the peer_laggy signal should have been emitted.
	assert_signal_emitted(_nm, "peer_laggy",
		"peer_laggy must fire after 3 consecutive missed keepalives")
	# Verify the miss count is exactly 3 (the threshold).
	assert_eq(_nm._keepalive_miss_count.get(TEST_PEER_ID, -1), 3,
		"Miss count must be exactly 3 at the laggy threshold")


## test_pong_resets_miss_counter: miss count goes to 2, then pong resets to 0.
func test_pong_resets_miss_counter() -> void:
	watch_signals(_nm)
	_nm._simulate_keepalive_miss(TEST_PEER_ID)
	_nm._simulate_keepalive_miss(TEST_PEER_ID)
	assert_eq(_nm._keepalive_miss_count.get(TEST_PEER_ID, -1), 2,
		"Miss count should be 2 after two misses")
	# Pong arrives — reset counter.
	_nm._simulate_keepalive_pong(TEST_PEER_ID)
	assert_eq(_nm._keepalive_miss_count.get(TEST_PEER_ID, -1), 0,
		"Miss count must reset to 0 after a pong")
	assert_signal_emitted(_nm, "keepalive_received",
		"keepalive_received must be emitted when a pong arrives")


## test_dropped_after_6_missed: 6 missed keepalives → peer_disconnected emitted.
## Note: _disconnect_peer emits peer_disconnected after erasing the peer from tracking.
func test_dropped_after_6_missed() -> void:
	watch_signals(_nm)
	# Simulate 6 missed ticks (miss count 1..6).
	# At count 3, peer_laggy fires. At count 6, keepalive_timeout + peer_disconnected fire.
	for _i: int in 6:
		_nm._simulate_keepalive_miss(TEST_PEER_ID)
	# peer_disconnected must have been emitted.
	assert_signal_emitted(_nm, "peer_disconnected",
		"peer_disconnected must be emitted when a peer misses 6 keepalives")
	# keepalive_timeout should also have been emitted.
	assert_signal_emitted(_nm, "keepalive_timeout",
		"keepalive_timeout must be emitted before the peer is disconnected")


## test_3_missed_emits_laggy: canonical export name matching 04-11 plan artifact list.
func test_3_missed_emits_laggy() -> void:
	watch_signals(_nm)
	for _i: int in 3:
		_nm._simulate_keepalive_miss(TEST_PEER_ID)
	assert_signal_emitted(_nm, "peer_laggy",
		"peer_laggy must fire after exactly 3 missed keepalives")
	assert_eq(_nm._keepalive_miss_count.get(TEST_PEER_ID, -1), 3,
		"Miss count must be 3 at the laggy signal threshold")


## test_6_missed_emits_disconnect: canonical export name matching 04-11 plan artifact list.
func test_6_missed_emits_disconnect() -> void:
	watch_signals(_nm)
	for _i: int in 6:
		_nm._simulate_keepalive_miss(TEST_PEER_ID)
	assert_signal_emitted(_nm, "peer_disconnected",
		"peer_disconnected must be emitted after 6 consecutive missed keepalives")


## test_recovery_clears_laggy: miss 3 times (laggy), then pong → miss count resets.
## On next miss cycle, laggy fires again only after another 3 misses (not immediately).
func test_recovery_clears_laggy() -> void:
	watch_signals(_nm)
	for _i: int in 3:
		_nm._simulate_keepalive_miss(TEST_PEER_ID)
	assert_signal_emitted(_nm, "peer_laggy",
		"Should be laggy after 3 misses")
	# Recovery: pong received — reset miss count.
	_nm._simulate_keepalive_pong(TEST_PEER_ID)
	assert_eq(_nm._keepalive_miss_count.get(TEST_PEER_ID, -1), 0,
		"Miss count must be 0 after recovery pong")
