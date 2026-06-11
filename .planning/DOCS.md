# Cubicraftia

> A 3D brick-and-block multiplayer sandbox where you build, explore, and survive — alone or with 2-4 friends — on every device you own.

<!-- DDD-SPEC: this document is the canonical spec for Cubicraftia.
     Each phase in ROADMAP.md implements one or more sections below.
     When implementation diverges, update this document and re-validate.
     Engineering and protocol detail lives in docs/dev/ — not here. -->

**Status:** v1 spec, draft 3 (2026-05-26 — Phase 2 doc-sync).
**Name:** Cubicraftia — final name, subject to a trademark clearance check before public release.
**License:** GPL-3.0-or-later — all derivatives must remain open source.
**Pricing:** €1 / $1 one-time purchase. Free redemption codes available for family and friends, distributed by the project owner.
**In-game purchases:** Additional brick packs can be purchased in-game (cosmetic / functional bricks beyond the v1 base set). Every brick needed to play a complete survival or sandbox game is in the base set; IAP packs add expression, not progression.
**Trademark notice:** Cubicraftia is not affiliated with, sponsored by, or endorsed by the LEGO Group or Mojang Studios.

---

## 0. What Cubicraftia is

Cubicraftia is an open-source 3D game. You spawn into a procedurally generated infinite world made of cube-shaped terrain — grass, dirt, stone, sand, water, wood — and you build inside it using **bricks**: small construction pieces in many shapes (rectangular bricks, plates, slopes, tiles, wheels, accessories) that snap onto each other's **studs**. Your character is a **builder**: a small posable figure you customise from head, body, legs, and accessories.

You can play alone, or your friends can join the same session over the internet. Up to four people share one world. Sessions are friends-only — you don't meet strangers in Cubicraftia.

The world supports two play styles, freely switchable per session:

- **Sandbox (creative).** Every brick available, no danger, fly mode, just build.
- **Survival.** Gather pieces by mining the world or defeating creatures, craft tools and weapons, survive the night, build shelter, expand.

It runs on Mac, Windows, Linux, iOS, and Android, with full cross-play. It is a one-time €1/$1 purchase (with free codes available from the project owner for family and friends), free of advertising, and the source is public on day one. Optional brick packs can be bought in-game — the base set is sufficient to play the whole game without ever opening the shop.

**Who it's for.** Friend groups (kids, teens, adults) who want a Minecraft-shaped game where building is expressive — with the variety of real construction pieces — and where they can drop into each other's worlds with one tap.

**What this section locks for downstream phases:**
- Game name: **Cubicraftia** (final)
- License: GPL-3.0-or-later
- Pricing: €1 / $1 one-time purchase. Free redemption codes available for family and friends.
- IAP: optional brick packs only. Never gates gameplay progression. Never gates survival viability.
- Player-facing terminology: **brick** (the pieces), **stud** (the bumps that snap), **builder** (the player character / NPC figures)
- Five supported platforms: macOS, Windows, Linux, iOS, Android
- Crossplay: yes, all platforms can join the same session
- "Friends-only" social model (no open lobbies)

---

## 1. First five minutes

**Status: IMPLEMENTED** — Phase 6 Plans 06-01 through 06-11 (2026-05-30).

The first five minutes determine whether someone plays a second session. This section is the contract for the onboarding experience.

### 1.1 First launch

1. **Title screen** (`src/ui/title_scene.gd` + `title_scene.tscn`): 2-second logo fade-in, UV-scrolling brick-pattern background shader, three buttons: *Sign in*, *Create account*, *Settings*. Deep-link detection runs at startup via `DeepLinkHandler` autoload — if a `cubicraftia://` URI or `--invite=TOKEN` CLI argument is present, the joiner flow is entered immediately (§1.3).

2. **Create account** is one screen (`src/ui/sign_in_panel.gd`): email, password, and an "I'm 13 or older" self-declaration checkbox. No phone number, no email verification gate (a verification link is sent in the background via Supabase GoTrue; play continues). Under-13 accounts are routed to the parental consent flow (§8.4) before online features unlock.

3. **Avatar creation** (`src/ui/avatar_creator.gd`, `CanvasLayer` layer 10) appears immediately after account creation:
   - One of **8 preset builders** (one tap → done), **or**
   - Customises: skin tone (5 swatches), head shape (3: square, round, tall), face expression (5: neutral, happy, cool, surprised, sleepy), body colour (10 swatches), body accessory (none, backpack, cape), leg colour (10 swatches), leg shoes (none, boots, sneakers), hand accessory (none, pickaxe, lantern, flower, blank).
   - A **Randomise** button generates a valid random config.
   - A 3D `SubViewport` preview at 256×256 px rotates the builder at 0.4 rad/s while the player adjusts parts.
   - **Done** writes `user://avatar.cfg` and calls `FriendsClient.save_avatar()` (Supabase `profiles.avatar_json`).
   - The config uses 8 keys: `skin_colour_index` (0–4), `head_shape`, `face_expression`, `body_colour_index` (0–9), `body_accessory`, `leg_colour_index` (0–9), `leg_shoes`, `hand_accessory`.

4. **World select screen** (`src/ui/world_select_screen.gd`): up to 5 worlds displayed as cards with 256×144 px thumbnails (stored at `user://worlds/{id}/thumbnail.png`, displayed at 128×72 px). Two action areas: *New world* (default highlight) and *Join with invite link*. *New world* opens the new-world modal: world name (profanity-guarded via `ProfanityFilter.filter_reject()`), seed, and mode (sandbox/survival) badge selector.

> **Phase 6 placeholder art note:** Preset thumbnail artwork ships as 8 placeholder PNG stubs in Phase 6; final hand-crafted artwork is post-v1. The builder mesh is programmatic `BoxMesh` sub-parts in Phase 6; a sculpted mesh is Phase 999.1. The title background ships as placeholder `title_bg.png`; artist replacement is post-v1. Title music ships as silence; `title_theme.ogg` will be added when available.

### 1.2 Spawning into a new world

When the player enters a new world in survival mode for the first time:

1. The world generates and the camera fades in from black to the spawn point: a small grass clearing, daytime, a wooden chest sitting on the ground next to a single placed builder-bed.

