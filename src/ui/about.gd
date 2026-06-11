# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# about.gd - About / Credits screen controller.
#
# Per UI-SPEC.md "Disclaimers + Legal Surface" and Copywriting Contract:
#   - Title: tr("ui.about.title") = "About Cubicraftia"
#   - Version: tr("ui.about.version") with {version} from project.godot
#   - License: tr("ui.about.license") + "View license" button (OS.shell_open)
#   - Disclaimer: tr("ui.about.disclaimer") (allowlisted for LEGO Group mention)
#
# This scene's path is allowlisted in scripts/glossary-allowlist.txt:
#   src/ui/about.tscn:
# because the disclaimer text rendered here contains "LEGO Group".

extends PanelContainer

@onready var _title_label: Label = $VBox/TitleLabel
@onready var _version_label: Label = $VBox/VersionLabel
@onready var _license_label: Label = $VBox/LicenseLabel
@onready var _disclaimer_label: Label = $VBox/DisclaimerLabel
@onready var _license_button: Button = $VBox/LicenseButton
@onready var _back_button: Button = $VBox/BackButton


func _ready() -> void:
	_title_label.text = tr("ui.about.title")

	var version: String = ProjectSettings.get_setting("application/config/version", "0.1.0")
	_version_label.text = tr("ui.about.version").format({"version": version})

	_license_label.text = tr("ui.about.license")
	_disclaimer_label.text = tr("ui.about.disclaimer")

	_license_button.text = "View license"
	_license_button.pressed.connect(_on_license_pressed)

	_back_button.text = tr("ui.common.back")
	_back_button.pressed.connect(_on_back_pressed)


func _on_license_pressed() -> void:
	var license_path := ProjectSettings.globalize_path("res://LICENSE")
	OS.shell_open(license_path)


func _on_back_pressed() -> void:
	queue_free()
