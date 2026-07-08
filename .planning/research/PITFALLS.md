# Domain Pitfalls: Cubicraftia v1.2 — Multiplayer & Distribution

**Domain:** Going live — single-host P2P backend deployment (Go signaling + coturn + self-hosted Supabase) + cross-platform signed distribution (desktop direct download + Apple App Store + Google Play) for a kids-adjacent, GPL-3.0-or-later, IAP-monetized multiplayer game.
**Researched:** 2026-07-08
**Overall confidence:** MEDIUM-HIGH. The GPL/App-Store conflict, coturn/firewall mechanics, and Android/Apple signing-lockout risks are HIGH confidence (well-documented, multi-source). Some 2026-specific policy details (Apple age-rating overhaul, EU DMA fee structure, US state age-verification laws) are MEDIUM confidence — verify against the live guideline text at submission time, not this document, since store policy changes faster than this research.

This document supersedes/extends `.planning/research/PITFALLS.md` from v1.0 research (CRIT-1 trademark, CRIT-2 CGNAT, CRIT-3 save corruption, CRIT-4 store UGC moderation) for the **v1.2 go-live and distribution milestone specifically**. Those v1.0 findings were about *designing* the systems; this document is about *deploying and shipping* them — the failure modes only appear once the backend is live on the real internet and the binary is in front of Apple/Google reviewers.

---

## How to Read This Document

Each pitfall has: **What goes wrong** (concrete), **Warning signs** (how to catch it before it bites), **Prevention** (actionable), **Mitigating phase** (where in the v1.2 roadmap this belongs). HARD BLOCKERS are legal/policy items that can stop store submission outright — they are called out first because the roadmap must sequence them before, not during, store submission work.

---

# HARD BLOCKERS

These are not "pitfalls to avoid while coding" — they are gating legal/policy decisions. If unresolved, they can make Apple App Store submission impossible or force a mid-milestone re-architecture. Read this section before sequencing any phase.

## HARD BLOCKER 1: GPL-3.0-or-later vs. Apple App Store Distribution Terms

**Severity:** CRITICAL — this is a real, well-documented, unresolved legal conflict, not a hypothetical.

**What goes wrong:**
The Free Software Foundation's long-standing position (and the position that led Apple to pull GNU Go and VLC from the App Store) is that **Apple's App Store Terms of Service are incompatible with the GPL, in both v2 and v3.** The mechanism: GPL section 2/6 (GPLv2) and the equivalent GPLv3 clauses guarantee that everyone who receives a copy of the software automatically gets the same rights to run, copy, modify, and redistribute it — and explicitly forbid the distributor from "impos[ing] any further restrictions on the recipients' exercise of the rights granted." Apple's Media Services Terms and Conditions impose exactly this kind of further restriction: the app can only be installed via Apple's own signed distribution mechanism, tied to an Apple ID / device limit, and cannot be freely redistributed copy-to-copy the way GPL requires. **GPLv3 specifically also adds the anti-tivoization clause (§6, "Installation Information")**, aimed at exactly this class of problem: locked-down consumer devices that refuse to run user-modified code. iOS enforces mandatory code signing, so a user who receives Cubicraftia's GPLv3 source, modifies it, and tries to run their modified build on an unmodified iPhone cannot — Hacker News commentary and multiple FSF-adjacent sources describe Apple's App Store model as "identical to the TiVoization problem GPLv3 was written to combat."

This is **not a theoretical Apple-side rejection risk** — Apple does not scan for license text and will not reject the binary for being GPL. The risk is a **legal-standing / community-trust problem**: the project is distributing software under a license whose own terms it cannot actually honor for the App Store channel, which is a real exposure if a copyright holder (including a future external contributor) or the FSF ever objects, and it undermines the "open source as principle" positioning that is core to Cubicraftia's identity.

**Important asymmetry — this is an Apple-specific problem, not a general mobile-store problem:** Google Play has **no equivalent conflict.** Real, currently-live GPL-licensed games ship on Google Play today (e.g., Shattered Pixel Dungeon — GPL-3.0 — and SuperTuxKart — GPL-2.0 — are both distributed via Google Play with no exception language). Google's Play Store terms do not impose the same "no further redistribution" restriction that trips the GPL. **Android/Google Play submission has no licensing blocker. Only Apple does.**

**Warning signs:**
- LICENSE / COPYING file states plain "GPL-3.0-or-later" with no App Store exception clause
- No CLA or contributor agreement exists yet (currently true for Cubicraftia — see below, this is actually good news)
- Team assumes "Godot is MIT so we're fine" — this conflates the *engine's* license (MIT, no conflict) with *Cubicraftia's own code's* license (GPL-3.0-or-later, which is the actual problem)
- Apple submission phase scheduled without a preceding "licensing decision" gate
- Nobody has read the actual App Store binary distribution channel decision through a legal lens before building the iOS CI export job

**Options (in order of recommendation):**

