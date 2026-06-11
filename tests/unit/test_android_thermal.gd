# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# test_android_thermal.gd — Unit tests for the AndroidThermal layered probe.
#
# On desktop builds (where OS.has_feature("android") is false), AndroidThermal
# should return "unavailable" from get_path() and NaN / -1 from all read methods.
#
# These tests run headlessly on the dev machine and in CI without any Android device.
# On-device behaviour (Layer 1/2 of the probe) is validated manually by the
# benchmark run per the MOTOROLA_BENCHMARK.md runbook.
#
# GUT test class: see addons/gut/README.md for GUT conventions.

extends GutTest


var _at: Node = null


func before_each() -> void:
	# Instantiate a fresh AndroidThermal node for each test.
	var script := load("res://src/autoload/android_thermal.gd")
	_at = Node.new()
	_at.set_script(script)
	add_child_autofree(_at)
	# _ready() is called automatically when added to the tree.


# Test 1: on a desktop (non-Android) build, get_path() returns "unavailable".
func test_get_probe_path_returns_unavailable_on_desktop() -> void:
	# On desktop, OS.has_feature("android") is false, so _path is always "unavailable".
	var path: String = _at.get_probe_path()
	assert_eq(path, "unavailable",
		"AndroidThermal.get_probe_path() must return 'unavailable' on non-Android builds")


# Test 2: read_headroom() returns NaN when path is "unavailable".
func test_read_headroom_returns_nan_when_unavailable() -> void:
	assert_true(is_nan(_at.read_headroom()),
		"AndroidThermal.read_headroom() must return NaN when path is 'unavailable'")


# Test 3: read_status() returns -1 when path is "unavailable".
func test_read_status_returns_minus_one_when_unavailable() -> void:
	assert_eq(_at.read_status(), -1,
		"AndroidThermal.read_status() must return -1 when path is 'unavailable'")


# Test 4: read_sysfs_millidegrees() returns NaN when path is "unavailable".
func test_read_sysfs_millidegrees_returns_nan_when_unavailable() -> void:
	assert_true(is_nan(_at.read_sysfs_millidegrees()),
		"AndroidThermal.read_sysfs_millidegrees() must return NaN when path is 'unavailable'")


# Test 5: provider interface — get_thermal_headroom() and get_thermal_status()
# must be present (called by ThermalProbe.set_thermal_provider on Android).
func test_provider_interface_methods_exist() -> void:
	assert_true(_at.has_method("get_thermal_headroom"),
		"AndroidThermal must expose get_thermal_headroom() for ThermalProbe provider interface")
	assert_true(_at.has_method("get_thermal_status"),
		"AndroidThermal must expose get_thermal_status() for ThermalProbe provider interface")
	assert_true(_at.has_method("get_probe_path"),
		"AndroidThermal must expose get_probe_path() for thermal_probe_path CSV column")


# Test 6: get_thermal_headroom() returns NaN on desktop (provider interface).
func test_get_thermal_headroom_provider_returns_nan_on_desktop() -> void:
	assert_true(is_nan(_at.get_thermal_headroom()),
		"AndroidThermal.get_thermal_headroom() must return NaN on desktop")


# Test 7: get_thermal_status() returns -1 on desktop (provider interface).
func test_get_thermal_status_provider_returns_minus_one_on_desktop() -> void:
	assert_eq(_at.get_thermal_status(), -1,
		"AndroidThermal.get_thermal_status() must return -1 on desktop")


# Test 8: ThermalProbe integration — setting AndroidThermal as provider causes
# _detect_probe_path() to use get_path() and return "unavailable" on desktop.
func test_thermal_probe_reads_path_from_android_thermal() -> void:
	var probe := get_node_or_null("/root/ThermalProbe")
	if probe == null:
		# ThermalProbe autoload may not be present in the unit test tree.
		# Skip gracefully.
		pass_test("ThermalProbe autoload not available in this test context — skip")
		return

	# Set the provider and verify the detected path comes from get_path().
	probe.set_thermal_provider(_at)
	var probe_path_label: String = probe._detect_probe_path()
	assert_eq(probe_path_label, "unavailable",
		"ThermalProbe._detect_probe_path() should return 'unavailable' on desktop via AndroidThermal.get_probe_path()")
	# Reset provider to null to avoid contaminating other tests.
	probe.set_thermal_provider(null)
