# Technology Stack — v1.2 "Multiplayer & Distribution" Additions

**Project:** Cubicraftia
**Milestone:** v1.2 — go-live backend + cross-platform signed distribution
**Researched:** 2026-07-08
**Scope:** NEW capabilities only. Godot 4.6, godot_voxel, WebRTC/ENet, the Go signaling server, Supabase, coturn, and SQLite are already validated in code (see root `CLAUDE.md` § Technology Stack, and this file's own v1.0 history in git blame) — not re-researched here. This file has been rewritten for v1.2; the full v1.0 rationale for the base stack lives permanently in `CLAUDE.md`.

---

## Overview

v1.2 turns three "exists in code but not deployed" pieces (Go signaling, coturn, Supabase) into a live, TLS-secured backend on the single owned host (`m1.linuxbe.com` / `cubicraftia.com`), and turns "exports locally" into "signed, notarized, store-submitted, auto-updating builds" across five platforms. Nothing here changes the client's core stack (Godot 4.6, WebRTCMultiplayerPeer, ENet, GDScript/Rust) — this is entirely deployment, signing, packaging, and distribution tooling layered on top.

Two integration facts drive most of the design:

1. **The project already has a version-stamping mechanism.** The "Build Stamp" editor plugin (commit `55dd17c`) auto-writes `version.txt` on every export and Play. This is the natural single source of truth for both auto-update checks and multiplayer version-match rejection — no new versioning scheme is needed, only new consumers of the existing artifact.
2. **The project already owns the domain and root on the deploy host.** DNS-01 Let's Encrypt challenges, subdomain routing, and `.well-known` static files for Universal/App Links are all straightforward because there is no shared-hosting or third-party DNS constraint.

Confidence is HIGH for backend deployment and desktop code signing (mature, widely documented patterns), MEDIUM for the mobile IAP plugin choice (fast-moving OSS ecosystem, one candidate library was archived and relocated mid-2026), and MEDIUM-LOW for iOS CI export automation (Godot's ecosystem tooling here is thinner than Android/desktop).

---

## Backend Deployment (Go signaling + coturn + Supabase on one host)

### Recommended topology

| Component | Role | Port(s) | Fronted by Caddy? |
|---|---|---|---|
| **Caddy 2.x** (Apache-2.0) | Single TLS-terminating reverse proxy / front door | 80, 443 | — (is the front door) |
| Go signaling server | WebSocket signaling, JWT-gated, session registry | internal (e.g. 8080) | Yes → `signal.cubicraftia.com` |
| Supabase `kong` (API gateway) | Fronts GoTrue, PostgREST, Realtime, Storage | internal 8000 | Yes → `api.cubicraftia.com` |
| Supabase `postgres` | Friends graph + auth tables | 5432, internal only | No — never expose publicly; reach via SSH tunnel for admin |
| **coturn** | STUN/TURN relay | 3478 (STUN/TURN), 5349 (TURNS), 49152-65535/udp (relay range) | No — TURN/TURNS are not HTTP; coturn terminates its own TLS on 5349 using certs obtained separately (see below) |

**Why Caddy over nginx/Traefik (HIGH confidence):** Caddy issues and renews Let's Encrypt certificates automatically with zero-config `Caddyfile` syntax (just list the domain, point to the upstream). This is a meaningfully smaller ops surface for a single maintainer than nginx + certbot cron, or Traefik's label-based Docker discovery. Since the project's ethos is "keep the single Linux host's ops burden low," Caddy is the right default. Confirmed pattern: run Supabase's own docker-compose stack unmodified, attach its `kong` container to an external Docker network Caddy also joins, and route `api.cubicraftia.com { reverse_proxy supabase-kong:8000 }`.

**coturn's TLS is a special case (MEDIUM confidence, verify at implementation time):** coturn (BSD-3) needs direct filesystem access to a cert/key pair for TURNS (TLS-over-TCP, port 5349) — it cannot sit behind a plain HTTP reverse proxy the way Kong/Go can, because TURN is not an HTTP protocol. Two viable approaches, in order of simplicity:
1. Run `certbot certonly --standalone` (or DNS-01 via the domain's registrar API) for a dedicated `turn.cubicraftia.com` name, and point coturn's `cert=` / `pkey=` config at the resulting files with a renewal hook that restarts/reloads coturn.
2. Share Caddy's certificate storage (`/data/caddy/certificates/...`) with coturn via a read-only bind mount, since Caddy already holds a valid cert for the apex domain — avoids a second ACME account/rate-limit bucket.
Given the project already controls DNS for `cubicraftia.com`, either works; approach 1 (dedicated certbot timer) is simpler to reason about and debug independently of Caddy's internal storage layout.

**Firewall discipline (HIGH confidence):** Only 80/443 (Caddy), coturn's STUN/TURN ports, and SSH should be open. Postgres (5432) and Kong's raw port (8000) must never be exposed directly — this is the single most common Supabase self-host misconfiguration flagged across current guides.

### Orchestration: docker-compose (not Kubernetes, not a PaaS layer) for the app containers, systemd for the Go binary

- **Supabase self-hosted** ships as an official `docker-compose.yml` (13 containers: Kong, GoTrue, PostgREST, Realtime, Storage, Studio, Postgres, etc.). Use it as-is — do not hand-roll a replacement. Minimum recommended: 4 GB RAM / 2 vCPU, but 8 GB / 4 vCPU is the documented comfortable floor for production; verify `m1.linuxbe.com`'s spec meets this before scheduling the deploy phase.
- **coturn**: standard Debian/Ubuntu package (`apt install coturn`) or a small dedicated container — either is fine; the package is simpler to fold into systemd for `systemctl restart coturn` on cert renewal.
- **Go signaling server**: already a single static binary per the existing stack decision — ship it as a `systemd` unit (`ExecStart=/opt/cubicraftia/signal-server`, `Restart=on-failure`), not a container. This matches "tiny memory footprint, easy single-binary deploy" from the original stack rationale and avoids adding Docker as a dependency for the one first-party service the team fully controls.
- **Caddy**: native Debian package or single static binary + systemd unit, sitting outside Docker so it can freely proxy into Docker Compose's network via an external Docker network (`docker network create proxy-net`; Supabase's compose file needs `kong` attached to it).

**Do not introduce Coolify, CapRover, Dokploy, or any self-hosted PaaS layer for this milestone (MEDIUM confidence recommendation).** These products are legitimate and popular in 2026 for exactly this "one VPS, several services" scenario (Coolify v4 ships Traefik + auto-TLS + one-click Supabase), and are worth a future look if the team's ops burden grows. But for v1.2, adding a PaaS control plane on top of three already-designed pieces (Go binary + coturn package + Supabase's own compose file) is an extra moving part with its own upgrade/security surface, contrary to the "keep it simple, single maintainer" ethos documented in the project's constraints. Revisit only if a second environment (staging) or a second host is added later.

### Secrets management

- Supabase requires unique `JWT_SECRET`, `ANON_KEY`, `SERVICE_ROLE_KEY`, `POSTGRES_PASSWORD` — generate via Supabase's own `generate-keys` script, never ship the `.env.example` placeholder values (this is flagged repeatedly as the #1 self-host security mistake in current guides).
- Store the `.env` file with `chmod 600`, owned by a dedicated non-root service user; do not commit it (already covered by existing `.gitignore` discipline for `settings.cfg`-style secrets in this repo).
- The Go signaling server's JWT signing secret and coturn's HMAC-SHA1 shared secret (already implemented per STATE.md) should be distinct from Supabase's JWT secret — no shared-secret reuse across services.
- For a single-host project of this size, a plain root-owned `/etc/cubicraftia/secrets.env` sourced by the systemd unit (`EnvironmentFile=`) is sufficient. **Do not add HashiCorp Vault or a cloud secrets manager** — that is enterprise-scale tooling disproportionate to a 200-session-cap, one-host deployment.

### DNS

Records needed on `cubicraftia.com` (already under project's control, per milestone context):
- `A`/`AAAA` for the apex + `www` → landing page
- `signal.cubicraftia.com` → Go signaling (via Caddy)
- `api.cubicraftia.com` → Supabase Kong (via Caddy)
- `turn.cubicraftia.com` → coturn's public IP (direct, not via Caddy)
- `.well-known/apple-app-site-association` and `.well-known/assetlinks.json` served from the apex over HTTPS with `Content-Type: application/json` (needed for iOS Universal Links / Android App Links deep-link fallback — see Distribution section)

---

## Code Signing & Packaging

### macOS — Developer ID + notarization (HIGH confidence)

Godot 4.6's export dialog has first-class support for this: Project → Export → macOS → **Codesign** section (Xcode codesign, Apple Team ID + Identity, found via `security find-identity -v -p codesigning`) and **Notarization** section (Xcode `notarytool`, API UUID + API Key file + Key ID from App Store Connect). Godot automates the `xcrun notarytool submit` + staple flow on export when these fields are populated — no external script needed for a manual export.

- Requires an active Apple Developer Program membership ($99/yr) — already listed as an operator prerequisite in STATE.md.
- CI note: the project's existing decision (`ci-macos-runner`) already uses `macos-latest` + native Homebrew Godot specifically to get correct Mach-O `.app` bundling — the same runner can hold the signing identity (import `.p12` into a CI keychain) and notarization API key as GitHub Actions secrets.
- Typical notarization turnaround is 5-30 minutes; CI jobs should poll `notarytool history`/`log` rather than assume synchronous completion.

### Windows — Authenticode via osslsigncode or Azure Trusted (Artifact) Signing (HIGH confidence choice; MEDIUM on which certificate provider)

Godot's export dialog has a **Code Signing** section under the Windows preset requiring `signtool.exe` (native Windows) or `osslsigncode` (any other OS, including the Linux/macOS CI runners this project already uses) plus a certificate identity.

**Certificate recommendation: Azure Trusted Signing (rebranded "Azure Artifact Signing" as of 2026), not a traditional EV cert.**
- Cost: ~$9.99/month for up to 5,000 signatures on one certificate profile (vs. $400-500/year for a traditional third-party EV cert) — a much better fit for an indie/OSS project's budget.
- As of April 2026 it's GA and self-employed individuals can apply without the previously-required 3-year business history — removes what used to be the practical blocker for solo/small-team indie developers.
- Availability: individuals in the US/Canada, organizations in EU/UK — verify current eligibility for whichever entity the project is registered under before committing (this is the one item that needs a real-world check, not just docs).
- Integration: Trusted Signing exposes a `dlib`/CLI-based signing flow (`signtool.exe` with the Trusted Signing dlib, or an equivalent `osslsigncode`-compatible path) rather than a locally-held `.pfx` — confirm the exact CI invocation against current Microsoft docs when implementing, since this is a fast-evolving Azure product name/API.
- **Known limitation:** embedded PCK exports cannot be signed (signing breaks once the PCK is embedded in the executable) — export with separate `.pck` file, not embedded, whenever code signing is required. This is already implicitly compatible with the existing CI setup since Steam-style embedded PCK was never a stated goal.

### Linux — AppImage + tarball, NOT Flatpak for v1.2 (HIGH confidence)

- **AppImage**: community export plugins exist (Godot Asset Library "Linux AppImage Export"); the simpler and more robust path for a project already comfortable with GitHub Actions is to build the AppImage directly in CI using `appimagetool` against the exported Linux binary + a minimal `.desktop`/icon, rather than depending on an editor plugin whose Godot-4.6 compatibility should be spot-checked at implementation time. Zero package-manager dependency for end users — matches "download and run."
- **Flatpak**: technically buildable (`flatpak-builder` only runs on Linux, so this must happen in a Linux CI job, not the macOS runner), and Flathub is the credible long-term distribution channel for Linux-native discoverability. **Defer Flatpak/Flathub submission to a post-v1.2 milestone** — Flathub has its own manifest-review queue and packaging conventions (sandboxing, `org.godotengine.Godot.BaseApp` runtime) that add real turnaround time disproportionate to this milestone's "get live + get signed" goal. A plain tarball + AppImage on itch.io/GitHub Releases fully satisfies v1.2's "signed, installable Linux build for direct download" requirement.
- No code-signing equivalent is required for Linux binaries (no OS-level Gatekeeper/SmartScreen analog) — this is the simplest of the five platforms.

### Android — upload keystore + Play App Signing (HIGH confidence)

- Generate an **upload key** (RSA 2048-bit, ~10,000-day validity) with `keytool`; this is what signs the AAB before upload, not the final distribution key.
- Enroll in **Play App Signing** (mandatory for new apps since 2021) — Google holds and protects the actual app signing key; the developer only ever handles the upload key. If the upload key is ever lost, Google's key-reset flow (identity verification) recovers it — no catastrophic "can never update the app again" scenario as with old-style self-managed signing.
- Target format is **AAB (Android App Bundle)** exclusively — Godot 4.6's Android export preset supports AAB export directly; this project's existing `export_presets.cfg` Android preset needs its export format switched to AAB (or a second AAB-specific preset added) for store submission, separate from the APK used for sideload/dev testing.
- **New for 2026:** as of August 31, 2026, all new apps/updates must target **Android API level 36 (Android 16)** or higher — confirm the Android export template / `gdextension` ABI compatibility (godot_voxel, godot-sqlite, webrtc-native prebuilt binaries) against API 36 before scheduling the Play Console submission phase; this is a hard Play Console gate, not optional.
- CI: `barichello/godot-ci` Docker image already supports Android exports with custom keystores via environment variables — a pattern the project can likely reuse for the desktop/Android matrix jobs (verify current image tag supports Godot 4.6 export templates before adopting).

### iOS — Apple Developer, provisioning, IPA (MEDIUM-LOW confidence on CI automation specifically)

- Godot 4.6's iOS export preset supports embedding the Team ID, provisioning profile, and (as of recent Godot 4.x releases) can drive `xcodebuild`'s automatic signing directly from the export dialog for **local/manual exports** — this part is HIGH confidence and well-documented.
- **CI automation is the weaker link.** `barichello/godot-ci`, the project's likely default Docker-based CI helper for other platforms, explicitly does not support iOS export (Xcode project automation "doable but not trivial"). Community alternatives exist (e.g. `dulvui/godot4-ios-export`, a GitHub Action targeting Godot 4.3 on `macos-latest` that installs certificates/provisioning profiles from base64-encoded secrets and runs `xcodebuild -allowProvisioningUpdates`) but compatibility with Godot 4.6 specifically should be verified/pinned at implementation time rather than assumed.
- Recommended pattern regardless of which action is used: store `IOS_BUILD_CERTIFICATE_BASE64` (the `.p12`) and `IOS_PROVISION_PROFILE_BASE64` as GitHub Actions secrets, decode into a CI-only keychain/profile directory, export via Godot's `--export-release "iOS"` on a `macos-latest` runner (consistent with the existing `ci-macos-runner` decision for native Mach-O tooling), then `xcodebuild -exportArchive` or `notarytool`-equivalent submission to App Store Connect via **Transporter** or `xcrun altool`/`notarytool` (Apple has been consolidating on `notarytool`/App Store Connect API keys for automated submission).
- Given the project's `no-ios-preset` decision recorded in STATE.md (export_presets.cfg deliberately has no iOS preset yet, deferred pending Apple Developer enrollment), this is squarely v1.2 net-new work, not a re-verification of something already built. Budget real investigation time here — this is the platform most likely to need its own phase-level research spike.

---

## Mobile Store Submission + IAP

### In-App Purchase plugin choice (MEDIUM confidence — fast-moving ecosystem, verify versions at implementation time)

**Recommendation: adopt the OpenIAP-conformant plugins for both platforms rather than mixing an ad-hoc iOS plugin with an ad-hoc Android plugin.**

- **iOS + Android unified:** `hyodotdev/openiap` monorepo, `libraries/godot-iap` — MIT license, wraps `openiap-apple` (StoreKit 2) and `openiap-google` (Play Billing 8.x) behind one GDScript API, auto-generated types. Requires Godot 4.3+ (covers 4.6). **Important:** the previous standalone repo (`hyochan/godot-iap`) was archived end of April 2026 and folded into this monorepo as of v2.0.0 — when implementing, pin to the monorepo path/tag, not the archived repo, and re-check its release cadence/maturity at that time since it's a young consolidation (spec-compliance and cross-platform parity are the value proposition, but the monorepo migration itself is only ~2-3 months old as of this research date).
- **Android-only alternative (if the OpenIAP monorepo's Godot implementation proves too immature at implementation time):** `godot-sdk-integrations/godot-google-play-billing` — the closest thing to an "official" first-party Android billing plugin (MIT, Godot 4.2+ including 4.6, actively released — v3.2.0 as of March 2026). A separate first-party-quality iOS StoreKit plugin would then be needed (e.g. `hrk4649/godot_ios_plugin_iap`, Swift/StoreKit-based) — this fallback trades a unified API for two independently-maintained, narrower-scope, longer-track-record plugins.
- **Do not hand-roll native StoreKit/Billing bindings from scratch** — both ecosystems (StoreKit 2, Play Billing 8.x) have non-trivial receipt validation, restore-purchase, and acknowledgment requirements that existing plugins already handle correctly.
- IAP scope per locked pricing decision (STATE.md): the €1/$1 one-time unlock + optional brick-pack IAP, no progression gating, no subscriptions — both plugin options support one-time/non-consumable purchases natively; no subscription API surface is needed.

### App Store Connect + Google Play Console submission

- Both are manual, form-driven submission consoles (metadata, screenshots, age rating, privacy nutrition labels/data-safety forms) — no meaningful automation shortcut beyond `fastlane deliver`/`fastlane supply` if the team later wants scripted metadata upload. For a single v1.2 submission, manual console entry is proportionate; **do not build Fastlane automation as a v1.2 requirement** unless repeated re-submission cadence justifies the setup cost.
- COPPA and parental-consent flows are already implemented (Phase 5, v1.0) — store submission just needs the existing EULA/Privacy Policy URLs and age-rating questionnaire answers to be consistent with what's already shipped; this is a metadata/paperwork task, not new engineering.
- Google Play's data-safety form and Apple's App Privacy "nutrition label" both require explicitly declaring what the Supabase-backed friends graph and Go signaling server collect (account email, friend UIDs, session/IP-adjacent WebRTC metadata) — flag this as a cross-cutting task against both console submissions, not purely engineering.

---

## Auto-Update (Desktop) + Version-Match

### Desktop auto-update: lightweight version-check + redirect, not a self-replacing binary patcher (HIGH confidence recommendation)

There is no mature, widely-adopted "Sparkle/Squirrel-equivalent" auto-updater purpose-built for Godot with an active 2026 track record at the reliability bar a signed/notarized macOS or Authenticode-signed Windows build requires. Building or adopting a full self-replacing updater (in-place binary swap, delta patching) is disproportionate engineering for a 2-4-friends indie project and interacts badly with code signing (a self-downloaded, self-replaced binary must itself already be correctly signed/notarized — you gain little bypassing store/itch update mechanisms to reimplement what they already do).

**Recommended v1.2 approach — two complementary channels:**

1. **itch.io channel: rely on the itch app.** Builds pushed via `butler` to itch.io and installed through the itch.io desktop app get automatic update-checking and one-click updates from the itch app itself — zero custom code required. This is the simplest of the three desktop channels and should be the default recommendation to players who want auto-update "for free."
2. **Direct-download / GitHub Releases channel: in-game soft version-check.** On launch (or session join), the client reads the local `version.txt` (already written by the existing Build Stamp plugin) and compares it against the latest published version. Two ways to source "latest," in order of simplicity:
   - Query the GitHub Releases API's stable "latest" redirect: `https://github.com/<owner>/<repo>/releases/latest/download/version.txt` (GitHub guarantees this URL always resolves to the most recent published release's asset of that exact filename — no API token or rate-limit-sensitive JSON parsing needed, just an `HTTPRequest` to a fixed URL).
   - If mismatched, show a non-blocking toast/dialog: "A new version is available — download it from [link]," linking to the download landing page (see Distribution). **Do not attempt in-place binary replacement** — let the user download and reinstall/overwrite through the OS's normal mechanism (drag-and-drop `.app`, run `.exe` installer, extract tarball/AppImage), which is also what preserves code-signing/notarization integrity trivially (they're re-downloading an already-signed artifact, not patching one).

### Version-match enforcement for multiplayer (custom code, no library — HIGH confidence this is the right call)

Godot's high-level multiplayer protocol deliberately performs **no** engine-level version handshake (confirmed via an open godot-proposals issue — even Godot patch releases can break wire compatibility, so the engine intentionally doesn't promise cross-version compatibility, and there is no built-in hook to rely on). This must be implemented at the application layer, which the project is already positioned to do cheaply:

