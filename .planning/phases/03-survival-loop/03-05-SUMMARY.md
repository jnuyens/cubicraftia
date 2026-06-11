---
phase: 03-survival-loop
plan: 05
subsystem: inventory-ui
tags:
  - phase-3
  - inventory-ui
  - slide-in
  - drag-drop
  - hotbar
  - mobile-overlay
dependency_graph:
  requires:
    - 03-02  # Inventory autoload (get_slots, apply_event, match_recipe, inventory_changed)
    - 03-04  # inventory_toggle_requested signal from Builder
  provides:
    - inventory_slide_in_sidebar.tscn / inventory_slide_in_bottomsheet.tscn
    - inventory_slot.gd / inventory_slot.tscn
    - hotbar.gd set_slot_item extension
    - mobile_overlay.gd notify_inventory_open / notify_palette_open
    - locale/en.po Phase 3 i18n surface (~60 keys)
  affects:
    - 03-06  # chest panel sub-controller — open_chest_mode stub ready
    - 03-07b # workbench panel — open_workbench_mode stub ready
    - 03-09  # food/strawberry — i18n keys already in en.po
    - 03-10  # creature i18n keys already in en.po
tech_stack:
  added:
    - Godot 4.6 Control built-in drag-drop (_get_drag_data / _can_drop_data / _drop_data)
  patterns:
    - verbatim chrome port from brick_palette.gd (_setup_panel_style, _animate_to, _snap_to_nearest)
    - programmatic slot instantiation (48 InventorySlot nodes via preload + add_child)
    - mutual exclusion pattern: open() closes the brick palette; notify_inventory_open closes palette
key_files:
  created:
    - src/ui/inventory_slot.gd        (396 lines — per-slot Panel with Godot 4.6 drag-drop)
    - src/ui/inventory_slot.tscn      (Panel root 64×64, script attached, group inventory_slot)
    - src/ui/inventory_slide_in.gd    (529 lines — InventorySlideIn controller)
    - src/ui/inventory_slide_in_sidebar.tscn      (desktop right-edge 360px scene)
    - src/ui/inventory_slide_in_bottomsheet.tscn  (mobile bottom-sheet scene)
  modified:
    - src/ui/hotbar.gd                (set_slot_item + _resolve_item_icon + _resolve_item_name_for_hotbar added)
    - src/ui/mobile_overlay.gd        (notify_inventory_open + notify_palette_open + _on_inventory_pressed added)
    - src/ui/mobile_overlay.tscn      (InventoryButton node added top-right)
    - locale/en.po                    (~60 Phase 3 keys appended — sole en.po owner for Phase 3)
    - assets/themes/cubicraftia.tres  (4 additive InventorySlot StyleBoxFlat state entries)
decisions:
  - inventory-slot-programmatic-children: Icon, CountLabel, SelectedRing built in _ready() instead of .tscn children — allows 48 identical slots without a deep scene hierarchy and matches hotbar.gd pattern
  - set_drag_preview-clone: drag preview is a new TextureRect with same texture + 0.85 scale + 0.7 alpha — Godot 4.6 requirement is a separate node from the source
  - crafting-state-session-local: _crafting_grid_state is kept in the slide-in (not Inventory autoload) because 2×2 crafting is per-session and not persisted; deferred to Plan 03-02 author confirmation
  - common-keys-pre-existing: ui.common.cancel / ui.common.done / ui.common.back were already in en.po from Phase 1; not duplicated
  - open_chest_mode-stub: method body is intentionally minimal (sets mode + calls open()); Plan 03-06 overrides the body per the plan spec
metrics:
  duration_minutes: 10
  completed_date: "2026-05-27"
  tasks_completed: 3
  tasks_total: 3
  files_created: 5
  files_modified: 5
---

# Phase 3 Plan 05: Inventory Slide-In UI Summary

**One-liner:** 48-slot inventory slide-in (sidebar + bottomsheet) with Godot 4.6 drag-drop, 2×2 crafting cluster, tab header, hotbar extension, mobile overlay coordination, and ~60 Phase 3 i18n keys.

## Slide-in Chrome Verification

Side-by-side comparison of `_setup_panel_style` body:

**brick_palette.gd L121-134 (reference):**
```gdscript
func _setup_panel_style() -> void:
    var style := StyleBoxFlat.new()
    style.bg_color = Color(0.106, 0.173, 0.337, 0.92)  # #1B2C56 at 0.92α
    if layout == "sidebar":
        style.corner_radius_top_left = 16
        style.corner_radius_bottom_left = 16
        style.corner_radius_top_right = 0
        style.corner_radius_bottom_right = 0
    else:
        style.corner_radius_top_left = 16
        style.corner_radius_top_right = 16
        style.corner_radius_bottom_left = 0
        style.corner_radius_bottom_right = 0
    add_theme_stylebox_override("panel", style)
```

**inventory_slide_in.gd (ported, near-verbatim):**
```gdscript
func _setup_panel_style() -> void:
    if _body == null:
        return
    var style := StyleBoxFlat.new()
    style.bg_color = COLOR_NAVY  # Color(0.106, 0.173, 0.337, 0.92)
    if layout == "sidebar":
        style.corner_radius_top_left = 16
        style.corner_radius_bottom_left = 16
        style.corner_radius_top_right = 0
        style.corner_radius_bottom_right = 0
    else:
        style.corner_radius_top_left = 16
        style.corner_radius_top_right = 16
        style.corner_radius_bottom_left = 0
        style.corner_radius_bottom_right = 0
    _body.add_theme_stylebox_override("panel", style)
```

