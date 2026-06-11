---
phase: 02-world-building-content
plan: 10
subsystem: tools
tags: [tools, durability, survival-mode, hotbar, ui, lantern]
dependency_graph:
  requires: [02-04, 02-09]
  provides: [tool-kit, tool-wear, durability-bar, handheld-lantern]
  affects: [hotbar-ui, builder-scene, features-autoload, locale]
tech_stack:
  added:
    - ToolDefinition (Resource class with class_name)
    - ToolWear (Node autoload — per-instance durability tracking)
    - ToolDurabilityBar (Control — 4px survival-only overlay)
  patterns:
    - Resource pattern from brick_definition.gd for ToolDefinition
    - Autoload pattern from thermal_probe.gd for ToolWear
    - StyleBoxFlat overlay from preset_chip.gd for ToolDurabilityBar
    - Signal-driven HUD update via ToolWear.durability_changed
key_files:
  created:
    - src/tools/tool_definition.gd
    - src/tools/pickaxe_wood.tres
    - src/tools/pickaxe_stone.tres
    - src/tools/pickaxe_iron.tres
    - src/tools/pickaxe_diamond.tres
    - src/tools/shovel.tres
    - src/tools/dynamite.tres
    - src/tools/lantern_handheld.tres
    - src/autoload/tool_wear.gd
    - src/ui/tool_durability_bar.gd
  modified:
    - src/autoload/features.gd
    - src/ui/hotbar.gd
    - src/builder/builder.tscn
    - src/builder/builder.gd
    - project.godot
    - locale/en.po
    - tests/unit/test_tool_wear.gd
decisions:
  - Resource type hints used in ToolWear autoload (not ToolDefinition class_name) to avoid
    class registry resolution ordering issue in headless/autoload parse order
  - _test_set_mode_override() added to ToolWear for unit test mode stubbing without real WorldSave
  - global_script_class_cache.cfg updated via godot --headless --import (not manually committed)
  - Lantern toggle wired from hotbar._update_lantern_light via Builder group lookup
metrics:
  duration: "~45 minutes"
  completed: "2026-05-26"
  completed_tasks: 2
  total_tasks: 2
  files_created: 10
  files_modified: 7
---

# Phase 02 Plan 10: Tool Kit + Durability System Summary

**One-liner:** ToolDefinition Resource + 7 tool .tres (4 pickaxe tiers, shovel, dynamite, lantern) + ToolWear autoload with survival/sandbox gate + 4px hotbar durability bar + Pitfall-9-safe handheld lantern OmniLight3D.

## Tasks Completed