2. The **FTUE overlay** (`src/ui/ftue_overlay.gd`, `CanvasLayer` layer=20, `MOUSE_FILTER_IGNORE` on all background controls) activates. It is a **4-step unskippable** walkthrough — no close or dismiss affordance exists anywhere in the scene (enforced by `grep -ic "skip" src/ui/ftue_overlay.gd` returning 0; T-06-FTUE1 mitigation).

   **Step 1 — Open the chest:** Narration strip (bottom-third, navy #1B2C56 at 0.92 alpha, rounded corners, brick-white text) shows the step 1 narration. Accent-yellow bouncing arrow points toward the starter chest. A progress bar (accent-yellow fill) at the top shows 1/4. Signal gate: `ChestEntity.opened`.

   **Step 2 — Mine the tree:** Narration updates. Arrow defers to scan for the nearest `wood_log` voxel within a 20-cell radius via `call_deferred` (T-06-FTUE2 one-shot scan mitigation). Signal gate: `Inventory.item_added(builder_id, "wood_log", count)`.

   **Step 3 — Place a wooden plank:** Narration updates. The `wood_plank` tile in the brick palette is highlighted via `BrickPaletteUI._set_ftue_highlight()` (looping accent-yellow alpha tween). Signal gate: `StudGrid.placed(anchor_cell, definition, colour_index, rotation)` where `definition.brick_id == "wood_plank"`.

   **Step 4 — Completion:** Narration fades in: **"That's it. The world is yours."** Progress bar shows 4/4. Persistence: `WorldSave.set_world_meta("ftue_complete", var_to_bytes(true))`. Telemetry event `ftue_complete` logged. After 3 seconds the overlay fades out and is freed.

3. After each step advance: `WorldSave.set_world_meta("ftue_step_N_complete", true)` and `OnboardingTelemetry.log(FTUE_STEP_N_COMPLETE)` are called.

4. A **night hint** (`ui.ftue.night_hint`) fades in non-blockingly if `WorldClock.current_phase == DUSK` while any step is still active. It does **not** gate step 4 completion.

5. The builder-bed remains beside the chest; the player can sleep through the first night by walking up to it and holding Shift (desktop) or pressing the contextual button (mobile).

The FTUE runs only in survival mode (`Features.is_survival_mode() == true`) and only when `WorldSave.get_world_meta("ftue_complete")` is null (first launch). On subsequent world opens, `main_scene._maybe_start_ftue()` detects the flag and never instantiates the overlay.

### 1.3 First launch via invite link

If the player reaches the game via an invite link (`cubicraftia://invite?token=TOKEN` Universal/App Link on mobile, or `--invite=TOKEN` CLI argument parsed by `DeepLinkHandler` on desktop), the FTUE walkthrough above is **skipped entirely**. The pending `ftue_complete` marker is written before world load so `main_scene._maybe_start_ftue()` does not instantiate the overlay.

The joiner appears directly in the host's session, next to the host, with a single-line tip from locale key `ui.deeplink.joiner_tip`: **"This is [Friend]'s world. They have what you need to get started."** A mutual friendship is created on link redemption.

Invite tokens are 26-character base32 strings (128-bit entropy), single-use, 24-hour TTL, enforced by the `redeemed_by` column RLS policy on the Supabase `invites` table (§6.9).

### 1.4 What this section locks

- Account is **email + password + age-13 self-declaration only**. No third-party OAuth in v1.
- Avatar customisation has exactly these 8 config slots: `skin_colour_index` (0–4), `head_shape` (square/round/tall), `face_expression` (5 values), `body_colour_index` (0–9), `body_accessory` (none/backpack/cape), `leg_colour_index` (0–9), `leg_shoes` (none/boots/sneakers), `hand_accessory` (none/pickaxe/lantern/flower/blank).
- **8 presets** with diverse skin tone coverage (all 5 skin tones appear; at least 3 distinct `skin_colour_index` values).
- Tutorial is **in-world and embedded** — no separate tutorial scene.
- Tutorial is **UNSKIPPABLE** (4 steps, no dismiss affordance; T-06-FTUE1 grep gate verified).
- Invite-link joiners skip the tutorial; FTUE flag written before world load.
- World select: **5-world cap** with thumbnails; new-world modal with profanity-guarded name, seed, and mode.
- Localisation in v1: English and Dutch (both `locale/en.po` and `locale/nl.po` complete with 478 msgids).

---

## 2. The world

The world Cubicraftia generates is procedural and infinite. It uses two grids at once, both visible to the player but with different feels.

### 2.1 The terrain grid (1 metre cubes)

Terrain — grass, dirt, stone, sand, water, ice, wood, leaves — exists on a coarse cube grid: every cell is a one-metre cube. This is the layer that looks and feels like Minecraft. You can mine through it, walk on top of it, and place terrain cubes from your inventory back into the world.

In **v1 the world has multiple biomes**, generated procedurally with smooth transitions: temperate grasslands and forest (the default spawn biome), desert (with sand, cacti, occasional desert villages), snow (with ice, snow-covered terrain, snow villages), jungle (dense foliage, jungle temples), savannah (open plains, savannah villages), and ocean (with abandoned shipwrecks on the seabed and underwater temples). (In practice this means a narrow ~5 m blend on terrain colour and ambient lighting, plus a sudden flora-species change at the biome boundary — biomes have distinct identities and you can feel when you cross from one to another.)

**Generated structures in v1**: desert villages, snow villages, savannah villages, jungle temples, abandoned ships (surface or partially submerged), underwater temples, underground chambers where monsters spawn, and mineshafts running through deeper stone layers. Each structure type contains its own loot tables and creature spawns.

**Inhabitants.** Villages in v1 are inhabited by wandering builder NPCs. They patrol pre-set paths inside the village footprint with no dialog, no trading, and no combat — they exist purely to make villages feel alive. Their visual skin variants are biome-appropriate (desert / snow / savannah). See §5 "Peaceful NPCs" for the distinction from hostile creatures.

**Atmospheric wildlife.** Each biome hosts locked atmosphere-only wildlife species, rendered as non-interactive crowd figures (VoxelInstancer). They are purely decorative — no combat, no inventory, no drops. Species per biome:

- **Grassland & Forest:** panda bear
- **Desert:** desert mouse
- **Snow:** reindeer; snowman/snowwoman (hybrid prop+wildlife silhouette)
- **Jungle:** monkey; toucan
- **Savannah:** elephant; giraffe; gnu (wildebeest)
- **Ocean:** manta ray; orca; school of fish; jellyfish

*(Implementation details — exact mesh authoring, VoxelInstancer integration, spawn density — are deferred to a later content pass. The species list above is locked so downstream plans can bind to it.)*

### 2.2 The stud grid (placed bricks)

Built bricks — every construction piece in your inventory other than terrain cubes — exist on a much finer grid anchored to the terrain. Studs sit on top of terrain cubes and on top of each other; bricks snap to studs in 90° rotation steps. This is the layer that makes Cubicraftia look and feel like real construction pieces.

In practice, the player doesn't think about two grids. They think: *terrain is the ground I walk on; bricks are what I build*. The two grids exist so that the world can be both Minecraft-vast and brick-detailed.

### 2.3 Day and night

A full day-night cycle takes about 15 real minutes: ~10 minutes of daylight, ~5 minutes of darkness. The day-night cycle is referred to in-game as a **Cubicraftia day**.

At night, hostile creatures spawn in dark areas: the world's caves, the shadows beneath dense foliage, and anywhere far from a lit source. **During the day, hostile creatures also spawn — but rarely** — in the very darkest places: deep dungeons, underground mineshafts, and dense forest interiors far from any light source.

Light sources include the sun, the moon (dim), lanterns, torches, fire, and lit blocks (placed lava, glow stones). A lit area suppresses creature spawning.

### 2.4 Weather

In v1.0 the weather is either **clear sun** or **rain** — switching naturally over Cubicraftia days. Rain visually darkens the sky a little, adds rain particles, and slightly reduces visibility. It does not damage builders or extinguish torches in v1.

**The rain dance**: any builder can perform a rain dance from the *Actions* menu (long-press in air on mobile, or press R on desktop) — this triggers rain to begin shortly after. **Each builder may perform the rain dance at most once per Cubicraftia day**; further attempts that day return a friendly "the sky won't listen again today" message.

Snow, thunderstorms, lightning, and weather damage are not in v1.

### 2.5 What this section locks

- Two-grid world: terrain (1 m cubes) + bricks (stud-snapped)
- Multiple biomes in v1: grasslands+forest, desert, snow, jungle, savannah, ocean
- Biome transitions: ~5 m terrain-colour/ambient-light blend + sudden flora change at boundary
- Generated structures in v1: 4 village types, jungle temples, shipwrecks, underwater temples, dungeons, mineshafts
- Village inhabitants: wandering builder NPCs with biome-appropriate skin variants (desert / snow / savannah); no dialog, no trading, no combat
- Atmospheric wildlife per biome: locked species list as above; atmosphere-only (no combat, no drops)
- Day-night cycle ~15 min total ("Cubicraftia day"): 10 day, 5 night
- Rare daytime hostile spawns in deep darkness
- Weather in v1: clear sun + rain
- Rain dance: max 1 per Cubicraftia day per builder
- Light-driven creature spawning

---

## 3. Building

Building is Cubicraftia's identity. This section is the longest because it must be the most precise.

### 3.1 The brick library (v1 set)

The v1 brick library contains **50 distinct brick types**, grouped below. The set covers every common construction idea plus the material variants that the survival loop needs (wood, stone, copper, iron, diamond, and ore-block forms).

| Category | Bricks (~count) |
|---|---|
| Rectangular bricks | 1×1, 1×2, 1×3, 1×4, 2×2, 2×3, 2×4 (7) |
| Plates (thin) | 1×1, 1×2, 1×4, 2×2, 2×4 (5) |
| Slopes | 1×1×1 (45°), 1×2×1, 1×2×2, 2×2 corner slope (4) |
| Tiles (smooth, no studs on top) | 1×1, 1×2, 2×2 (3) |
| Round | 1×1 round brick, 2×2 round brick, 1×1 round plate, 1×1 cylinder (4) |
| Functional | Wheel, door (1×4), window (1×2), trapdoor (2×2), workbench, chest (regular) (6) |
| Decorative | Flower, lantern, torch, ladder, sign (5) |
| Materials & ores (terrain-style blocks) | Wood log, wood plank, stone, cobblestone, copper ore, iron ore, diamond ore, sand, glass (9) |
| Special chests & keys | Bronze chest, silver chest, gold chest, diamond chest (4 — see §4.4); 4 key types (see §4.4) — *keys are items not bricks, but appear here for traceability* |
| Accessories (held / worn) | Pickaxe, shovel, sword, dynamite, lantern (handheld) (5) |
| Mob-drop bricks | Bone (drops from skeletons), slime cube (drops from cube slime) (2) |

The final list of 50 brick types is **locked as of Phase 2**: 7 rectangular bricks, 5 plates, 4 slopes, 3 tiles, 4 round, 6 functional, 5 decorative, 9 materials & ores, 5 accessories, 2 mob-drops — total 50. The complete ordered list is maintained in `src/bricks/manifest.json`. (Note: fence post was deferred to a future IAP brick pack; chest_regular appears in the Functional category per the locked manifest.) **IAP brick packs add to (never gate) this base set.**

Every brick comes in a **palette of 18 colours**: white, light grey, dark grey, black, red, orange, yellow, lime, green, dark green, cyan, light blue, blue, purple, pink, brown, tan, sand-yellow. Identical bricks in different colours stack separately in the inventory. Material bricks (wood, stone, ores) have their natural colour and are not colour-swappable.

**IAP brick packs** (post-launch addition, not blocking v1.0): themed brick packs (e.g., "Castle pack", "Space pack") add additional brick types and colours. The base 50 listed above are sufficient for every survival or sandbox playthrough.

### 3.2 Placing a brick

Placement is point-and-click, no drag preview.

1. Open the inventory.
2. Drag the brick onto a hotbar slot. Selecting it as the active hotbar slot equips it in the builder's hand.
3. A small **crosshair** sits in the centre of the screen at all times. Point the crosshair at the position you want the brick to attach to — the surface of an existing brick, a stud, or a terrain cube. The crosshair direction is derived from the active camera, so placement works identically in both camera modes (see below).
4. Left-click (desktop) or tap *Place* (mobile) to place. The brick attaches to the nearest valid stud or terrain face under the crosshair.

**Camera modes.** The builder has two camera modes:

- **First-person (FPV):** eye-height perspective; the builder's hand is not visible.
- **Third-person chase camera (default):** SpringArm3D-based smooth follow behind and above the builder.

The default mode for a fresh world is **chase**. On desktop, the player toggles between modes with **V**. On mobile, the toggle is available via the palette UI overlay button (the exact mobile binding ships in Plan 02-12's palette gesture work). Mouse-wheel up/down adjusts the chase-camera arm length between 2.0 m and 8.0 m in 0.5 m steps; the wheel is a no-op in FPV mode.

**No rotation in v1.** Every brick has a single canonical orientation. To "rotate" a placement, the builder moves to a different position relative to the target — the placement automatically orients away from the builder.

**Bricks can float.** If you stack two bricks on top of each other and then break the bottom one, the top brick remains floating in the air. There is no gravity on placed bricks in v1 (this is part of the building expression — castles, floating islands, archways all rely on this).

A brick **can be placed if**: there is a valid attachment surface under the crosshair (an existing brick, a stud, or terrain) and the placement does not overlap a builder or creature. Otherwise the action is rejected with a small "can't place there" indication.

### 3.3 Breaking a brick

Bricks can be broken bare-handed (slow), with a pickaxe (faster), or destroyed in a small area with dynamite. A broken brick drops as a small, glowing, floating version of itself (see §4.3).

Broken brick = lost brick: it disappears from the world and re-enters the world as an item to pick up.

### 3.4 Tools

| Tool | Effect |
|---|---|
| Pickaxe | Faster brick/stone/ore breaking. Different tier pickaxes (wood, stone, iron, diamond) needed for higher-tier ores |
| Shovel | Faster terrain breaking on dirt, sand, snow |
| Dynamite | Place, light fuse, ~4 s timer, **~5 m radius destruction**. All bricks/cubes in radius drop as pickupable items |
| Lantern (handheld) | Hand-held light source (does not light placed blocks; only the builder) |

Tools wear out in survival mode (durability bar). In sandbox mode tools never wear out.

### 3.5 The brick palette UI

On desktop: a sidebar with a search field at the top, category tabs, and a colour swatch row. Hover a brick → preview. Click → equip.

On mobile: a bottom sheet that slides up when the player taps the *Build* button. Same content reorganised vertically: search field, category tabs, scrollable brick grid, colour swatch row, currently-selected brick at the top. The sheet covers about 50% of the screen — the world above remains visible so the player sees their placement context.

### 3.6 What this section locks

- v1 brick library: **50 brick types** across the categories in §3.1 (locked as of Phase 2 — see `src/bricks/manifest.json`)
- 18-colour palette for non-material bricks
- Material/ore bricks (wood, stone, copper, iron, diamond, etc.) have natural colours
- Placement: point-and-click, **no rotation in v1**
- Camera modes: FPV and third-person chase (default chase); V-key desktop toggle; mobile toggle via palette UI overlay; chase arm 2.0–8.0 m via scroll-wheel (no-op in FPV)
- Bricks can float — there is no gravity on placed bricks
- Tools: pickaxe (tiered), shovel, dynamite, lantern (v1 set)
- Dynamite radius: **~5 metres**
- Palette UI patterns: sidebar (desktop) + bottom-sheet (mobile)
- IAP brick packs add to (not gate) the base set

---

## 4. Inventory, items, and crafting

### 4.1 Inventory layout

The inventory is a **6 columns × 8 rows grid** = 48 slots. Each slot holds up to **64 of the same brick or item**. Identical items stack automatically when you pick them up; different items occupy different slots.

The **hotbar** is the bottom row of 8 slots, always visible during play. Number keys 1-8 (desktop) or a tap (mobile) select the active hotbar slot.

Drag-and-drop moves stacks between slots. Holding shift while dragging splits a stack in half. Right-click (desktop) or long-press (mobile) takes one item from a stack.

### 4.2 Equipped items

Whatever's in the active hotbar slot is what the builder holds. If the hotbar slot is empty the builder's hands are empty (a fist for breaking; nothing for placing).

### 4.3 Dropped items in the world

When a brick is broken, dynamite is detonated, or a creature is defeated, the resulting items appear in the world as **small floating versions of themselves with a soft glow**. The glow is light-emitting — visible in the dark, useful at night.

- An item floats and bobs gently above the ground or wherever it spawned.
- Walking within ~1 metre auto-picks it up; touching it directly also works.
- An unpicked item **despawns after 2 Cubicraftia days** (~30 real minutes).
- If the inventory is full when the player tries to pick up an item, the item stays in the world and a "Inventory full" tip appears for a few seconds.

### 4.4 Chests and keys

There are **5 chest types** in v1, each with progressively higher capacity and protection:

| Chest type | Slots | Lock | Where found / how to obtain |
|---|---|---|---|
| **Regular chest** | 6×8 (48) | No key needed | Crafted from wood; the starter chest at spawn is a regular chest |
| **Bronze chest** | 6×8 (48) | Bronze key | Found in mineshafts, savannah villages; crafted from copper + iron |
| **Silver chest** | 6×9 (54) | Silver key | Found in jungle temples, shipwrecks; crafted from iron + silver |
| **Gold chest** | 6×10 (60) | Gold key | Found in underwater temples, dungeons; crafted from gold |
| **Diamond chest** | 6×12 (72) | Diamond key | Rare loot; crafted from diamond — the safest, biggest storage in the game |

**4 key types** correspond to the 4 locked chest types. A key is consumed on first use to unlock a chest; once unlocked, the chest stays unlocked for the world's lifetime, and can be opened freely by any builder with session access. Keys are stored in the inventory like any item.

Chests can be **combined into double chests** by placing two of the same type immediately adjacent: a double chest has double the slot count of a single chest (e.g., double regular chest = 12×8 = 96 slots). Breaking either half splits the double chest back into two singles.

Anyone with access to the session can open any unlocked chest. Locked chests require either the appropriate key (consumed once) or the chest having been unlocked previously in the world.

### 4.5 Crafting

Crafting combines items into new items. There are two crafting surfaces:

- **2×2 inline crafting**: a small 2×2 grid in the inventory screen. Used for basic recipes (wooden planks, sticks, simple items).
- **Workbench (3×3)**: a placeable workbench in the world. Walk up and open to access a 3×3 crafting grid. Required for advanced recipes (tools, dynamite, doors, complex bricks).

v1 includes about **10 recipes**: planks-from-wood, sticks-from-planks, pickaxe, shovel, sword, dynamite, lantern, torch, ladder, chest. Exact recipes are listed in the crafting documentation.

### 4.6 What this section locks

- Inventory: 6×8 = 48 slots, max 64 per stack
- Hotbar: bottom 8 slots, keys 1-8
- Dropped items: small + floating + soft glow, despawn after **2 Cubicraftia days (~30 min)**, ~1 m auto-pickup
- **5 chest types** (regular, bronze, silver, gold, diamond) with **4 key types**
- **Double chests** in v1 (any two adjacent of the same type combine)
- Crafting: 2×2 inline + 3×3 workbench, ~10 v1 recipes

---

## 5. Survival, creatures, and death

### 5.1 The two modes

A session has a single mode selected when the world is created: **sandbox** or **survival**. Mode is persistent for the world — it cannot be changed after creation in v1 (this restriction lifts in v1.1).

**Sandbox**:
- Every brick available unlimited from the palette
- No HP, no damage, no hunger
- Fly mode toggle (double-tap jump)
- Creatures don't spawn (peaceful)
- Tools don't wear out
- No day-night threat — day-night cycle still happens for atmosphere

**Survival**:
- Inventory starts empty (except the starter chest gift)
- HP (10 hearts), damage, death loop (§5.4)
- Hunger is **not in v1** — added in v1.1
- Creatures spawn at night and in dark spots (§5.3)
- Tools wear out
- Resources must be gathered by mining, looting, defeating creatures

### 5.2 The creature roster (v1)

Five hostile creatures in v1:

| Creature | Behaviour | HP | Drops |
|---|---|---|---|
| **Laser penguin** | Waddles toward the builder; eyes glow then fire a short-range laser beam (~3 m). 4 HP. Spawns in snow biome day and night. | 4 | 1-2 bone bricks, occasional ice fragments |
| **Ghost** | Floats through bricks and terrain — cannot be blocked by walls. Slow but persistent. Visible only in dim/dark light. 3 HP. Spawns in dungeons, jungle temples, abandoned ships. | 3 | 1 ghost fragment (rare crafting material) |
| **Vampire** | Flies, attacks by diving. **Transforms into a bat** under threat (low HP) — bat form is faster and harder to hit. Active only at night. 5 HP (vampire) / 2 HP (bat). | 5 / 2 | 1-2 bone bricks, 1 fang (rare) |
| **Bat (regular)** | Small, flies erratically, attacks by swooping. Spawns in dungeons, mineshafts, dense forest at night. 1 HP. | 1 | 1 bone brick (occasional) |
| **Cube slime** | Slow, hostile, ground-bound. When defeated, **splits into smaller cube slimes** (each smaller cube must also be defeated). Three size tiers: large → medium → small. Spawns in jungles and underground chambers. | 6 / 3 / 1 | Each tier drops 1-2 slime cubes |

**Explosive "creeper-style" creatures are not in v1** — the player-side explosive role is filled by dynamite.

### Peaceful NPCs

Villages in desert / snow / savannah biomes are inhabited by wandering builder NPCs (see §2). These are distinct from the hostile creatures listed above — they never attack, never drop loot, and exist for atmosphere. They do not spawn at night and are not affected by the §5.3 spawning rules. Atmospheric wildlife (panda, desert mouse, reindeer, etc. — see §2) follows the same peaceful classification.

### 5.3 Spawning rules

- Hostile creatures spawn in light level below a threshold (roughly: less than the light produced by a single torch).
- Spawning is suppressed within 8 metres of any sleeping builder-bed.
- Maximum ~10 active hostile creatures per chunk in the area around active players.

### 5.4 Death and respawn

When a builder's HP reaches zero:

1. Their entire inventory drops as floating items at the death location (same visual as §4.3).
2. The screen fades to dark.
3. After ~3 seconds, the builder respawns at the last builder-bed they slept in, or at the world spawn point if no bed has been slept in.
4. The dropped inventory remains in the world for the standard 10-minute despawn timer. The player can return to collect it.

If the death was caused by an environmental drop into a void (deep water, fall damage to lethal floor), the items drop at the surface above for retrievability.

### 5.5 Sleeping

Right-click (desktop) or tap (mobile) a placed builder-bed at night to sleep. If all builders currently in the session sleep simultaneously, night fast-forwards to dawn. If not everyone sleeps, the bed simply sets the sleeper's respawn point for the next death.

### 5.6 The first night

Because every survival world starts with the **starter chest + builder-bed at spawn**, the first night is always survivable: open the chest, take the lantern, light a few squares, walk to the bed, sleep.

### 5.7 What this section locks

- Mode chosen at world creation; not changeable in v1
- Creative-mode toggle ("sandbox") lives alongside survival
- **5 hostile creatures** in v1 (laser penguin, ghost, vampire, bat, cube slime), no creeper-explode
- Cube slime splits into 3 size tiers when defeated
- Vampire transforms to bat under threat
- 10-heart HP, no hunger in v1
- Death drops inventory + respawn at bed/spawn
- Starter chest + bed at survival world spawn

---

## 6. Playing with friends

### 6.1 Friends

A **friend** is another player you've added (or who's added you and you accepted). Friendship is mutual. You see your friends' online status and which world they're in (if it's open to you).

Friends can be added by:

- Searching by exact username (returns one builder if found).
- Accepting an invite-link (§6.3).
- Accepting an in-app request from another builder.

Unfriending is a single tap and immediate. There is no "request rejected" notification — the other side simply doesn't appear as a friend.

### 6.2 Blocking

Blocking is stronger than unfriending: it removes the other party from your friends list, prevents them from finding you or sending requests, and prevents them from joining any session you host. Blocking is mutual: neither side sees the other. Blocking is instant and persistent across sessions.

### 6.3 Invite links

The host (the player who started the session) can generate an **invite link**:

- Tap *Invite* in the pause menu → copy link to clipboard, or share via the OS share sheet.
- The link is single-use and expires 24 hours after creation.
- Anyone who opens the link is taken to the join flow. If they don't have an account, they create one (§1.1); if they do, they sign in.
- On accepting the link, the joiner and the host **automatically become mutual friends**. This stays until either side unfriends.

If the joiner is on a phone, the link opens the app directly via Universal Links (iOS) or App Links (Android).

### 6.4 Sessions

A **session** is one running world. The host is the player whose machine is authoritative — their game state is the truth. Sessions support **1 to 4 players**. Solo play is simply a session with one player.

When the second player joins:
- The host's session is published to the discovery server with a join code.
- Other friends in the host's friends list see the session as "Open — [host] is playing [world name]" in their friends list.
- One-tap join from the friends list takes them directly in.

**Mid-session join is seamless** — joining player appears next to the host, no world-restart, no wait beyond the connection handshake.

### 6.5 Host concept and seamless host failover

The host's machine carries the canonical world state. **The host needs decent internet** — when the session has multiple players, the host machine is also relaying state to the peers.

**Seamless host failover (v1.0)**. If the host disconnects mid-session, the remaining player with the **best measured connection** automatically becomes the new host. The session does not end. Players see a brief 2-4 second handover screen ("Switching host — keeping the world…") while:

1. The new host promotes its most recent local snapshot to authoritative state.
2. Peers reconnect to the new host via WebRTC.
3. The discovery server updates the session's host pointer.
4. The original host's last save is reconciled if they ever return (latest-snapshot wins).

If only one player remains when the host disconnects, that player becomes the new host of a session of 1 — survival/sandbox play continues uninterrupted. World ownership stays with the original creator regardless of who hosted last; the world file syncs back to the creator's device when they next host.

The 2-4 second handover budget is a v1 promise — *seamless* means "session continues" rather than "imperceptible".

### 6.6 Chat

Text chat is available in-session, world-wide (everyone in the session sees every message). Open with **Enter** (desktop) or a *Chat* button (mobile). A profanity filter is applied — messages flagged are replaced with `[filtered]` for everyone but the sender.

Voice chat is **not in v1** (§9).

### 6.7 Host admin tools

The host has these powers, accessible from the pause menu's *Players* tab:

- **Kick**: removes a player from the session. They can rejoin if invited again.
- **Freeze build**: prevents a specific player from placing or breaking bricks for the remainder of the session. Undoable.
- **Roll back**: restores the world to a recent automatic snapshot (~30 min ago). Affects everyone. Confirmation required.

### 6.8 Player nameplates

Above each builder, a small nameplate shows the builder's username, in their builder's primary colour. Nameplates fade with distance. Toggleable in settings.

### 6.8.5 World save format (informational)

Cubicraftia stores worlds in a per-world directory on the host's device, containing SQLite files for terrain chunks and world metadata. Per-chunk deltas are compressed with **Zstd** (`FileAccess.COMPRESSION_ZSTD` in Godot 4.6). Writes are atomic-rename + CRC-32 checksum + rolling 3-snapshot backup. Only modified chunks are persisted; procedurally-regenerable chunks store the world seed only. (Earlier planning documents referenced LZ4 compression; Godot 4.6 does not ship LZ4 — Zstd is the correct implementation choice and is canonical here.)

### 6.9 What this section locks

- Friends-only social model, no open lobbies
- Invite-by-link makes mutual friends until unfriended
- Sessions 1-4 players, host-authoritative
- Mid-session join is seamless
- **Seamless host failover in v1.0** (2-4 s handover; best-connection peer becomes new host)
- World ownership remains with original creator across host changes
- World-wide text chat with profanity filter; no voice
- Host admin: kick, freeze-build, roll-back

---

## §6 Multiplayer Architecture (Phase 4)

This section documents the implemented Phase 4 multiplayer architecture. It reflects the contracts established in Plans 04-02 through 04-11 and is intended for contributors working on the networking subsystem. Player-facing behaviour is described above in §6.1–6.9.

### §6.1 Transport layer

Online sessions use `WebRTCMultiplayerPeer` backed by **libdatachannel** (MPL-2.0) for native desktop and mobile builds. This gives NAT traversal via ICE/STUN/TURN without requiring a central relay server for most connection types. LAN and development sessions fall back to `ENetMultiplayerPeer` when both peers share the same subnet.

The Go signaling server coordinates WebRTC offer/answer/ICE-candidate exchange over WebSocket. HMAC-signed credentials gate TURN relay access. The signaling server never carries game state — it is strictly a signaling relay and session registry.

### §6.2 Session state machine (NetworkManager)

`NetworkManager` implements a 10-state string enum:

- `IDLE` — no session active
- `CONNECTING` — WebRTC negotiation in progress
- `CONNECTED_AS_HOST` — this peer is the session host
- `CONNECTED_AS_PEER` — this peer is a non-host participant
- `FAILOVER_DETECTING` — host disconnect detected; election timer running (200 ms)
- `FAILOVER_ELECTED` — this peer won the election; snapshot save in progress
- `FAILOVER_PROMOTING` — WebRTC server rebuilt; waiting for peers to reconnect
- `FAILOVER_COMPLETE` — at least one peer has reconnected; transition to CONNECTED_AS_HOST imminent
- `FAILOVER_WAITING` — another peer won; waiting for `update_host` signal from signaling server
- `RECONNECTING` — reconnecting to the new host as a peer
- `DISCONNECTED` — session ended

State transitions emit `session_state_changed(new_state: String)`.

### §6.3 Keepalive protocol

The host sends a keepalive ping to all peers at 1 Hz. Each peer responds with a pong containing the original timestamp for RTT calculation. Missed pong counts are tracked per peer:

- **3 consecutive misses** (3 s): `peer_laggy(peer_id, true)` emitted — UI shows "[Player] is laggy".
- **6 consecutive misses** (6 s): `keepalive_timeout(peer_id)` emitted, peer disconnected, `peer_disconnected(peer_id)` fired. If the disconnected peer was the host, failover is triggered.

RTT is tracked as an Exponential Weighted Moving Average (EWMA, alpha=0.1 ≈ 30-second rolling window at 1 Hz). A pong receipt resets the miss counter.

### §6.4 Host election algorithm

When a host disconnects, surviving peers run a deterministic election locally — no coordination round-trip is needed because every peer has the same shared RTT data.

Election rules (applied in order):
1. **Lowest EWMA RTT** wins (peer with best connection becomes host).
2. **Tiebreak: lowest join_order** (earliest joiner wins when RTTs are equal within 1 ms).
3. **Final tiebreak: lowest peer_id** (deterministic when join_orders also match).

The failed host is excluded from the survivor pool. Each peer runs `SessionRegistry.compute_elected_host()` and calls `SessionRegistry.am_i_elected()` to determine whether to promote.

### §6.5 Host failover sequence — VALIDATED

**SLA: ≤ 4 seconds from detection to FAILOVER_COMPLETE.** This SLA is validated by `tests/integration/test_failover_fault_injection.gd::test_failover_convergence_under_4s`, which drives the full state machine without a live WebRTC connection and asserts `elapsed < 4000 ms`.

Full sequence:
1. Host disconnect → `_on_host_disconnected()` → `FAILOVER_DETECTING`, 200 ms election timer starts.
2. Timer expires → `_on_failover_timer_timeout()` → `SessionRegistry.set_surviving_peers(1)` removes failed host; `SessionRegistry.am_i_elected()` determines winner.
3. If this peer won: `_do_failover_elected()` → `FAILOVER_ELECTED` (snapshot saved) → `FAILOVER_PROMOTING` (WebRTC server rebuilt, `update_host` sent to signaling server).
4. If another peer won: `FAILOVER_WAITING` → signaling delivers `update_host` → `RECONNECTING` → reconnect as peer.
5. Surviving peer reconnects to the new host → `_on_peer_connected_during_promotion()` → snapshot pushed to reconnecting peer → `FAILOVER_COMPLETE` → `CONNECTED_AS_HOST`.

If only one player remains when the host disconnects, that player promotes directly to host of a solo session.

### §6.6 Event replication

The host is authoritative for all world mutations (brick placement, inventory changes, etc.). The replication bridge works as follows:

1. `Inventory.apply_event(event)` is called on the host.
2. The host calls `NetworkManager.broadcast_event(event)`.
3. `broadcast_event` is guarded by `if not multiplayer.is_server(): return` — non-host peers never broadcast.
4. `_receive_replicated_event.rpc(event)` is dispatched to all peers with `@rpc("authority", "call_remote", "reliable")` — Godot's RPC layer enforces that only peer_id=1 (the server) can call this function on peers.
5. Peers receive the event and call `Inventory.apply_event(event)` locally.

`FREEZE_BUILD` events use the same path; frozen peers' `Inventory.apply_event()` calls are rejected by the inventory guard.

### §6.7 World snapshot cadence

- **Periodic autosave:** Every 30 seconds while `CONNECTED_AS_HOST`, `WorldSave.save_world_snapshot()` is called with a timestamped ID.
- **Pre-failover snapshot:** When a peer wins the election (`_do_failover_elected()`), a snapshot is saved immediately before rebuilding the WebRTC server.
- **App backgrounding:** On iOS, losing window focus triggers a snapshot and a graceful disconnect to ensure world state is preserved if the OS suspends the process.
- **SNAPSHOT_RESET:** After promotion, the new host pushes the current inventory state to each reconnecting peer via `_receive_snapshot_reset.rpc(state_blob)`. Peers apply the state blob and emit `snapshot_reset_applied`.

Snapshots are stored in the `snapshots` SQLite table (schema_version 3). Chunk deltas are Zstd-compressed. A rolling pruning step retains only the 3 most recent snapshots per session.

### §6.8 Chat system

Chat messages travel via a separate RPC path (not the event journal) to avoid contaminating the world-mutation audit log:

- Peer sends `_send_chat_to_host.rpc_id(1, filtered_text)`.
- Host applies a second profanity filter pass (defense in depth), checks the host-side rate limit, and relays via `_deliver_chat.rpc(sender_id, filtered, ts)`.
- `ProfanityFilter.filter()` replaces matched stub words with `[filtered]`. The Phase 4 stub list contains ~20 words; the Phase 5 community-curated list replaces it.

**Rate limit:** 5 messages per 10-second sliding window, enforced both client-side (`ChatOverlay._message_count`) and host-side (`NetworkManager._chat_rate_counts`). The 6th message in a window is dropped silently; the sender sees a countdown timer on their UI. This is verified by `tests/unit/test_chat_rate_limit.gd`.

### §6.9 Account and friends backend

Authentication uses **Supabase GoTrue** (self-hosted). Sign-in tokens are stored in `user://auth.cfg` and auto-refreshed 60 seconds before expiry.

The friendships table enforces canonical UUID ordering (`user_a < user_b`) via a Postgres `CHECK` constraint, mirrored client-side in `FriendsClient._canonical_pair()`. This prevents duplicate rows for the same pair. Row-Level Security (RLS) restricts visibility to participants.

Invite tokens are 26-character base32 strings (128-bit entropy, alphabet `abcdefghijklmnopqrstuvwxyz234567`), generated by `FriendsClient._generate_invite_token()`. Tokens expire after 24 hours and are single-use (enforced by the `redeemed_by` column RLS policy). These contracts are verified by `tests/unit/test_invite_token.gd` and `tests/unit/test_friends_schema.gd`.

---

## 7. Performance and supported devices

This section commits to what runs where and what's promised at each tier.

### 7.1 Supported platforms (v1)

> **PROVISIONAL — pending Phase 1 empirical confirmation.**
> The Android Tier 3 device list has not yet been confirmed by a real-device benchmark run. The Motorola One Macro (XT2016-1) is listed below as a `candidate (unconfirmed)` — it is the planned Tier 3 reference device but has not been tested. The device list will be pinned (and this admonition removed) after `bash scripts/run-benchmark.sh` is run per `docs/MOTOROLA_BENCHMARK.md` and the result is committed to `.planning/phases/01-foundation-mobile-spike/motorola-benchmark.csv`. See also STATE.md open-debt entry.

| Platform | Minimum version | Notes |
|---|---|---|
| macOS | 12 (Monterey) on Apple Silicon and recent Intel | |
| Windows | 10, 64-bit | |
| Linux | Recent (Ubuntu 22.04+, equivalent) | x86_64 |
| iOS | iOS 16 | iPhone XR / iPad 9th gen and newer |
| Android | Android 9 (API 28) | Devices on the Tier 3 list below — Tier 3 reference device: Motorola One Macro XT2016-1 (Helio P70, Mali-G72 MP3, 4 GB RAM) — `candidate (unconfirmed)` |

### 7.2 Performance tiers

> **PROVISIONAL — pending Phase 1 empirical confirmation.**
> The Tier 3 frame budget below has NOT been measured on a real device. The targets (30 FPS / 5 chunks / shadows off) are `proposed targets — requires real-device confirmation per scripts/run-benchmark.sh`. Any phase building on these numbers must treat them as a planning target, not a confirmed contract. See §7.2.1 below for the discharge path and escalation options.

| Tier | Devices | Render distance | Shadows | Frame target |
|---|---|---|---|---|
| **Tier 1 — Full** | Recent desktops with discrete or modern integrated GPU (~2021+) | High (12 chunks) | On (soft) | 60 FPS |
| **Tier 2 — Mobile-Full** | iPhone 13 / Pixel 6 or newer | Medium (8 chunks) | On (hard) | 30-60 FPS adaptive |
| **Tier 3 — Mobile-Lite** | iPhone XR / Pixel 4a or 4-year-old equivalent — `candidate (unconfirmed)` | Short (5 chunks) — `proposed` | Off — `proposed` | 30 FPS cap — `proposed` |
| **Tier 4 — Unsupported** | Older devices | — | — | Graceful "device not supported" warning at first launch |

Exact Tier 3 device list is locked at the end of phase 1 after the mobile performance benchmark.

#### 7.2.1 Tier 3 contract discharge path (Phase 1 carryover)

The Tier 3 contract becomes confirmed when all of the following are done:

1. Run `bash scripts/run-benchmark.sh` with the Motorola One Macro (XT2016-1) connected via ADB per `docs/MOTOROLA_BENCHMARK.md`.
2. Commit the resulting CSV to `.planning/phases/01-foundation-mobile-spike/motorola-benchmark.csv`.
3. If the benchmark passes the proposed targets (min-FPS in worst 30s window of last 10 minutes ≥ 30): update §7.1 to pin the Motorola as confirmed Tier 3 and remove the PROVISIONAL admonitions from §7.1 and §7.2.
4. If the benchmark fails after one round of settings tuning (CONTEXT.md D-06): apply the D-07 escalation — lower the §7.2 Tier 3 contract to whatever the hardware actually sustains (e.g. 25 FPS or 4 chunks). The response to failure is to lower the contract, NOT to add Rust hot paths (CONTEXT.md D-12). Update §7.2 with the measured contract and add a calibration note referencing the CSV.

Until step 3 or 4 is completed, any Phase 2+ work that depends on the Tier 3 performance floor must treat the numbers in §7.2 as a planning target and build in a margin of safety.

### 7.3 Graphics presets

The settings screen exposes three presets — *Low*, *Medium*, *High* — and an *Auto* option that picks based on the detected device tier. Power users can fine-tune render distance, shadows, particle density, and frame cap individually.

As of Phase 2, the four presets also control the following visual subsystems:

| Setting | Auto | Low (Tier-3) | Medium | High |
|---|---|---|---|---|
| Ghost preview mode | transparent mesh | outline-only | transparent mesh | transparent mesh |
| Palette 3D previews | always-on | on-tap | always-on | always-on |
| Dynamite particle count | 120 | 30 | 80 | 200 |
| Biome ambient blend distance | 5.0 m | 2.0 m | 5.0 m | 5.0 m |
| Rain particle density | high | low | medium | high |
| Sky mode | procedural | panorama fallback | procedural | procedural |

Tier-3 (Low preset) flips ghost preview to outline-only, palette previews to on-tap, and sky to panorama fallback to keep the frame budget within the §7.2 Tier-3 contract.

### 7.4 Network requirements

| Scenario | Connection |
|---|---|
| Solo session | Offline-capable. Internet only needed to sign in once per device. |
| 2-player session | Both players: stable 1 Mbps up / 5 Mbps down. Either can host. |
| 3-4 player session | Host: 3 Mbps up. Players: 1 Mbps. Host should ideally be on home Wi-Fi. |
| Mobile cellular | Supported. May fall back to TURN relay if both peers are on cellular CGNAT; the session UI shows a "Relay" badge when this happens. |

### 7.5 Desktop controls

Desktop uses a WoW-style scheme: keyboard for movement and turning, mouse cursor stays free for window interaction unless you hold the right mouse button to look up/down.

**Movement**
- `W` / `↑` — walk forward (camera-relative)
- `S` / `↓` — walk back
- `A` / `←` — strafe left
- `D` / `→` — strafe right
- `Space` — jump

**Turning + camera**
- `Q` — turn left (smooth yaw rotation of the builder; camera follows behind)
- `E` — turn right
- `Right mouse button (hold)` + mouse motion — steer with the mouse (yaw + pitch). Releasing RMB stops the look-around. WoW-classic style.
- Mouse motion alone does **not** rotate the camera (cursor stays free for UI)

**Interaction**
- `I` — open / close inventory slide-in
- `Shift` (hold) — interact with chest / workbench / bed (walk-up entities show "Hold SHIFT to ..." prompts)
- `Left click` — place brick (when a brick is equipped) / attack
- `Right click (tap, not hold)` — break brick

**UI**
- `Esc` — open settings menu (releases the cursor)
- `Tab` — release the cursor without opening any menu (toggle; press Tab again to recapture)
- `1`-`8` — hotbar slot select

**Hotbar**
- Scroll wheel — cycle hotbar slots (Phase 6)

### 7.6 Mobile controls

Mobile uses on-screen controls overlaid on the world:

- **Virtual joystick** (left thumb): move
- **Swipe right half** (right thumb): camera
- **Place / break buttons** (right thumb area): contextual based on what's targeted
- **Jump button** (right thumb area)
- **Hotbar strip** (bottom centre): tap to select, drag-up reveals full inventory
- **Build button**: opens the brick palette bottom sheet (§3.5)
- **Long-press world**: eyedropper (copies the targeted brick to hotbar)

Buttons follow OS-recommended touch target sizes (44pt iOS, 48dp Android).

### 7.7 Adaptive quality

The game monitors device thermal state (via OS APIs) and frame rate. If sustained frame rate drops or thermal pressure rises:

1. Render distance shrinks one step.
2. Particles reduce.
3. If still struggling, the *Auto* preset drops one tier.

A small notification shows: **"Graphics adjusted for performance."** The player can override and lock the preset in settings.

### 7.8 What this section locks

- 5 supported platforms with crossplay
- 4-tier device matrix, Tier 4 gets graceful warning
- Mobile controls layout (above)
- Adaptive quality with player override
- TURN relay fallback for cellular CGNAT, badged in UI

---

## 8. Safety, accounts, and reporting

Cubicraftia is friends-only, but friends grief friends. This section is the moderation surface — required for App Store and Play Store approval, and required for trust.

### 8.1 Block (already covered in §6.2)

Blocking is mutual, instant, persistent across sessions and devices.

### 8.2 Report

Any player can report from three contexts:

- **A player** (from a nameplate menu or friends-list overflow menu): submits username, world ID, and a free-text reason.
- **A build** (long-press on placed bricks): reports the structure for "inappropriate content" with optional reason.
- **A chat message** (long-press the message): reports the message verbatim with the surrounding 5 messages of context.

Reports go to the discovery server. The moderation flow (a small team of moderators, escalations, decisions) is documented in the project's governance docs.

### 8.3 Profanity filter

The profanity filter applies to:

- Usernames at sign-up (rejected if matched).
- Avatar names (rejected at save time).
- Chat messages (replaced with `[filtered]` for receivers; sender sees their original text).
- World names (rejected at creation).

The filter list is community-maintained, open in the repo, and supports per-language word lists (English and Dutch in v1, more contributable).

### 8.4 Account safety

- Email + password (no third-party identity in v1).
- Password reset by email link.
- Email change requires confirmation on both old and new addresses.
- Account deletion is one button in settings — irreversible after a 7-day grace period, during which the player can cancel the deletion.

### 8.5 Age policy and EULA

- Self-declared age 13+ at account creation (no verification, but on-record).
- Players who declare under-13 are routed to a **parental consent flow**: a parent's email address is requested, a consent link is sent, and the parent (after confirming the linked account belongs to them) can explicitly approve the under-13 child's use of Cubicraftia. The approval is logged with timestamp and parent email. Once approved, the account is fully active.
- Until parental consent is recorded, the under-13 account is read-only (account exists but cannot join sessions or chat).
- A parent may revoke consent at any time from the consent link, which suspends the under-13 account.
- The EULA and privacy policy are linked from the title screen and from the *Settings → About* screen. Plain language summaries are visible above the legal text.
- Personal data collected: email, hashed password, username, friend list, blocked list, world ownership pointers, and (for under-13 accounts) the parent's email + consent record. Game telemetry (FPS, crash logs) is opt-in and anonymous.

### 8.6 Open-source safety

- All discovery-server source is in the same repository as the game.
- The privacy policy describes precisely what the discovery server stores and what it never stores (no game state).
- The community can audit the moderation flow because the moderation tooling is also open source.

### 8.7 What this section locks

- Three report surfaces (player, build, message)
- Profanity filter on usernames, avatar names, chat, world names — open-list, contributable
- Email + password only in v1, no third-party identity
- Self-declared 13+
- EULA + privacy policy linked from title and settings

---

## §8 Safety, Accounts, and Reporting — Phase 5 Architecture (IMPLEMENTED)

**Status: IMPLEMENTED** — Phase 5 Plans 05-01 through 05-12. This section documents the implemented architecture for contributors working on the safety and moderation subsystem. Player-facing behaviour is described above in §8.1–8.7.

### §8.1 Block system

Global mutual blocks are stored in the Supabase `blocks` table (schema: `blocker_uid TEXT`, `blocked_uid TEXT`, `created_at TIMESTAMPTZ`). Direction is preserved: only the initiator (blocker) can see the row via Row-Level Security (`SELECT WHERE blocker_uid = auth.uid()`). The blocked user cannot see they are blocked.

The Go signaling server enforces blocks at the session-join boundary: before relaying an offer from a joining peer to the host, the server queries both directions of the blocks table using the service-role key (which bypasses RLS). If either party has blocked the other, the offer is silently dropped and the joiner receives an `error: blocked` message. The Go signaling check is the **hard gate** — no blocked user can join regardless of client state.

Client-side, `NetworkManager._is_blocked_locally()` checks a local cache (`_blocks_cache`) populated from `FriendsClient.get_blocks()`. If a peer's UID is in this cache, the `peer_connected` signal is suppressed (display-only, not a security gate). `FriendsClient._blocks_cache` is updated when `blocks_loaded` fires. Source: `src/autoload/friends_client.gd`, `src/autoload/network_manager.gd`, `supabase/migrations/004_blocks.sql`.

Tests: `tests/unit/test_block_unblock.gd` (RLS direction, visibility, unblock). `tests/integration/test_blocks_check_on_join.gd` (_is_blocked_locally predicate for peer_connected suppression).

### §8.2 Report flow

Reports are immutable audit records in the Supabase `reports` table (schema: `id UUID`, `reporter_uid TEXT`, `reported_uid TEXT`, `surface TEXT`, `category TEXT`, `reason TEXT`, `evidence JSONB`, `session_id TEXT`, `created_at TIMESTAMPTZ`). No UPDATE or DELETE RLS policy exists — reports can only be inserted.

Three report surfaces are supported: `player` (from the nameplate or friends-list overflow menu), `build` (long-press on placed bricks), and `chat_message` (long-press a chat line, includes up to 5 surrounding messages as evidence JSONB). Five category values are accepted: `harassment`, `spam`, `cheating`, `csam`, and `other`.

Rate limiting: 5 reports per 24-hour rolling window, enforced client-side in `FriendsClient` and as a Postgres row-count check in the RLS INSERT policy. The Go signaling server exposes an `/admin/reports` endpoint (service-role only) for moderation tooling. Source: `supabase/migrations/005_reports.sql`, `src/autoload/friends_client.gd`.

Tests: `tests/unit/test_report_submission.gd` (reporter visibility, reported-user blindness, chat evidence JSONB).

### §8.3 Profanity filter

The profanity filter uses two separately compiled regexes — one for English, one for Dutch — loaded at startup from `assets/profanity/wordlist_en.txt` and `assets/profanity/wordlist_nl.txt`. Word lists are sourced from LDNOOBW (List of Dirty, Naughty, Obscene, and Otherwise Bad Words), licensed CC-BY-4.0, and are community-contributable via pull request.

Two public methods are exposed:

- `ProfanityFilter.filter(text: String) -> String` — replaces whole-word matches with `[filtered]`. Applied to chat messages (host-side relay, defense in depth) and world names.
- `ProfanityFilter.filter_reject(text: String) -> bool` — returns `true` if the text contains any blocked word. Applied at sign-up to usernames and avatar names; callers show a generic "Please choose another name." error and never echo the rejected input.

The dual-regex architecture (separate EN and NL regexes, each under 500 words) avoids regex engine timeout on Tier-3 Android devices (T-05-P2 threat mitigation). A `set_word_list(words)` extension point allows runtime override for testing. Source: `src/networking/profanity_filter.gd`.

Tests: `tests/unit/test_profanity_multilang.gd` (EN/NL filter, filter_reject, set_word_list, clean passthrough).

### §8.4 Parental consent (COPPA 2025 compliance path)

When a user declares a date-of-birth indicating they are under 13, the age gate fires client-side in `sign_in_panel.gd`. The raw date-of-birth is never sent to the server — only the derived `is_under_13: bool` is stored in GoTrue user metadata (GDPR minimum-data principle, T-05-DOB threat mitigation).

The parental consent flow:

1. The under-13 account submits a parent's email via the `ParentalGatePanel` UI (Surface D).
2. `FriendsClient.request_parental_consent(parent_email)` POSTs to the Go signaling server `/consent/request`.
3. The Go server generates two 128-bit CSPRNG tokens encoded as base32 — a `consent_token` and a `revoke_token` — inserts a `parental_consents` row in Supabase, and sends an email via SMTP containing the consent confirmation link (`/consent/confirm?token=<consent_token>`).
4. When the parent clicks the link, the Go server sets `consented_at` to the current timestamp and clears `consent_token` (single-use enforcement). The `revoke_token` remains for future revocation.
5. `FriendsClient.check_consent_status()` polls `/rest/v1/parental_consents` and emits `consent_status_received(true, false)`, setting `FriendsClient.is_consented = true`.
6. `NetworkManager._is_under_13_unconsented()` reads `FriendsClient.is_under_13` and `FriendsClient.is_consented`. With `is_consented = true`, chat and session joins are unblocked.

Token TTL: 7 days. After expiry, the parent must re-request via the app. A parent may revoke consent at any time by visiting the revoke link, which sets `revoked_at` and re-restricts the account. Source: `src/autoload/friends_client.gd`, `src/autoload/network_manager.gd`, `signaling-server/internal/hub/consent.go`, `supabase/migrations/006_parental_consents.sql`.

Tests: `tests/unit/test_parental_consent_token.gd` (128-bit entropy, single-use, 7-day TTL, revoke distinctness). `tests/unit/test_dob_parser.gd` (under-13 detection, boundary, invalid date). `tests/integration/test_parental_consent_e2e.gd` (client-side consent state machine: restrict → confirm → unlock → revoke → restrict).

**Phase 5 carryover debt:**

- COPPA legal review by qualified counsel has not been completed. The technical implementation follows COPPA 2025 "email-plus" good-faith standard, but legal sign-off is required before the app is marketed to audiences that may include under-13 users.
- NCMEC CSAM hash-matching integration is not implemented. The `csam` report category is present in the schema; a future plan must wire NCMEC's PhotoDNA or equivalent service to the report moderation pipeline before public launch.
- Apple Developer Program enrollment ($99/year) is required for TestFlight and App Store distribution. Not yet purchased.

### §8.5 EULA and privacy policy

The EULA and privacy policy are bundled as plain-text Markdown files at `res://docs/EULA.md` and `res://docs/PRIVACY.md`. Plain-language summaries appear above the legal text in the EULA viewer UI. Both documents are linked from the title screen and from *Settings → About*.

Version detection uses SHA-256: at startup, `FriendsClient.check_eula_acknowledgement()` computes the SHA-256 hash of the bundled `EULA.md` file using `HashingContext.HASH_SHA256` and compares the first 16 hex characters against the stored value in `user://settings.cfg` under `[legal] eula_hash`. A mismatch triggers a re-acknowledge modal before the title screen is shown. The stored hash is written via `FriendsClient.store_eula_hash(hash)` when the user taps "I Agree". Source: `src/autoload/friends_client.gd`, `docs/EULA.md`, `docs/PRIVACY.md`.

Tests: `tests/unit/test_eula_hash_recompute.gd` (SHA-256 determinism, collision resistance, mismatch detection).

### §8.6 Username policy

Usernames are validated client-side by `UsernamePol` (`src/autoload/username_policy.gd`) and enforced server-side by a Postgres trigger and RLS policies.

Rules:

- **Format:** 3–20 characters, alphanumeric plus underscore only (`^[a-zA-Z0-9_]{3,20}$`).
- **Reserved prefixes:** `admin`, `mod`, `moderator`, `cubicraftia`, `support`, `staff`, `system`, `official` — including any username that begins with these strings (e.g., `admin123` is rejected).
- **Profanity check:** `UsernamePol.validate()` delegates to `ProfanityFilter.filter_reject()` for the profanity check.
- **30-day cooldown:** Once a username is changed, the `can_change_username()` Postgres function enforces a 30-day cooldown via the `username_change_log` table (migration 007). Client-side, `UsernamePol.days_until_change_allowed(last_changed_at_unix)` provides UX feedback without a server round-trip.

Source: `src/autoload/username_policy.gd`, `supabase/migrations/007_username_cooldown.sql`.

Tests: `tests/unit/test_username_validator.gd` (reserved prefix, format regex, cooldown).

### §8.7 Store readiness

Seven store-readiness documents are located in `docs/store-readiness/`:

- `ios-app-store-submission.md` — App Store submission checklist (age rating 4+, privacy nutrition labels, IDFA)
- `android-play-store-submission.md` — Play Store data safety form and content rating questionnaire
- `data-deletion-instructions.md` — Required deletion instructions for iOS (linked from App Privacy page)
- `privacy-policy-hosting.md` — Self-hosting instructions for the public privacy policy URL
- `content-rating-questionnaire.md` — IARC/PEGI questionnaire answers for both stores
- `platform-policy-compliance.md` — Checklist for Apple App Store Review Guidelines §5.1 (Kids Category) and Google Play Families Policy
- `legal-review-checklist.md` — Items requiring legal sign-off before public launch (COPPA, trademark, GDPR)

iOS CI runs on `macos-15` in `.github/workflows/ci.yml`, building the Godot iOS export template via GitHub Actions (Phase 1 D-04 closure committed in Plan 05-11).

---

## 9. What's not in v1 (and why)

| Feature | Why deferred |
|---|---|
| **Snow, thunderstorms, lightning** | Rain ships in v1.0; full weather palette is v1.1. |
| **Hunger / thirst** | A whole subsystem. v1.1 or v1.2. |
| **Voice chat** | Significant scope (voice infrastructure, moderation, opt-in flows). v1.2+ at the earliest. |
| **Open lobbies / play with strangers** | Contradicts the social model. **Indefinite.** |
| **PvP combat** | Contradicts the friend-group ethos. v2 if ever. |
| **Creeper-style exploding mob** | Dynamite already plays the same role for the player. v1.1. |
| **Official mod / plugin system** | Source is open; advanced users can fork. An official extension API is post-v1. |
| **VR mode** | Out of scope for v1. |
| **Cosmetics shop subscription** | One-time purchase + optional brick packs only. No subscription, no cosmetics-shop model. **Indefinite.** |
| **Cloud world sync** | Worlds live on the host's device in v1. Cloud-side world hosting is post-v1. |
| **Custom textures / resource packs** | Community-contributable post-v1. |
| **Large servers (5+ players)** | P2P architecture caps cleanly at ~4. Larger scale is v2 architecture work. |
| **Dedicated server software** | The headless host build exists internally; packaging a "Cubicraftia Server" distribution is v1.1. |
| **Web browser client** | Godot supports it; networking via WebRTC already works. Likely v1.2. |
| **Cross-mode switching mid-world** | Locked at creation in v1. v1.1. |
| **Brick rotation by player** | Bricks orient automatically based on builder position in v1. Manual rotation is v1.1. |
| **Master Builder gating / progression** | Contradicts "every brick available eventually." **Indefinite.** |
| **Brick gravity** | Bricks float once placed in v1. Optional gravity mode is post-v1 if requested. |

**Phase 2 known carryover debt** (items shipped as infrastructure but not yet empirically confirmed):

| Item | Status | Discharge path |
|---|---|---|
| HUMAN-UAT 4-row hardware run (Plan 02-15) | Deferred by explicit user decision 2026-05-26 | Run `bash scripts/run-benchmark.sh` on Motorola XT2016-1; validate bottom-sheet swipe on physical device; run save force-quit 5-repetition cycle; run cross-platform export smoke on all 5 targets. See `docs/PHASE2_BENCHMARK.md` and `.planning/phases/02-world-building-content/02-HUMAN-UAT.md`. |
| RainParticles process_material stub (Plan 02-14) | Rain particles emit but render nothing; `process_material = null` in `main_scene.tscn` | Wire `ParticleProcessMaterial` (rain_particles.tres) with downward velocity, wind offset, and alpha fade in Phase 6 polish pass. |
| StudGrid.remove_bulk test regression (Plan 02-09) | 1 unit test `removed_bulk signal should have been emitted` fails headlessly due to pre-existing DynamiteHandler parse-error chain | Triage in Phase 3 gap-closure work: fix the headless parse-error chain for `DynamiteHandler` transitive dependencies so the signal assertion can run. |

---

## 10. Glossary (player-facing terms)

| Term | Meaning |
|---|---|
| **Brick** | Any placeable construction piece in the game — rectangular bricks, plates, slopes, tiles, wheels, accessories. |
| **Stud** | The bumps on top of a brick that connect to other bricks. |
| **Builder** | The player character; also used for hostile non-player figures (e.g. "skeleton builder"). |
| **Terrain** | The cube-grid world (grass, dirt, stone, etc.) that bricks are placed onto. |
| **Hotbar** | The bottom row of the inventory, always visible, mapped to keys 1-8 on desktop. |
| **Session** | One running world with 1-4 connected players. |
| **Host** | The player whose machine carries the canonical world state for a session. |
| **Workbench** | A placed crafting station with a 3×3 grid. |
| **Sandbox** | The creative mode — every brick, no danger. |
| **Survival** | The mode where bricks must be gathered, creatures attack, and tools wear out. |
| **Biome** | A distinct region of the world with its own terrain type, flora, atmosphere, and wildlife. Six biomes in v1: grassland+forest, desert, snow, jungle, savannah, ocean. |
| **Structure** | A pre-authored brick construction that appears in the world at generation time — villages, temples, shipwrecks, dungeons, mineshafts. |
| **Village** | A generated structure (desert / snow / savannah) inhabited by wandering peaceful builder NPCs. |
| **Mineshaft** | A generated underground corridor network found deep in stone layers, containing loot and creature spawners. |
| **Tool** | An item that speeds up or enables specific actions: pickaxe (mining), shovel (digging), dynamite (area destruction), lantern (light). Tools wear out in survival mode. |
| **Palette** | The brick selection UI — sidebar on desktop, bottom sheet on mobile. Lists all available brick types and colours. |
| **Durability** | The wear bar on a tool in survival mode. Reaches zero and the tool breaks. Sandbox mode tools never wear out. |
| **Dynamite** | A placeable tool-brick with a ~4 s fuse and ~5 m destruction radius. All bricks and terrain in the radius drop as pickupable items. |
| **Lantern** | A held light source (carried in the builder's hand) that illuminates the area around the builder, not the world. |
| **Rain** | A weather state (alternates with clear sun). Visually darkens the sky, adds rain particles. Builders can trigger rain via the rain dance (once per Cubicraftia day). |
| **Weather** | The current environmental condition: clear sun or rain. |
| **Day** | The lit phase of a Cubicraftia day (~10 real minutes). |
| **Night** | The dark phase of a Cubicraftia day (~5 real minutes). Hostile creature spawning increases. |

---

*Spec version 1, draft 2 — 2026-05-24. Initial draft.*

---

## Revision Log

### 2026-05-29 — Phase 5 doc-sync (Plan 05-12)

- **§8 — Phase 5 Architecture (IMPLEMENTED):** Added §8 Safety, Accounts, and Reporting section documenting the implemented architecture for all 7 DOC-08 deliverables: block system (Supabase blocks table + Go signaling hard gate), report flow (3 surfaces, 5 categories, immutable audit trail, 5/24h rate limit), profanity filter (dual-regex EN+NL LDNOOBW CC-BY-4.0, filter() + filter_reject() API), parental consent (DOB client-side, CSPRNG 128-bit tokens, 7-day TTL, Go SMTP email-plus), EULA/Privacy (bundled Markdown, SHA-256 hash re-acknowledge), username policy (3-20 chars, reserved prefixes, 30-day cooldown), store readiness (7 docs/store-readiness/ files, iOS CI on macos-15).
- **§8 Phase 5 carryover debt:** Documented three manual items deferred post-05-12: COPPA legal review, NCMEC CSAM integration, Apple Developer Program enrollment.
- **Status banner:** Section marked IMPLEMENTED with phase reference.

### 2026-05-26 — Phase 2 doc-sync (Plan 02-16)

- **§2 Inhabitants:** Added wandering builder NPC paragraph (D-09 — villages in desert/snow/savannah biomes).
- **§2 Atmospheric wildlife:** Added locked species list per biome (panda, desert mouse, reindeer/snowman, monkey/toucan, elephant/giraffe/gnu, manta ray/orca/fish/jellyfish) — atmosphere-only, locked for downstream binding.
- **§2.1:** Clarified "smooth transitions" to confirm the ~5 m narrow-blend interpretation (D-05): terrain-colour/ambient-light blend, sudden flora change.
- **§2.5:** Added biome-transition, village-inhabitants, and atmospheric-wildlife to the locks list.
- **§3.1:** Locked the 50-brick list as of Phase 2 (7/5/4/3/4/6/5/9/5/2); updated Decorative count to 5 (fence post deferred to IAP); added reference to `src/bricks/manifest.json`.
- **§3.2:** Added FPV↔chase camera toggle (default chase, V desktop toggle, scroll-wheel zoom 2–8 m, no-op in FPV; crosshair works identically in both modes).
- **§3.6:** Added camera mode locks.
- **§5 Peaceful NPCs:** Added subsection distinguishing village NPCs and atmospheric wildlife from the §5.2 hostile roster.
- **§6.8.5:** Added World save format section documenting Zstd compression (`FileAccess.COMPRESSION_ZSTD`) and atomic-rename + rolling-backup pattern; corrects earlier LZ4 references in planning docs.
- **§7.3:** Added Phase 2 adaptive-quality preset extension table (ghost-preview mode, palette-3D-previews, dynamite-particle-count, biome-ambient-blend-distance, rain-particle-density, sky-mode).
- **§9:** Added Phase 2 known carryover debt (HUMAN-UAT 4-row deferral, RainParticles stub, StudGrid.remove_bulk test regression).
- **§10:** Added new Phase 2 glossary terms (biome, structure, village, mineshaft, tool, palette, durability, dynamite, lantern, rain, weather, day, night).