- Session join (via the Go signaling server or the WebRTC data channel handshake) should exchange the Build Stamp `version.txt` value as the very first application-level message, before any game-state RPCs are trusted.
- On mismatch, reject the join with a clear, translated message (e.g. `ui.join.error_version_mismatch`, following the existing i18n key convention) rather than allowing a silent desync — this directly satisfies the milestone's "auto-update keeping every peer on the same build" requirement without needing peers to actually be forced to auto-update; it just prevents mismatched peers from ever entering a broken session.
- This slots naturally into the existing `NetworkManager` session-state machine (11 string-constant states per `network-manager-state-strings` decision) as one more rejection reason, and into the existing Go signaling server's session-registry validation (it already gates on JWT and 200-session cap; version string is one more field to check at the same layer).

---

## Distribution Channels

### itch.io (butler)

- `butler` is itch.io's official CLI, MIT-licensed-adjacent (itch's own tooling), and the standard automation path: `butler push <build-dir> <user>/<game>:<channel>` where channel strings containing `mac`/`win`/`linux`/`android` auto-tag the platform.
- GitHub Actions integration is a solved, widely-documented pattern: a `BUTLER_API_KEY` repo secret (itch.io issues a dedicated Butler-scoped key, distinct from the general itch.io API key — do not confuse the two when provisioning), a build step per platform, then one `butler push` per artifact. This is a natural addition to the project's existing GitHub Actions export matrix.

