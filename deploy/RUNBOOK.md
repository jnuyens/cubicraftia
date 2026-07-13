# Cubicraftia Backend Deploy Runbook (Phase 11)

## DEPLOYED STATE (2026-07-10)

Live and publicly verified on m1:
- **Signaling** (DEPLOY-02): `cubicraftia-signaling.service` on `127.0.0.1:8129`, public `https://signal.cubicraftia.com/health` -> 200 `ok`.
- **Supabase** (DEPLOY-03): 11 containers healthy in `/opt/cubicraftia/supabase/docker`; Kong `127.0.0.1:8000`; public `https://supabase.cubicraftia.com` (401 without apikey = reachable). Migrations 001-009 applied (friendships/invites/profiles/blocks/reports/parental_consents/username_change_log).
- **nginx + certbot** (DEPLOY-01): `conf.d/signal.cubicraftia.com.conf` + `conf.d/supabase.cubicraftia.com.conf`, Let's Encrypt cert (SAN both, expires 2026-10-07, auto-renew), HTTP->HTTPS redirect. `nginx -t`-gated; the other ~12 sites untouched.
- **Secret parity** (DEPLOY-05): `/etc/cubicraftia/secrets.env` shared JWT + service key across signaling and Supabase.
- **coturn** (DEPLOY-04): `turnserver` bound on `88.99.136.145:3478` (STUN/TURN) + `:5349` (TLS), cert `turn.cubicraftia.com` with a certbot deploy-hook (`/etc/letsencrypt/renewal-hooks/deploy/cubicraftia-coturn.sh`) that re-copies + reloads on renewal. `static-auth-secret` = shared `TURN_SHARED_SECRET`. ufw opened 3478/5349 (tcp+udp) + 49152:65535/udp. Verified: TURN allocation test relayed 0-loss with an ephemeral HMAC credential (auth parity with signaling confirmed). NOTE: coturn must be `systemctl restart`ed (not just `enable --now`) to load `/etc/turnserver.conf`, else it binds all interfaces incl. Docker bridges.
- **Backups** (DEPLOY-06): OWNED BY OPERATOR (existing backup active per project owner). `pg-backup.sh` unused.

- **Supabase auth signup:** `ENABLE_EMAIL_AUTOCONFIRM=true` in `/opt/cubicraftia/supabase/docker/.env` (accounts confirm immediately, no email). Set 2026-07-13 to unblock testing because only the fake demo SMTP relay is configured, which made GoTrue return 500 "Error sending confirmation email" on every signup. PRODUCTION DECISION before public launch: either wire a real SMTP relay (GOTRUE_SMTP_*) for email verification, or keep autoconfirm. The parental-consent SMTP (signaling server, under-13) is a separate, still-pending item.

**Docker networking exception (required, applied):** m1's `/etc/modprobe.d/modulejail-blacklist.conf` blocks ~6344 modules including `veth`/`br_netfilter`/`iptable_nat`/`iptable_filter` (Docker bridge). Added `/etc/modprobe.d/00-cubicraftia-docker-net.conf` (sorts before the jail; first-match-wins) re-enabling exactly those four. Reversible: delete that file + reboot to restore the full jail. (The jail also blocks `xt_multiport` so ufw multiport warns, but simple per-port ALLOW rules land fine.)

## Public endpoints (live)
- `wss://signal.cubicraftia.com` (signaling)
- `https://supabase.cubicraftia.com` (Supabase API/auth)
- STUN/TURN `cubicraftia.com:3478` and `turn.cubicraftia.com:3478/5349` (TURN secret via ephemeral REST)
- `https://cubicraftia.com` (apex): static site + `updates/latest.json` (auto-update manifest) + `downloads/Cubicraftia.zip` (DIST-05, notify-and-link). Root `/var/www/cubicraftia`, cert auto-renew. Publish a new build with `deploy/publish-update.sh <zip>`.

Remaining: **DEPLOY-07** — set these into the client's release export presets (signaling + Supabase URLs currently default to localhost; STUN/TURN already default to `cubicraftia.com:3478`), then an end-to-end smoke test (dovetails with Phase 12 real-device validation).

---


Target host: **m1.linuxbe.com** (88.99.136.145, Ubuntu 24.04, 8 vCPU / 38 GiB / 228 GB free).
Operator: `jnuyens` (passwordless sudo).

## CRITICAL: shared production host

m1 also serves ~12 unrelated live sites through the SAME nginx + certbot (aspirantwhales.com,
binnenluchtzaak.be, brusselair-parapente.be, buildomator.com, fluggy.com, cardioleuven.be,
beta.project78.com, internal.opensource-enterprise.com, dekroegzemst.be, lfs.cubicraftia.com, ...).

Rules, non-negotiable:
- Never edit or delete an existing nginx vhost. Only ADD new `conf.d/*.conf` files for the
  cubicraftia subdomains.
