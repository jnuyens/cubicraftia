# Phase 2 Biome Briefs — Index

**Phase:** 02-world-building-content | **Plan:** 01
**Created:** 2026-05-26 | **Deliverable:** CONTEXT.md D-06

---

## Purpose

This index links the six per-biome design briefs that CONTEXT.md D-06 requires Claude to
author during plan-phase, before any content-generation code lands. Per D-06:

> "The approved brief becomes a canonical-refs entry consumed by structure-generation and
> content-population plans."

Each brief locks the design knobs that the following downstream plans read as canonical input:
- **Plan 06** — biome compositor (reads: ambient tint, terrain palette, flora species list,
  Whittaker classification windows)
- **Plan 07** — structure templates (reads: structures owned, NPC skin variants)
- **Plan 08** — mineshafts & dungeons (reads: structures owned — shared entries)
- **Plan 13** — wandering NPCs (reads: NPC skin variants, village biomes)

No downstream plan in the above set may begin until this index shows all six rows as
"approved".

---

## Biome Briefs

| Biome ID           | File                    | Structures Owned                            | Status                           |
|--------------------|-------------------------|---------------------------------------------|----------------------------------|
| grassland_forest   | [grassland_forest.md](biomes/grassland_forest.md) | dungeons (shared), mineshafts (shared) | approved 2026-05-26 (revision 1) |
| desert             | [desert.md](biomes/desert.md)             | desert village; dungeons (shared), mineshafts (shared) | approved 2026-05-26 (revision 1) |
| snow               | [snow.md](biomes/snow.md)                | snow village; dungeons (shared), mineshafts (shared) | approved 2026-05-26 (revision 1) |
| jungle             | [jungle.md](biomes/jungle.md)             | jungle temple; dungeons (shared), mineshafts (shared) | approved 2026-05-26 (revision 1) |
| savannah           | [savannah.md](biomes/savannah.md)         | savannah village; dungeons (shared), mineshafts (shared) | approved 2026-05-26 (revision 1) |
| ocean              | [ocean.md](biomes/ocean.md)              | shipwrecks, underwater temples; dungeons (shared), mineshafts (shared) | approved 2026-05-26 (revision 1) |

---

## Approval Status Summary

| Biome            | Approved By           | Date       | Notes                                    |
|------------------|-----------------------|------------|------------------------------------------|
| grassland_forest | jnuyens@gmail.com     | 2026-05-26 | Approved revision 1 (atmospheric wildlife) |
| desert           | jnuyens@gmail.com     | 2026-05-26 | Approved revision 1 (atmospheric wildlife) |
| snow             | jnuyens@gmail.com     | 2026-05-26 | Approved revision 1 (atmospheric wildlife) |
| jungle           | jnuyens@gmail.com     | 2026-05-26 | Approved revision 1 (atmospheric wildlife) |
| savannah         | jnuyens@gmail.com     | 2026-05-26 | Approved revision 1 (atmospheric wildlife) |
| ocean            | jnuyens@gmail.com     | 2026-05-26 | Approved revision 1 (atmospheric wildlife) |

**Approved 2026-05-26 (revision 1)** — User approved all six briefs after atmospheric wildlife revision. Wildlife added per user request: pandas (grassland_forest), desert mouse (desert), reindeer + snowmen/snowwomen (snow), monkeys + toucans (jungle), elephants + giraffes + gnu (savannah), manta rays + orcas + schools of fish + jellyfish + kelp (ocean, kelp under flora). Plans 06/07/08/13 may now bind to the species lists in `biomes/*.md`.

---

## Sign-off Log

| Date       | Approver              | Action                                        |
|------------|-----------------------|-----------------------------------------------|
| 2026-05-26 | jnuyens@gmail.com     | Approved all six briefs (revision 1) — atmospheric wildlife revision accepted. Plans 06/07/08/13 unblocked. |

---

## How to Review

1. Read each brief linked in the table above.
2. For each brief, check:
   - **Identity** paragraph: does the player-emotional read feel right?
   - **Ambient tint** hex: paste into a colour picker — does it feel "in the splash north-star
     band" (saturated, cheerful, biome-appropriate)?
   - **Signature flora** list: 3-6 species; are they appropriate and right-sized?
   - **Signature props**: would you want to find these while exploring?
   - **NPC skin variants** (desert, snow, savannah only): do the three village biomes feel
     clearly distinct from each other?
3. Reply "approved" to lock all six and unblock Plans 06/07/08/13, OR list the briefs
   that need revision with one-line change requests per brief.
