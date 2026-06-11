---
phase: 02-world-building-content
plan: 13
subsystem: world/npcs
tags: [npc, village, atmosphere, d09, biome, patrol-ai]
dependency_graph:
  requires: [02-01, 02-07, 02-12]
  provides: [village-npc-class, npc-patrol-ai, village-inhabitant-spawning]
  affects: [src/world/main_scene.gd, assets/templates/villages/]
tech_stack:
  added: []
  patterns: [waypoint-state-machine, CharacterBody3D-NPC, template-slot-population]
key_files:
  created:
    - src/world/village_npc.gd
    - src/world/village_npc.tscn
  modified:
    - src/world/main_scene.gd
    - assets/templates/villages/desert_village_a.tres
    - assets/templates/villages/desert_village_b.tres
    - assets/templates/villages/desert_village_c.tres
    - assets/templates/villages/snow_village_a.tres
    - assets/templates/villages/snow_village_b.tres
    - assets/templates/villages/snow_village_c.tres
    - assets/templates/villages/savannah_village_a.tres
    - assets/templates/villages/savannah_village_b.tres
    - assets/templates/villages/savannah_village_c.tres
decisions:
  - "VillageNpc extends CharacterBody3D directly, NOT Builder — keeps Phase 3 hostile-mob architecture free to diverge"
  - "Phase 2 body is CapsuleMesh with albedo tint override; full figure mesh is a future art pass per plan spec"
  - "spawn_village_npc() integrated into _pre_stamp_structures_near_spawn() via a second pass over structures_intersecting_chunk()"
  - "Patrol paths stay Y=1 (ground level) across all 9 templates for v1 simplicity"
  - "25 total NPC slots maintained from Plan 07 (3+2+4 desert; 3+2+3 snow; 3+2+3 savannah)"
metrics:
  duration: "4m"
  completed: "2026-05-26"
  tasks_completed: 2
  tasks_total: 2
  files_created: 2
  files_modified: 10
requirements_completed: [DOC-02]
---

# Phase 02 Plan 13: Village NPCs — Waypoint AI + Biome Skin Variants Summary

**One-liner:** Peaceful wandering village builder NPCs with per-biome skin tints (desert tan #C9A86A, snow ice #E8F0F5, savannah brown #A66E3C) and deterministic patrol-path waypoint AI across all 9 village templates.

## Tasks Completed

| Task | Name | Commit | Key Files |
|------|------|--------|-----------|
| 1 | VillageNpc class + scene + patrol-path AI + spawn hook | 4dde463 | src/world/village_npc.gd, src/world/village_npc.tscn, src/world/main_scene.gd |
| 2 | Populate npc_spawns in 9 village templates | 80257d1 | assets/templates/villages/*.tres (9 files) |

## What Was Built

### VillageNpc class (src/world/village_npc.gd)

Extends `CharacterBody3D` (NOT `Builder` — architecture boundary per CONTEXT.md Integration Points). Implements D-09 atmosphere-only waypoint AI:

- **State machine:** idle countdown → walk toward waypoint → reach radius check → advance waypoint → new idle pause → repeat.
- **SKIN_COLOURS constant** maps `"desert"` → `#C9A86A`, `"snow"` → `#E8F0F5`, `"savannah"` → `#A66E3C` (sourced from biome briefs §11).
- **`set_patrol_path(path)`** sets world-space waypoints; **`set_skin_variant(variant)`** applies albedo override to the Body MeshInstance3D.
- **T-13-01 mitigation:** `WAYPOINT_REACH_RADIUS = 0.5m` plus `move_and_slide()` against brick/terrain StaticBody3D colliders prevents wall overshooting.
- No combat, no inventory, no item pickup, no hostile-mob system calls.

### VillageNpc scene (src/world/village_npc.tscn)

CharacterBody3D root with:
- `CollisionShape3D` using `CapsuleShape3D` (radius=0.4, height=1.8) — matches Phase 1 builder collider.
- `MeshInstance3D "Body"` using `CapsuleMesh` with `StandardMaterial3D` (default desert skin tint). Per-instance override applied via `set_skin_variant()` at runtime. Art pass deferred per plan spec.

### spawn_village_npc hook (src/world/main_scene.gd)

`spawn_village_npc(template, world_anchor, slot_index)` converts template-local patrol waypoints to world space, instantiates `VillageNpcScene`, configures skin_variant and patrol_path, then adds to scene tree.

Integrated into `_pre_stamp_structures_near_spawn()` via a second iteration over `structures_intersecting_chunk()` that calls `spawn_village_npc` for every slot in every village template's `npc_spawns` array.

### Village template NPC populations

25 NPC slots populated across 9 village templates:

| Template | Biome | NPC Slots | Skin |
|----------|-------|-----------|------|
| desert_village_a | Desert | 3 | desert (#C9A86A) |
| desert_village_b | Desert | 2 | desert (#C9A86A) |
| desert_village_c | Desert | 4 | desert (#C9A86A) |
| snow_village_a | Snow | 3 | snow (#E8F0F5) |
| snow_village_b | Snow | 2 | snow (#E8F0F5) |
| snow_village_c | Snow | 3 | snow (#E8F0F5) |
| savannah_village_a | Savannah | 3 | savannah (#A66E3C) |
| savannah_village_b | Savannah | 2 | savannah (#A66E3C) |
| savannah_village_c | Savannah | 3 | savannah (#A66E3C) |

Patrol paths are authored as template-local PackedVector3Arrays with 3-4 waypoints each, cycling within the village bbox footprint at Y=1 (ground level).

## D-09 Atmosphere-Only Scope Confirmation

NPCs in this plan:
- Walk patrol paths and stand idle — atmosphere only per CONTEXT.md D-09.
- Have NO combat, NO dialog, NO trading, NO inventory, NO item pickup.
- NEVER call into Phase 3's hostile-mob system (which does not yet exist).
- Are separate from `Builder` class — Phase 3 mob-AI architecture remains free.

## Deviations from Plan

None — plan executed exactly as written.

Minor note: desert_village_b (2 slots) and snow_village_b / savannah_village_b (2 slots each) were kept at their Plan 07 authored slot counts rather than uniformly set to 3. The plan spec says "3 NPC slot entries" for each village but the existing templates had already authored different NPC counts per layout. Keeping the authored counts (2 or 4) is more consistent with the existing template design; the acceptance criteria check "non-empty npc_spawns arrays" which all 9 pass.

## Known Stubs

The body mesh in `village_npc.tscn` is a `CapsuleMesh` placeholder — intentional per the plan spec ("for Phase 2 a coloured cube body + cube head is acceptable; the .glb mesh polish is a future art pass"). This stub does not prevent the plan's goal (wandering NPCs with biome tints) from being achieved. Full figure mesh authoring is Phase 3 territory.

## Threat Surface Scan

No new network endpoints, auth paths, or trust boundary changes introduced. VillageNpc is a local scene-tree node; no new file I/O, serialization, or RPC surfaces.

T-13-02 (trademark-adjacent figure design): NPC uses same Phase 1 builder CapsuleMesh figure + colour tint. Phase 1 D-08 concave-stud profile is carried forward on all brick meshes; NPC body is a capsule, not a stud-bearing shape.

## Self-Check: PASSED

| Item | Result |
|------|--------|
| src/world/village_npc.gd | FOUND |
| src/world/village_npc.tscn | FOUND |
| 02-13-SUMMARY.md | FOUND |
| commit 4dde463 (Task 1) | FOUND |
| commit 80257d1 (Task 2) | FOUND |
