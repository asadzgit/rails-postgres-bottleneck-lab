# Phase 6 — physical streaming replica and read-your-writes fences

Compose's replication profile runs an actual PostgreSQL physical standby created
with pg_basebackup. It is not a second independent database or an application-side
copy pretending to be a replica. The standby has a dedicated persistent volume,
standby.signal and streaming WAL replay. No replica database port is published.

```sh
script/setup-dev
K6_VUS=10 K6_DURATION=15s script/experiment-advanced read-primary results/reads-before
K6_VUS=10 K6_DURATION=15s script/experiment-advanced read-replica results/reads-after
```

Both cases use the same stable lab_replica_items row and matching expected version,
with both PostgreSQL nodes available. Compare primary-statements.csv and
replica-statements.csv to see where reads executed, plus replication snapshots and
HTTP outcomes. A tiny row lookup may be Rails/network bound; do not promise faster
latency or linear read scaling on a shared host. Replicas move work and add
consistency/operational costs; they do not speed up primary writes.

## Explicit read semantics

- GET /lab/replica/items/:id?source=primary reads the writer.
- source=replica reads the standby and reports in_recovery=true.
- POST /lab/replica/items/:id/increment writes only the primary and returns a
  min_lsn WAL fence sampled after commit. It is at least as new as that write;
  concurrent commits can make it more conservative than the exact commit LSN.
- A replica request with min_lsn and bounded wait_ms waits for replay >= that LSN.
  It returns 409 replica_lag if the fence is not met, rather than silently serving
  an older value or hiding routing with automatic primary fallback.

The fence is PostgreSQL-cluster/timeline specific. Do not reuse it blindly after
failover or across shards. This lab has one primary/standby pair and no automatic
promotion, failover orchestration or replication-aware connection balancing.
PostgreSQL itself enforces standby read-only behavior, even for the raw admin
connection; Rails also marks the optional connection as a replica.

## Reproduce stale reads safely

```sh
script/advanced-checks results/replica-correctness
```

The suite requests pg_wal_replay_pause, waits until replay is actually paused,
writes to the primary, observes the stale replica, verifies a fenced read fails,
then resumes replay in ensure and verifies catch-up. It separately tries a raw
standby write and requires PostgreSQL's read-only error. Cache/replica fixtures
are independent of original orders. Do not pause replay on a production/shared
server. If interrupted by an uncatchable signal, explicitly resume:

```sh
bin/lab --profile replication exec -T replica psql -U rails -d rails_postgres_bottleneck_lab_development \
  -c 'SELECT pg_wal_replay_resume();'
bin/lab exec -T db psql -U rails -d rails_postgres_bottleneck_lab_development \
  -c 'SELECT application_name,state,sent_lsn,write_lsn,flush_lsn,replay_lsn FROM pg_stat_replication;'
```

LSN byte distance and replay state describe actual progress. An old
pg_last_xact_replay_timestamp on an idle primary is not necessarily replication
lag; there may simply have been no transactions to replay.

The replication login is limited to the required login/replication capability,
but this private lab uses trust authentication, not production replication auth.
The HBA file is mounted explicitly so existing primary volumes gain the matching
replication rule. A physical base backup copies the whole cluster (including test
DBs/roles), not just the selected lab table. Keep it local; archives exclude data.

The primary retains at least 128 MB of WAL for reconnecting standbys and uses no
permanent replication slot, avoiding unbounded slot retention. A long-offline
standby can miss required WAL and need a fresh base backup. Its start script never
overwrites an existing non-standby cluster. Reinitialization requires stopping and
explicitly removing only the replica's volume; that destroys the standby copy,
not primary data. Never delete the primary volume to repair a replica.

## Actual validation

[Raw measurements, correctness/fault results and limitations](../validation/phases-5-8-2026-11-08/README.md).
