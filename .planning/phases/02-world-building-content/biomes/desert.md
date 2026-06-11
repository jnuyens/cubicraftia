# Biome Brief: Desert

**ID:** `desert` | **Phase:** 02 | **Status:** pending — awaiting user approval

---

## 1. Identity

Vast sun-blasted dunes of sand and crumbling sandstone, broken only by cacti and occasional
ruin-fragments half-buried in drift. The horizon is harsh and vast. Lighting is dramatic — warm
amber at midday. Players feel exposed but thrilled: resources are scarce, but a desert village
makes exploration worthwhile. The palette is gold, tan, and vivid red-orange sky.

## 2. Whittaker classification

Temperature 0.4 → 1.0 (hot); Moisture −1.0 → −0.2 (very dry / arid).
`_classify`: `t > 0.4 and m < -0.2` → `DESERT`.

## 3. Ambient tint

**Hex:** `#FFCF70` — warm golden-amber that gives all shadows a sandy undertone. Anchored near
`#F5C30D` (brick yellow) shifted toward amber to read as bleaching desert heat.

## 4. Sun colour temperature

4 200 K — noticeably orange-warm (`#FFD580`). Bleaching midday sun in open desert.

## 5. Terrain palette

`sand` (surface) · `sandstone` (sub-surface) · `stone` (deep)

## 6. Signature flora (VoxelInstancer species)

1. `cactus_tall` — 4-6 cell columnar with two side-arms; solitary, sparse
2. `cactus_short` — 2-3 cell stubby variant; scattered between tall cacti
3. `dead_bush` — 1-cell dried twig; very high density, fills sandy gaps
4. `desert_grass_tuft` — 1-cell dried-grass clump; occasional ground cover

## 7. Atmospheric wildlife

1. **Desert mouse** — small scurrying brick-built critter with a rounded 1×1 body and short stud-peg ears; darts across open sand in short bursts then freezes flat against the ground.

*Implementation: rendered like Village NPCs (Plan 02-13) using VoxelInstancer for non-interactive crowds; scope and exact implementation plan are deferred — these species are locked here so downstream plans can bind to them.*

## 8. Signature props

1. **Ruined-wall fragment** — 3-5 sandstone bricks stacked in an irregular L-shape, eroded at
   the top; evokes an ancient structure buried by drift.
2. **Sand-drift mound** — low 3-brick-high oval pile of sand-tone 2×4 and 1×2 bricks; looks
   like a naturally formed dune crest.

## 9. Structures owned

**Desert village** (3-5 layout variants; sandstone-and-sand-yellow brick; wandering builder
NPCs, see §11). **Shared** (all biomes): dungeons and mineshafts per DOCS §2.

## 10. Ambient sound

Deferred to a later audio pass. Target feel: dry wind across sand, faint creak of sun-baked
stone, no animal calls — openness and heat of a mid-day desert.

## 11. NPC skin variants

Desert village (D-09): warm tan to medium-brown skin; lightweight sand-yellow and off-white
linen tunics; wrapped cloth head-covering in tan; terracotta-orange trim band accent; carries
a small clay water-jug accessory (1×1 round stud prop) during patrol.
