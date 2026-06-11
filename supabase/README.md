# Supabase — Cubicraftia Backend

Self-hosted Supabase instance (GoTrue auth + Postgres + PostgREST).
Friends graph and invite links are relational; Row-Level Security (RLS) is the
authorization boundary. The Go signaling server reads from `auth.users` via JWT
validation only — it does not query Postgres directly.

## Applying Migrations

### Option A — Supabase CLI (recommended for development)

```bash
# From the repository root:
supabase db push
```

### Option B — psql (for production VPS)

Apply migrations in order. Each file is idempotent only if applied once in sequence:

```bash
psql -h <supabase-db-host> -U postgres -d postgres \
  -f supabase/migrations/001_friendships.sql

psql -h <supabase-db-host> -U postgres -d postgres \
  -f supabase/migrations/002_invites.sql

psql -h <supabase-db-host> -U postgres -d postgres \
  -f supabase/migrations/003_profiles.sql
```

Replace `<supabase-db-host>` with the hostname of your Supabase Postgres instance
(typically `localhost` if running via Docker Compose on the same VPS, or the
public IP / container name otherwise).

## Migration Summary

| File | Table | Purpose |
|------|-------|---------|
| 001_friendships.sql | `public.friendships` | Friend relationships. `CHECK (user_a < user_b)` enforces canonical ordering so each pair is stored exactly once. Three RLS policies: SELECT (members), INSERT (member + ordering), DELETE (member). |
| 002_invites.sql | `public.invites` | Single-use invite links. 26-char base32 token, 24-hour TTL. The `redeemed_by IS NULL` condition in the UPDATE RLS policy is the atomic single-use lock — Postgres row-level locking prevents double redemption. |
| 003_profiles.sql | `public.profiles` | Builder display names. `username TEXT NOT NULL UNIQUE`. Any authenticated user can read (for friend search); only the owner can update. |

## coturn Configuration

The coturn TURN relay **must** be deployed in `restricted` mode:

```
lt-cred-mech
use-auth-secret
static-auth-secret=<random-secret>
realm=cubicraftia.com
no-loopback-peers
no-multicast-peers
total-quota=1000
```

HMAC time-limited TURN credentials are generated per-session by the Go signaling
server on `session.publish` using `use-auth-secret` mode. Do **not** deploy
coturn as an open relay — it will be abused.

See [`signaling-server/internal/hub/session.go`](../signaling-server/internal/hub/session.go)
for the TURN credential generation implementation.
