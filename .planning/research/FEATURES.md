# Feature Landscape: v1.2 Multiplayer & Distribution

**Domain:** Going from code-complete friends-only P2P multiplayer to a live, deployed backend, plus cross-platform distribution (desktop direct download, mobile stores, auto-update)
**Researched:** 2026-07-08
**Supersedes for v1.2 purposes:** the v1.0-era FEATURES.md content (dated 2026-05-24, gameplay feature landscape) — that research is preserved in git history and remains valid for the base game; this document covers ONLY the new v1.2 surface.
**Scope note:** This document covers ONLY the new v1.2 surface (live join/reconnect UX, connection-failure recovery, distribution/install/update, store IAP). It does not re-research the already-built game features (world, bricks, inventory, mobs) or the already-written multiplayer code itself — only what changes once that code runs against a live internet backend and ships through real distribution channels.

## Overview

v1.2 has two halves that share almost no code but share one user-facing promise: "you and your friends are always on the same build, connected the same way, no matter which of the 5 platforms you're each on." Everything below traces back to that promise.

Half one — **live multiplayer** — is mostly a *validation and UX-hardening* problem, not a new-feature problem. The WebRTC P2P stack, host-failover state machine, friends graph, and invite-by-link system are already built and unit/integration tested; what's missing is (a) a deployed discovery server + coturn + Supabase actually reachable from the internet, and (b) the player-facing feedback for the failure modes that only show up on real, uncontrolled networks (NAT types, mobile carrier weirdness, dropped Wi-Fi, symmetric-NAT relay fallback). Three of the "6 deferred WebRTC tests" already named in STATE.md (relay badge, nameplates, freeze UI) are themselves the UX work this document scopes.

