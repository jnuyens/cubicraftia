# Biome Brief: Savannah

**ID:** `savannah` | **Phase:** 02 | **Status:** pending — awaiting user approval

---

## 1. Identity

Wide sun-warmed grassland with scattered flat-topped acacia trees and a honey-coloured sky
that feels perpetually late afternoon. Big, open, sweeping vistas — terrain rises and falls in
long low waves. Neither as safe as grassland nor as hostile as desert. Finding a savannah
village is a social moment: a community clearly adapted to this warm dry place.

## 2. Whittaker classification

Temperature 0.0 → 0.4 (warm); Moisture −0.5 → 0.0 (dry to moderate).
`_classify`: `t > 0.0 and m < 0.0` → `SAVANNAH`.

## 3. Ambient tint

**Hex:** `#FFB84D` — deep warm amber-orange that gives shadows a golden-hour glow at all
times of day. Anchored near `#F5C30D` (brick yellow) pushed toward orange to distinguish
from desert heat (`#FFCF70`) and suggest dry-warm grassland.

## 4. Sun colour temperature

4 800 K — warm, sunset-adjacent even at midday (`#FFE4A0`). "Golden hour all day" feel of
open tropical grassland.

## 5. Terrain palette

`savannah_grass` (surface) · `dirt` (sub-surface) · `stone` (deep)

## 6. Signature flora (VoxelInstancer species)

1. `acacia_tree` — flat-top canopy (7-9 cells) on short angled trunk; the biome's signature
   silhouette; sparse, 1-2 per cluster
2. `acacia_small` — 3-5 cell scrubby acacia variant; fills gaps
3. `savannah_grass_tall` — 2-cell dry amber-tinted grass tufts; high density in open areas
4. `dry_shrub` — 1-cell rounded dried-leaf shrub in tan and brown; scattered
5. `termite_mound_small` — 2-3 cell earth-brown conical prop; see §7

## 7. Atmospheric wildlife

1. **Elephant** — large brick-built quadruped with a broad stud-plated body, wide ear plates in flat grey, and a segmented trunk built from stacked 1×1 round bricks; moves in family groups of 2-3 across open grassland.
2. **Giraffe** — tall stilt-legged brick figure with a long neck assembled from 1×2 plate stacks and a small rounded head with two stud-top horns; solitary or in pairs near acacia trees.
3. **Gnu (wildebeest)** — stocky brick-built quadruped with a dark grey-brown body, broad horned head, and a short mane of dark plate tiles; roams in loose herds of 3-6 across the open plains.

*Implementation: rendered like Village NPCs (Plan 02-13) using VoxelInstancer for non-interactive crowds; scope and exact implementation plan are deferred — these species are locked here so downstream plans can bind to them.*

## 8. Signature props

1. **Termite mound** — 2-3 cell tall conical cluster of earth-brown and tan 1×1 round bricks,
   irregular at the top; appears singly, away from trees.
2. **Acacia-root outcrop** — 3-4 flat tan-brown 2×2 bricks radiating from an acacia trunk
   base; reads as prominent surface roots baking in the sun.

## 9. Structures owned

**Savannah village** (3-5 layout variants; warm-tan and brown-brick with open-sided shelters
and covered market-stall roofs; wandering builder NPCs, see §11). **Shared** (all biomes):
dungeons and mineshafts per DOCS §2.

## 10. Ambient sound

Deferred to a later audio pass. Target feel: distant grassland wind, intermittent cicada hum,
a single far-off bird cry — the wide, unhurried atmosphere of open tropical grassland at
golden hour.

## 11. NPC skin variants

Savannah village (D-09): medium-dark to dark-brown skin; sleeveless orange-brown leather wrap
torso with single shoulder strap; tan short-wrap legs; flat sandal foot pieces; terracotta-red
arm-band accent. Carries a short decorative spear prop (1×1 bar brick, upright) during patrol
— no weapon function in v1.
