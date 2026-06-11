# Biome Brief: Snow

**ID:** `snow` | **Phase:** 02 | **Status:** pending — awaiting user approval

---

## 1. Identity

A crystalline, hushed landscape of snow-covered hills and frozen lakes; the ground gleams
blue-white and distant terrain fades into pale mist. Beautiful but indifferent to human warmth.
Entering raises the stakes: resources are harder to spot, creatures more dangerous at night.
A snow village, when found, feels like a genuine reward — amber lanterns glowing against white.

## 2. Whittaker classification

Temperature −1.0 → −0.3 (cold); Moisture 0.0 → 0.3 (moderate-damp).
`_classify`: `t < -0.3` (and not ocean) → `SNOW`.

## 3. Ambient tint

**Hex:** `#C8EAFF` — cool blue-white that desaturates shadows toward icy pale blue. Anchored
near `#1F7BCB` (brick blue) but heavily lightened to read as reflected snowlight.

## 4. Sun colour temperature

6 500 K — cool, blue-tinted, low-angle winter sun (`#E8F4FF`). Bright but without warmth.

## 5. Terrain palette

`snow` (surface) · `dirt` (sub-surface) · `ice` (frozen water) · `stone` (deep)

## 6. Signature flora (VoxelInstancer species)

1. `spruce_tree` — tall narrow conifer (7-10 cells), triangular silhouette, snow-cap on top
   leaf node; clusters of 2-4
2. `snow_pine_small` — compact 3-5 cell spruce variant; fills gaps between full-size spruces
3. `frozen_fern` — 1-cell rigid blue-tinted fern; ground cover on dirt patches
4. `icicle_cluster` — 1-2 cell downward-pointing transparent geometry; hangs from rock
   overhangs and branch undersides

## 7. Atmospheric wildlife

1. **Reindeer** — tall brick-built quadruped with branching stud-plate antlers; moves in small herds of 2-4 across snowy clearings between spruce stands.
2. **Snowman / Snowwoman** — static brick-built sculpture of stacked white spherical bricks with coloured scarf and button details; a hybrid prop-wildlife silhouette placed singly near tree clusters; snowwoman variant wears a small brick-built bow accent on the top tier.

*Implementation: rendered like Village NPCs (Plan 02-13) using VoxelInstancer for non-interactive crowds; scope and exact implementation plan are deferred — these species are locked here so downstream plans can bind to them.*

## 8. Signature props

1. **Frozen log half-buried** — 1×4 log brick in brown-grey, horizontal, snow-plate layer on
   top; suggests a fallen tree under snowfall.
2. **Snowdrift mound** — 3-5 white and light-grey 2×4 and 1×2 bricks in an irregular rounded
   pile; frequently adjacent to spruce trunks.

## 9. Structures owned

**Snow village** (3-5 layout variants; white-and-light-blue brick with dark timber accents;
wandering builder NPCs, see §11). **Shared** (all biomes): dungeons and mineshafts per DOCS §2.

## 10. Ambient sound

Deferred to a later audio pass. Target feel: soft wind, occasional snow-creak underfoot,
no bird calls — a still winter afternoon in a high-altitude forest.

## 11. NPC skin variants

Snow village (D-09): fair to light-pink skin; thick white-and-light-blue parka with fur-trim
collar; navy wool trousers; dark-brown insulated boots; bright-cyan scarf accent. Carries a
small warm-amber lantern accessory during patrol — the key visual read against cold surroundings.
