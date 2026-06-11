<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
# Multipass API Spike — Phase 2

**Decision (2026-05-26):** multipass-available

**Evidence:**

Files inspected during this spike:

- `addons/godot_voxel/generators/multipass/voxel_generator_multipass_cb.h` — C++ class definition confirming the GDVIRTUAL binding: `GDVIRTUAL2(_generate_pass, Ref<VoxelToolMultipassGenerator>, int)` (line 123) and `GDVIRTUAL2(_generate_block_fallback, Ref<godot::VoxelBuffer>, Vector3i)` (line 126).
- `addons/godot_voxel/generators/multipass/voxel_generator_multipass_cb.cpp` — `_bind_methods()` (line 626+) confirms `_generate_pass` is bound with parameter names `"voxel_tool"` and `"pass_index"` (line 655).
- `addons/godot_voxel/doc/classes/VoxelGeneratorMultipassCB.xml` — Official class doc confirms the virtual method signature and semantics.

**Exact GDScript API surface (from XML doc):**

```gdscript
# Required override — called once per pass per column of blocks.
# voxel_tool: VoxelToolMultipassGenerator — query + edit voxels in the column;
#             do NOT store as a member variable; only valid during this call.
# pass_index: int — 0 = first pass (no neighbor access); 1+ = subsequent passes.
func _generate_pass(voxel_tool: VoxelToolMultipassGenerator, pass_index: int) -> void:
    pass

# Optional — generates blocks above/below the column-based region.
func _generate_block_fallback(out_buffer: VoxelBuffer, origin_in_voxels: Vector3i) -> void:
    pass

# Optional — declare which VoxelBuffer channels the generator writes.
func _get_used_channels_mask() -> int:
    return 0
```

Additional API relevant to mineshafts:
- `get_pass_count() / set_pass_count(count: int)` — configure number of passes.
- `get_pass_extent_blocks(pass_index) / set_pass_extent_blocks(pass_index, extent)` — how many blocks around a column each pass can read (pass 0 is always 0; pass 1+ can be > 0).
- `debug_generate_test_column(column_position_blocks: Vector2i) -> VoxelBuffer[]` — offline testing helper.

**Caveats:**
- `VoxelGeneratorMultipassCB` is marked `is_experimental="true"` in the XML doc. It is present and bound in the installed addon at commit `4a9d311` (pinned in `scripts/install-deps.sh`).
- Only works with `VoxelTerrain` (not `VoxelLodTerrain`). Cubicraftia's terrain scene already uses `VoxelTerrain` — no change needed.

**Implication for Plan 02-08:**

multipass-available: Plan 02-08 ships `src/world/multipass_generator.gd extends VoxelGeneratorMultipassCB` with `_generate_pass(voxel_tool: VoxelToolMultipassGenerator, pass_index: int) -> void` as the entry point.

Recommended two-pass structure for mineshafts:
- **Pass 0** (`pass_index == 0`): base terrain (dense stone/ore fill in the underground zone) — no neighbor access, maps directly to what `terrain_generator.gd` does today for the relevant depth band.
- **Pass 1** (`pass_index == 1`, `set_pass_extent_blocks(1, 2)` for corridor reach): mineshaft corridor carving — picks up the pre-seeded corridor piece library (~5 types from D-07) and carves them into the block data using `voxel_tool.set_voxel()`.

The `_generate_block_fallback` override handles everything above the column region (air) and below (bedrock), keeping parity with the current `terrain_generator.gd` depth behaviour.

The spike outcome is binding for Plan 02-08; the planner does not re-litigate this choice at execution time. The file `src/world/multipass_generator.gd` IS shipped; it is NOT folded inline into `terrain_generator.gd`.
