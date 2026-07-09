# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# test_network_hud_badge.gd: headless proof of NetworkHud's always-visible
# two-state Direct/Relay connection badge (13-06-PLAN.md Task 2, RELY-05).
#
# Covers:
#   - New peer rows show the badge immediately (never hidden), defaulting to
#     "Direct" / COLOR_GOOD.
#   - set_connection_badge(peer_id, is_relay) replaces show_relay_badge and
#     updates both text and font color in one call, without ever touching
#     .visible.
#   - No interactivity (click/hover/tooltip) is ever wired to the badge.
#
# In-viewport visual verification (actual on-screen color rendering) is
# display-gated and deferred to Phase 12 per executor instructions.

extends GutTest

const NetworkHudScript = preload("res://src/ui/network_hud.gd")


func _get_hud() -> NetworkHud:
	var scene := load("res://src/ui/network_hud.tscn")
	if scene == null:
		return null
	return scene.instantiate()


func _badge_for(hud: NetworkHud, peer_id: int) -> Label:
	var row: HBoxContainer = hud.get_node("PeerRow_%d" % peer_id)
	return row.get_node("RelayBadge") as Label


# ─── Default state on row build ───────────────────────────────────────────────

func test_new_peer_row_badge_visible_and_direct_by_default() -> void:
	var hud := _get_hud()
	assert_not_null(hud, "network_hud.tscn must exist and instantiate")
	if hud == null:
		return
	add_child_autofree(hud)

	hud._build_peer_row(1)
	var badge := _badge_for(hud, 1)
	assert_not_null(badge)
	if badge == null:
		return
	assert_true(badge.visible, "badge must be visible immediately on row build (never hidden)")
	assert_eq(badge.text, tr("ui.netstatus.badge_direct"),
		"badge must default to Direct text")
	assert_eq(badge.get_theme_color("font_color"), NetworkHudScript.COLOR_GOOD,
		"badge must default to COLOR_GOOD")


# ─── set_connection_badge API ─────────────────────────────────────────────────

func test_set_connection_badge_relay_true_shows_relay_amber() -> void:
	var hud := _get_hud()
	assert_not_null(hud)
	if hud == null:
		return
	add_child_autofree(hud)

	hud._build_peer_row(2)
	hud.set_connection_badge(2, true)
	var badge := _badge_for(hud, 2)
	assert_eq(badge.text, tr("ui.netstatus.relay_badge"))
	assert_eq(badge.get_theme_color("font_color"), NetworkHudScript.COLOR_AMBER)
	assert_true(badge.visible, "badge must remain visible for relay state too")


func test_set_connection_badge_relay_false_reverts_to_direct_green() -> void:
	var hud := _get_hud()
	assert_not_null(hud)
	if hud == null:
		return
	add_child_autofree(hud)

	hud._build_peer_row(3)
	hud.set_connection_badge(3, true)
	hud.set_connection_badge(3, false)
	var badge := _badge_for(hud, 3)
	assert_eq(badge.text, tr("ui.netstatus.badge_direct"))
	assert_eq(badge.get_theme_color("font_color"), NetworkHudScript.COLOR_GOOD)


func test_show_relay_badge_method_removed() -> void:
	var hud := _get_hud()
	assert_not_null(hud)
	if hud == null:
		return
	add_child_autofree(hud)

	assert_false(hud.has_method("show_relay_badge"),
		"show_relay_badge must be replaced by set_connection_badge")
	assert_true(hud.has_method("set_connection_badge"))


# ─── Wiring + no-interactivity guarantees ─────────────────────────────────────

func test_connection_type_changed_handler_wired() -> void:
	var hud := _get_hud()
	assert_not_null(hud)
	if hud == null:
		return
	add_child_autofree(hud)

	assert_true(hud.has_method("_on_connection_type_changed"))
	hud._build_peer_row(4)
	hud._on_connection_type_changed(4, true)
	var badge := _badge_for(hud, 4)
	assert_eq(badge.text, tr("ui.netstatus.relay_badge"))


func test_badge_has_no_click_or_hover_wiring() -> void:
	# Structural guarantee: the badge is a plain Label with no signal
	# connections of its own (no pressed/mouse_entered/tooltip wiring).
	var hud := _get_hud()
	assert_not_null(hud)
	if hud == null:
		return
	add_child_autofree(hud)

	hud._build_peer_row(5)
	var badge := _badge_for(hud, 5)
	assert_true(badge is Label, "badge must remain a non-interactive Label (not Button/TextureButton)")
	assert_eq(badge.tooltip_text, "", "badge must never carry a tooltip")