| Task | Name | Commit | Key Files |
|------|------|--------|-----------|
| 1 | ToolDefinition + 7 .tres + ToolWear autoload + survival gate | 3beead4 | src/tools/*, src/autoload/tool_wear.gd, src/autoload/features.gd |
| 2 | Durability bar overlay + handheld lantern OmniLight3D | 92efb72 | src/ui/tool_durability_bar.gd, src/ui/hotbar.gd, src/builder/builder.tscn |

## What Was Built

### Task 1: ToolDefinition + 7 Tools + ToolWear + Survival Gate

**ToolDefinition Resource** (`src/tools/tool_definition.gd`):
- `class_name ToolDefinition extends Resource`
- Enum `ToolCategory { PICKAXE=0, SHOVEL=1, DYNAMITE=2, LANTERN=3 }`
- Exports: `tool_id`, `display_name_key`, `category`, `tier`, `max_durability`, `dynamite_radius_m`, `lantern_light_radius_m`, `mesh`

**7 Tool .tres files** (all per DOCS §3.4 spec):
- `pickaxe_wood.tres`: tier=0, max_durability=60
- `pickaxe_stone.tres`: tier=1, max_durability=120
- `pickaxe_iron.tres`: tier=2, max_durability=240
- `pickaxe_diamond.tres`: tier=3, max_durability=500
- `shovel.tres`: category=SHOVEL, max_durability=80
- `dynamite.tres`: category=DYNAMITE, max_durability=1, dynamite_radius_m=5.0 (single-use)
- `lantern_handheld.tres`: category=LANTERN, max_durability=0 (never wears out)

**ToolWear autoload** (`src/autoload/tool_wear.gd`):
- Registered in project.godot after Weather, before BrickRegistry
- Signals: `durability_changed(tool_id, instance_id, new_pct)` + `worn_out(tool_id, instance_id)`
- `decrement_on_use(tool: Resource, instance_id: String) -> bool`
- Gate 1: sandbox → no decrement (Features.is_survival_mode() == false)
- Gate 2: lantern (max_durability=0) → never wears out
- `get_durability`, `set_durability`, `is_worn_out` public API
- `attach_world()` / `detach_world()` for WorldSave persistence via `get_world_meta("tool_durability")`
- Uses `Resource` type hints (not `ToolDefinition`) to avoid autoload class parse ordering issue

**Features.is_survival_mode()** extension (`src/autoload/features.gd`):
- `const CURRENT_MODE_KEY = "mode"` for clarity
- `func is_survival_mode() -> bool` reads WorldSave.get_world_meta("mode") == "survival"
- NOT a §9-deferred feature flag — sandbox/survival is a world-creation property (DOCS §5.1)

**Locale additions** (`locale/en.po`): 7 tool names + ui.tool.worn_out + ui.tool.durability_sr + ui.tool.dynamite_fuse_lit + ui.hud.mode.survival + ui.hud.mode.sandbox

**Tests** (`tests/unit/test_tool_wear.gd`): 3/3 GREEN
- `test_sandbox_mode_no_decrement`: 100 uses in sandbox → durability stays at max
- `test_survival_mode_decrement_on_use`: 10 uses in survival → durability = max - 10
- `test_durability_zero_emits_worn_out`: set to 1, one use → worn_out emitted, is_worn_out returns true

### Task 2: Durability Bar + Handheld Lantern

**ToolDurabilityBar** (`src/ui/tool_durability_bar.gd`):
- `class_name ToolDurabilityBar extends Control`
- `custom_minimum_size = Vector2(0, 4)` — 4px tall per UI-SPEC.md
- Anchored to bottom edge of parent slot (PRESET_BOTTOM_WIDE)
- `visible = Features.is_survival_mode()` in `_ready()` — hidden in sandbox
- Connects to `ToolWear.durability_changed` signal, filters by `"slot_{_slot_index}"`
- `_draw()`: navy track + coloured fill (green #5DBB46 at ≥30%, red #D63828 below)
- `set_durability_pct(pct)` for direct test/initial-sync use

**Hotbar extensions** (`src/ui/hotbar.gd`):
- Instantiates one `ToolDurabilityBar` per slot in `_build_slots()`; sets `_slot_index`
- `_build_mode_badge()`: Label showing "Survival"/"Sandbox" via tr() at top-right of parent
- `set_slot_tool_id(slot, tool_id)` for Plan 12 palette-to-hotbar equip wiring
- `_update_lantern_light(prev_slot, next_slot)` toggles `Builder.set_handheld_lantern()`

**Builder scene** (`src/builder/builder.tscn`):
- `Hand` (Node3D) at position (0.3, 1.0, -0.4) — held-item attachment point
- `HandheldLanternLight` (OmniLight3D child of Hand):
  - `light_cull_mask = 2` (CHANNEL_BUILDER_ONLY — Pitfall 9 mitigation)
  - `omni_range = 8.0` (matches lantern_handheld.tres.lantern_light_radius_m)
  - `light_color = #F5C30D` (warm yellow per D-03 palette)
  - `light_energy = 1.5`
  - `visible = false` initially

**Builder script** (`src/builder/builder.gd`):
- `set_handheld_lantern(lit: bool)`: gets Hand/HandheldLanternLight node, sets `.visible = lit`
- Defensive `is_node_ready()` guard + null check with warning

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Resource type hints in ToolWear autoload instead of ToolDefinition class_name**
- **Found during:** Task 1
- **Issue:** In Godot 4.6, autoload scripts are parsed before the global class registry fully resolves `class_name` types. Using `ToolDefinition` as a parameter type annotation in `tool_wear.gd` caused "Parse Error: Could not find type 'ToolDefinition'" in headless/CI runs, preventing the autoload from loading.
- **Fix:** Changed all `ToolDefinition` parameter types to `Resource` (the parent class) with dynamic property access via `tool.get("max_durability")` etc. The same pattern is used by `world_save.gd` (uses `Object` for SQLite). Callers still pass ToolDefinition resources; GDScript's duck-typing handles the rest.
- **Files modified:** src/autoload/tool_wear.gd
- **Commit:** 3beead4

**2. [Rule 2 - Missing critical functionality] Added `_test_set_mode_override()` to ToolWear for unit tests**
- **Found during:** Task 1 test writing
- **Issue:** Unit tests need to stub WorldSave mode without a real SQLite database open. Without a test hook, tests would always hit the "WorldSave not open" path and return false (sandbox) unconditionally.
- **Fix:** Added `_test_mode_override: String` field and `_test_set_mode_override(mode)` method to ToolWear. Wrapped `Features.is_survival_mode()` calls via `_is_survival_mode()` which checks the override first.
- **Files modified:** src/autoload/tool_wear.gd, tests/unit/test_tool_wear.gd
- **Commit:** 3beead4

## Known Stubs

None. All tool resources have proper data. The dynamite VFX handler stub is documented in the plan as intentional — Plan 11 wires the VFX; this plan ships the resource only. No stub that prevents the plan's goal from being achieved.

## Threat Surface Scan

| Flag | File | Description |
|------|------|-------------|
| threat_flag: light_channel_isolation | src/builder/builder.tscn | HandheldLanternLight with light_cull_mask=2 is the correct Pitfall 9 mitigation (CHANNEL_BUILDER_ONLY). The OmniLight3D does NOT appear in the visual layer that is_deep_dark() checks for hostile spawn suppression. This was an explicit design requirement, not an unplanned surface. |

## Self-Check: PASSED

All 10 created files confirmed present on disk. Both task commits (3beead4, 92efb72) confirmed in git log. 3/3 tests GREEN. Glossary check passes.
