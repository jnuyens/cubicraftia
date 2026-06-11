# Asset Provenance: assets/meshes/

## brick_1x1.glb — 1×1 Concave-Top-Stud Brick Mesh

### Summary

Phase 1's single brick mesh: a 1×1 cuboid body with one concave-top cylindrical stud on the
top face. Concave top (bottle-cap indent) is locked per CONTEXT.md D-08.

### Authoring Tool

**Blender 5.1.2** (2026-05-19, `ec6e62d40fa9`), run headless via:

```bash
blender -b -P scripts/generate-brick-mesh.py
```

The script is committed at `scripts/generate-brick-mesh.py` and is the canonical
deterministic source for the asset.

### Geometry Specification

All dimensions in world-space metres (1 stud = 1.0 m per DOCS.md §2.1):

| Part | Dimension |
|------|-----------|
| Body width (X) | 1.0 m |
| Body height (Y) | 1.2 m (= 1 brick = 3 plates × 0.4 m/plate) |
| Body depth (Z) | 1.0 m |
| Stud outer radius | 0.3 m |
| Stud height | 0.18 m (above body top face at Y=1.2) |
| Stud top (tip) | Y = 1.38 m |
| Cavity (concave indent) radius | 0.18 m |
| Cavity depth | 0.12 m (sunk into stud from top) |
| Cylinder segments | 16 |

### Boolean Operations

The concave-top stud (D-08 invariant) is produced by:

1. Primitives: `BrickBody` (cube, body dimensions) + `BrickStud` (cylinder, stud dims).
2. A cutter cylinder `BrickCavity` (radius=0.18 m, depth=0.18 m) centred at the stud's
   top face is created.
3. A `BOOLEAN DIFFERENCE` (FLOAT solver) is applied to `BrickStud` with `BrickCavity`
   as the operand — producing a cylindrical hollow in the stud top (bottle-cap profile).
4. Body and stud are joined into a single mesh object `Brick_1x1`.

### stud_profile Invariant

The `extras` field `cubicraftia.stud_profile == "concave_top"` is written on the mesh.
The unit test `test_brick_definition.gd::test_concave_top_marker` asserts this value
on every load — any asset replacement that loses the concave intent fails the test (T-05-02).

### glTF extras Schema

Per RESEARCH.md Pattern 2. The following custom properties are written on the Blender
object and exported into the glTF node-level `extras` dictionary:

```json
{
  "cubicraftia.brick_id":     "brick_1x1",
  "cubicraftia.dimensions":   "[1, 1, 1]",
  "cubicraftia.studs_top":    "[{\"x\": 0.0, \"y\": 1.0, \"z\": 0.0, \"gender\": \"male\"}]",
  "cubicraftia.studs_bottom": "[{\"x\": 0.0, \"y\": 0.0, \"z\": 0.0, \"gender\": \"female\"}]",
  "cubicraftia.material":     "plastic_solid",
  "cubicraftia.stud_profile": "concave_top"
}
```

Note: Blender 5.x serialises Array custom properties as JSON strings. `BrickDefinition.from_gltf()`
calls `_parse_json_if_string()` to deserialise them on load.

**NOT using EXT_structural_metadata** — per RESEARCH.md Pitfall 1 / A11: Godot 4.6 silently
drops that extension. The `extras` dict is the correct pragmatic path for Phase 1.

### Godot Import Notes

- extras land on the **Node** (MeshInstance3D's parent or the MeshInstance3D itself),
  not the `Mesh` resource.
- `BrickDefinition.from_gltf()` walks the import tree: mesh-level → node-level → parent
  nodes, to handle wherever Godot places the metadata (Assumption A4).

### Regeneration

```bash
# From project root:
blender -b -P scripts/generate-brick-mesh.py
shasum -a 256 assets/meshes/brick_1x1.glb
# Compare with SHA-256 below. If it matches, asset is identical.
```

### SHA-256 Checksums

```
brick_1x1.glb:   052dff6682aa29ca98a6f19262a643535f34e673b2af3ffb50e26d1f4d41f9c6
```

File size: 11004 bytes

### License

`GPL-3.0-or-later` — see `brick_1x1.glb.license` and `brick_1x1.blend.license`.
