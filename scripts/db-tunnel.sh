#!/usr/bin/env bash
# Open an SSH tunnel to the Postgres behind Supabase on the Coolify VPS.
# Forwards localhost:$LOCAL_PORT -> hostinger2026:127.0.0.1:5432.
#
#   ./scripts/db-tunnel.sh          # localhost:5432
#   ./scripts/db-tunnel.sh 55432    # localhost:55432, if compose already owns 5432
#
# Remote 5432 is the supabase-db container's direct port, NOT Supavisor.
# Keep it that way: LISTEN/NOTIFY and session-level advisory locks — both
# load-bearing for the outbox relay — do not survive a transaction-mode pooler.
#
# Ctrl-C to close.
set -euo pipefail

REMOTE_HOST="hostinger2026"
LOCAL_PORT="${1:-5432}"

if lsof -iTCP:"$LOCAL_PORT" -sTCP:LISTEN -n >/dev/null 2>&1; then
  echo "error: localhost:$LOCAL_PORT is already in use (dev compose Postgres?)." >&2
  echo "       pass another port, e.g. ./scripts/db-tunnel.sh 55432" >&2
  exit 1
fi

echo "tunnelling localhost:$LOCAL_PORT -> $REMOTE_HOST:127.0.0.1:5432  (Ctrl-C to close)"
exec ssh -N -L "$LOCAL_PORT":127.0.0.1:5432 -o ServerAliveInterval=30 "$REMOTE_HOST"
