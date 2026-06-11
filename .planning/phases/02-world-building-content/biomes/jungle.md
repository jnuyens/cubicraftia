# Biome Brief: Jungle

**ID:** `jungle` | **Phase:** 02 | **Status:** pending — awaiting user approval

---

## 1. Identity

An overwhelming explosion of green — dense canopy overhead that filters sun into dappled
shafts, root-laced ground that is hard to navigate, vines trailing from every surface. Getting
lost here is part of the thrill. Jungle temples, half-concealed by vines, deliver one of the
strongest exploration highs in the game: the feeling that the world hid something remarkable
just out of sight.

## 2. Whittaker classification

Temperature 0.2 → 1.0 (warm to hot); Moisture 0.0 → 1.0 (wet).
`_classify`: `t > 0.2 and m > 0.0` → `JUNGLE`.

## 3. Ambient tint

**Hex:** `#5CE86A` — vivid saturated green that pushes shadows toward emerald and makes the
canopy feel dense and alive. Anchored near `#5DBB46` (brick green) but shifted yellow-green
to distinguish from the temperate grassland tint (`#B5E890`).

## 4. Sun colour temperature

5 000 K — warm-neutral, slightly amber (`#FFEEDC`). The canopy largely blocks direct sun; the
ambient channel tint dominates ground-level lighting.

## 5. Terrain palette

`jungle_grass` (surface) · `dirt` (sub-surface) · `stone` (deep) · `water` + `water_surface`
(pools and rivers)

## 6. Signature flora (VoxelInstancer species)

1. `jungle_tree_large` — massive 2×2-cell trunk, canopy at 10-14 cell height; 3-5 per cluster
2. `jungle_tree_small` — single-cell trunk, 5-8 cell height; fills mid-layer gaps
3. `vine_drape` — 3-6 cell vertical strip of green plate bricks hanging from branches
4. `jungle_fern` — broad-leaf 2-cell fern; dense ground cover under canopy
5. `tropical_flower_red` — 1-cell vivid red flower on stem; accent colour against green
6. `bamboo_cluster` — 4-7 cell lime-green round-brick stalks; groups of 3-5

## 7. Atmospheric wildlife

1. **Monkey** — small brick-built quadruped with a long curved tail made of linked 1×1 round bricks; swings between vine_drape props and perches on large branch-level canopy nodes.
2. **Toucan** — compact stud-segmented bird with a disproportionately large coloured bill in vivid orange and yellow; perches singly on upper jungle_tree_large canopy edges, occasionally gliding to a neighbouring tree.

*Implementation: rendered like Village NPCs (Plan 02-13) using VoxelInstancer for non-interactive crowds; scope and exact implementation plan are deferred — these species are locked here so downstream plans can bind to them.*

## 8. Signature props

1. **Moss-covered stone block** — 2×2 stone brick with green slope plates draped across top and
   one side; a boulder colonised by moss; appears near tree roots.
2. **Vine-wrapped pillar fragment** — 1×1×4 dark-grey stone column with a vine_drape attached;
   suggests a ruined structure absorbed by the jungle.

## 9. Structures owned

**Jungle temple** (3 variants; dark-stone brick covered in vine and moss; partially buried;
contains loot and creature spawners per DOCS §2). **Shared** (all biomes): dungeons and
mineshafts per DOCS §2.

## 10. Ambient sound

Deferred to a later audio pass. Target feel: continuous insect drone, distant bird calls (2-3
distinct), occasional dripping water — a dense humid rainforest canopy in full afternoon heat.

## 11. NPC skin variants

n/a — no village in this biome.
