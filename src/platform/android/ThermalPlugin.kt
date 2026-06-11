// SPDX-FileCopyrightText: 2026 Cubicraftia contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//
// ThermalPlugin.kt — Godot v2 Android plugin exposing the Android Thermal API.
//
// Extends GodotPlugin per the Godot 4.2+ v2 plugin architecture.
// Exposes three methods to GDScript via @UsedByGodot:
//   getThermalHeadroom(forecastSeconds)  — API 30+ (Android 11+), returns Double (NaN if unavailable)
//   getCurrentThermalStatus()           — API 29+ (Android 10+), returns Int (-1 if unavailable)
//   readSysfsZone()                     — reads /sys/class/thermal/thermal_zone0/temp,
//                                         returns millidegrees as Double (NaN on error)
//
// Layered probe (RESEARCH.md Pitfall 2):
//   1. getThermalHeadroom  — preferred (API 30+ only)
//   2. getCurrentThermalStatus  — fallback (API 29+)
//   3. readSysfsZone  — sysfs fallback for older devices
//
// Poll cadence: GDScript must NOT call getThermalHeadroom more than once per 10 s
// (Android's documented contract; RESEARCH.md Pitfall 3). The GDScript wrapper in
// android_thermal.gd enforces this cache; the Kotlin layer does not rate-limit.
//
// Package: T-07-SC — build.gradle pins org.godotengine:godot:4.6.3.stable (Maven Central).

package org.cubicraftia.android

import android.content.Context
import android.os.Build
import android.os.PowerManager
import org.godotengine.godot.Godot
import org.godotengine.godot.plugin.GodotPlugin
import org.godotengine.godot.plugin.UsedByGodot
import java.io.File

class ThermalPlugin(godot: Godot) : GodotPlugin(godot) {

    override fun getPluginName() = "CubicraftiaThermal"

    // ─── Layer 1: getThermalHeadroom (API 30+ / Android 11+) ─────────────────

    /**
     * Returns the normalised thermal headroom float for the given forecast window.
     *
     * A value of 1.0 means the device is at its thermal limit; 0.0 means no headroom
     * consumed. Returns Double.NaN if the API is not available (API < 30) or if
     * PowerManager cannot be obtained.
     *
     * @param forecastSeconds  Number of seconds to forecast ahead (pass 0 for current).
     */
    @UsedByGodot
    fun getThermalHeadroom(forecastSeconds: Int): Double {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return Double.NaN  // API 30+
        val pm = activity?.getSystemService(Context.POWER_SERVICE) as? PowerManager
            ?: return Double.NaN
        return try {
            pm.getThermalHeadroom(forecastSeconds).toDouble()
        } catch (e: Exception) {
            Double.NaN
        }
    }

    // ─── Layer 2: getCurrentThermalStatus (API 29+ / Android 10+) ────────────

    /**
     * Returns the discrete thermal status integer (PowerManager.THERMAL_STATUS_*).
     *
     * Maps to Android's thermal status enum:
     *   0 = THERMAL_STATUS_NONE
     *   1 = THERMAL_STATUS_LIGHT
     *   2 = THERMAL_STATUS_MODERATE
     *   3 = THERMAL_STATUS_SEVERE
     *   4 = THERMAL_STATUS_CRITICAL
     *   5 = THERMAL_STATUS_EMERGENCY
     *   6 = THERMAL_STATUS_SHUTDOWN
     *
     * Returns -1 if the API is not available (API < 29) or PowerManager cannot be obtained.
     */
    @UsedByGodot
    fun getCurrentThermalStatus(): Int {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return -1  // API 29+
        val pm = activity?.getSystemService(Context.POWER_SERVICE) as? PowerManager
            ?: return -1
        return try {
            pm.currentThermalStatus
        } catch (e: Exception) {
            -1
        }
    }

    // ─── Layer 3: readSysfsZone (sysfs fallback for API < 29) ────────────────

    /**
     * Reads /sys/class/thermal/thermal_zone0/temp and returns the value in
     * millidegrees Celsius as a Double. Most Android kernels expose zone0 as the
     * primary SoC temperature sensor.
     *
     * Returns Double.NaN if the file cannot be read (permission denied, or the
     * thermal zone does not exist on this kernel).
     *
     * This is the Pitfall 2 sysfs fallback layer — used when both getThermalHeadroom
     * and getCurrentThermalStatus are unavailable.
     */
    @UsedByGodot
    fun readSysfsZone(): Double {
        return try {
            val raw = File("/sys/class/thermal/thermal_zone0/temp").readText().trim()
            raw.toDouble()
        } catch (e: Exception) {
            Double.NaN
        }
    }
}
