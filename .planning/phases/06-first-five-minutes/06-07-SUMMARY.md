---
phase: 06-first-five-minutes
plan: "07"
subsystem: builder/avatar
tags: [avatar, builder, mesh, customisation, gdscript]
dependency_graph:
  requires: [06-04]
  provides: [Builder.apply_avatar_config, Builder.load_avatar_from_file, multi-part-avatar-mesh]
  affects: [src/builder/builder.gd, src/ui/avatar_creator.gd]
tech_stack:
  added: []
  patterns: [programmatic-mesh-setup, configfile-persistence, index-bounds-clamping]
key_files:
  created: [tests/unit/test_builder_avatar.gd]
  modified: [src/builder/builder.gd]
decisions:
  - "Avatar mesh nodes created programmatically in _setup_avatar_mesh_nodes() in _ready() rather than in .tscn — avoids headless editor toolchain for node additions and works identically in main world and SubViewport preview"
  - "Hand/body accessory shapes are BoxMesh stubs; real sculpted meshes deferred to Phase 999.1 per plan spec"
  - "get_active_material(0) used to retrieve the surface override material set via set_surface_override_material(0, mat) — consistent with Godot 4.x API"
  - "avatar_creator.gd._apply_config_to_preview() already contains a has_method() check that routes to apply_avatar_config() — no changes to avatar_creator.gd required"
metrics:
  duration: "~25 minutes"
  completed: "2026-05-29"
  tasks_completed: 1
  files_changed: 2
---

# Phase 06 Plan 07: Builder.apply_avatar_config + Multi-Part Mesh Summary

Builder gains programmatic multi-part avatar mesh (Head/Body/Legs/HandItem/BodyAccessory) with `apply_avatar_config()` for colour and accessory updates driven by the 8-key avatar config schema, closing the loop between avatar_creator and the in-world builder appearance.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| RED | Failing tests for apply_avatar_config | bfec87b | tests/unit/test_builder_avatar.gd |
| GREEN | Builder avatar implementation | 90cf8f8 | src/builder/builder.gd |

## What Was Built

### `src/builder/builder.gd` additions

**Constants:**
- `SKIN_COLOURS: Array[Color]` — 5 values matching `avatar_creator.gd` exactly
- `BODY_COLOURS: Array[Color]` — 10 values matching `avatar_creator.gd` exactly
- `DEFAULT_AVATAR_CFG: Dictionary` — all 8 keys with Classic-preset defaults (index 0 skin, blue body/legs, no accessories)

**Avatar mesh node refs:** `_avatar_mesh_root`, `_head_mesh`, `_body_mesh`, `_legs_mesh`, `_hand_nodes: Dictionary`, `_body_accessory_nodes: Dictionary`

**New methods:**

`_setup_avatar_mesh_nodes() -> void` — creates the full avatar node tree programmatically:
- `AvatarMesh` (Node3D root container)
  - `Head` (BoxMesh 0.5×0.5×0.5, Y=1.4) — skin colour target
  - `Body` (BoxMesh 0.4×0.6×0.3, Y=0.9) — body colour target
  - `Legs` (BoxMesh 0.4×0.5×0.3, Y=0.35) — leg colour target
  - `HandItem` (Node3D, Y=0.9, X=0.3, Z=-0.25) with 5 children: `none`, `pickaxe`, `lantern`, `flower`, `blank`
  - `BodyAccessory` (Node3D) with 3 children: `none`, `backpack`, `cape`

`apply_avatar_config(cfg: Dictionary) -> void`:
- Applies `SKIN_COLOURS[skin_colour_index]` to head mesh albedo
- Applies `BODY_COLOURS[body_colour_index]` to body mesh albedo
- Applies `BODY_COLOURS[leg_colour_index]` to legs mesh albedo
- Sets head mesh scale for `head_shape` (square=1.0, round=0.9×1.0×0.9, tall=1.0×1.2×1.0)
- Toggles hand accessory visibility (only selected key visible)
- Toggles body accessory visibility (only selected key visible)
- T-06-B1 mitigate: all indices clamped with `clampi()` before array access

`load_avatar_from_file() -> void` — loads `user://avatar.cfg`, falls back to `DEFAULT_AVATAR_CFG`

**`_ready()` additions:** calls `_setup_avatar_mesh_nodes()` then `load_avatar_from_file()` at the end of the existing init sequence.

### `src/ui/avatar_creator.gd`

No changes needed. The existing `_apply_config_to_preview()` method already contains:
```gdscript
if _preview_builder.has_method("apply_avatar_config"):
    _preview_builder.apply_avatar_config(cfg)
    return
```
This routes to `apply_avatar_config()` now that the method exists, upgrading the SubViewport preview automatically.

### `tests/unit/test_builder_avatar.gd`

17 tests covering:
- Method existence (`apply_avatar_config`, `load_avatar_from_file`)
- Constant sizes (5 skin, 10 body colours)
- Colour value correctness vs. `avatar_creator.gd`
- Head/body/legs albedo colour application
- Hand accessory visibility toggling
- Body accessory visibility toggling
- Multiple call safety (no resource leaks)
- Out-of-range index clamping (T-06-B1)
- `DEFAULT_AVATAR_CFG` completeness
- Node tree existence after `_ready()`
- Head shape scale variants

## Deviations from Plan

None — plan executed exactly as written. The `avatar_creator.gd` upgrade mentioned in the plan was already in place via the `has_method()` guard (no separate edit required).

## Known Stubs

The hand accessory and body accessory meshes are BoxMesh stubs:
- `HandItem/pickaxe`, `HandItem/lantern`, `HandItem/flower`, `HandItem/blank` — box stubs with approximate colours
- `BodyAccessory/backpack`, `BodyAccessory/cape` — box stubs

These are **intentional** per plan spec (Phase 6 ships programmatic primitive sub-meshes; real sculpted meshes are Phase 999.1). The goal — colour-driven avatar customisation visible in both the SubViewport preview and the in-world builder — is fully achieved with the primitive meshes.

## Threat Model Coverage

| Threat ID | Category | Mitigation Applied |
|-----------|----------|--------------------|
| T-06-B1 | Tampering (out-of-range index) | `clampi(idx, 0, COLOURS.size()-1)` before all array accesses in `apply_avatar_config()` |

## Self-Check: PASSED

- `src/builder/builder.gd` — exists and contains `apply_avatar_config`, `load_avatar_from_file`, `SKIN_COLOURS`, `BODY_COLOURS`, `DEFAULT_AVATAR_CFG`, `clampi`
- `tests/unit/test_builder_avatar.gd` — exists with 17 tests
- Commit `bfec87b` (RED: test) — present
- Commit `90cf8f8` (GREEN: implementation) — present
- All 6 plan verification checks pass