1. **RECOMMENDED — Add an explicit "App Store" supplemental permission under GPLv3 §7, now, while the copyright is still 100% owned by a single person.** GPLv3 §7 allows the licensor to grant additional permissions. The standard community-tested clause (used by projects such as the wger fitness app and Feeel, both of which ship GPL/AGPL code through Apple's App Store) reads approximately:

   > "As an additional permission under GNU GPL version 3 section 7, you are allowed to distribute the software through an app store, even if that store has terms and conditions that are incompatible with the GPL, provided that the source code is also available under the GPL, with or without this permission, through a channel without those restrictive terms and conditions (for example, GitHub or a direct download from cubicraftia.com)."

   This resolves the conflict cleanly: GitHub / direct-download users get plain GPL-3.0-or-later; the App Store binary carries the extra permission that reconciles it with Apple's terms; the "spirit" of the GPL (source availability, forkability) is fully preserved through the non-Apple channel.

   **Why now specifically matters:** per `STATE.md`, Cubicraftia's git history to date is effectively single-author (jnuyens). Adding a license exception unilaterally is legally simple *today* because there is one copyright holder. The moment external contributors land PRs without a CLA or without accepting this permission explicitly, retrofitting the exception requires **tracking down and getting consent from every contributor** — in practice, impossible past a few dozen contributors (this is precisely LEGAL-1 from the v1.0 research, now with a concrete, time-sensitive trigger). **This is the single highest-leverage legal action available this milestone: add the clause to LICENSE/COPYING before Phase "mobile store submission" even starts, and add one sentence to CONTRIBUTING.md/CLA-equivalent so all future contributions are made under the same terms.**

2. **Do not add the exception; ship Android + desktop only, defer/skip Apple.** Legally the cleanest option (no conflict to resolve) but contradicts the locked v1.2 scope ("both mobile stores"). Only recommended if the attorney review (already a gating dependency per STATE.md) comes back opposed to Option 1 for some jurisdiction-specific reason.

3. **EU-only partial workaround via DMA alternative distribution.** Since 2024, EU users can install notarized iOS apps directly from a developer's own website or an alternative marketplace, without going through the standard Apple Media Services Terms that trigger the GPL conflict (Apple still requires Apple-performed notarization, but the *distribution and redistribution* terms are materially different from full App Store terms). This is a real, current (2026) mechanism — but it **only covers EU-region users**; the primary market (US, rest of world) still needs standard App Store distribution if the goal is broad reach, so this does not replace Option 1, it only reduces exposure for EU-based installs specifically. Treat as a secondary mitigation, not the primary fix.

4. **Relicense the whole project to a permissive license (MIT/Apache-2.0/MPL-2.0).** Technically resolves the conflict (permissive licenses have no "no further restrictions" clause to violate) but reverses a "Locked" decision in PROJECT.md made specifically to prevent proprietary forks, and is a much bigger and less reversible change than Option 1. Not recommended given the project's stated open-source principles.

**Prevention / action items:**
1. Draft and land the GPLv3 §7 App-Store exception clause in `LICENSE`/`COPYING` as an early, low-risk, code-independent commit — this can happen in parallel with, and ahead of, any backend deployment work.
2. Update `CONTRIBUTING.md` to state new contributions are made under GPL-3.0-or-later **with** the same store exception, so the door doesn't close on future contributors.
3. Explicitly flag this decision for the deferred COPPA/EULA attorney review (STATE.md already lists this as a gating operator/legal dependency) — get the attorney to bless the exact clause wording, not just draft it internally.
4. Do NOT let iOS CI export / App Store Connect submission work start before this is resolved — treat it as a phase-0 prerequisite gate for the "mobile app stores" workstream, not a parallel task.

**Mitigating phase:** A dedicated early phase (or the first task of the "Mobile app stores" phase) — **licensing decision + LICENSE file update**, gated on attorney sign-off, completed before any App Store Connect account work or iOS signing begins.

---

## HARD BLOCKER 2 (related, lower severity): IAP Requires StoreKit — GPL Openness vs. Apple's Payment Mandate

**What goes wrong:** Apple requires digital goods (the optional brick-pack IAP) to be sold exclusively through Apple's In-App Purchase / StoreKit, with Apple taking its standard commission, for the standard (non-EU) storefront. This is a business-model constraint, not strictly a GPL conflict, but it interacts with the GPL exception above: the exception text should explicitly *not* attempt to promise users a way to get IAP content outside Apple's payment system on iOS, since that would itself violate 3.1.1 (Apple's in-app purchase rule) and risk store rejection independent of any GPL question. On Android, Google Play allows more IAP flexibility and the constraint is milder.

**Warning signs:** Store-listing copy or in-game text implying "buy brick packs cheaper on our website" while also being available as an iOS IAP (anti-steering violation risk under Apple's standard terms). EU-only External Purchase Link entitlement conflated with global capability.

**Prevention:** Treat iOS IAP as StoreKit-only, full price parity with Apple's cut baked in; treat Android/desktop IAP or direct-purchase flows as separate, since GPL and store rules don't force parity across platforms.

**Mitigating phase:** IAP wiring task within "Mobile app stores" phase — coordinate pricing/wording with the attorney review pass.

---

# Backend Deployment Pitfalls (Single-Host: Go Signaling + coturn + Supabase)

## BACKEND-1: Port 443 Contention Between coturn (TURN-over-TLS) and the Signaling/Supabase Reverse Proxy

**What goes wrong:** coturn is commonly configured to also listen on TCP/TLS port 443 specifically because many restrictive corporate/mobile-carrier firewalls block everything except 80/443 — this is the *single most valuable* TURN listener for exactly the CGNAT/symmetric-NAT case the v1.0 research flagged as CRIT-2. But port 443 is also where the Go signaling server's `wss://` endpoint and Supabase's Kong gateway (HTTPS) need to live, behind whatever reverse proxy (nginx/Caddy) terminates TLS and handles Let's Encrypt renewal. Two services binding 443 on one box without a plan is an immediate deployment blocker, and the naive fix (put coturn behind the same nginx) breaks coturn's need to directly terminate TLS for the TURN protocol (a generic HTTP reverse proxy does not speak TURN).

**Warning signs:** Deployment runbook doesn't mention a port-allocation plan across coturn / Go signaling / Supabase before first `docker compose up` on the production host. `systemctl status coturn` and `nginx` both show `bind: address already in use` on staging. TURN-over-TLS (443) untested — team only validated coturn on 3478/5349 in dev, which will silently fail for exactly the CGNAT users it exists to rescue.

**Prevention:**
1. Decide port allocation explicitly before deployment: e.g., nginx/Caddy owns 443 for HTTPS/wss (signaling + Supabase Kong), coturn uses 3478 (STUN/TURN UDP+TCP) + 5349 (TURN/TLS) as its primary ports, **and** additionally binds 443 via SNI-based TLS demultiplexing (nginx `stream` module routing by SNI hostname to coturn's TLS listener) if the "TURN disguised as HTTPS" fallback is required for the worst-case CGNAT/corporate-firewall users.
2. If SNI muxing is too complex for a v1.2 timeline, explicitly accept the tradeoff (TURN-over-TLS-443 fallback deferred) and document it as a known limitation — don't silently drop it.
3. Confirm the UDP relay port range (default 49152-65535, or a narrowed custom range) is opened on the host firewall/cloud security group **in addition to** 3478/5349 — this is the most commonly missed line item in coturn deployments; TURN allocation succeeds but the actual relayed media/data never flows because the relay ports are closed.
4. Test with `turnutils_uclient` / a real STUN/TURN probe from an external network before declaring the backend "live," not just from localhost.

**Mitigating phase:** "Go-live multiplayer" phase — backend deployment task, before DNS cutover.

---

## BACKEND-2: TLS Certificate Renewal Breaks a Service Silently

**What goes wrong:** Let's Encrypt certs expire every 90 days; certbot renewal hooks must restart/reload nginx **and** coturn (coturn needs its own cert files, often a separate copy or symlink, and does not auto-reload on Let's Encrypt renewal unless explicitly wired). A common failure: nginx renews and reloads fine (its automated hook works), but coturn's cert reference goes stale because nobody wired a `--deploy-hook` for it — TURN/TLS quietly stops working for the subset of players who need it (which is disproportionately the mobile/CGNAT players CRIT-2 already flagged as fragile), while the game "seems fine" for testers on WiFi with successful direct P2P.

**Warning signs:** Only one certbot deploy-hook exists (for nginx); coturn's `cert`/`pkey` config lines point at a path that isn't part of the renewal hook chain; no monitoring/alerting on certificate expiry; no synthetic TURN connectivity test running on a schedule.

**Prevention:**
1. Single certbot deploy-hook script that restarts/reloads **every** TLS-terminating service on the box (nginx, coturn, and Kong/Supabase if it terminates TLS itself rather than behind nginx).
2. Add a scheduled synthetic check (daily) that actually performs a TURN allocation over TLS and alerts if it fails — cert expiry is silent until someone can't connect.
3. Keep an expiry-date dashboard/alert (e.g., a cron job emailing 14 days before expiry) as a second line of defense independent of the renewal automation.

**Mitigating phase:** "Go-live multiplayer" phase, backend hardening sub-task.

---

## BACKEND-3: Resource Contention on a Single Box (coturn Relay Bandwidth vs. Postgres vs. Go Signaling)

**What goes wrong:** Self-hosted Supabase alone recommends 4GB RAM/2 CPU minimum, 8GB/4 CPU for anything production-like, and runs ~10-12 containers (Postgres, GoTrue, PostgREST, Realtime, Storage, Kong, etc.). Add coturn (which becomes CPU/network-bound the moment TURN relay is actually used — every relayed byte of a 2-4 player session's voice/game-state traffic is proxied through this one box's NIC) and the Go signaling service. On a single modest Linux VPS, a burst of several concurrent relayed sessions (worst-case: all players on CGNAT, all sessions needing full relay) can saturate the NIC or CPU, causing Postgres/auth latency spikes that look like "the friends list is broken" when the actual root cause is TURN relay traffic starving the box.

**Warning signs:** No resource-isolation (cgroups/containers with CPU/memory limits) between coturn and Supabase; no bandwidth monitoring on the box; load-tested only with a handful of manual sessions, never with the worst-case "everyone needs full relay" scenario; single systemd/docker-compose stack with no per-service resource caps.

**Prevention:**
1. Set explicit resource limits per service (Docker `--memory`/`--cpus`, or cgroup slices for coturn/Postgres) so one noisy neighbor can't starve auth/signaling.
2. Budget bandwidth explicitly: at 2-4 players fully relayed, estimate worst-case Mbps per session (voice + WebRTC data channel game-state) × max concurrent sessions the single host is expected to support, and confirm the VPS's actual network tier covers it with headroom.
3. Monitor (even simple `vnstat`/`node_exporter` + a dashboard) CPU, memory, and bandwidth on the shared box from day one of going live — don't wait for a complaint to discover the box is the bottleneck.
4. Consider (if budget allows) separating coturn onto its own small VPS if relay usage in practice is higher than expected — the architecture doc's "must be horizontally scalable later" constraint already anticipated this; treat "split off coturn" as the first, cheapest scaling lever if BACKEND-3 symptoms appear.

**Mitigating phase:** "Go-live multiplayer" phase — deployment + a post-launch monitoring task; also informs "Reliability hardening" phase if load issues surface during real-device validation.

---

## BACKEND-4: Open Signaling/TURN Endpoints Get Abused Even at Small Scale

**What goes wrong:** A publicly reachable WebSocket signaling endpoint and a publicly reachable TURN server are both attractive abuse targets independent of Cubicraftia's actual player count: (a) TURN servers with weak/no authentication get used by *third parties* as UDP reflection/amplification DDoS tools (attacker sends spoofed-source unauthenticated STUN/Allocate requests; server replies with a larger packet at the spoofed victim — well documented ~4x amplification pattern); (b) an open signaling WebSocket accepting connections from anyone can be hammered with junk session-creation requests, exhausting the 200-session cap or the box's file descriptors, well before any real player is affected.

**Warning signs:** coturn started with `no-auth` or without `use-auth-secret`/HMAC credentials for testing and the flag never got removed for production; no rate limiting on the signaling WebSocket's session-creation path; coturn version predates 4.14.0's per-source rate limit on 401 responses; firewall allows the full UDP relay range from *any* source without any connection-tracking/rate limit at the network level.

**Prevention:**
1. Confirm HMAC-based short-lived TURN credentials (already an implemented v1.0 design decision per STACK.md) are actually wired end-to-end in the deployed config — verify with an external scan/test that anonymous TURN allocation is refused.
2. Add `iptables`/`nftables` rate limiting on UDP to the relay port range as a network-level backstop, independent of coturn's own config (coturn's own limits can be bypassed by spoofed-source floods that never complete the coturn-level auth handshake).
3. Rate-limit and cap concurrent unauthenticated connections on the Go signaling WebSocket endpoint (already JWT-gated per STATE.md, but confirm the JWT check happens *before* any expensive per-connection allocation, not after).
4. Consider Cloudflare (or equivalent) in front of the signaling HTTP(S)/WSS endpoint for basic DDoS absorption — TURN's raw UDP can't go through a typical CDN, so this only helps the signaling/Supabase HTTP surface, not the TURN port itself.

**Mitigating phase:** "Go-live multiplayer" phase, security-hardening sub-task, before DNS/public launch.

---

## BACKEND-5: No Tested Disaster Recovery for the One Box

**What goes wrong:** Everything (signaling, coturn, Supabase/Postgres friends-graph, DNS-adjacent config) lives on one Linux host. If the host is compromised, the disk fails, or the hosting account lapses, there is no rehearsed recovery path. This is PROCESS-2 from the v1.0 research, now concretely urgent because the box is about to go from "dev-local" to "the thing real friend groups depend on to find each other."

**Warning signs:** No off-box database backup exists yet (Postgres friends graph, invite tokens, block/report records); no documented runbook for "stand up a fresh box from scratch"; SSH keys/root access/DNS registrar credentials exist only in one person's head or one password manager entry with no documented recovery contact.

**Prevention:**
1. Automated nightly off-box Postgres dump (a different provider/region than the primary VPS) — this is cheap and prevents the worst-case "friend graph gone forever" outcome.
2. A written, tested runbook: "rebuild this stack from a clean Debian/Ubuntu host in under N hours," including where secrets live and how DNS gets repointed.
3. Document bus-factor items explicitly (per v1.0 CRIT-5 prevention): domain registrar login, DNS provider, SSH keys, TURN/JWT secrets, Supabase service-role keys — written down somewhere durable, not just in the operator's memory.

**Mitigating phase:** "Go-live multiplayer" phase — should be a checklist item before DNS cutover, not an afterthought.

---

# WebRTC-Over-Internet Pitfalls

## NET-1: Headless/CI Failover Tests Validate Logic, Not Real Network Behavior

**What goes wrong:** STATE.md records the host-failover state machine converging in under 100ms in headless GUT tests — genuinely good evidence the *logic* is correct. But headless tests run all peers in the same process/loop with no real network, no packet loss, no jitter, and no actual ICE renegotiation. The real failure modes that matter for v1.2 — a host disappearing mid-session on a real lossy 4G connection, ICE candidates needing to be re-gathered and re-exchanged through the signaling server during migration, ENet fallback vs WebRTC renegotiation timing — are **entirely unvalidated** by the existing test suite. This is precisely why "6 multi-device WebRTC tests" are still marked `human_needed` in the deferred-items table.

**Warning signs:** Team treats the headless failover SLA result as sufficient proof of production readiness; no test plan exists for host-migration specifically over real cellular/CGNAT links; "it passed in CI" used as a go-live gate without a corresponding real-device pass.

**Prevention:**
1. Explicitly budget the "Real-device validation" phase's 6 deferred WebRTC tests as their own workstream with real, geographically-separated test devices on real ISPs/carriers (not all on one office WiFi) — same-LAN testing hides exactly the NAT-traversal and relay-fallback problems that matter.
2. Specifically test host failover *while* the outgoing host is on a bad connection (throttled/lossy, not just killed cleanly) — clean-kill failover and lossy-link failover are different failure classes.
3. Track ICE renegotiation time during failover as its own metric, separate from the in-process state-machine convergence time already measured.

**Mitigating phase:** "Real-device validation" phase (already scoped in v1.2 target features) — this pitfall is the reason that phase exists; don't let it get compressed.

---

## NET-2: Symmetric NAT / CGNAT Still Breaks Direct P2P Even With STUN Working

**What goes wrong:** Carrier-grade NAT (the majority of mobile carriers) commonly presents as symmetric NAT: the external port mapping differs per destination, so a STUN-discovered server-reflexive candidate for peer A talking to the STUN server is *not* the same mapping peer B will see — hole-punching fails even though STUN itself "worked." This was already flagged CRIT-2 in v1.0 research as a design-time risk; the v1.2-specific version of this pitfall is **operational**: the deployed coturn must actually be reachable and correctly configured as the fallback, or the design intent (TURN relay when direct fails) becomes a silent failure with no fallback rather than a graceful degrade.

**Warning signs:** Real-device tests only performed on WiFi-to-WiFi pairs; no test pairs both peers on cellular data from different carriers (the worst and most realistic case for two friends playing from different locations); "relay badge" UI (already a deferred v1.0 UAT item) never actually exercised because TURN never got triggered in testing.

**Prevention:**
1. Explicitly construct a test matrix cell for "both peers on cellular, different carriers" — this is the single most important untested combination, and the one most likely to actually occur among real friend groups.
2. Verify the previously-implemented HMAC TURN credential flow actually results in a successful *relayed* connection end-to-end on a real device, not just that coturn issues credentials.
3. Make the relay badge / "you're on relay, using more data" UI functionally verified during this same real-device pass — it was deferred specifically because TURN was never triggered in earlier testing.

**Mitigating phase:** "Real-device validation" phase.

---

## NET-3: TURN Relay Bandwidth Cost Was Budgeted as "Low" But Reality Depends on Actual Session Mix

**What goes wrong:** The architecture assumed TURN relay would be the exception, not the rule, to keep hosting costs low (a stated project constraint). If real-world CGNAT prevalence among the actual friend-group userbase is higher than the design assumed (a real risk — CGNAT usage varies heavily by country/carrier and skews upward over time as IPv4 exhaustion continues), the single Linux host's bandwidth bill and CPU load from constant relaying could be materially higher than planned, silently degrading everyone's experience (see BACKEND-3) rather than showing up as an obvious line-item cost until observed.

**Warning signs:** No telemetry on relay-vs-direct connection ratio in real usage; hosting cost/bandwidth plan doesn't have a "what if 50%+ of sessions need relay" contingency; "session recovery" and "reconnect flows" work (already in scope) doesn't specifically account for a relay connection dropping and needing to re-establish (relay connections can be less stable under NAT-rebinding than a stable home connection).

**Prevention:**
1. Instrument the direct-vs-relay ratio from day one of going live (this doubles as a useful ongoing health metric, not just a v1.2 concern).
2. Set an explicit bandwidth/cost alert threshold on the host so a spike in relay usage is visible before it becomes an outage.
3. Treat "relay-heavy usage" as a plausible outcome to design reconnect/session-recovery flows around, not an edge case.

**Mitigating phase:** "Reliability hardening" phase.

---

# Code-Signing & Notarization Pitfalls

## SIGN-1: macOS Notarization/Stapling Rejections (Godot-Specific)

**What goes wrong:** Godot's macOS export flow does not fully automate notarization-and-staple; multiple real-world Godot GitHub issues report notarization failures from: MFA-enabled Apple IDs needing an **app-specific password** rather than the account password, incorrect Team ID in the codesign identity field, unaccepted updated Apple Developer Program terms silently blocking notarization submission, and "the signature does not include a secure timestamp" / "the signature of the binary is invalid" errors from subtly wrong signing-identity configuration. Godot does not automatically staple the notarization ticket to the `.app` after Apple approves it — a missed manual step here means a build that *passed* notarization but still triggers a Gatekeeper block on a machine without network access (stapling exists precisely for offline verification).

**Warning signs:** CI export job signs and submits for notarization but the pipeline doesn't include an explicit `xcrun stapler staple` step; no automated check that `spctl -a -vvv` (Gatekeeper assessment) passes on the final artifact; Apple Developer account has MFA and CI is using the plain account password instead of an app-specific password; nobody has re-run the export since last accepting updated Apple Developer Program terms (a routine, easy-to-miss gate).

**Prevention:**
1. CI pipeline must include, in order: codesign → notarize (`xcrun notarytool submit --wait`) → staple (`xcrun stapler staple`) → verify (`spctl -a -vvv` + `xcrun stapler validate`). Treat any of these four steps failing as a hard CI failure, not a warning.
2. Use an app-specific password (generated at appleid.apple.com) for CI notarization credentials, never the primary account password.
3. Confirm Team ID and signing identity are pulled from a single source of truth (export_presets.cfg or CI secret), not hand-typed per run.
4. Add a periodic (e.g., monthly) canary CI job that just re-runs the full sign+notarize+staple pipeline even without a new release, specifically to catch "Apple changed the terms and now silently blocks submission" before a real release is blocked by it.

**Mitigating phase:** "Desktop direct download" phase.

---

## SIGN-2: Windows SmartScreen Reputation Cannot Be Bought — EV Certificates No Longer Bypass It

**What goes wrong:** As of the 2024 policy change (still in effect through 2026), Extended Validation (EV) certificates **no longer grant an automatic SmartScreen reputation bypass** — that shortcut was removed. Both EV and standard OV certificates now go through the same reputation-building process, based on unique download/execution counts of that specific file hash. A brand-new indie game's first release **will** show a SmartScreen warning ("Windows protected your PC") regardless of certificate type, until enough real users have run that exact build without reports of malicious behavior. Paying $400+/year for an EV cert specifically to avoid this warning is no longer effective and is a wasted budget line if that's the only reason for the purchase.

**Warning signs:** Budget/plan includes an EV certificate specifically framed as "so users don't see the warning"; team is surprised when the first tagged release still shows SmartScreen despite being signed; no plan for how build-hash churn (every new signed release resets the reputation clock for that specific file) interacts with the "auto-update" feature — each auto-updated build is a *new* file hash needing to rebuild reputation from zero unless a mechanism avoids it.

**Prevention:**
1. Sign with a standard (OV, not EV) certificate — cheaper, same practical SmartScreen outcome for a fresh indie release.
2. Set expectations explicitly with the community: first release(s) will show a SmartScreen prompt; document the click-through ("More info → Run anyway") in the download page/FAQ rather than trying to engineer it away.
3. Consider Microsoft's Trusted Signing / Artifact Signing service (no hardware token, CI-friendly, cheaper than EV+HSM) if signing is needed for other reasons (driver-level trust, enterprise policy) beyond SmartScreen specifically.
4. Be aware that **every new signed build is a new reputation-building instance** — if auto-update ships frequent point releases, SmartScreen warnings may recur on each one until that specific binary accumulates enough clean downloads; this is a real UX cost of a frequent auto-update cadence, not a one-time problem to solve and forget.

**Mitigating phase:** "Desktop direct download" phase + informs "Auto-update" phase design (frequent-release cadence tradeoff).

---

## SIGN-3: Android Keystore Loss = Permanent Publishing Lockout (Unless Enrolled in Play App Signing)

**What goes wrong:** This is the single most catastrophic, irreversible signing failure mode across all platforms. If Cubicraftia's Android release is **not** enrolled in Google Play App Signing, and the upload keystore (`.jks`/`.keystore` file + password) is lost or corrupted, there is **no recovery path** — the app cannot ever be updated again under that package ID; the only option is publishing as a brand-new app listing (losing all reviews, install history, and the store URL). If it **is** enrolled in Play App Signing, a lost *upload* key (as distinct from the Google-held *app signing* key) can be reset via a Play Console request (requires uploading proof and a manual Google review, taking anywhere from minutes to 1-2 business days) — but this recovery path only exists because Google, not the developer, custodies the actual signing key.

**Warning signs:** CI/export pipeline generates or stores the Android keystore in exactly one place with no backup; nobody has verified Play App Signing enrollment status before the first upload; keystore password stored only in one person's password manager with no documented recovery contact; `.gitignore`/CI secrets audit never explicitly confirmed the keystore file is backed up somewhere durable and encrypted.

**Prevention:**
1. **Enroll in Google Play App Signing on the very first upload** — this is a one-time decision made at first release and is by far the most important single action here; skipping it is the sole cause of "permanent lockout" horror stories.
2. Back up the upload keystore (encrypted) in at least two independent, durable locations (e.g., a password manager vault the operator controls + a second offline copy) — treat it with the same care as the domain registrar credentials from BACKEND-5.
3. Document the exact keystore alias, password, and key password alongside the backup (a keystore file alone, without its passwords, is equally useless).
4. Confirm the CI pipeline reads the keystore from a secret store (GitHub Actions secrets, per existing CI patterns in this repo) rather than committing it or leaving it only on one developer's machine.

**Mitigating phase:** "Mobile app stores" phase — this must be nailed down at the very first Android upload, not retrofitted later.

---

## SIGN-4: iOS Provisioning Profile / Entitlements Mismatches Block Submission Late

**What goes wrong:** iOS signing requires a matching chain of: Apple Developer Team ID, App ID (with the exact bundle identifier and entitlements — e.g., push notifications, associated domains for Universal Links which v1.2 explicitly needs for the "one download link"/deep-link flow), a provisioning profile encoding all of the above, and a distribution certificate. Any mismatch (bundle ID typo, missing associated-domains entitlement for the Universal Links flow, expired provisioning profile, wrong distribution vs. development profile type) produces a rejection or an Xcode/altool upload failure, often with an error message that doesn't clearly point at the actual root cause. STATE.md already notes `no-ios-preset` as a locked decision (no iOS export preset existed as of v1.0/v1.1, deferred specifically to this phase) — meaning the entire iOS signing chain is being stood up for the first time in v1.2, with no prior working baseline to diff against when something breaks.

**Warning signs:** Universal Links (`apple-app-site-association` well-known file) not tested until submission time, even though it's needed for the deep-link/one-download-link feature; App ID capabilities configured in the Apple Developer portal don't match what's requested in the exported `.entitlements` file; provisioning profile downloaded once and never regenerated after an App ID capability change (profiles must be regenerated any time the App ID's capabilities change).

**Prevention:**
1. Stand up the iOS signing chain and a minimal TestFlight build *before* wiring the full feature set — validate the mechanics (Team ID, App ID, entitlements, profile, cert) work end-to-end on a trivial build first, so the "does signing work at all" question is answered independently of "does the game work."
2. Test the Universal Links `.well-known/apple-app-site-association` file and Android App Links equivalent (both already flagged as a deferred v1.0 item: "iOS Universal Links + Android App Links `.well-known` server config") as their own standalone verification step, since these depend on the *server* (cubicraftia.com) as much as the app.
3. Re-generate the provisioning profile any time an App ID capability changes; don't assume a profile downloaded weeks ago is still valid after even a small entitlements change.
4. Keep the iOS CI export job's error output verbose and logged — entitlement mismatches often produce generic-looking Xcode errors that require reading the full log, not just the summary line.

**Mitigating phase:** "Mobile app stores" phase — sequence a minimal-viable-signing spike before full feature wiring.

---

# App Store Submission Pitfalls (Kids-Adjacent, UGC, IAP)

## STORE-1: "Friends-Only" Does Not Exempt the App from UGC Moderation Requirements (confirmed, escalated from v1.0 CRIT-4)

**What goes wrong:** This was already flagged in v1.0 research; the v1.2-specific escalation is that a **public store listing** is a much higher-visibility, harder-to-walk-back commitment than a private GitHub repo — a rejected or later-pulled store listing is publicly visible and reputationally costly in a way a code review comment never was. Apple's Guideline 1.2 (Safety — User-Generated Content) requires: content filtering, a flagging/reporting mechanism, a user-block mechanism, a published EULA prohibiting objectionable content, and a developer commitment to act on reports — for **any** app allowing user-to-user content exchange, and Apple has explicitly clarified this includes friends-based social features, not just open/anonymous chat. Per STATE.md, block/report/profanity-filter/parental-consent are already **code-complete** (Phase 5) — the v1.2-specific risk is not "we forgot to build this," it's "these systems have never been exercised against a live, internet-reachable backend, and the App Store reviewer will test them against the actual production service, not a local dev build."

**Warning signs:** Store submission scheduled without first confirming the block/report/profanity/consent flows work end-to-end against the **deployed** production Supabase/Go backend (not just against a local dev instance); no fresh reviewer-facing test account with a populated friends list/session prepared for the App Review team to actually exercise these features (Apple reviewers commonly need working demo credentials for social/UGC features, especially ones gated behind "friends only" — a reviewer who cannot get past an empty friends list cannot verify the moderation features exist).

**Prevention:**
1. Explicitly re-verify (not re-implement) block/report/profanity/consent against the live production backend as part of the "Real-device validation" or a dedicated pre-submission QA pass — this is a deployment-verification task, not a development task, since the code itself is already done.
2. Prepare App Review demo instructions/credentials that let a reviewer reach a populated session and exercise chat, block, and report without needing a second real device or friend.
3. Confirm the EULA and Privacy Policy are actually live and linked from the store listing metadata (not just drafted) before submission — this is one of the gating attorney-review items already flagged as deferred in STATE.md.

**Mitigating phase:** "Mobile app stores" phase, pre-submission QA sub-task; depends on the attorney review of EULA/Privacy Policy (already a listed operator/legal prerequisite).

---

## STORE-2: Apple Kids Category / Age-Rating Rules Are Stricter Than General-Audience Rules, and 2026 Brought a Ratings Overhaul

**What goes wrong:** If Cubicraftia is submitted under (or defaults into, via its age-rating questionnaire answers) Apple's Kids Category or a low age-rating band, additional rules apply that are easy to violate by accident: no purchasing opportunities, no external links, and no other "distractions" unless placed behind a parental gate; third-party analytics/ads SDKs targeting children are restricted; Apple's 2025→2026 App Store age-rating system overhaul introduced new bands (13+, 16+, 18+) and a more detailed content questionnaire, with **all developers required to update ratings by January 31, 2026** — meaning the age-rating questionnaire itself, and the rules that follow from the answer, may differ from what older tutorials/blog posts describe. Given Cubicraftia's UGC (chat, custom builds, avatar names) and multiplayer nature, it likely does **not** cleanly fit the Kids Category's strict "no unmoderated user-to-user communication for the youngest bands" expectations without careful configuration — submitting into Kids Category incorrectly is a common and avoidable rejection cause.

**Warning signs:** Store listing/age-rating questionnaire filled out without first deciding, deliberately, whether Cubicraftia is submitted as a general-audience app with an accurate mixed-age content rating (more likely correct given friends-only multiplayer + chat) vs. actually placed in the dedicated Kids Category (a much stricter, purpose-built program that friends-only chat-enabled multiplayer likely does not qualify for cleanly); IAP purchase flow not placed behind a parental gate if any Kids-Category-adjacent rating is chosen; COPPA parental-consent flow (already code-complete per STATE.md) not cross-checked against Apple's *own* age-rating questions, which are a separate mechanism from the in-app COPPA gate.

**Prevention:**
1. Decide explicitly and early: Cubicraftia should almost certainly be submitted as a general-audience app with an honest age rating reflecting its UGC/chat/multiplayer content (likely 12+/13+-equivalent band given unmoderated-adjacent chat exists even with filtering), **not** placed in Apple's dedicated Kids Category — the Kids Category's "no unmoderated content" bar is a poor fit for a friends-chat game and inviting extra scrutiny by opting into it is avoidable.
2. Re-run the current (2026) age-rating questionnaire fresh at submission time rather than relying on older assumptions — the questionnaire changed materially.
3. If any purchase or external-link surface is shown to users who could plausibly be under 13 (given the already-implemented under-13 COPPA gate), confirm it sits behind whatever the current parental-gate mechanism requires — cross-check this specifically with the attorney review rather than assuming the existing code-complete COPPA gate automatically satisfies Apple's separate age-rating-driven requirements.

**Mitigating phase:** "Mobile app stores" phase — age-rating/category decision should be an explicit, documented task, not an incidental questionnaire click-through.

---

## STORE-3: Google Play Families Policy + New 2026 State Age-Verification Laws

**What goes wrong:** Google Play's Families Policy requires disclosure of any personal/sensitive data collection (including via third-party SDKs), restricts which advertising SDKs may be used if the app's target audience includes children, and restricts transmission of certain identifiers from users of unknown age. Separately and newly relevant: **starting January 1, 2026, new state laws (Texas, Utah, Louisiana specifically named in current guidance) require Google Play developers to verify user ages and obtain parental approval for minors** as a *platform-level* requirement layered on top of Google's own Families Policy — this is in addition to, not a replacement for, the COPPA-driven consent flow Cubicraftia already built. This is a fast-moving 2026 policy area; assume the specific mechanics (which states, what verification method Google accepts, deadlines) have continued to evolve past this research's cutoff and must be re-checked against live Play Console guidance at submission time, not against this document.

**Warning signs:** Target-audience/content-rating declaration in Play Console filled out without cross-checking against the *current* Families Policy and the new state-law requirements; assumption that the existing COPPA email-plus consent flow automatically satisfies Google's separate age-verification mechanism; ad SDK (if any is ever added later) not checked against Google's Families Ads Program self-certification requirement.

**Prevention:**
1. Treat Google Play's Data Safety form and target-audience declaration as a **fresh** compliance exercise at submission time, re-reading current Play Console Help pages rather than relying on older documentation.
2. Explicitly confirm with the attorney review whether the existing COPPA email-plus consent mechanism (already built, per STATE.md) needs any Android-specific supplement to satisfy the new state-level age-verification laws taking effect in 2026.
3. If no ad SDKs are used (currently true — IAP only, no ads, per the locked pricing model), that removes a large surface of Families Ads Program complexity; keep it that way unless a future milestone deliberately revisits ads.

**Mitigating phase:** "Mobile app stores" phase, Play Console submission sub-task, coordinated with the attorney review.

---

## STORE-4: Privacy Nutrition Labels (Apple) / Data Safety Form (Google) Must Match Actual Data Practices Exactly

**What goes wrong:** Both stores require a structured, store-listing-level disclosure of exactly what data is collected, why, whether it's linked to identity, and whether it's shared with third parties. This must be **audited against the real, deployed system** (Supabase auth fields, friend graph, any crash/telemetry logging, IP addresses logged by coturn/signaling for abuse-prevention purposes) — not against an assumption of what the system does. A mismatch between the declared label and actual behavior is both a store-policy violation (can trigger removal even after approval) and a real legal exposure given the COPPA/GDPR-K context.

**Warning signs:** Nobody has produced an actual data-inventory document cross-referencing every Supabase table/column, every log line the Go signaling server writes, and every client-side stored value, against what the privacy label will claim; the label is drafted from the privacy policy's prose rather than from a technical audit of the schema and logs.

**Prevention:**
1. Produce a literal data inventory (table/column/log-field level) before drafting either store's privacy disclosure — this is materially different work from writing the Privacy Policy prose, even though both should obviously agree.
2. Specifically account for data that's easy to forget: IP addresses in TURN/signaling logs (retained for abuse-prevention — for how long? disclosed?), crash reports if any crash-reporting SDK is added, DOB-derived `is_under_13` boolean (already correctly minimized per the `dob-raw-never-sent` decision in STATE.md — a good existing precedent to point the privacy-label audit at as a model of "minimal disclosed data").
3. Re-run this audit any time the backend schema changes materially — the label is a point-in-time snapshot that silently rots.

**Mitigating phase:** "Mobile app stores" phase, coordinated with the attorney review and the EULA/Privacy Policy finalization.

---

# Auto-Update / Version-Match Pitfalls

## UPDATE-1: Peers on Mismatched Builds Fail to Connect or, Worse, Connect and Desync

**What goes wrong:** Two failure modes, and the second is worse than the first: (a) the client correctly refuses to connect a mismatched-version peer, producing a clear "please update" error — annoying but safe; (b) the client's version/protocol check is incomplete or the protocol change was "compatible enough" to connect but not identical, and mismatched peers connect anyway, then silently desync (different serialization of a world-save event, a new brick type one peer doesn't recognize, a chat/report protocol field one build doesn't parse) — this is far more damaging because it looks like a gameplay bug rather than a version problem, and directly compounds the already-flagged TECH-5 (host migration desync) risk from v1.0 research: a version-mismatched peer promoted to host during failover is a realistic way to trigger exactly that failure mode in production for the first time.

**Warning signs:** Version check exists but only checks a major-version number, not full build/protocol compatibility; no CI test simulates two different build versions attempting to join the same session; auto-update mechanism doesn't guarantee all connected peers finish updating before a session starts (e.g., one friend updates immediately, another defers the update and joins anyway).

**Prevention:**
1. Version/protocol-compatibility check must be **explicit and strict**: refuse the join outright on any mismatch, with a clear in-UI "your friend needs to update" or "you need to update" message — do not attempt best-effort compatibility across versions for a friends-only 2-4 player game; the complexity of a Minecraft-style `ViaVersion`-equivalent cross-version translation layer is not worth building for this project's scale.
2. Add a dedicated integration test that starts two different simulated build/protocol versions and asserts the join is cleanly rejected (not silently allowed, not crashed) — this closes the gap the naive per-feature GUT tests don't cover.
3. Auto-update should be enforced (or at minimum strongly nagged, ideally blocking session-join until updated) rather than optional, specifically because this is a P2P game where "my friend didn't update" is the other player's problem too, unlike a client-server game where the server enforces a single version for everyone.
4. Specifically test the failover case with a version-mismatched peer as one of the failover candidates — confirm the election logic either excludes mismatched-version peers from host eligibility or (simpler) the version check already prevented them from being in the session at all.

**Mitigating phase:** "Auto-update" phase, in direct coordination with "Reliability hardening" (host-failover) work — treat version-mismatch-during-failover as one of the explicit test scenarios for that phase, not a separate afterthought.

---

## UPDATE-2: Save/Protocol Compatibility Breaks Across Auto-Updated Versions

**What goes wrong:** Once auto-update ships and players are expected to always be near-current, it becomes easy to make a schema or protocol change in a later patch assuming "everyone will auto-update anyway" — but a player who was offline (no internet, or deliberately deferred an update) opens an old save with a newer client, or vice versa, and the existing `schema_version`-based migration path (already built per `03-01` decisions in STATE.md) needs to keep working for every version jump, not just the one that shipped it.

**Warning signs:** Migration code only handles the immediately-previous schema version, not N-versions-back; no CI test exercises "open a v1.0-era save file with the current build" as a regression check; auto-update assumed to make old-save compatibility a non-issue, so the discipline around `_migrate_N_to_N+1` chains (already established, per STATE.md's `v2-table-stmts-helper` pattern) isn't explicitly required to continue for every future schema bump.

**Prevention:**
1. Keep every schema migration function in the chain, never delete an old migration step, even once auto-update makes "everyone's current" the common case — the whole point of auto-update is to reduce this risk, not eliminate the need to handle it.
2. Add a regression test fixture: a real save file from the oldest still-supported version, re-opened by the current build, asserted to migrate cleanly, re-run in CI on every release.
3. Explicitly decide and document a support window ("we guarantee migration from the last N major versions") rather than leaving it open-ended.

**Mitigating phase:** "Auto-update" phase.

---

# Trademark-at-Public-Listing

## TRADEMARK-1: A Public Store Listing Is a Materially Higher Trademark-Risk Event Than a Private Repo (escalated from v1.0 CRIT-1)

**What goes wrong:** v1.0 research already flagged (CRIT-1) that LEGO is an aggressive trademark enforcer and that visual/naming similarity needs active mitigation. The v1.2-specific escalation: **a public, searchable, indexed Apple App Store / Google Play listing is a fundamentally different exposure than an open-source GitHub repo.** LEGO's enforcement teams (and Mojang's, for the Minecraft-adjacent aesthetic) monitor app store listings far more actively than they monitor GitHub — store listings are exactly the kind of consumer-facing, monetized (even at €1), publicly discoverable product that trademark enforcement is designed to catch, whereas a GitHub repo requires someone to actively search code hosting to find it. Additionally, both Apple and Google have their own trademark-complaint/takedown processes independent of any lawsuit — a competitor or rights-holder can file a takedown directly with the store, which can result in the *listing itself* being pulled pending resolution, entirely separate from and faster than any court process.

**Warning signs:** The v1.0-flagged "trademark clearance check" is still listed only as "a pre-public-release gate, currently in Phase 5's pre-launch checklist" (per STATE.md's open-questions section) rather than as a completed, dated action; store screenshots/marketing copy/app icon not yet reviewed specifically against the CRIT-1 visual-divergence checklist (minifig proportions, stud terminology, color palette, disclaimer text) before submission assets are finalized; app store keywords/description drafted without checking they don't use "Lego" or "Minecraft" even descriptively/comparatively (store review guidelines and trademark risk both penalize this, for different reasons — Apple/Google review can reject keyword-stuffing on a competitor's trademark as misleading metadata, independent of LEGO/Mojang's own trademark complaint risk).

**Prevention:**
1. Treat the "trademark clearance search on the final name across US/EU/relevant markets" (already identified as an open item in STATE.md Q8) as a **hard prerequisite** for store submission specifically — not just a "nice to do before public release" item, since store submission is the actual public-release moment, and a rejected/pulled store listing after investing in signing, IAP wiring, and review is a far more expensive failure than catching a name conflict before submitting.
2. Do a dedicated visual/copy audit of every store-facing asset (icon, screenshots, description, keywords, promotional text) against the CRIT-1 checklist from the v1.0 research immediately before submission — screenshots are exactly the kind of asset that gets scrutinized by both automated review systems and human rights-holder monitoring, and are easy to forget to re-audit if they were produced by a different phase/team than the one that did the original art-direction trademark review.
3. Add the "not affiliated with the LEGO Group or Mojang/Microsoft" disclaimer explicitly to both store listings' description text and the EULA, not just in-app — the store listing itself is the artifact that gets indexed and found by automated trademark-monitoring tools and human search alike.
4. If a cease-and-desist or store takedown notice does arrive post-launch, do not contest it defensively while continuing to sell — pull the flagged asset/listing immediately, consult the attorney (already engaged for COPPA/EULA review — extend scope), and treat it as urgent, not as a queued issue.

**Mitigating phase:** "Mobile app stores" phase — the trademark clearance search and the store-asset visual/copy audit should both be explicit, checked-off gating tasks before submission, coordinated with (but distinct from) the COPPA/EULA attorney review already scheduled.

---

# Phase-Mapping Summary

| Pitfall | Severity | Mitigating Phase / Workstream |
|---|---|---|
| HARD BLOCKER 1: GPL-3.0 vs Apple App Store | CRITICAL — resolve before iOS work starts | Licensing decision (phase-0 gate, before "Mobile app stores") |
| HARD BLOCKER 2: IAP StoreKit mandate | High | "Mobile app stores" — IAP wiring |
| BACKEND-1: Port 443 contention (coturn/nginx/Supabase) | High | "Go-live multiplayer" — backend deployment |
| BACKEND-2: TLS renewal misses coturn | High | "Go-live multiplayer" — backend hardening |
| BACKEND-3: Resource contention, single box | Medium-High | "Go-live multiplayer" + ongoing monitoring |
| BACKEND-4: Open endpoint abuse / DDoS | High | "Go-live multiplayer" — security hardening |
| BACKEND-5: No disaster recovery | High | "Go-live multiplayer" — pre-DNS-cutover checklist |
| NET-1: Headless tests ≠ real network | Critical | "Real-device validation" |
| NET-2: Symmetric NAT/CGNAT operational failure | Critical | "Real-device validation" |
| NET-3: TURN bandwidth cost reality-check | Medium | "Reliability hardening" |
| SIGN-1: macOS notarization/stapling | High | "Desktop direct download" |
| SIGN-2: Windows SmartScreen reputation | Medium | "Desktop direct download" + "Auto-update" |
| SIGN-3: Android keystore loss lockout | Critical (irreversible) | "Mobile app stores" — first upload |
| SIGN-4: iOS provisioning/entitlements | High | "Mobile app stores" — signing spike first |
| STORE-1: UGC moderation live-verification | Critical | "Mobile app stores" — pre-submission QA |
| STORE-2: Apple Kids Category / age rating | High | "Mobile app stores" — category decision |
| STORE-3: Google Play Families + state age laws | High | "Mobile app stores" — Play submission |
| STORE-4: Privacy labels vs. actual data practices | High | "Mobile app stores" — data inventory |
| UPDATE-1: Version-mismatched peers desync | Critical | "Auto-update" + "Reliability hardening" |
| UPDATE-2: Save/protocol compatibility drift | Medium | "Auto-update" |
| TRADEMARK-1: Public listing risk escalation | Critical | "Mobile app stores" — clearance + asset audit |

---

# Quick Reference: "If you forget everything else, remember these five"

1. **Add the GPLv3 §7 App-Store exception clause to LICENSE now, while copyright is still solely held by one person.** This is the cheapest, highest-leverage, most time-sensitive action in this entire document — it gets exponentially harder once external contributors land PRs. Android/Google Play has no equivalent problem; this is Apple-only.
2. **coturn needs port 443 too, and its own certbot renewal hook** — the single most commonly missed line item in single-host WebRTC/TURN deployments, and it silently disables the fallback path for exactly the CGNAT users who need it most.
3. **Enroll in Google Play App Signing on the very first Android upload.** Skipping this is the sole cause of "lost my keystore, app is dead forever" horror stories; it costs nothing and has no downside.
4. **Headless failover tests prove the state machine is correct; they prove nothing about real cellular/CGNAT/lossy-link behavior.** Budget the real-device validation phase as seriously as the backend deployment phase — this is where CRIT-2 (from v1.0) either gets confirmed solved or discovered to still be broken.
5. **A public store listing is a materially bigger trademark-exposure event than a GitHub repo.** Do the trademark clearance search and the store-asset (icon/screenshots/copy) visual audit as explicit gating tasks before submission, not as a vague "pre-launch checklist" line item.

---

# Sources

## GPL / Apple App Store Licensing Conflict
- [VLC developer takes a stand against DRM enforcement in Apple's App Store — FSF](https://www.fsf.org/blogs/licensing/vlc-enforcement)
- [Solving the Apple App Store Incompatibility with the GPL — Network World](https://www.networkworld.com/article/751206/opensource-subnet-solving-the-apple-app-store-incompatibility-with-the-gpl.html)
- [The GPL, the App Store, and you — Engadget](https://www.engadget.com/2011-01-09-the-gpl-the-app-store-and-you.html)
- [More about the App Store GPL Enforcement — FSF](https://www.fsf.org/blogs/licensing/more-about-the-app-store-gpl-enforcement)
- [GPL Enforcement in Apple's App Store — FSF](https://www.fsf.org/news/2010-05-app-store-compliance)
- [The GPL and Commercial App Stores: Time for a Reconsideration — App Fair Project](https://appfair.org/blog/gpl-and-the-app-stores/)
- [FSF takes on Apple's App Store over GPL — LWN.net](https://lwn.net/Articles/391423/)
- [Hacker News discussion — GPLv3/LGPLv3 iOS App Store anti-tivoization](https://news.ycombinator.com/item?id=10896773)
- [Hacker News discussion — Apple's App Store is identical to the TiVoization problem](https://news.ycombinator.com/item?id=16574208)
- [Add app store exception to license — wger-project/flutter GitHub issue #10](https://github.com/wger-project/flutter/issues/10)
- [Adding a license exception — SagerNet/sing-box GitHub issue #1695](https://github.com/SagerNet/sing-box/issues/1695)
- [GPLv3 incompatible with App Store ToS — tigase/siskin-im GitHub issue #103](https://github.com/tigase/siskin-im/issues/103)
- [Godot Engine — License](https://godotengine.org/license/)

## coturn / TURN Deployment
- [Coturn behind NAT, correct firewall setting for a range of ports — coturn GitHub issue #1471](https://github.com/coturn/coturn/issues/1471)
- [Securing coturn: Configuration Guide — Enable Security](https://www.enablesecurity.com/blog/coturn-security-configuration-guide/)
- [TURN Security Threats: A Hacker's View — Enable Security](https://www.enablesecurity.com/blog/turn-server-security-threats/)
- [Turn Server Configuration — BigBlueButton docs](https://docs.bigbluebutton.org/administration/turn-server/)
- [Configuring a Turn Server — Synapse (Matrix)](https://matrix-org.github.io/synapse/v1.56/turn-howto.html)
- [CoturnConfig — coturn GitHub Wiki](https://github.com/coturn/coturn/wiki/CoturnConfig)

## Self-Hosted Supabase
- [Self-Hosting with Docker — Supabase Docs](https://supabase.com/docs/guides/self-hosting/docker)
- [Multiple Projects on Single Self-Hosted Supabase Instance — Supabase GitHub Discussion #38048](https://github.com/orgs/supabase/discussions/38048)
- [Cannot self host two supabase instances at the same time — Supabase GitHub Discussion #37444](https://github.com/orgs/supabase/discussions/37444)

## WebRTC / NAT Traversal
- [ICE in WebRTC: Server Setup and Relative Performance — WebRTC.ventures](https://webrtc.ventures/2022/04/ice-in-webrtc/)
- [Why Your ICE Connection Fails (And How to Debug It) — RTC Insights](https://www.rtcinsights.com/blog/ice-connection-failures/)
- [ICE always tastes better when it trickles! — webrtcHacks](https://webrtchacks.com/trickle-ice/)

## Code Signing / Notarization
- [Exporting OSX Fails Notarization — Godot Engine GitHub issue #64544](https://github.com/godotengine/godot/issues/64544)
- [Unable to export to macOS with Notarization Xcode altool — Godot Engine GitHub issue #69345](https://github.com/godotengine/godot/issues/69345)
- [How to notarize & sign your macOSX Godot app — Godot Forums](https://godotforums.org/d/37190-how-to-notarize-sign-your-macosx-godot-app)
- [SmartScreen reputation for Windows app developers — Microsoft Learn](https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/smartscreen-reputation)
- [Reputation with OV certificates and are EV certificates still the better option? — Microsoft Q&A](https://learn.microsoft.com/en-us/answers/questions/417016/reputation-with-ov-certificates-and-are-ev-certifi)
- [Google Play Console App Signing Key Lost (Recovery) — PTKD Journal](https://ptkd.com/journal/google-play-signing-key-lost)
- [Use Play App Signing — Play Console Help](https://support.google.com/googleplay/android-developer/answer/9842756?hl=en)
- [Sign your app — Android Developers](https://developer.android.com/studio/publish/app-signing)

## App Store / Play Store Policy (Kids, COPPA, Privacy)
- [Design safe and age-appropriate experiences — Apple Developer](https://developer.apple.com/kids/)
- [App Store Age Ratings Guide — Capgo](https://capgo.app/blog/app-store-age-ratings-guide/)
- [App store age verification laws for Android & iOS apps — Median.co](https://median.co/blog/new-age-verification-laws-2026)
- [App Store Age Verification Laws Trigger New Federal and State Children's Privacy Requirements — Loeb & Loeb LLP](https://www.loeb.com/en/insights/publications/2025/12/app-store-age-verification-laws-trigger-new-federal-and-state-childrens-privacy-requirements)
- [Google Play Families Policies — Play Console Help](https://support.google.com/googleplay/android-developer/answer/9893335?hl=en)
- [Data practices in Families apps — Play Console Help](https://support.google.com/googleplay/android-developer/answer/11043825?hl=en)
- [Policy announcement: April 15, 2026 — Play Console Help](https://support.google.com/googleplay/android-developer/answer/16926792?hl=en)
- [BuddyBoss — How to Resolve App Store Guideline 1.2 – User-Generated Content](https://buddyboss.com/docs/app-store-guideline-1-2-safety-user-generated-content/)

## EU DMA / Alternative Distribution
- [Update on apps distributed in the European Union — Apple Developer](https://developer.apple.com/support/dma-and-apps-in-the-eu/)
- [Apple's June 2025 EU update: one entitlement, three fees — RevenueCat](https://www.revenuecat.com/blog/growth/apple-eu-dma-update-june-2025/)
- [EU DMA Guide: Alternative iOS App Distribution (2026) — iOS Submission Guide](https://iossubmissionguide.com/eu-dma-alternative-app-distribution/)

## Version Mismatch / Save Compatibility
- [Minecraft Server Version Mismatch: Compatibility Solutions — GameTeam](https://gameteam.io/blog/minecraft-server-version-mismatch-compatibility-solutions/)
- [Palworld "Game Version Does Not Match Host" error explainer — The Spike](https://www.thespike.gg/apex-legends/beginners-guides/game-version-does-not-match-host-error)

## Prior Cubicraftia Research (referenced/escalated, not re-derived)
- `.planning/research/PITFALLS.md` (v1.0 research, 2026-05-24) — CRIT-1 (trademark), CRIT-2 (CGNAT), CRIT-3 (save corruption), CRIT-4 (UGC moderation), CRIT-5 (maintainer burnout), LEGAL-1 (license choice), PROCESS-2 (single-host SPOF)
- `.planning/STATE.md` — locked decisions, deferred items table, Phase 4/5 verification gaps
- `.planning/PROJECT.md` — constraints, trademark note, key decisions
