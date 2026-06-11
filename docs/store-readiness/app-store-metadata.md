<!-- SPDX-FileCopyrightText: 2026 Cubicraftia contributors -->
<!-- SPDX-License-Identifier: GPL-3.0-or-later -->

# App Store Connect — Submission Metadata

**Product:** Cubicraftia
**Prepared:** 2026-05-29
**Status:** Draft — attorney + marketing review required before submission

---

## Identity

| Field | Value | Char limit |
|-------|-------|------------|
| **Name** | Cubicraftia: Brick Sandbox | 30 / 30 |
| **Subtitle** | Build worlds. With friends. | 27 / 30 |
| **Bundle ID** | `com.cubicraftia.game` | — |
| **SKU** | `cubicraftia-v1` | — |

> Subtitle must be distinct from the name and must not repeat marketing copy from the description.

---

## Categories

| Slot | Category |
|------|----------|
| **Primary** | Games → Simulation |
| **Secondary** | Games → Adventure |

---

## Description (4000 chars max)

```
Cubicraftia is a sandbox game built entirely from bricks — interlocking
stud-based pieces that snap together just like the plastic building sets
you grew up with, inside a procedurally generated voxel world that goes
on forever.

WHAT MAKES CUBICRAFTIA DIFFERENT

Every boulder, hillside, and dungeon floor is made of 1-metre terrain
cubes. Every creature, every built structure, every item you place is
assembled from a library of 50 brick types — 1×1s, 2×4 plates, slopes,
tiles, ladders, torches, and more — in 18 colours. Build anything. The
only limit is your imagination and the number of studs you carry.

EXPLORE AN INFINITE WORLD

Procedural biomes generate snow fields, deserts, forests, oceans, and
underground caverns wherever you walk. Structures — villages, shipwrecks,
temples, dungeons — appear at rare intervals, each filled with locked
chests and loot. The world never ends and never repeats.

CRAFT, SURVIVE, OR JUST BUILD

Choose Sandbox mode for unlimited resources and a peaceful setting, or
Survival mode where you gather materials, manage a health bar, cook food,
craft tools, and fend off five types of hostile creatures at night.
Switch between the two at any time.

BUILD AND PLAY WITH FRIENDS

Invite up to three friends directly from your friends list — no public
matchmaking, no strangers. One device hosts the session; if the host
disconnects, the session migrates to another player automatically,
mid-game, without interruption. Your world is saved to the host's device
as a single file you can back up and share.

DESIGNED FOR FAMILIES

All online play is friends-only. There are no open lobbies, no public
chat channels, and no strangers. A profanity filter covers all
user-authored text. Accounts for players under 13 require a parent or
guardian to confirm a consent email before any online feature unlocks;
offline solo play is available immediately. Block and report tools are
accessible from every player nameplate and chat message.

OPEN SOURCE

Cubicraftia is published under the GNU General Public License v3 and is
not affiliated with the LEGO Group or Mojang Studios. The source code is
available at the project repository.

Note: Cubicraftia requires an internet connection for multiplayer
sessions and account creation. Solo offline play requires no connection
after initial setup.
```

Character count: approximately 1 980 / 4 000. Expand with localisation copy if required.

---

## Keywords (100 chars max)

```
bricks,sandbox,multiplayer,building,creative,voxel,kids,family,friends,craft
```

Character count: 76 / 100.

> Do not repeat words from the name or subtitle. No competitor names, no trademark terms.

---

## What's New (v1.0 release)

```
Welcome to Cubicraftia v1.0 — the first public release.

Build and explore a procedurally generated world made entirely of
interlocking bricks. Play solo or invite up to three friends for a
shared session. Features: infinite terrain, 50 brick types in 18
colours, Sandbox and Survival modes, five hostile creature types,
crafting, and a friends-only multiplayer system with full block and
report tools.

Thank you for playing.
```

---

## URLs

| Field | Value |
|-------|-------|
| **Support URL** | `https://cubicraftia.com/support` *(placeholder — create before submission)* |
| **Marketing URL** | `https://cubicraftia.com` *(placeholder)* |
| **Privacy Policy URL** | `https://cubicraftia.com/privacy` *(must match docs/PRIVACY.md content)* |

---

## Age Rating

See `docs/store-readiness/age-rating.md`.

Expected rating: **12+** (App Store Connect age-rating questionnaire)

---

## Screenshots (6 per device per locale)

See `docs/store-readiness/screenshot-checklist.md` for exact dimensions and capture guidance.

### Required devices (English / EN-US locale)

| Device | Resolution (pixels) | Orientation |
|--------|---------------------|-------------|
| iPhone 6.9" (required) | 1320 × 2868 @3x | Portrait |
| iPhone 6.5" (required) | 1242 × 2688 @3x | Portrait |
| iPad 13" (required) | 2064 × 2752 @2x | Landscape or Portrait |

### Suggested shot sequence (same for all devices)

1. Title screen with logo and "Build worlds. With friends." tagline
2. Aerial view of a procedurally generated world — mix of biomes
3. Active brick-building moment — player placing a coloured slope
4. Friends panel — session with 3 invited friends listed
5. Chat overlay during a multiplayer session
6. Hostile creature encounter at night with torchlight

---

## Pricing

| Field | Value |
|-------|-------|
| **Base price** | €1.00 / $1.00 (tier 1) |
| **In-app purchases** | None in v1 (IAP brick packs planned for v1.x) |
| **Free redemption codes** | Available from project owner |

---

## Localisation (v1)

English (EN-US) only for v1. Dutch (NL) is the second language target; add NL locale before v1.1 submission.

---

## Legal Notices

- Not affiliated with the LEGO Group.
- Not affiliated with Mojang Studios.
- Sign-in with Apple: **not required** for v1. Cubicraftia offers email + password authentication only and no other third-party sign-in — therefore Apple's SIWA requirement does not apply. Confirm during pre-submission review.
- No advertising SDKs, no advertising IDs, no cross-app tracking.

---

## Pre-Submission Checklist

- [ ] Bundle ID registered in App Store Connect
- [ ] All 6 screenshot slots filled for iPhone 6.9" and 6.5" and iPad 13"
- [ ] Privacy nutrition label submitted (see `docs/store-readiness/privacy-nutrition.json`)
- [ ] Age-rating questionnaire completed
- [ ] Support URL is live and returns HTTP 200
- [ ] Privacy Policy URL is live and matches `docs/PRIVACY.md`
- [ ] EULA URL is live and matches `docs/EULA.md`
- [ ] iOS export signed with Distribution certificate (see `docs/store-readiness/code-signing-runbook.md`)
- [ ] Attorney review of EULA and Privacy Policy complete
- [ ] Trademark clearance check complete for "Cubicraftia"
