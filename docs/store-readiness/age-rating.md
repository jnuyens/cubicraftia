<!-- SPDX-FileCopyrightText: 2026 Cubicraftia contributors -->
<!-- SPDX-License-Identifier: GPL-3.0-or-later -->

# Age Rating — IARC Questionnaire Answers

**Product:** Cubicraftia v1.0
**Prepared:** 2026-05-29
**Status:** Draft — complete the official IARC questionnaire at https://www.globalratings.com/ before submission. This document records the intended answers and the rationale for each.

## Target Ratings

| Rating Body | Expected Rating | Rationale |
|-------------|-----------------|-----------|
| **ESRB** (North America) | **Everyone 10+** | Cartoon fantasy violence, online interactivity with friends |
| **PEGI** (Europe) | **PEGI 7** | Mild implied violence in a fantasy setting, online game |
| **USK** (Germany) | **USK 6** | Mild cartoon action, friends-only online interaction |
| **App Store (Apple)** | **12+** | Online interaction with other players |
| **Google Play (IARC)** | **Everyone 10+** / PEGI 7 (EU) | Same factors as above |

> Apple's App Store applies a minimum of 12+ to any app with user-generated content or online interaction with other users, regardless of the nature of that interaction. Cubicraftia's friends-only architecture is the strongest mitigating factor but does not lower the Apple floor below 12+.

---

## IARC Questionnaire — Question-by-Question

### Section 1: Violence

**Q1.1 Does the app contain violence?**
**Answer: Yes — Mild / Fantasy**

Cubicraftia contains five types of hostile creatures that the player can combat in Survival mode. Combat involves a tool (pickaxe or similar) striking a creature. Creatures are made of bricks and break apart; there is no blood, no gore, and no realistic injury portrayal. This is equivalent in tone to other brick-construction games with creatures.

**Q1.2 Does the violence include blood or gore?**
**Answer: No.**

No blood, no realistic wounds. Defeated creatures dissolve into dropped brick items.

**Q1.3 Is violence directed at realistic or human-like characters?**
**Answer: No.**

All creatures are clearly stylised brick constructs (Cube Slimes, Vampire Bats, etc.). Builders (player characters) are also made of bricks.

**Q1.4 Is there torture, sadism, or gratuitous violence?**
**Answer: No.**

---

### Section 2: Sexual Content

**Q2.1 Does the app contain sexual content, nudity, or suggestive themes?**
**Answer: No.**

No romantic, sexual, or suggestive content of any kind. Player characters are brick constructs without anatomical representation.

---

### Section 3: Language

**Q3.1 Does the app contain profanity or strong language in scripts, audio, or UI?**
**Answer: No.**

No profanity in developer-authored content. A profanity filter (English + Dutch word lists) is applied to all user-authored text (chat messages, usernames, world names) and replaces matched words with `[filtered]` before display to other players.

---

### Section 4: Drugs, Alcohol, Tobacco

**Q4.1 Does the app depict or reference drugs, alcohol, or tobacco use?**
**Answer: No.**

No such content.

---

### Section 5: Gambling

**Q5.1 Does the app include gambling features?**
**Answer: No.**

No loot boxes, randomised paid rewards, or gambling mechanics. Chests contain deterministically seeded loot based on world seed and chest position. No real-money randomised rewards of any kind.

---

### Section 6: Fear / Horror

**Q6.1 Does the app contain horror elements or jump scares?**
**Answer: Mild / No.**

The game has a day-night cycle where hostile creatures spawn at night. The atmosphere is intended to be tense but playful, not horrific. No jump scares, no explicit horror themes.

---

### Section 7: Online Features

**Q7.1 Does the app allow online interaction with other players?**
**Answer: Yes.**

**Q7.2 Is online interaction limited to the player's friends/contacts?**
**Answer: Yes — friends-only.**

Cubicraftia's multiplayer model is exclusively friends-only. Sessions can only be joined via a private invite link sent to an existing mutual friend. There are no open lobbies, no public matchmaking, and no way for a stranger to join a session. This is a core architectural decision, not a setting that can be changed.

