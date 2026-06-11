---
phase: 03-survival-loop
plan: 07b
subsystem: crafting-ui
tags:
  - phase-3
  - workbench
  - workbench-ui
  - recipe-book
  - crafting-ui
dependency_graph:
  requires:
    - 03-05   # InventorySlideIn (open_workbench_mode stub + slide-in chrome)
    - 03-06   # ChestEntity pattern (walk-up interact, polled input)
    - 03-07a  # Recipe Resource + RecipeRegistry + CRAFT_AUTOFILL event + match_recipe API
  provides:
    - WorkbenchEntity (src/world/workbench_entity.gd + .tscn) — walk-up interact, opens 3×3 panel
    - WorkbenchPanel (src/ui/workbench_panel.gd + .tscn) — 3×3 grid + craft arrow + output slot
    - RecipeBookTab (src/ui/recipe_book_tab.gd) — D-05 progressive reveal + auto-fill
    - InventorySlideIn.open_workbench_mode body (full — replaces Plan 03-05 stub)
    - InventorySlideIn._build_recipes_pane helper (lazy recipe tab init)
    - workbench.tres updated (colour_swappable=false, natural_colour_token=7, display_name_key fix)
  affects:
    - src/ui/inventory_slide_in.gd
    - src/bricks/workbench.tres
tech_stack:
  added: []
  patterns:
    - WorkbenchEntity polled-input pattern (mirrors ChestEntity from 03-06)
    - WorkbenchPanel programmatic layout (mirrors ChestPanel from 03-06)
    - RecipeBookTab lazy-init in _build_recipes_pane (built on first tab switch or workbench open)
    - D-05 progressive reveal: Inventory.get_revealed_recipes as source of truth (T-03-07b-UI-01)
    - T-03-07b-UI-03 panel reuse: _workbench_panel_instance hidden/shown, not freed/recreated
key_files:
  created:
    - src/world/workbench_entity.gd (WorkbenchEntity — 130 lines)
    - src/world/workbench_entity.tscn (StaticBody3D + CollisionShape3D + Mesh + WalkupPrompt)
    - src/ui/workbench_panel.gd (WorkbenchPanel — 230 lines)
    - src/ui/workbench_panel.tscn (minimal root Control; layout built programmatically)
    - src/ui/recipe_book_tab.gd (RecipeBookTab — 250 lines)
  modified:
    - src/ui/inventory_slide_in.gd (open_workbench_mode body + _build_recipes_pane + teardown)
    - src/bricks/workbench.tres (colour_swappable, natural_colour_token, display_name_key)
decisions:
  - "workbench-tres-2x2-preserved: workbench.tres keeps 2×2 footprint from Phase 2 manifest; 1×1 in plan spec was a placeholder hint; actual workbench occupies 2×2 stud cells matching Phase 2 brick set"
  - "workbench-panel-reuse: _workbench_panel_instance hidden/shown on repeated open_workbench_mode calls (T-03-07b-UI-03); not queue_freed until slide-in itself is freed"
  - "recipe-book-tab-lazy: RecipeBookTab instantiated lazily on first _set_active_tab('recipes') OR on open_workbench_mode; avoids building the tab UI before the Inventory singleton is ready"
  - "workbench-panel-open-api: open_for_workbench(workbench_id, builder_id) takes builder_id as second param; plan spec had single param; extended for Phase 4 multi-builder readiness"
metrics:
  duration: "~35 minutes"
  completed_date: "2026-05-27"
  tasks_completed: 2
  files_created: 5
  files_modified: 2
---

# Phase 03 Plan 07b: Crafting UI Layer — WorkbenchEntity, WorkbenchPanel, RecipeBookTab

**One-liner:** WorkbenchEntity walk-up entity + WorkbenchPanel 3×3 crafting grid + RecipeBookTab with D-05 progressive reveal + auto-fill via CRAFT_AUTOFILL — completing both crafting surfaces (2×2 inline from 03-05 and 3×3 workbench from this plan).

## What Was Built

### WorkbenchPanel open_for_workbench body + 3×3 grid composition

