#!/usr/bin/env bash
set -euo pipefail
install -d -m 0700 -o postgres -g postgres "$PGDATA"
if [[ ! -s "$PGDATA/PG_VERSION" ]]; then
  # Never overwrite an existing cluster; volume removal is a separate user action.
  gosu postgres pg_basebackup -h db -U lab_replicator -D "$PGDATA" -R -X stream --no-slot -c fast
elif [[ ! -f "$PGDATA/standby.signal" ]]; then
  echo 'Refusing to start a non-standby cluster as the lab replica.' >&2
  exit 1
fi
exec docker-entrypoint.sh postgres -c hot_standby=on -c shared_preload_libraries=pg_stat_statements -c track_io_timing=on