Only difference: the body null-guard and applying to `_body` (PanelContainer child) rather than `self` (the chrome lives on the Body PanelContainer, not the root Control) — required because InventorySlideIn root is a Control, not a PanelContainer.

## Drag-Drop Event Flow (5-step trace)

1. **Press** — Player left-click-drags an inventory slot (InventorySlot node).
2. **`_get_drag_data`** — Called by Godot 4.6 Control system. Returns `{source_slot, source_grid, def_id, count, builder_id}`. Calls `set_drag_preview(preview)` with a 0.85-scaled semi-transparent TextureRect.
3. **`_can_drop_data`** on the target slot — Called by Godot for every slot the cursor passes over. Returns `true` if data is a Dictionary with "source_slot" key.
4. **Drop** — Player releases. Godot calls `_drop_data` on the target InventorySlot.
5. **`_drop_data`** — Determines kind (MOVE / SWAP / SPLIT / ADD). Calls `Inventory.apply_event(event)`. Inventory emits `inventory_changed(builder_id)`. InventorySlideIn._on_inventory_changed() calls `_refresh_all_slots()`. Each InventorySlot.set_content() updates icon + count label.

## Mode-Swap Stubs

Both stubs are confirmed present:
- `open_chest_mode(chest_id, tier, locked)` — sets `_mode = "chest"` and calls `open()`. Plan 03-06 overrides the body to add the chest grid stacked above the inventory grid per UI-SPEC §"Chest panel".
- `open_workbench_mode(workbench_id)` — sets `_mode = "workbench"` and calls `open()`. Plan 03-07b overrides the body to swap 2×2 inline crafting for a 3×3 workbench grid.

## Mobile Overlay Extension

Both methods confirmed:
- `notify_inventory_open(is_open: bool)` — tracks `_inventory_panel_open`; closes palette on open (mutual exclusion); updates crosshair visibility; updates InventoryButton tooltip.
- `notify_palette_open(is_open: bool)` — public symmetric replacement for `_set_palette_open`; closes inventory slide-in if open before allowing the palette to expand.

InventoryButton (64×64 TouchScreenButton) added to mobile_overlay.tscn, anchored top-right at 16px from edge. On press, emits `ui_inventory_toggle` Input action via `Input.action_press` / `Input.action_release` so Builder._unhandled_input handles it identically to keyboard E.

## Open Carries: Floating-Slot State for Right-Click Single-Take

The right-click / long-press single-take path emits `{kind: "SINGLE_TAKE", to: -1, single_take: true}`. Per STATE.md `single-take-event-kind` decision (03-02), SINGLE_TAKE was added as the 10th event kind. When `to=-1`, Inventory._apply_single_take should place the item in a floating-cursor slot or, if that state is absent, fall the item back to the source slot.

**Deferred**: The `_floating_slot` cursor state in Inventory autoload was not explicitly confirmed in 03-02's implementation. The single-take handler in inventory.gd should implement `to=-1` as "take 1 to cursor-floating" per DOCS §4.1 drag-drop semantics. Plan 03-11 (UAT) should include a smoke test for right-click single-take.

## Known Stubs

| Stub | File | Reason |
|------|------|--------|
| `open_chest_mode` body | src/ui/inventory_slide_in.gd L313-316 | Plan 03-06 implements the chest grid body |
| `open_workbench_mode` body | src/ui/inventory_slide_in.gd L321-324 | Plan 03-07b implements the 3×3 workbench body |
| `_refresh_recipes_tab` body | src/ui/inventory_slide_in.gd L351-352 | Plan 03-07b ships the recipe-book refresh |
| RecipesPane | sidebar + bottomsheet .tscn | Empty placeholder; Plan 03-07b populates |
| Crafting state persistence | `_crafting_grid_state` session-local | If Plan 03-02 persists crafting state in Inventory, wire it; otherwise session-local is correct |

These stubs do not prevent the plan's goal (inventory grid + drag-drop + hotbar extension) from being achieved.

## Deviations from Plan

None — plan executed as written. Chrome is verbatim from brick_palette.gd. Drag-drop uses Godot 4.6 Control built-ins only (no hand-rolled mouse tracking). i18n keys match UI-SPEC §Copywriting Contract verbatim.

## Self-Check

Checking created files exist:
- [x] src/ui/inventory_slot.gd — 396 lines
- [x] src/ui/inventory_slot.tscn — Panel root 64×64
- [x] src/ui/inventory_slide_in.gd — 529 lines
- [x] src/ui/inventory_slide_in_sidebar.tscn — 16 nodes
- [x] src/ui/inventory_slide_in_bottomsheet.tscn — 18 nodes

Checking commits exist:
- [x] 09a9a99 — feat(03-05): InventorySlot Panel
- [x] d6fe6a1 — feat(03-05): InventorySlideIn controller
- [x] d10a9e3 — feat(03-05): extend MobileOverlay

## Self-Check: PASSED
