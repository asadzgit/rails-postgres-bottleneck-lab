# Phase 2 — Rails pools versus PostgreSQL connection exhaustion

These are **two different failures**. A Ruby process can run out of pool leases
while PostgreSQL has spare connections; PostgreSQL can also reject a new session
because a restricted application role has reached its actual connection limit.
The experiment reports separate JSON error codes rather than calling both a
"database timeout". No missing-index query or million-row seed is needed here.

## Prepare and run the Rails-pool pair

From the repository root, run script/setup-dev to apply the baseline migrations.
The runner enables the local-only experiment endpoints, restarts web to release
old sessions, creates/verifies a non-superuser lab_client role, and grants only
SELECT on customers/orders/counters and UPDATE on the dedicated counter. Normal
migration/monitoring commands use the separate rails administrator role.

```sh
K6_VUS=12 K6_DURATION=15s script/experiment-next pool-starved results/pool-before
K6_VUS=12 K6_DURATION=15s script/experiment-next pool-balanced results/pool-after
```

Both use one Puma process, 12 threads, 100 ms of database work per request,
checkout_timeout=0.05 seconds and a database role budget of 16. Only AR pool size
changes: 2 → 12. The short checkout deadline makes the undersized pool's failure
visible; it is an experimental setting, not a general production recommendation.
`GET /lab/connections?hold_ms=100` times checkout and the actual SELECT round trip.
It holds a real connection using pg_sleep; this simulates occupancy, not DB CPU
work. 12 threads can demand more leases than the pool's 2 available connections.

Increasing pool size helps only while a real server connection budget can support
it. Raising pool and thread counts without a budget can move the failure into
PostgreSQL. An alternative to a larger pool is bounded admission/concurrency and
longer checkout waits, with explicit queue-latency tradeoffs; it does not create
more database capacity. Pool capacity is per process, not per Rails application.

## Observe the distinction

```sh
# Same Puma process's actual pool state (does not acquire a DB lease):
bin/lab exec -T web curl -fsS http://127.0.0.1:3000/lab/pool
# PostgreSQL sessions, role budget, wait events and connection counts:
bin/lab exec -T db psql -X -U rails -d rails_postgres_bottleneck_lab_development \
  < experiments/02-connection-exhaustion/activity.sql
```

| Symptom | Diagnosis |
| --- | --- |
| 503 rails_pool_timeout; busy reaches AR pool size; waiting > 0; PG sessions below budget | Rails checkout starvation |
| 503 database_connection_unavailable; PostgreSQL logs FATAL too many connections for role lab_client | Actual PostgreSQL role connection-budget refusal |
| Few active sessions, low CPU, many ClientRead/idle connections | Session occupancy, not necessarily active database load |
| 503 query_canceled | SQL statement interrupted; diagnose its actual source separately |
| pg_sleep sessions show Timeout/PgSleep | Intentional occupancy/sleep, not expensive SQL or CPU saturation |

The runner samples both /lab/pool and pg_stat_activity while k6 is active. Pool
statistics are process-local and only meaningful for this one-process setup; do
not query a new rails runner process and treat its separate pool as the web pool.
Puma queues ahead of the controller are not included in checkout_wait_ms. The
reported database_round_trip_ms includes driver/network time and any PgBouncer
queue later; it is not pure server execution time.

## Reproduce server-side refusal

```sh
K6_VUS=12 K6_DURATION=15s script/experiment-next db-exhausted results/db-direct
```

This holds AR pool=12, checkout_timeout=2 seconds, threads=12, but sets
**lab_client CONNECTION LIMIT 4**. It uses a restricted login because superusers
can bypass role connection limits. The normal rails administrator stays available
for observation. The limit is a genuine PostgreSQL role-level connection budget,
not the cluster-wide max_connections setting. PG_MAX_CONNECTIONS is separately
configurable in Compose (default 100); changing it requires recreating db. Leave
room for admin/reserved sessions; do not lower it indiscriminately on shared DBs.
The runner rejects an existing privileged role instead of silently treating it as
a safe experiment account. Stop old web/PgBouncer sessions before changing limits.

Proceed to [Phase 3](../03-pgbouncer/README.md) to repeat the same client load and
server-role budget through a bounded transaction pool.

## Results and reproducibility

HOLD_MS, K6_VUS and K6_DURATION are configurable. Keep them the same within a pair;
record client settings, role budget, Rails threads/pool, image/source versions,
resource limits and actual responses. The runner uses fresh web clients on each
run and no warmup; these experiments deliberately include lazy-connection startup
and rejection behavior. This differs from Phase 1's warm query-capacity protocol.
Repeat longer runs and alternate order before publishing capacity conclusions.

All responses appear in http_req_failed and successful_requests. Baseline expected
503s are **not successes**, even though the `checks` threshold confirms their error
codes are recognized. pool-balanced additionally requires <1% HTTP failures;
unknown statuses/payloads fail every scenario. Do not interpret fast failures as a
latency improvement. Use successful_latency alongside failure rate and counts.
Raw output and diagnostic snapshots go into the selected ignored results directory;
existing directories are never overwritten.

```sh
bin/lab run --rm --no-deps web ruby script/summarize-next.rb results/pool-before results/pool-after results/db-direct
# Restore ordinary service settings by recreating with default shell/.env values:
bin/lab --profile pooling down
bin/lab up -d --wait web
# Default LAB_EXPERIMENT_ENDPOINTS=0 makes all /lab endpoints return 404.
bin/lab down
```

The experiments do not toggle the Phase 1 orders index or alter customer/order
data. Lab endpoints are explicitly enabled by the runner, bounded in duration,
and always disabled in Rails production. This is still an unauthenticated local
lab: keep its private Docker network and loopback-only web binding.

## Actual validation

[Cloud validation, raw artifacts and limitations](../validation/phases-2-4-2026-11-08/README.md).