### GitHub Releases

- Tag-triggered (the project's existing CI already gates artifact upload to tag runs per the `ci: only upload build artifacts on tag runs + 30-day retention` commit) — extend the same tag-triggered job to also create/attach to a GitHub Release via `gh release create`/`softprops/action-gh-release`, uploading the signed macOS `.dmg`/`.zip`, Windows `.exe`/installer, and Linux AppImage/tarball as release assets.
- Exploit the stable `/releases/latest/download/<asset-name>` URL pattern (see Auto-Update section) for both the landing page's download buttons and the in-game version-check — one mechanism serves two purposes.

### One-link, platform-detecting landing page

- A static HTML+JS page hosted on `cubicraftia.com` (served by the same Caddy instance fronting the backend — just another `Caddyfile` `handle`/`file_server` block, no separate hosting needed) that sniffs `navigator.userAgent`/`navigator.platform` client-side and highlights the matching download button (macOS/Windows/Linux → direct GitHub Releases/itch.io links; iOS/Android → App Store/Play Store links). This is a well-understood, low-risk pattern — no framework or SDK needed beyond plain JS; **do not reach for a SaaS "smart link" product** (e.g. Branch.io-style deep-link services) — those solve deferred-deep-linking-into-app-store-then-back-into-content problems this project doesn't have (friends-only sessions, no viral acquisition funnel requirement).
- The "join my friend's session" deep link already has its client-side handler (`DeepLinkHandler`, Phase 6, `cubicraftia://` custom scheme). For v1.2, the **new** work is hardening the fallback path: custom URI schemes are unreliable when clicked from within a mobile browser or messaging app (increasingly blocked without a prior user gesture, and fail silently if the app isn't installed) — mitigate with:
  - **iOS Universal Links**: host `/.well-known/apple-app-site-association` (no file extension, `application/json` content-type, no redirect) on `cubicraftia.com`, referencing the app's Team ID + Bundle ID.
  - **Android App Links**: host `/.well-known/assetlinks.json` referencing the app's package name + signing certificate SHA-256 fingerprint (available once Play App Signing is enrolled).
  - Both are static files served by the same Caddy instance — no new backend logic, just two JSON files and DNS/HTTPS the project already controls. This was already flagged as a known operator prerequisite in STATE.md's Future/deferred list ("iOS Universal Links + Android App Links `.well-known` server config") — v1.2 is the milestone that actually does it.

---

## CI/CD Additions

Extending the existing GitHub Actions matrix (macOS native runner for macOS export; presumably Linux runners or `barichello/godot-ci` for Windows/Linux/Android; no iOS job yet):

1. **New: `export_ios` job** on `macos-latest`, gated behind the (now-provisioned) Apple Developer credentials — decode `.p12`/provisioning profile secrets, run Godot's iOS export, `xcodebuild -exportArchive`, submit via `notarytool`/Transporter/App Store Connect API key. Treat this as its own research/implementation spike given the MEDIUM-LOW confidence noted above.
2. **Extend macOS job**: add Codesign + Notarization fields to the export preset (Team ID, Apple API key secrets) so the existing tag-triggered build is notarized/stapled, not just built.
3. **Extend Windows job**: add `osslsigncode` (already cross-platform-available, so no runner change needed) + Azure Trusted Signing credentials as secrets; sign the unsigned `.exe` post-export.
4. **Extend Android job**: switch/add an AAB export preset using the release upload keystore (already partially anticipated — `CI_KEYSTORE_SETUP.md` exists per the allowlist decision in STATE.md); confirm API 36 target compliance.
5. **New: Linux packaging step**: build AppImage via `appimagetool` (Linux runner) alongside the existing raw binary/tarball export.
6. **New: `butler push` step(s)** per platform artifact, gated on tag runs, using a `BUTLER_API_KEY` secret.
7. **New: GitHub Release creation step**, uploading signed artifacts as release assets, using the existing tag trigger.
8. **New: backend deploy job(s)** — likely a separate, manually-triggered or `main`-branch-triggered workflow (not tied to game-client tags) that SSHs into `m1.linuxbe.com` (or uses `docker compose pull && up -d` via SSH action) to redeploy the Go signaling binary / Supabase compose stack / Caddy config on change. Keep this decoupled from the client export matrix — different release cadence, different secrets (SSH key vs. signing certs).

**Existing pattern to preserve, not replace:** the Build Stamp plugin's auto-stamp-on-export behavior should remain the single source of truth version.txt is derived from — none of the new CI steps should introduce a second, competing version-numbering scheme (e.g. don't let `butler`'s own channel/build-number system or GitHub Release tag names silently diverge from `version.txt`; wire the tag name and `version.txt` from the same source at tag-creation time).

---

## Do NOT Add (anti-scope)

- **Steamworks / GodotSteam** — explicitly out of scope (already rejected in the root stack rationale; mobile-first cross-play model doesn't fit a Steam-only networking layer, and Steam distribution isn't part of v1.2's stated channels).
- **Nakama, or any authoritative game server** — already rejected; game state stays P2P, backend stays signaling-only.
- **Firebase, Auth0, Clerk** — already rejected in favor of self-hosted Supabase; do not reconsider for v1.2.
- **Kubernetes, Nomad, or any container orchestrator** — one host, docker-compose (for Supabase's own stack) + systemd (for the Go binary + Caddy + coturn) is sufficient. Orchestration complexity is unjustified at 200-session-cap, single-host scale.
- **Coolify / CapRover / Dokploy or any self-hosted PaaS control plane** — legitimate products, but an unnecessary extra layer for v1.2 given the three services already have clear individual deploy stories (see Backend Deployment). Revisit only if a second host/environment is added.
- **HashiCorp Vault or a cloud secrets manager** — a root-owned `EnvironmentFile=` with `chmod 600` is proportionate to this project's scale; do not add secrets-management infrastructure.
- **A custom or third-party self-replacing binary auto-updater (Sparkle-equivalent, Squirrel, etc.)** — the lightweight version-check-and-redirect approach (backed by the itch app for the itch channel) fully satisfies the milestone's stated goal ("auto-update keeping every peer on the same build" is actually solved by the version-match multiplayer gate, not by silently patching binaries).
- **Flatpak/Flathub submission** — defer to post-v1.2; AppImage + tarball satisfies "signed, installable Linux build for direct download" without incurring Flathub's review-queue turnaround.
- **Fastlane `deliver`/`supply` automation for store metadata** — manual App Store Connect / Play Console submission is proportionate for a single v1.2 launch; only worth automating if re-submission cadence increases later.
- **Any subscription or cosmetic-shop IAP surface** — pricing is locked (one-time unlock + optional brick packs, no progression gating); do not let the IAP plugin integration scope-creep into subscription APIs neither chosen plugin candidate needs to expose.
- **A branded "smart link" / deferred-deep-linking SaaS** (Branch.io-style) — the project's friends-only, no-viral-acquisition-funnel model doesn't need it; static Universal Links/App Links `.well-known` files fully cover the stated "join my friend's session" flow.
- **Hand-rolled StoreKit/Play Billing native bindings** — use the OpenIAP-conformant plugin (or the first-party-quality Android Play Billing plugin as fallback); both ecosystems have enough receipt-validation/restore-purchase subtlety that reinventing them is a false economy.
- **Engine-level or third-party multiplayer version-negotiation libraries** — Godot has none, and none are needed; this is ~10 lines of application-layer handshake code against the Go signaling server's existing session-registry validation.

---

## Open Questions

- **iOS CI export automation maturity for Godot 4.6 specifically:** the community GitHub Actions (`dulvui/godot4-ios-export` et al.) were last verified against Godot 4.3 in search results; confirm compatibility (or budget manual export as an interim fallback) before committing this to the CI matrix. Flag as a phase-level research spike.
- **OpenIAP `godot-iap` monorepo maturity:** the migration from the standalone `hyochan/godot-iap` repo to the `hyodotdev/openiap` monorepo completed only ~2-3 months before this research date (April 2026 archive, "v2.0.0" in the new home). Re-verify release cadence, open-issue count, and real-world App Store/Play Console acceptance reports at implementation time; have `godot-sdk-integrations/godot-google-play-billing` (mature, MIT, actively released) + a standalone iOS StoreKit plugin as the fallback pairing if the unified plugin proves too young.
- **Azure Trusted Signing / Artifact Signing exact entity eligibility:** confirm which legal entity/individual the project will register under for Windows code signing, and re-check current (as of implementation time) US/Canada/EU/UK eligibility rules — this Azure product has rebranded and changed eligibility rules multiple times within 2026 already.
- **`m1.linuxbe.com` current hardware spec vs. Supabase's recommended 8 GB / 4 vCPU production floor:** verify before scheduling the backend-deploy phase; if the host is smaller, Supabase self-host still runs on the documented 4 GB / 2 vCPU minimum but headroom for coturn's relay traffic + the Go signaling server should be budgeted alongside it.
- **coturn TLS certificate strategy (dedicated certbot vs. sharing Caddy's ACME storage):** both are viable; pick one during phase planning rather than deciding here, since it's an implementation detail with no roadmap-level consequence either way.
- **Whether Android's API 36 (Android 16) target requirement (effective August 31, 2026) affects any pinned GDExtension binary (godot_voxel prebuilt v1.6x, godot-sqlite, webrtc-native)** — verify ABI/target-SDK compatibility for all three before the Play Console submission phase; this is a hard gate, not a nice-to-have.

---

## Sources

- [Godot 4.6 — Exporting for macOS](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_macos.html)
- [How to notarize & sign your macOSX Godot app — Godot Forums](https://godotforums.org/d/37190-how-to-notarize-sign-your-macosx-godot-app)
- [Exporting for Windows — Godot Engine docs](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_windows.html)
- [Code signing your games (mainly Godot) — itch.io blog](https://itch.io/blog/744096/code-signing-your-games-mainly-godot)
- [Azure Artifact Signing (Trusted Signing) — Microsoft Azure](https://azure.microsoft.com/en-us/products/artifact-signing)
- [Trusted Signing open for individual developers — Microsoft Community Hub](https://techcommunity.microsoft.com/blog/microsoft-security-blog/trusted-signing-is-now-open-for-individual-developers-to-sign-up-in-public-previ/4273554)
- [Code signing Windows apps with Azure Artifact service — devclass.com](https://www.devclass.com/security/2026/01/14/code-signing-windows-apps-may-be-easier-and-more-secure-with-new-azure-artifact-service/4079554)
- [Linux AppImage Export — Godot Asset Library](https://godotengine.org/asset-library/asset/4859)
- [Publish Your Godot Engine Game to Flathub — Cassidy James](https://cassidyjames.com/blog/publish-godot-engine-game-flathub-flatpak/)
- [Android App Bundle FAQ — Android Developers](https://developer.android.com/guide/app-bundle/faq)
- [Use Play App Signing — Play Console Help](https://support.google.com/googleplay/android-developer/answer/9842756)
- [godot-sdk-integrations/godot-google-play-billing](https://github.com/godot-sdk-integrations/godot-google-play-billing)
- [hyodotdev/openiap monorepo](https://github.com/hyodotdev/openiap) / [libraries/godot-iap](https://github.com/hyodotdev/openiap/tree/main/libraries/godot-iap)
- [godot-iap migration discussion](https://github.com/hyochan/godot-iap/discussions/29)
- [OpenIAP documentation](https://docs.openiap.io/)
- [hrk4649/godot_ios_plugin_iap](https://github.com/hrk4649/godot_ios_plugin_iap)
- [dulvui/godot4-ios-export](https://github.com/dulvui/godot4-ios-export)
- [abarichello/godot-ci](https://github.com/abarichello/godot-ci)
- [Godot proposal: version check on multiplayer connect (#10348)](https://github.com/godotengine/godot-proposals/issues/10348)
- [Supabase: Self-Hosting with Docker](https://supabase.com/docs/guides/self-hosting/docker)
- [Supabase: Configure Reverse Proxy and HTTPS](https://supabase.com/docs/guides/self-hosting/self-hosted-proxy-https)
- [Self-Hosting Supabase with Docker and Caddy — flori.dev](https://flori.dev/reads/supabase-self-host-docker-caddy-reverse-proxy/)
- [Reverse-Proxy self-hosted Supabase with Caddy — Caddy Community](https://caddy.community/t/reverse-proxy-self-hosted-supabase-with-caddy/20529)
- [Make coturn work reverse proxied through nginx — coturn issue #702](https://github.com/coturn/coturn/issues/702)
- [WebRTC TURN Server Setup: Complete Production Guide 2026 — CelloIP](https://celloip.com/blog/webrtc-turn-server-production-guide/)
- [Best Self-Hosted PaaS Platforms in 2026 — servercompass.app](https://servercompass.app/blog/best-self-hosted-paas-platforms-2026)
- [Coolify docs — Supabase service](https://coolify.io/docs/services/supabase)
- [Butler CLI — itch.io](https://itch.io/board/24575/butler)
- [Automating Godot game releases to itch.io — DEV Community](https://dev.to/jeremyckahn/automating-godot-game-releases-to-itchio-1a96)
- [What Are Universal Links and App Links — idura.eu](https://idura.eu/blog/universal-links-and-app-links)
- [Deep Linking Explained — Appy Pie](https://www.appypie.com/blog/deep-linking-explained)