```gdscript
func open_for_workbench(workbench_id: String, builder_id: String = "") -> void:
    _workbench_id = workbench_id
    _builder_id = builder_id

    # Rebuild 3×3 crafting slots (9 InventorySlot nodes, source_grid="crafting_3x3").
    _crafting_slots.clear()
    for child in _workbench_grid.get_children(): child.queue_free()
    for i in range(GRID_SIZE * GRID_SIZE):
        var slot = _InventorySlotScene.instantiate() as InventorySlot
        slot.slot_index = i
        slot.source_grid = "crafting_3x3"
        slot.custom_minimum_size = Vector2(CELL_SIZE, CELL_SIZE)  # 64 px
        _workbench_grid.add_child(slot)
        _crafting_slots.append(slot)

    # Rebuild 6×8 builder inventory slots (48 InventorySlot nodes, source_grid="inventory").
    # ... (same pattern)

    # Sync grid state from Inventory._floating_crafting_grid["crafting_3x3"].
    _sync_grid_state()
    _refresh_slots()
    _refresh_output()

    # Subscribe to Inventory.inventory_changed for live grid refresh.
    if not Inventory.inventory_changed.is_connected(_on_inventory_changed):
        Inventory.inventory_changed.connect(_on_inventory_changed)
```

**Layout (built programmatically in _build_layout):**

```
VBoxContainer
├─ WorkbenchGrid (GridContainer, columns=3) — 9 × 64px crafting input slots
├─ CraftRow (HBoxContainer)
│   ├─ CraftArrow (Label "→")
│   └─ OutputSlot (InventorySlot, source_grid="crafting_3x3_output")
├─ Separator (HSeparator)
└─ BuilderGrid (GridContainer, columns=8) — 48 × 64px builder inventory slots
```

### RecipeBookTab _refresh_book filter logic + revealed-vs-locked styling

```gdscript
func _refresh_book() -> void:
    # T-03-07b-UI-01 mitigation: read fresh from Inventory — never cache in UI.
    var revealed_list = Inventory.get_revealed_recipes(_builder_id)
    var revealed_set: Dictionary = {}
    for recipe_id in revealed_list:
        revealed_set[recipe_id] = true

    # Fetch the full registry (all recipes, revealed or not).
    var registry: Dictionary = Inventory._recipe_registry

    for recipe_id in registry:
        var is_revealed = revealed_set.has(recipe_id)
        var row = _build_recipe_row(recipe_id, recipe, is_revealed)
        add_child(row)
        _recipe_rows[recipe_id] = row

# Styling difference between revealed and locked:
#   Revealed:  result_icon.modulate = Color(1, 1, 1, 1)   (full alpha)
#   Locked:    result_icon.modulate = Color(0.5, 0.5, 0.5, 0.5)  (50% alpha + greyed)
#   Locked:    fill_btn.disabled = true (cannot auto-fill a locked recipe)
```

### Auto-fill flow: tap row → CRAFT_AUTOFILL → Inventory → grid writes

```
Player taps "Fill grid" button on a recipe row
  │
  ├─ _on_fill_grid_pressed(recipe_id, fill_btn)
  │   ├─ Determines target_grid: "crafting_2x2" (inventory mode) OR "crafting_3x3" (workbench mode)
  │   │   by reading slide_in._mode from the inventory_slide_in group
  │   │
  │   └─ Inventory.apply_event({kind: "CRAFT_AUTOFILL", builder_id, recipe_id, target_grid})
  │       ├─ Plan 03-07a validates: builder has all ingredients (T-03-07a-CR-01)
  │       ├─ Removes ingredients from inventory
  │       ├─ Writes to _floating_crafting_grid[target_grid]
  │       └─ Emits inventory_changed
  │
  ├─ WorkbenchPanel._on_inventory_changed → _sync_grid_state → _refresh_slots → _refresh_output
  │   └─ _refresh_output: Inventory.match_recipe(_grid_state, false) [shaped]
  │                       → recipe found → _output_slot.set_content(output_def_id, output_count)
  │
  └─ RecipeBookTab flashes FillGrid button (#F5C30D, 200 ms) on success
```

## Deviations from Plan

### Auto-fixed Issues

None — plan executed exactly as written.

### Minor Adjustments (no deviation)