- Run `sudo nginx -t` before EVERY `nginx -s reload`. A failed `-t` means do not reload.
- Supabase's bundled Postgres stays inside the Docker network. Never bind host port 5432
  (the host already runs its own Postgres there).
- coturn uses its own ports (3478/5349 TCP+UDP, 49152-65535/udp relay). ufw is active: open
  exactly those, nothing else.

## DNS (already in place via Cloudflare, DNS-only / not proxied)

All resolve to 88.99.136.145: `cubicraftia.com`, `www`, `signal`, `api`, `supabase`, `turn`, `lfs`.
No DNS changes required.

## Endpoint topology

| Public | nginx TLS terminates -> | Backend |
|--------|------------------------|---------|
| `wss://signal.cubicraftia.com` | proxy_pass | `127.0.0.1:8129` (Go signaling, systemd) |
| `https://supabase.cubicraftia.com` | proxy_pass | `127.0.0.1:8000` (Supabase Kong, docker) |
| `https://api.cubicraftia.com` | (alias for signaling REST/admin) | `127.0.0.1:8129` |

> **Port note:** signaling runs on **8129**, not 8080. On m1, 8080 is already owned by an
> existing Java/Jetty service. Lesson: this is a shared host, always pick a free port (`ss -tlnH`)
> and never assume a default is free. Supabase Kong (8000) and Postgres (5432) must likewise be
> checked, and Supabase's Postgres stays inside Docker so it cannot collide with the host's 5432.
| STUN/TURN `turn.cubicraftia.com:3478/5349` | direct (bypasses nginx) | coturn (systemd) |

Client already defaults STUN/TURN to `cubicraftia.com:3478` and resolves signaling/Supabase URLs
via ProjectSettings -> env -> localhost; release export presets get the production URLs (DEPLOY-07).

## Secrets (DEPLOY-05 — parity is the #1 correctness risk)

Single source of truth: `/etc/cubicraftia/secrets.env` (root, 0600), generated by
`deploy/generate-secrets.sh`. The SAME values are consumed by all three services:
- `SUPABASE_JWT_SECRET` -> Supabase GoTrue AND signaling `SUPABASE_JWT_SECRET`
- `TURN_SHARED_SECRET`  -> coturn `static-auth-secret` AND signaling `TURN_SHARED_SECRET`
- `POSTGRES_PASSWORD`   -> Supabase compose only
- `ANON_KEY` / `SERVICE_ROLE_KEY` -> derived from JWT secret (Supabase); service key -> signaling
- `ADMIN_SECRET`        -> signaling `/admin/reports`

Nothing here is committed to git. `.gitignore` excludes `deploy/secrets/` and `*.env` (not templates).

## Staged execution (each stage verified before the next)

1. **Foundation (isolated, zero blast radius):** create `cubicraftia` user + `/etc/cubicraftia`
   + `/var/log/cubicraftia`; run `generate-secrets.sh`; build the signaling Linux binary on-host
   (`go build`) -> `/usr/local/bin/cubicraftia-signaling`; install systemd unit + `signaling.env`.
2. **Supabase (docker):** clone `supabase/docker`, write `.env` from `secrets.env`, keep Postgres
   internal (no 5432 host bind), `docker compose up -d`, apply `supabase/migrations/00{1..9}` to the
   in-container Postgres, verify Kong on 127.0.0.1:8000.
3. **Signaling live:** fill `SUPABASE_URL=http://127.0.0.1:8000`, `SUPABASE_SERVICE_KEY`,
   `SUPABASE_JWT_SECRET` into signaling.env; `systemctl enable --now cubicraftia-signaling`;
   verify `/health` on 127.0.0.1:8080.
4. **coturn:** `apt install coturn`; write `turnserver.conf` from template (`static-auth-secret` =
   TURN_SHARED_SECRET, realm `cubicraftia.com`, TLS cert from certbot); `ufw allow` 3478,5349,
   49152:65535/udp; `systemctl enable --now coturn`; verify allocation with `turnutils_uclient`.
5. **nginx + certbot (shared — verify-before-reload):** add `conf.d/signal|api|supabase.cubicraftia.com.conf`;
   `certbot --nginx -d signal... -d api... -d supabase...` (or `turn.` standalone for coturn);
   `nginx -t` then reload; curl each endpoint over TLS.
6. **Backups + client (DEPLOY-06/07):** install `pg-backup.sh` + systemd timer (off-box target);
   set production endpoints in the release export presets; end-to-end smoke test (sign-up, invite,
   join, forced-TURN) from a release client.

## Rollback

Every stage is additive. To fully remove: `docker compose down -v` (Supabase),
`systemctl disable --now cubicraftia-signaling coturn`, `apt remove coturn`, delete the three
`conf.d/*cubicraftia*.conf` + `certbot delete` the new certs + `nginx -t && reload`,
`ufw delete` the coturn rules, `userdel cubicraftia`, `rm -rf /etc/cubicraftia`. No existing
site is touched at any point.
