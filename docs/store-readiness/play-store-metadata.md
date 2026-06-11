<!-- SPDX-FileCopyrightText: 2026 Cubicraftia contributors -->
<!-- SPDX-License-Identifier: GPL-3.0-or-later -->

# Google Play Console — Submission Metadata

**Product:** Cubicraftia
**Prepared:** 2026-05-29
**Status:** Draft — attorney + marketing review required before submission

---

## Identity

| Field | Value | Char limit |
|-------|-------|------------|
| **App name** | Cubicraftia: Brick Sandbox | 50 / 50 |
| **Package name** | `com.cubicraftia.game` | — |

---

## Store Listing Text

### Short description (80 chars max)

```
Build and explore a brick world with friends. Sandbox or survival.
```

Character count: 65 / 80.

### Full description (4000 chars max)

```
Cubicraftia is a sandbox game built entirely from bricks — interlocking
stud-based pieces that snap together inside a procedurally generated world
that goes on forever.

WHAT MAKES CUBICRAFTIA DIFFERENT

Every boulder, hillside, and dungeon floor is made of 1-metre terrain cubes.
Every creature, every built structure, every item you place is assembled from
a library of 50 brick types — 1×1s, 2×4 plates, slopes, tiles, ladders,
torches, and more — in 18 colours. Build anything. The only limit is your
imagination and the number of studs you carry.

EXPLORE AN INFINITE WORLD

Procedural biomes generate snow fields, deserts, forests, oceans, and
underground caverns wherever you walk. Structures — villages, shipwrecks,
temples, dungeons — appear at rare intervals, each filled with locked chests
and loot. The world never ends and never repeats.

CRAFT, SURVIVE, OR JUST BUILD

Choose Sandbox mode for unlimited resources and a peaceful setting, or
Survival mode where you gather materials, manage a health bar, cook food,
craft tools, and fend off five types of hostile creatures at night.

BUILD AND PLAY WITH FRIENDS

Invite up to three friends directly from your friends list — no public
matchmaking, no strangers. One device hosts the session; if the host
disconnects, the session migrates to another player automatically, mid-game,
without interruption.

DESIGNED FOR FAMILIES

All online play is friends-only. There are no open lobbies, no public chat
channels, and no strangers. A profanity filter covers all user-authored text.
Accounts for players under 13 require a parent or guardian to confirm a
consent email before any online feature unlocks. Block and report tools are
accessible from every player nameplate and chat message.

OPEN SOURCE

Cubicraftia is published under the GNU General Public License v3. Source code
is available at the project repository. Not affiliated with the LEGO Group or
Mojang Studios.

Note: multiplayer requires an internet connection and a free account. Solo
offline play requires no connection after initial setup.
```

Character count: approximately 1 730 / 4 000. Expand with localisation copy if required.

---

## Categories

| Slot | Selection |
|------|-----------|
| **Application type** | Game |
| **Category** | Simulation |
| **Tags** | Building, Sandbox, Multiplayer |

---

## Graphics

### Feature graphic (required)

| Spec | Value |
|------|-------|
| **Size** | 1024 × 500 px |
| **Format** | JPEG or 24-bit PNG (no alpha) |
| **Content** | Key art — brick world vista with logo centred, no text other than game name |

> The feature graphic is shown on the Play Store home row. It must work at 100% and at 50% crop (top and bottom may be hidden in some placements). Keep the logo in the centre vertical strip.

### Icon

| Spec | Value |
|------|-------|
| **Size** | 512 × 512 px |
| **Format** | 32-bit PNG with alpha |

### Screenshots (minimum 2, maximum 8 per device type)

Recommended: 6 screenshots per device type (EN locale). See `docs/store-readiness/screenshot-checklist.md`.

| Device type | Resolution (pixels) |
|-------------|---------------------|
| Android phone | 1080 × 1920 minimum; 9:16 preferred |
| Android 7" tablet | 1200 × 1920 minimum |
| Android 10" tablet | 1920 × 1200 minimum (landscape) |

### Suggested shot sequence

1. Title screen with logo
2. Aerial view of a procedurally generated world
3. Active brick-building moment — placing a coloured slope
4. Friends panel — session with 3 invited friends
5. Chat overlay during a multiplayer session
6. Hostile creature encounter at night with torchlight

---

## Pricing and distribution

| Field | Value |
|-------|-------|
| **Price** | €1.00 / $0.99 (paid) |
| **Countries** | All available countries |
| **In-app purchases** | None in v1 |
| **Contains ads** | No |

---

## Content Rating (IARC questionnaire)

See `docs/store-readiness/age-rating.md` for full IARC answers.

Expected rating: **Everyone 10+** (ESRB) / **PEGI 7** (Europe) / **USK 6** (Germany)

Key answers that determine the rating:

| Question | Answer | Notes |
|----------|--------|-------|
| Violence | Mild fantasy | Creatures take damage, no gore |
| Online interactions | Yes | Friends-only sessions |
| User-generated content | Yes | Worlds and chat, moderated |
| Sexual content | No | |
| Gambling | No | |
| In-app purchases | No | v1 |
| Ads | No | |

---

## Data safety (Play Store privacy)

### Data collected and shared

| Data type | Collected | Purpose | Required | Shared |
|-----------|-----------|---------|----------|--------|
| Email address | Yes | Account creation / auth | Yes | No |
| User ID | Yes | Account identity | Yes | No |
| Username | Yes | In-game display name | Yes | No |
| Gameplay content | Yes | World saves, placed bricks | Yes | No |
| Crash logs | Optional (opt-in) | Bug diagnosis | No | No |

### Data practices

| Practice | Answer |
|----------|--------|
| Data encrypted in transit | Yes (TLS) |
| Users can request data deletion | Yes (Settings → Delete Account) |
| Data sold to third parties | No |
| Data used for tracking/advertising | No |

---

## URLs

| Field | Value |
|-------|-------|
| **Website** | `https://cubicraftia.com` *(placeholder)* |
| **Email** | `operator-contact-email@example.com` *(replace before submission)* |
| **Privacy policy** | `https://cubicraftia.com/privacy` *(must match docs/PRIVACY.md)* |

---

## Localisation (v1)

English (EN-GB / EN-US) only for v1. Dutch (NL) second language target for v1.1.

---

## Pre-Submission Checklist

- [ ] Package name registered in Play Console
- [ ] Signing key generated and upload key configured (see `docs/store-readiness/code-signing-runbook.md`)
- [ ] Feature graphic (1024 × 500) uploaded
- [ ] App icon (512 × 512) uploaded
- [ ] At least 2 phone screenshots uploaded
- [ ] Data safety section completed and submitted
- [ ] IARC content rating questionnaire completed
- [ ] Privacy Policy URL is live
- [ ] Attorney review of Privacy Policy complete
- [ ] Trademark clearance for "Cubicraftia" complete
- [ ] Target SDK version ≥ Android 14 API level (required for 2026 Play Store compliance)