Half two — **distribution** — is almost entirely *new* integration work: Godot has no built-in cross-platform auto-updater (a long-standing open proposal, godotengine/godot-proposals#8588), so "auto-update keeps peers on matching builds" needs to be built, not configured. Desktop (itch.io, GitHub Releases, own site) and mobile (App Store, Play Store) behave completely differently here: mobile stores solve auto-update and IAP for you; desktop solves neither, and the three desktop channels don't even solve auto-update consistently among themselves (itch.io's *app* diffs and auto-updates, but a raw zip downloaded from itch.io's *web page* does not).

The unifying finding across both halves: **the version-mismatch problem is the connective tissue.** A stale invite link, an out-of-date desktop build, and a friend still waiting on their app-store update are all the same player-facing symptom — "I can't join my friend" — and should share one clear, actionable message pattern rather than three different vague "connection failed" states.

## Live Multiplayer Join/Reconnect

### Table Stakes

| Feature | Why Expected | Complexity | Notes |
|---|---|---|---|
| Persistent sign-in across launches | Every friends-graph game (Discord, Steam, mobile co-op titles) keeps you signed in; re-entering credentials every session is a top complaint driver | Low | Already built (Supabase/GoTrue session token) — this is a deploy/validate item, not new code |
| Friends list shows online/offline + "in a session" presence | Baseline expectation once a friends graph exists at all — a friends list that can't tell you who's playable is dead weight | Low-Med | Presence channel already implicit in the discovery server design; needs a live heartbeat once deployed |
| One-click "Join" on a friend's active session | This *is* the core value prop ("same session grows to multiplayer") — any extra step (codes, room browsing) contradicts the "no separate modes" design decision | Low | Already built (`join_session_requested` signal per STATE.md `friends-join-signal`) |
| Invite-link click deep-links straight into the join flow | Standard for Discord/Zoom/Spotify-style links; players expect tap-link → land-in-app, not tap-link → open-browser → copy-code → paste-in-app | Med | `cubicraftia://` DeepLinkHandler already built (06-09); needs the *web fallback* for not-yet-installed players (see Distribution section) |
| Direct P2P attempted first, TURN relay fallback automatic and invisible unless the player asks | This is the entire point of paying for a STUN/TURN deployment — if relay requires user action, you've built the wrong thing | Med | ICE/WebRTC handles the STUN→TURN escalation natively; coturn deployment is the new work, not client logic |
| Visible, non-frozen "Connecting…" state with a sane timeout (10-15s) before a clear failure | Any P2P game that ships without this gets "the game is broken" reviews the first time a NAT negotiation takes a few seconds | Low | UI state machine work on top of existing `NetworkManager` string-constant states |
| Host migration is automatic — remaining players don't manually reconnect or lose world state | Without this, P2P is arguably "not feasible" for a co-op game per the Godot community's own assessment of the missing core-engine feature | — | **Already built and SLA-verified** (≤4s, tested at <100ms headless per STATE.md `phase4-failover-sla-verified`) — this is the one item in this whole table that's ahead of the ecosystem norm, not behind it |

### Differentiators

| Feature | Value Proposition | Complexity | Notes |
|---|---|---|---|
| Visible relay-vs-direct connection quality badge | Most indie P2P games hide this entirely, leaving confused players wondering why latency varies session to session; showing it sets expectations honestly | Med | Already scoped as a deferred UAT item ("relay badge") — this document confirms it as a genuine differentiator worth keeping in v1.2, not cutting |
| Live nameplates that update in real time as peers connect/reconnect | Reduces "did that even work?" uncertainty during the join handshake | Low-Med | Already scoped as deferred UAT item; straightforward UI binding to existing peer-list signals |
| Silent auto-reconnect after a brief network blip (Wi-Fi↔cellular handoff, phone lock) before showing any error UI | Mobile co-op players expect a few seconds of grace before the game gives up — dropping straight to an error/menu on a 2-second Wi-Fi hiccup reads as broken | Med | New: needs a short client-side "waiting to reconnect" grace window layered on the existing session state machine |
| True crossplay join (desktop friend joins a mobile-hosted session or vice versa) | Already a locked decision (`Crossplay: yes, all 5 platforms`) — most friends-only indie co-op titles restrict crossplay by platform pairs; Cubicraftia doing all 5 uniformly is a genuine differentiator worth calling out in store copy | — | Already architecturally supported by the single WebRTC/ENet transport choice; this is a validation item, not new code |

### Anti-Features

| Anti-Feature | Why Avoid | What to Do Instead |
|---|---|---|
| Open lobbies / public matchmaking / "quick play" | Hard constraint from PROJECT.md — explicitly out of scope, guards the social safety model and avoids moderation overhead at scale | Friends-only join + invite-by-link only, as already locked |
| Server browser / session list of strangers | Same reasoning — no discovery surface beyond your own friends graph | N/A |
| Spectator mode for non-friends | Extends the "who can see into a session" surface beyond the friends-only boundary the safety/COPPA work (block/report, parental consent) was built around | N/A |
| Ranked/competitive matchmaking, session skill rating | Not a competitive game; 2-4 friends building together has no meaningful "rank" | N/A |

## Connection-Failure & Recovery UX

The general principle validated across every source consulted (Discord's own invite-error documentation, Xbox GDK's invite-flow guidance, Minecraft's outdated-client messaging): **vague "connection failed" is the single most common UX complaint about multiplayer join flows, and it's almost always fixable by distinguishing the failure mode in the message.** Cubicraftia should surface a *specific* reason for every failure, not one generic toast.

| Failure Mode | Expected Player-Facing Behavior | Confidence |
|---|---|---|
| A non-host peer drops | Session continues uninterrupted for everyone else; nameplate disappears; toast "X left the session" | HIGH — standard co-op pattern |
| The host drops mid-session | Automatic promotion of the next-best peer (already built, ≤4s SLA); remaining players see a brief, clearly-labeled "Reconnecting…" freeze state that resolves on its own — never a silent multi-second stall with no feedback | HIGH — the "freeze UI" deferred item is exactly this; Godot's own community explicitly flags the lack of host-migration signals as the biggest gap for P2P titles, and Cubicraftia already has the underlying signals (`snapshot_reset_applied`, etc.) to drive this UI |
| NAT traversal fails and falls back to relay | Should be *transparent* by default (see relay badge above) — the player should not have to do anything; only surface if relay *also* fails | HIGH |
| Relay itself fails (coturn down, or genuinely restrictive network) | Explicit, actionable error: "Could not connect to [friend]. Check your connection or try again." — never a silent hang past the join timeout | MEDIUM — general P2P best practice, not Cubicraftia-specific research |
| Build/version mismatch between peers | Block the join outright with an explicit message naming both versions and a direct path to update — mirrors the exact pattern seen across Minecraft/other live-service titles where vague "connection refused" on version drift is a top support-ticket generator | HIGH (well-documented failure mode across many shipped multiplayer games) |
| Invite link expired (time-boxed) | Distinct message: "This invite has expired — ask [friend] for a new one" | MEDIUM — modeled on Discord's own invite-error taxonomy, which explicitly separates "expired" from "invalid" from "you're not welcome here" rather than using one generic error |
| Invite link points to a session that's already full (4/4) or has ended | Distinct message per case — "This session is full" vs "This session has ended" | MEDIUM |
| Invite sender is blocked by / has blocked the recipient | Fails closed silently at the network layer (already the pattern per `block-gate-fail-closed` decision) — UI should still show *some* generic non-revealing message, not "you're blocked," to avoid leaking block state | HIGH — matches the existing fail-closed COPPA/block gate pattern already in the codebase; this document just extends that pattern to the invite-link surface |

**Key pattern to adopt:** a single shared "connection problem" screen with a *reason enum* (expired / full / ended / blocked-generic / version-mismatch / relay-failed / timeout) rather than N separate ad-hoc error dialogs. This is cheap to build given the existing `NetworkManager` string-constant state pattern and avoids five slightly-different-looking failure screens.

## Distribution + Install + Auto-Update UX (per channel)

### Desktop direct download (itch.io web page, GitHub Releases, own site)

- **macOS:** Gatekeeper does not merely *warn* on an unsigned/unnotarized app on first launch — for un-notarized builds distributed outside the App Store it can outright block the launch depending on Gatekeeper config, requiring a right-click→Open workaround. Developer ID signing + notarization is close to a hard requirement for a smooth first-run, not a nice-to-have. (HIGH confidence — standard, well-documented Apple platform behavior.)
- **Windows:** an unsigned `.exe` triggers SmartScreen's "Windows protected your PC" interstitial. Many indie titles ship this way at launch (it's a "More info → Run anyway" click, not a hard block) and add code-signing later once revenue justifies the cert cost. Treat as a stretch item, not a v1.2 launch blocker. (MEDIUM confidence.)
- **Auto-update — no built-in engine support.** Godot has no cross-platform self-updater; the relevant community proposal is still open (godotengine/godot-proposals#8588). The mature open-source pattern for this problem is Sparkle (macOS) / WinSparkle (Windows) — signed-appcast-driven self-updaters — but adopting them means building signed appcast infrastructure and per-platform native glue, which is a meaningfully larger lift than the "auto-update" phrase implies. **Recommendation for v1.2 scope:** ship a lightweight version-check instead of a full self-updater — on launch, compare the local build stamp (already emitted by the existing Build Stamp plugin, per the recent `feat(build): auto-stamp version.txt` commit) against a version endpoint, and if mismatched, block joining a live session and show a direct link to the current download. This satisfies "peers never mismatch" without the cost of building Sparkle/WinSparkle-grade self-replacing installers. Full self-update remains a good post-v1.2 differentiator. (MEDIUM confidence — this is a reasoned recommendation, not an observed existing pattern for this exact stack; flagged for validation during roadmap/phase planning.)

### itch.io specifically

- If distributed through the **itch.io desktop app** (not just the itch.io web page) and uploaded via `butler push` with a per-platform channel name (e.g. `windows-64`, `osx-universal`, `linux-64`), players get real diffed auto-updates automatically — this is itch.io's own documented, official behavior. (HIGH confidence, official itch.io docs.)
- **Important distinction to design around:** a player who downloads the raw zip from the itch.io *web page* in a browser (rather than installing via the itch.io app) does **not** get any auto-update at all — same as a plain GitHub Releases zip. If Cubicraftia wants "peers never mismatch" to hold for itch.io users, either (a) push players toward the itch.io app install path in marketing copy, or (b) rely on the same version-check-and-block approach used for GitHub Releases/own-site downloads, treating itch.io-web-zip the same as any other unmanaged desktop binary.

### GitHub Releases / own site

- No auto-update mechanism exists at all by default. Same version-check-and-redirect approach as above applies uniformly. Recommend one shared "check current version" endpoint/service used by all three desktop channels rather than three bespoke mechanisms.

### Mobile app stores (Apple App Store, Google Play)

- **Auto-update is essentially solved for free.** Both stores handle update delivery; developers only need to bump the version identifier (`CFBundleVersion`/`CFBundleShortVersionString` on iOS, `versionCode`/`versionName` on Android) on every build. Most users have store auto-update enabled by default. This is by a wide margin the least-effort channel for "peers stay on matching build." (HIGH confidence — standard platform behavior.)
- Because store auto-update timing isn't instantaneous (staged rollouts, user Wi-Fi settings), the same version-mismatch-at-join-time gate described above should still apply on mobile — a player on a slightly older store build should get the same clear "please update" message rather than a raw connection failure.

### One platform-detecting download + join link

- Standard, well-documented web pattern: a landing page does user-agent sniffing and shows one large "Download for [detected OS]" button plus small secondary links for the other four platforms below it. On a mobile user agent, this should redirect straight to the relevant App Store / Play Store badge rather than offering a raw binary. (HIGH confidence — this is a common, low-risk pattern with no notable pitfalls found.)
- This same page should be the **web fallback destination** for the `cubicraftia://` deep link when the app isn't installed yet — click an invite link with no app installed → land on this page → install → the link's session/invite token should still resolve after first launch. This ties directly into the already-flagged Future/prerequisite item "iOS Universal Links + Android App Links `.well-known` server config" — that config is *exactly* what makes deep links degrade gracefully to this web page instead of just failing with "no app found" on a browser that doesn't recognize a custom URI scheme.

## Store IAP UX

- **Apple requires a working "Restore Purchases" affordance** for any restorable purchase type (App Review Guideline 3.1.1) — this applies to non-consumables, which is exactly how the €1 unlock and brick packs should be modeled (permanent, one-time, no re-purchase), consistent with the already-locked "no progression gating" design. The restore action must work without contacting support. (HIGH confidence — official Apple guideline.)
- **Google Play has no equivalent built-in OS-level restore button** — Android apps must implement this manually, typically via the Play Billing Library's purchase-query call on launch/sign-in, silently re-granting entitlements the account already owns. (MEDIUM-HIGH confidence.)
- **Brick packs should be non-consumable, not consumable.** Consumables (repeatable, re-purchasable) are the wrong model for "no progression gating" cosmetic content and don't fit the Restore Purchases expectation cleanly. Model every purchasable thing in Cubicraftia (the €1 unlock, each brick pack) as a one-time permanent unlock tied to the player's account.
- **Desktop/itch.io/GitHub Releases builds have no store receipt system at all** — there is no Apple/Google IAP infrastructure to lean on outside the two mobile stores. The natural fit, given Supabase is already the account/auth backend, is a simple entitlement row per account (`purchases(user_id, product_id, purchased_at)`) checked at launch, with desktop purchases going through a lightweight web checkout (Stripe/similar) that writes to that same table — this is **new integration work**, not a research-verified existing pattern, and should be scoped explicitly as its own item rather than assumed to "just work" once mobile IAP is wired up.
- **Store cut is 15-30%** (Apple's Small Business Program drops to 15% under $1M/year; Google mirrors this) — worth noting as economics context for the €1/$1 price point, not a UX item, but relevant to whether brick-pack IAP pricing needs to account for the platform's cut versus the desktop-direct channel where a payment processor's cut is typically far smaller.
- **Anti-pattern to explicitly avoid:** any consumable, repeatable, or loot-box-adjacent IAP structure. This directly contradicts the locked "no progression gating" design, and both Apple and Google apply extra scrutiny to loot-box-style mechanics — a meaningfully higher review-friction path that isn't worth the risk for a game that already has under-13 players in scope (COPPA parental consent is already built for account creation; gambling-adjacent monetization patterns invite exactly the kind of regulatory attention that design should avoid).

## Feature Dependencies on Existing Systems

| New v1.2 Capability | Depends On (already built) | Nature of Dependency |
|---|---|---|
| Live join over the internet | WebRTC P2P (libdatachannel) + ENet fallback, Go discovery/signaling server, coturn, Supabase friends graph, invite-by-link `cubicraftia://` handler | Deployment + real-network validation of code that already exists; not new client logic |
| Relay badge / nameplates / freeze UI | `NetworkManager` string-constant session states, existing peer-list signals, existing host-failover state machine signals (`snapshot_reset_applied`, etc.) | These are literally 3 of the 6 already-named "deferred multi-device WebRTC tests" — UI work on top of existing signals, not new architecture |
| Host migration mid-game | Existing failover election timer (200ms) + ≤4s SLA state machine (already verified in tests) | No new work needed on the failover mechanism itself — only the player-facing "freeze UI" wrapper around it |
| Version-mismatch gate at join time | The Build Stamp plugin (recent commit: auto-stamps `version.txt` on every export/play) | Reusable as the source of truth for both the desktop update-check and a version-handshake step before allowing a session join |
| Deep-link join flow with web fallback | Existing `cubicraftia://` `DeepLinkHandler` (Phase 6, `06-09`) | Needs the *web* fallback page plus the already-flagged-as-Future "iOS Universal Links + Android App Links `.well-known` config" prerequisite — without that config, links degrade to "no app found" instead of the platform-detecting landing page |
| Mobile IAP entitlements | Supabase account system (existing auth) | Needs a new `purchases`-style table, but reuses the existing account identity rather than inventing a new identity system |
| Desktop IAP entitlements | Same Supabase account system | New: requires a web checkout flow with no existing precedent in the codebase — flagged as net-new integration, not a deployment of existing code |
| Reconnect/failure UX (all cases) | Existing fail-closed pattern already used for block/COPPA gates (`block-gate-fail-closed` decision) | The same "fail closed, don't leak state" principle used for safety gates should extend to invite-link/version/relay failure messaging |

## Complexity Notes

| Item | Complexity | Why |
|---|---|---|
| Deploying discovery server + coturn + Supabase live with TLS/DNS/secrets | Medium-High | Ops/infra work (new), but the software itself is already built and tested; risk is deployment correctness, not design |
| Real-device WebRTC validation (the 6 deferred tests) | Medium-High | Not code complexity — the complexity is that these are, by definition, only reproducible on real uncontrolled networks (NAT types, mobile carriers), which is inherently slower and flakier to validate than headless tests |
| Relay badge / nameplates / freeze UI | Medium | UI layered on existing signals; low architectural risk, but requires the live backend above to actually exercise relay/failover paths for testing |
| Version-mismatch join gate | Medium | Small protocol addition (a version handshake before session join) but the Build Stamp foundation already exists |
| Full self-updating desktop installer (Sparkle/WinSparkle-grade) | High | Requires signed appcast infrastructure and per-OS native update agents; recommend deferring in favor of a lightweight check-and-redirect for v1.2 |
| Lightweight version-check-and-redirect (desktop) | Low-Medium | Just an HTTP call + semver compare + browser-open; much cheaper than full self-update and satisfies the "peers never mismatch" goal adequately |
| Platform-detecting download landing page | Low | Standard, well-documented web pattern (UA sniffing + conditional button), no notable pitfalls |
| Mobile store auto-update | Low | Stores handle it; only work is disciplined version-bumping per build |
| Mobile IAP (Apple/Google) | Medium | Standard StoreKit/Play Billing integration plus the Restore Purchases requirement; well-trodden path with clear platform docs |
| Desktop IAP (no store receipt system) | High | Genuinely new: a web checkout + entitlement table with no existing precedent in the codebase; higher risk of scope surprises than any other v1.2 item |
| Deep-link web fallback + Universal Links/App Links config | Medium | Mostly server/DNS config (`.well-known` files) plus a landing page; already flagged as a Future prerequisite so timeline dependency is known |

## Anti-Features (with why)

| Anti-Feature | Why Avoid | What to Do Instead |
|---|---|---|
| Open lobbies / public matchmaking / server browser | Hard constraint in PROJECT.md; breaks the friends-only social-safety model the entire block/report/COPPA system was designed around | Friends-only join + invite-by-link, as already locked |
| Spectator access for non-friends | Same social-safety reasoning extended to a new surface | N/A — no spectator feature at all in v1.2 |
| Silent, self-replacing desktop auto-updater that swaps the binary without any visible check | High implementation cost (signed appcast infra, per-OS native agents) for a stretch-goal polish item; also a common malware vector pattern if done without proper code-signing discipline, and Cubicraftia doesn't yet have confirmed signing budget/certs | Transparent, visible version-check-and-redirect: tell the player a new version exists and link them to it, rather than silently replacing files |
| Consumable / repeatable brick-pack purchases | Directly contradicts the already-locked "no progression gating, cosmetic-only" design; also complicates the Restore Purchases requirement, which expects non-consumables | Model every purchase (unlock + brick packs) as a one-time, permanent, account-tied entitlement |
| A second, parallel payment processor for mobile (bypassing store IAP where a store exists) | Apple/Google both require in-app purchases to go through their own billing for digital content within their apps; building around this invites store rejection | Store IAP on mobile; a separate web checkout only where no store applies (desktop-direct) |
| Voice chat surfaced anywhere in the connection/reconnect flow | Explicitly out of scope for the whole project per PROJECT.md, not just v1.2 | N/A |
| Generic single "Connection failed" message reused across every failure mode | Directly contradicts the pattern found across every comparable multiplayer title's own postmortems/support docs (Discord, Minecraft, Xbox GDK) — vague errors are consistently the top support-ticket driver in this exact class of feature | One shared "connection problem" screen with a specific reason enum (expired / full / ended / blocked / version-mismatch / relay-failed / timeout) |

## Sources

- [Godot host-migration proposal #7912](https://github.com/godotengine/godot-proposals/issues/7912) — MEDIUM-HIGH: confirms host migration is not a solved problem in the engine core; Cubicraftia's custom solution is ahead of the ecosystem baseline
- [Godot auto-updater proposal #8588](https://github.com/godotengine/godot-proposals/issues/8588) — HIGH: confirms no built-in cross-platform desktop auto-update exists in Godot
- [Reconnecting problems in multiplayer — Godot Forum](https://forum.godotengine.org/t/reconnecting-problems-in-multiplayer/116266) — MEDIUM: community-reported reconnect UX pain points
- [WinSparkle](https://winsparkle.org/) / [NetSparkleUpdater](https://github.com/NetSparkleUpdater/NetSparkle) — HIGH: established appcast-based desktop self-update pattern, used as the "what full self-update would cost" baseline
- [How updates work — itch.io app book](https://itch.io/docs/itch/integrating/updates.html) — HIGH: official documentation of itch.io app channel-based diff auto-update, and the web-zip-vs-app-install distinction
- [Automating Godot game releases to itch.io — DEV Community](https://dev.to/jeremyckahn/automating-godot-game-releases-to-itchio-1a96) — MEDIUM: confirms `butler`-based CI upload pattern for Godot specifically
- [App Review Guidelines — Apple Developer](https://developer.apple.com/app-store/review/guidelines/) — HIGH: Restore Purchases requirement (3.1.1), official source
- [A Complete Guide to Restoring Purchases on Google Play and App Store — Apphud](https://apphud.com/blog/restoring-purchases) — MEDIUM: confirms Android has no OS-level restore UI, must be built manually
- [Comprehensive Guide to Monetizing Mobile Games with In-App Purchases — FoxData](https://foxdata.com/en/blogs/comprehensive-guide-to-monetizing-mobile-games-with-inapp-purchases/) — MEDIUM: consumable vs non-consumable modeling guidance, store cut figures
- [Understanding WebRTC and P2P Connections — NAT Checker](https://natchecker.com/blog/webrtc-p2p-connection) / [WebRTC.link STUN/TURN guide](https://webrtc.link/en/articles/stun-turn-servers-webrtc-nat-traversal/) — MEDIUM: general direct-vs-relay success-rate figures (~75-80% direct on open internet), used as context for why a relay indicator matters
- [Invalid Invite Links — Discord Support](https://support.discord.com/hc/en-us/articles/360001556852-Invalid-Invite-Links) — MEDIUM: real-world invite-link failure taxonomy (expired vs invalid vs no-permission), used as the model for Cubicraftia's reason-enum recommendation
- [Flows for multiplayer game invites — Microsoft GDK docs](https://learn.microsoft.com/en-us/gaming/gdk/docs/services/multiplayer/invites/concepts/live-multiplayer-invite-flows) — MEDIUM: toast/notification pattern guidance for invite flows (avoid notification spam, one-shot "invite sent" toast)
- [Minecraft Server 'Outdated Client': Version Mismatch — GameTeam](https://gameteam.io/blog/minecraft-server-outdated-client-version-mismatch/) — MEDIUM: real-world version-mismatch UX failure pattern used to justify the explicit "please update" gate
- Existing project sources: `.planning/STATE.md` (locked decisions, deferred verification items, Build Stamp plugin commit), `.planning/PROJECT.md` (locked scope constraints, pricing, friends-only model) — HIGH, first-party
