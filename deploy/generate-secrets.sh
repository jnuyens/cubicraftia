#!/usr/bin/env bash
# generate-secrets.sh (Phase 11, DEPLOY-05)
# Generates the single source of truth for backend secrets, root-owned, off-git.
# Idempotent: if /etc/cubicraftia/secrets.env already exists it refuses to overwrite
# (rotating secrets is a deliberate, separate action, not an accidental re-run).
#
# Run on m1 as: sudo bash deploy/generate-secrets.sh
set -euo pipefail

OUT=/etc/cubicraftia/secrets.env
mkdir -p /etc/cubicraftia
chmod 0750 /etc/cubicraftia

if [[ -e "$OUT" ]]; then
  echo "Refusing to overwrite existing $OUT (rotate secrets deliberately, not by re-run)." >&2
  exit 1
fi

JWT_SECRET="$(openssl rand -hex 40)"
TURN_SHARED_SECRET="$(openssl rand -hex 32)"
ADMIN_SECRET="$(openssl rand -hex 32)"
POSTGRES_PASSWORD="$(openssl rand -hex 24)"

# Mint the Supabase anon + service_role keys as HS256 JWTs signed with JWT_SECRET
# (10-year expiry, iss=supabase), matching Supabase self-host conventions.
mint_key() {
  local role="$1"
  python3 - "$JWT_SECRET" "$role" <<'PY'
import sys, hmac, hashlib, base64, json, time
secret, role = sys.argv[1], sys.argv[2]
def b64(b): return base64.urlsafe_b64encode(b).rstrip(b'=')
header = b64(json.dumps({"alg":"HS256","typ":"JWT"},separators=(',',':')).encode())
iat = int(time.time()); exp = iat + 10*365*24*3600
payload = b64(json.dumps({"role":role,"iss":"supabase","iat":iat,"exp":exp},separators=(',',':')).encode())
signing_input = header + b'.' + payload
sig = b64(hmac.new(secret.encode(), signing_input, hashlib.sha256).digest())
sys.stdout.write((signing_input + b'.' + sig).decode())
PY
}

ANON_KEY="$(mint_key anon)"
SERVICE_ROLE_KEY="$(mint_key service_role)"

umask 077
cat > "$OUT" <<EOF
# Cubicraftia backend secrets (Phase 11 DEPLOY-05). Root-owned 0600. NEVER commit.
# Generated $(date -u +%Y-%m-%dT%H:%M:%SZ) on $(hostname).
SUPABASE_JWT_SECRET=${JWT_SECRET}
ANON_KEY=${ANON_KEY}
SERVICE_ROLE_KEY=${SERVICE_ROLE_KEY}
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
TURN_SHARED_SECRET=${TURN_SHARED_SECRET}
ADMIN_SECRET=${ADMIN_SECRET}
EOF
chmod 0600 "$OUT"
echo "Wrote $OUT (0600). Parity source of truth for signaling + Supabase + coturn."
echo "JWT_SECRET/TURN_SHARED_SECRET/SERVICE_ROLE_KEY must be copied verbatim into each service config."
