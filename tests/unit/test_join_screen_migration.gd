# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# test_join_screen_migration.gd — headless proof of the JoinScreen → shared
# ConnectionProblemOverlay migration (13-06-PLAN.md Task 1).
#
# Covers:
#   - Spinner node added under Overlay/Content, ErrorContent subtree removed.
#   - _show_error() removed entirely; _on_connection_problem() added and
#     queue_free()s JoinScreen on ANY connection_problem reason.
#   - STATE_FAILOVER_WAITING / STATE_RECONNECTING now shows the new
#     ui.join.status_reconnecting copy (was ui.join.status_loading).
#
# In-viewport visual verification (spinner actually animating on-screen,
# layout) is display-gated and deferred to Phase 12 per executor instructions.

extends GutTest


func _get_join_screen() -> Node:
	var scene := load("res://src/ui/join_screen.tscn")
	if scene == null:
		return null
	return scene.instantiate()


# ─── Scene structure ──────────────────────────────────────────────────────────

func test_scene_has_spinner_between_heading_and_status_label() -> void:
	var screen := _get_join_screen()
	assert_not_null(screen, "join_screen.tscn must exist and instantiate")
	if screen == null:
		return
	add_child_autofree(screen)

	var spinner := screen.get_node_or_null("Overlay/Content/Spinner")
	assert_not_null(spinner, "Overlay/Content/Spinner must exist")
	if spinner != null:
		assert_true(spinner is AnimatedSprite2D, "Spinner must be an AnimatedSprite2D")
		assert_eq(spinner.autoplay, "default", "Spinner must autoplay the 'default' animation")


func test_scene_no_longer_has_error_content_subtree() -> void:
	var screen := _get_join_screen()
	assert_not_null(screen)
	if screen == null:
		return
	add_child_autofree(screen)

	assert_null(screen.get_node_or_null("Overlay/ErrorContent"),
		"ErrorContent must be removed entirely")


# ─── Script surface ───────────────────────────────────────────────────────────

func test_show_error_method_removed() -> void:
	var screen := _get_join_screen()
	assert_not_null(screen)
	if screen == null:
		return
	add_child_autofree(screen)

	assert_false(screen.has_method("_show_error"),
		"_show_error must be removed — ConnectionProblemOverlay owns all error rendering")


func test_on_connection_problem_handler_exists_and_frees_join_screen() -> void:
	var screen := _get_join_screen()
	assert_not_null(screen)
	if screen == null:
		return
	add_child_autofree(screen)

	assert_true(screen.has_method("_on_connection_problem"),
		"_on_connection_problem must exist")
	screen._on_connection_problem("timeout")
	assert_true(screen.is_queued_for_deletion(),
		"JoinScreen must queue_free itself on ANY connection_problem reason")


# ─── Reconnecting copy (RELY-02/03 Case 2) ────────────────────────────────────

func test_failover_waiting_shows_reconnecting_copy() -> void:
	var screen := _get_join_screen()
	assert_not_null(screen)
	if screen == null:
		return
	add_child_autofree(screen)

	screen._on_session_state_changed(NetworkManager.STATE_FAILOVER_WAITING)
	var status_label: Label = screen.get_node("Overlay/Content/StatusLabel")
	assert_eq(status_label.text, tr("ui.join.status_reconnecting"),
		"STATE_FAILOVER_WAITING must show ui.join.status_reconnecting, not the old status_loading copy")


func test_reconnecting_state_shows_reconnecting_copy() -> void:
	var screen := _get_join_screen()
	assert_not_null(screen)
	if screen == null:
		return
	add_child_autofree(screen)

	screen._on_session_state_changed(NetworkManager.STATE_RECONNECTING)
	var status_label: Label = screen.get_node("Overlay/Content/StatusLabel")
	assert_eq(status_label.text, tr("ui.join.status_reconnecting"))


func test_disconnected_state_no_longer_handled_locally() -> void:
	# STATE_DISCONNECTED match arm is removed; JoinScreen must not crash on it,
	# and must not render any local error content (no _error_content node exists
	# anymore to render into).
	var screen := _get_join_screen()
	assert_not_null(screen)
	if screen == null:
		return
	add_child_autofree(screen)

	# Must not error/crash — the arm is simply absent from the match statement.
	screen._on_session_state_changed(NetworkManager.STATE_DISCONNECTED)
	assert_null(screen.get_node_or_null("Overlay/ErrorContent"))
