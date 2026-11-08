#!/usr/bin/env bash
set -euo pipefail
size="${PGBOUNCER_POOL_SIZE:-4}"
[[ "$size" =~ ^[1-9][0-9]*$ ]] && ((size <= 80)) || { echo 'Pool size must be 1..80' >&2; exit 1; }
sed "s/POOL_SIZE/$size/g" /etc/pgbouncer/pgbouncer.ini > /tmp/lab-pgbouncer.ini
exec pgbouncer /tmp/lab-pgbouncer.ini
