# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# test_title_scene_create_account.gd - Regression guard for the real-device "Create account
# button does nothing" bug.
#
# Root cause: sign_in_panel.tscn ships `visible = false` by contract (its own header comment
# requires the caller to set `.visible = true` after instantiating). title_scene.gd's
# _on_sign_in_pressed() (shared by both the "Sign in" and "Create account" buttons) never did.
# This test instantiates TitleScene, invokes _on_sign_in_pressed() directly (bypassing the
# button-press animation/tween), and asserts the resulting overlay panel is actually visible.
#
# Headless note: TitleScene extends CanvasLayer and only constructs Control/Button/Label/
# AudioStreamPlayer nodes in _build_ui() (no GPU-only resources), so it instantiates safely
# under `godot --headless`. Autoloads (FriendsClient, DeepLinkHandler, OnboardingTelemetry) are
# project-registered singletons, available in any run including headless GUT.
#
# Anchor: src/ui/title_scene.gd _on_sign_in_pressed(); src/ui/sign_in_panel.tscn header contract.

extends GutTest

const TitleSceneScript := preload("res://src/ui/title_scene.gd")

func test_create_account_button_opens_visible_panel() -> void:
	var scene: CanvasLayer = TitleSceneScript.new()
	add_child_autofree(scene)
	await get_tree().process_frame  # let _ready() finish building the UI + tween setup

	scene.call("_on_sign_in_pressed", true)  # simulates the Create account button

	var overlay: Node = scene.get("_open_overlay")
	assert_not_null(overlay, "Create account press must create an overlay CanvasLayer")
	if overlay == null:
		return
	var panel: Node = overlay.get_child(0) if overlay.get_child_count() > 0 else null
	assert_not_null(panel, "overlay must contain the instantiated sign_in_panel")
	if panel != null:
		assert_true(panel.visible,
			"sign_in_panel must be visible after Create account is pressed; it ships visible=false by contract and the caller must show it")


func test_sign_in_button_opens_visible_panel() -> void:
	# Same shared _on_sign_in_pressed() handler, create_account_mode=false: must be equally fixed.
	var scene: CanvasLayer = TitleSceneScript.new()
	add_child_autofree(scene)
	await get_tree().process_frame

	scene.call("_on_sign_in_pressed", false)

	var overlay: Node = scene.get("_open_overlay")
	assert_not_null(overlay, "Sign in press must create an overlay CanvasLayer")
	if overlay == null:
		return
	var panel: Node = overlay.get_child(0) if overlay.get_child_count() > 0 else null
	assert_not_null(panel, "overlay must contain the instantiated sign_in_panel")
	if panel != null:
		assert_true(panel.visible,
			"sign_in_panel must be visible after Sign in is pressed")