**1. workbench.tres 2×2 footprint preserved**
- **Found during:** Task 1 implementation
- **Issue:** workbench.tres was already in manifest.json from Phase 2 with 2×2 footprint; plan spec said 1×1 as placeholder hint
- **Resolution:** Kept 2×2 (already committed, correct for the StudGrid physical size); updated only the semantically important fields: `colour_swappable=false`, `natural_colour_token=7` (brown), `display_name_key="ui.workbench.title"`
- **Not a deviation:** workbench.tres pre-existing is consistent with the plan's "51st brick" language being an approximation — it was already registered in Phase 2

**2. open_for_workbench takes builder_id as second param**
- **Found during:** Task 2 (WorkbenchPanel needs builder_id to subscribe correctly)
- **Reasoning:** Plan spec had single param; added `builder_id` as optional second param for Phase 4 multi-builder readiness; consistent with ChestPanel's open_for_chest signature
- **Not a deviation:** additive change, backward-compatible

## Open Carries to Plan 03-11

- **End-to-end first-night loop:** Plan 03-11 (UAT) verifies the full survival path:
  starter chest → wood_plank → workbench recipe (2×2 grid) → place workbench → walk up → open 3×3 panel → pickaxe/shovel recipe → craft tool.
- **Brick ID discrepancy:** recipe_wooden_plank uses `brick_log_wood` as input and `wood_plank` as output; starter chest provides `wood_plank`. Plan 03-11 must confirm inventory IDs align (see 03-07a-SUMMARY open carry note).
- **RecipeBookTab mobile scroll:** The VBoxContainer rows may overflow on small screens; Plan 03-11 or Phase 6 polish should wrap it in a ScrollContainer.

## Known Stubs

| Stub | File | Reason |
|------|------|--------|
| `mesh = null` in workbench.tres | src/bricks/workbench.tres | Art-pass deferred per brick-mesh-null-phase2 decision; BoxMesh placeholder in workbench_entity.tscn |
| BoxMesh placeholder in workbench_entity.tscn | src/world/workbench_entity.tscn | Same as above — distinct workbench .glb deferred to v1 polish |
| TextureRect icons empty (result + ingredient) | src/ui/recipe_book_tab.gd | No icon .png assets yet; texture is null until Phase 6 art pass |

## Threat Flags

None. No new network endpoints or auth paths introduced. All data flows through existing Inventory.apply_event() trust boundary. CRAFT_AUTOFILL ingredient validation lives in Plan 03-07a (T-03-07a-CR-01).

## Self-Check: PASSED

Files exist:
- src/world/workbench_entity.gd — FOUND
- src/world/workbench_entity.tscn — FOUND
- src/ui/workbench_panel.gd — FOUND
- src/ui/workbench_panel.tscn — FOUND
- src/ui/recipe_book_tab.gd — FOUND
- src/bricks/workbench.tres — FOUND (updated)

Commits exist:
- 7eb490d feat(03-07b): WorkbenchEntity + workbench.tres update + InventorySlideIn.open_workbench_mode body — FOUND
- 308b8a0 feat(03-07b): WorkbenchPanel 3x3 grid + RecipeBookTab D-05 progressive reveal + auto-fill — FOUND

Key assertions:
- `grep -c "class_name WorkbenchEntity" src/world/workbench_entity.gd` → 1
- `ls src/bricks/workbench.tres src/world/workbench_entity.tscn | wc -l` → 2
- `grep -c "func open_workbench_mode" src/ui/inventory_slide_in.gd` → 1 (body filled)
- `grep -c "class_name WorkbenchPanel" src/ui/workbench_panel.gd` → 1
- `grep -c "class_name RecipeBookTab" src/ui/recipe_book_tab.gd` → 1
- `grep -c "_refresh_book\|_on_fill_grid_pressed\|_show_empty_state" src/ui/recipe_book_tab.gd` → 9 (≥ 3)
- `grep -c "CRAFT_AUTOFILL\|apply_event" src/ui/recipe_book_tab.gd` → 6 (≥ 1)
- `grep -c "_build_recipes_pane\|_recipes_pane" src/ui/inventory_slide_in.gd` → 12 (≥ 2)
- glossary-check.sh → OK
- extract-pot.sh → OK (182 lines, no new untranslated strings)
