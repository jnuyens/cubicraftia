# Biome Brief: Grassland & Forest

**ID:** `grassland_forest` | **Phase:** 02 | **Status:** pending — awaiting user approval

---

## 1. Identity

Open grassy clearings give way to oak and birch stands, wildflowers dotting the ground. This
reads as *home base*: vivid green, wide blue sky, safe and inviting. Players build their first
shelter here and return after dangerous expeditions. Daytime feels genuinely cheerful.

## 2. Whittaker classification

Temperature −0.3 → 0 (temperate); Moisture −0.3 → 0.3 (moderate). Default fallback biome in
`_classify(t, m)` after all other conditions are checked.

## 3. Ambient tint

**Hex:** `#B5E890` — soft warm-green that pushes WorldEnvironment ambient shadows toward
green rather than grey. Anchored near `#5DBB46` (brick green) but lightened for a breezy
temperate feel rather than a jungle intensity.

## 4. Sun colour temperature

5 500 K — neutral-white, faint warm cast (`#FFF8F0`). High mid-morning sun on a clear day.

## 5. Terrain palette

`grass` (surface) · `dirt` (sub-surface) · `stone` (deep) · `water` + `water_surface`
(ponds) · `oak_log` + `oak_leaves` (tree trunks and canopy voxel volumes)

## 6. Signature flora (VoxelInstancer species)

1. `oak_tree` — medium (5-8 cells), round canopy; 3-6 per grove
2. `birch_tree` — tall thin (6-10 cells), white trunk; solitary or in pairs
3. `fern` — low ground cover under tree canopy
4. `daisy` — scattered white flowers across clearings
5. `tall_grass` — 2-cell tuft; fills open areas
6. `mushroom_red` — rare under dense oak shade

## 7. Atmospheric wildlife

1. **Panda bear** — slow-moving black-and-white quadruped with a stud-segmented round body; typically found near bamboo clusters at forest edges, ambling in pairs.

*Implementation: rendered like Village NPCs (Plan 02-13) using VoxelInstancer for non-interactive crowds; scope and exact implementation plan are deferred — these species are locked here so downstream plans can bind to them.*

## 8. Signature props

1. **Mossy boulder cluster** — 3-5 dark-grey stone bricks half-sunk near tree roots.
2. **Wildflower patch border** — 5-7 red, orange, and yellow 1×1 flower-plate bricks lining
   a clearing edge; purely decorative.

## 9. Structures owned

None exclusively. **Shared** (all biomes): dungeons (deep underground) and mineshafts (deep
stone layer) per DOCS §2.

## 10. Ambient sound

Deferred to a later audio pass. Target feel: birdsong, light wind, distant crickets at dusk —
temperate European countryside on a warm afternoon.

## 11. NPC skin variants

n/a — no village in this biome.
