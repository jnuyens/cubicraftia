# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# first_launch_disclaimer.gd - First-launch disclaimer dialog.
#
# Shows the disclaimer on the very first run on a device.
# Persistence: writes [first_launch] acknowledged=true to user://settings.cfg the
# first time the "Got it" button is tapped; subsequent launches skip the dialog.
#
# Per UI-SPEC.md "Disclaimers + Legal Surface":
#   - Body: tr("ui.first_launch.disclaimer") = same as ui.about.disclaimer.
#   - Primary button: tr("ui.first_launch.acknowledge") = "Got it".
#   - After acknowledge: writes [first_launch] acknowledged=true to user://settings.cfg.
#
# ALLOWLISTED in scripts/glossary-allowlist.txt: src/ui/first_launch_disclaimer.tscn
# because this scene displays the disclaimer copy which contains "LEGO Group" verbatim.

extends Control

const SETTINGS_PATH := "user://settings.cfg"
const SECTION := "first_launch"
const KEY := "acknowledged"

@onready var _disclaimer_label: Label = $Panel/VBox/DisclaimerLabel
@onready var _ack_button: Button = $Panel/VBox/AcknowledgeButton


func _ready() -> void:
	# Check if already acknowledged
	var cfg := ConfigFile.new()
	var err := cfg.load(SETTINGS_PATH)
	if err == OK and cfg.get_value(SECTION, KEY, false):
		# Already acknowledged - hide and free immediately
		visible = false
		queue_free()
		return

	# Show the disclaimer
	visible = true
	if _disclaimer_label != null:
		_disclaimer_label.text = tr("ui.first_launch.disclaimer")
	if _ack_button != null:
		_ack_button.text = tr("ui.first_launch.acknowledge")
		_ack_button.pressed.connect(_on_acknowledge_pressed)


func _on_acknowledge_pressed() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)  # Load existing or start fresh
	cfg.set_value(SECTION, KEY, true)
	cfg.save(SETTINGS_PATH)
	queue_free()