Rationale for rating: Many rating bodies assign a higher rating tier for any app with online interaction. Cubicraftia's friends-only constraint is a strong mitigating factor and is equivalent in risk profile to games rated PEGI 7 / ESRB E10+ with "Users interact" descriptor.

**Q7.3 Does the app include text chat?**
**Answer: Yes.**

In-session text chat between players in the same session (who are already mutual friends). All messages pass through a server-side profanity filter before relay. Players can mute, block, and report other players from the chat overlay.

**Q7.4 Does the app include voice chat?**
**Answer: No.**

Voice chat is not implemented in v1.

**Q7.5 Is there any way for players to share personal information?**
**Answer: Users may choose to share information via text chat (as in any text communication product).**

Mitigations: friends-only sessions (no strangers in chat), profanity filter, block and report tools accessible from all chat messages, parental consent gate for under-13 accounts.

---

### Section 8: User-Generated Content (UGC)

**Q8.1 Does the app allow user-generated content?**
**Answer: Yes.**

Players author worlds (procedurally modified terrain and placed bricks), usernames, world names, and chat messages.

**Q8.2 Is UGC visible to other users?**
**Answer: Yes — but only to mutual friends in a shared session.**

UGC is not publicly indexed or browsable. A world is only accessible to players explicitly invited by the host. Chat is only visible to players in the same session.

**Q8.3 Does the app have moderation for UGC?**
**Answer: Yes.**

- Profanity filter on all user-authored text strings (English + Dutch, with more languages contributable by the community).
- Block tool: any player can block any other player; blocked players cannot join that player's sessions or appear in friend search results.
- Report tool: available from every player nameplate, placed build, and chat message. Three report categories: harassment, spam, cheating. CSAM is a separate urgent category. Reports are submitted to an operator-reviewed moderation queue.
- Under-13 accounts: require parental consent before any UGC sharing or online feature is accessible.

---

### Section 9: In-App Purchases

**Q9.1 Does the app include in-app purchases?**
**Answer: No (v1).**

Cubicraftia v1 is a one-time-purchase app (€1 / $1). No in-app purchases, no subscription, no loot boxes. IAP brick packs are planned for v1.x but are not present at launch.

---

### Section 10: Advertisements

**Q10.1 Does the app display advertisements?**
**Answer: No.**

No advertising SDKs, no advertising IDs, no ad placements of any kind.

---

## Summary of Rating-Raising Factors

| Factor | Present | Mitigation | Impact on rating |
|--------|---------|------------|-----------------|
| Fantasy violence | Yes (mild) | No blood/gore; brick constructs only | +1 tier in some regions |
| Online interaction | Yes | Friends-only; no strangers possible | Required "online game" descriptor |
| Text chat | Yes | Profanity filter; block/report; parental gate | Descriptor only |
| UGC | Yes | Friends-only; moderated; profanity-filtered | Descriptor only |
| In-app purchases | No | — | None |
| Gambling | No | — | None |
| Sexual content | No | — | None |
| Horror | Mild (night creatures) | Playful tone; brick aesthetic | None |

---

## COPPA / Under-13 Specific

Under-13 accounts are gated behind a parental consent flow (email-based, FTC "email plus" method). Until consent is received:

- Online features are fully locked (no sessions, no chat, no friend requests).
- Only solo offline play is available.
- The account cannot be discovered in friend search.

This gate applies regardless of the IARC rating. Even if a jurisdiction's rating would allow under-13 access, the in-app gate remains.

---

## References

- [IARC rating service](https://www.globalratings.com/)
- [Apple App Store rating criteria](https://developer.apple.com/help/app-store-connect/reference/age-ratings/)
- [PEGI descriptors](https://pegi.info/page/pegi-age-ratings)
- [ESRB rating categories](https://www.esrb.org/ratings-guide/)
- 05-RESEARCH.md Assumption A5: friends-only architecture as IARC mitigating factor
