#!/usr/bin/env bash
# pg-backup.sh (Phase 11 DEPLOY-06)
# Nightly logical backup of the Supabase (in-container) Postgres, pushed OFF the box.
# Runs via systemd timer. Requires: docker access + an off-box target (rsync/scp/S3).
#
# Configure BACKUP_REMOTE below to a real off-box location before enabling the timer.
set -euo pipefail

STAMP="$(date -u +%Y%m%d-%H%M%S)"
LOCAL_DIR=/var/backups/cubicraftia
REMOTE="${BACKUP_REMOTE:-}"   # e.g. user@backup-host:/srv/cubicraftia-pg  OR  s3://bucket/path
RETAIN_DAYS=14
COMPOSE_DIR=/opt/cubicraftia/supabase   # where supabase docker-compose lives

mkdir -p "$LOCAL_DIR"
FILE="$LOCAL_DIR/cubicraftia-pg-${STAMP}.sql.gz"

# Dump from the running Supabase Postgres container (adjust service name if different).
docker compose -f "$COMPOSE_DIR/docker-compose.yml" exec -T db \
  pg_dumpall -U postgres | gzip -9 > "$FILE"

echo "Local dump: $FILE ($(du -h "$FILE" | cut -f1))"

if [[ -z "$REMOTE" ]]; then
  echo "WARNING: BACKUP_REMOTE unset. Backup is LOCAL ONLY (not off-box)." >&2
  echo "DEPLOY-06 requires an off-box copy before DNS cutover. Set BACKUP_REMOTE." >&2
else
  case "$REMOTE" in
    s3://*) aws s3 cp "$FILE" "$REMOTE/" ;;
    *)      rsync -a "$FILE" "$REMOTE/" ;;
  esac
  echo "Pushed off-box to $REMOTE"
fi

# Local retention
find "$LOCAL_DIR" -name 'cubicraftia-pg-*.sql.gz' -mtime +"$RETAIN_DAYS" -delete
