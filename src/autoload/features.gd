# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# features.gd — Features singleton (Pattern 1: Feature-Flag on ProjectSettings)
#
# Registered as autoload "Features" in project.godot.
#
# Source of truth: DOCS.md §9 "What's not in v1 (and why)" — 18 rows.
# Every §9 deferred feature has a corresponding flag here, all shipping false.
#
# Note on count: RESEARCH.md Pattern 1 listed 19 keys by splitting "snow_weather"
# and "thunderstorms" into two entries. DOCS.md §9 row 576 collapses these into
# one ("Snow, thunderstorms, lightning"). DOCS.md is the authoritative source;
# this file uses the DOCS.md row count of 18.
#
# Phase 2+ plans may flip individual flags to true ONLY after a coordinated
# DOCS.md §9 update. The CI script scripts/verify-feature-flags.sh enforces
# that no flag is true in project.godot.
#
# Usage:
#   if Features.is_enabled("brick_rotation"):
#       apply_rotation()
#
# Pitfall 10: feature flags are READ-ONLY at runtime. Never write them via
# ProjectSettings.set_setting() outside this file's _ready().
extends Node

# ─── Source-of-truth dict (18 keys = 18 DOCS.md §9 rows) ──────────────────────
const _DEFERRED_FEATURES: Dictionary = {
	"snow_thunder_lightning":   false,   # DOCS.md §9 — Rain ships v1.0; full weather is v1.1
	"hunger_thirst":            false,   # DOCS.md §9 — Whole subsystem; v1.1+
	"voice_chat":               false,   # DOCS.md §9 — Significant scope; v1.2+
	"open_lobbies":             false,   # DOCS.md §9 — Contradicts social model; indefinite
	"pvp_combat":               false,   # DOCS.md §9 — Contradicts friend-group ethos; v2
	"creeper_explode":          false,   # DOCS.md §9 — Dynamite plays same role; v1.1
	"mod_system":               false,   # DOCS.md §9 — Official extension API is post-v1
	"vr_mode":                  false,   # DOCS.md §9 — Out of scope for v1
	"cosmetics_subscription":   false,   # DOCS.md §9 — No subscription model; indefinite
	"cloud_world_sync":         false,   # DOCS.md §9 — Cloud hosting is post-v1
	"resource_packs":           false,   # DOCS.md §9 — Community-contributable post-v1
	"large_servers_5plus":      false,   # DOCS.md §9 — P2P caps at ~4; v2 architecture work
	"dedicated_server_dist":    false,   # DOCS.md §9 — Server distribution packaging; v1.1
	"web_browser_client":       false,   # DOCS.md §9 — WebRTC works; likely v1.2
	"cross_mode_switching":     false,   # DOCS.md §9 — Locked at creation in v1; v1.1
	"brick_rotation":           false,   # DOCS.md §9 — Auto-orient in v1; manual rotation v1.1
	"master_builder_gating":    false,   # DOCS.md §9 — Contradicts "every brick available"; indefinite
	"brick_gravity":            false,   # DOCS.md §9 — Bricks float in v1; optional gravity post-v1
}

# Also expose as build_palette_enabled per DOC-09 (Phase 2 flips this)
const build_palette_enabled: bool = false


func _ready() -> void:
	# Register each deferred-feature flag in ProjectSettings with its default.
	# This makes the flag visible in the Godot editor's ProjectSettings UI
	# and readable via ProjectSettings.get_setting() from any script.
	# Pitfall 10: this is the ONLY place flags are set; gameplay code only READs.
	for key: String in _DEFERRED_FEATURES:
		var setting := "cubicraftia/features/%s" % key
		if not ProjectSettings.has_setting(setting):
			ProjectSettings.set_setting(setting, _DEFERRED_FEATURES[key])
		# Register type hint for the editor
		ProjectSettings.add_property_info({
			"name": setting,
			"type": TYPE_BOOL,
			"hint": PROPERTY_HINT_NONE,
			"hint_string": "",
		})


## Returns true if the named feature flag is enabled.
##
## Asserts (debug builds) on unknown feature keys to catch typos early.
## Plans 2-6 call this to guard §9-deferred behaviour; in Phase 1 it always
## returns false.
func is_enabled(feature: String) -> bool:
	var setting := "cubicraftia/features/%s" % feature
	assert(ProjectSettings.has_setting(setting),
		"Unknown feature flag: '%s'. Add it to _DEFERRED_FEATURES in features.gd." % feature)
	return ProjectSettings.get_setting(setting)


## Key used to read the world mode from WorldSave.
## Sandbox/survival is locked at world-creation time (DOCS §5.1).
## NOT a §9-deferred feature flag — this is a runtime world property.
const CURRENT_MODE_KEY: String = "mode"

## Returns true if the current world is in survival mode.
##
## Reads WorldSave.get_world_meta("mode") == "survival".
## Returns false (sandbox assumed) if no world is open or if the key is missing.
##
## Per DOCS §5.1: mode is locked at world creation; cross-mode switching is §9-deferred
## (see "cross_mode_switching" in _DEFERRED_FEATURES above).
##
## Used by ToolWear.decrement_on_use() and ToolDurabilityBar visibility gating
## (UI-SPEC.md §"Tool Durability Bar").
func is_survival_mode() -> bool:
	# Defensive: WorldSave can be null mid-startup or during a stale-cache
	# editor reload (saw user-reported error-spam at world_select_screen when
	# .godot/ had partially-rebuilt cache from a directory rename).
	if not is_instance_valid(WorldSave) or not WorldSave.is_open():
		return false
	var mode: Variant = WorldSave.get_world_meta(CURRENT_MODE_KEY)
	if mode == null:
		return false
	return (mode as String) == "survival"
