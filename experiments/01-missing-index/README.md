# Experiment 1: missing composite index

## Hypothesis, not a promised result

The query filters orders for one customer and sorts recent timestamps. Without
an appropriate index, PostgreSQL may scan a large portion of orders and sort the
matches to return a small LIMIT. The optional index aligns the equality prefix
and descending sort, so PostgreSQL can often fetch the first matching rows
without a full scan or explicit sort. Actual plans depend on table size,
selectivity, statistics, cache and PostgreSQL configuration: inspect the plan;
do not assume its shape or invent speedup numbers.

```sql
SELECT orders.* FROM orders
WHERE customer_id = 1
ORDER BY created_at DESC, id DESC
LIMIT 20;
-- Optional optimization:
-- CREATE INDEX CONCURRENTLY index_orders_on_customer_recent
-- ON orders (customer_id, created_at DESC, id DESC);
```

The final ID key preserves deterministic ordering for timestamp ties. A foreign
key does not automatically create the referencing customer_id index in PostgreSQL.
The baseline intentionally omits both a standalone customer index and this
composite index. Model relationships, data correctness and constraints remain.

## Prepare and validate the slow version first

From the repository root:

```sh
script/setup-dev
bin/lab run --rm web bin/rails db:seed
bin/lab run --rm web bin/rails lab:index:disable
RAILS_ENV=benchmark bin/lab up -d --wait web
curl -fsS 'http://127.0.0.1:3000/customers/1/orders?limit=20'
bin/lab exec -T db psql -X -U rails -d rails_postgres_bottleneck_lab_development \
  -c "SELECT indexname, indexdef FROM pg_indexes WHERE tablename='orders';"
```

Confirm one million orders and 10,000 customers for the default experiment. Keep
the same data throughout a comparison. Seeds are uniform and deterministic;
production skew, joins, writes, vacuum pressure and bloat are not modeled yet.

## Investigate PostgreSQL

```sh
# Executes the exact order lookup and returns actual timing/buffer observations:
bin/lab exec -T db psql -X -U rails -d rails_postgres_bottleneck_lab_development \
  -v ON_ERROR_STOP=1 -v customer_id=1 -v order_limit=20 \
  < experiments/01-missing-index/explain.sql
# Observe live queries and waits WHILE another terminal runs load:
bin/lab exec -T db psql -X -U rails -d rails_postgres_bottleneck_lab_development \
  < experiments/01-missing-index/activity.sql
# Cumulative normalized query execution statistics:
bin/lab exec -T db psql -X -U rails -d rails_postgres_bottleneck_lab_development \
  < experiments/01-missing-index/statements.sql
```

In an interactive psql session, run the activity query followed by `\watch 1`.
Look for Seq Scan/Parallel Seq Scan, rows removed by filter, Sort/top-N heapsort,
actual execution time and shared hit/read buffers. A shared hit is a PostgreSQL
buffer-cache hit; a shared read may still be served by the OS cache. EXPLAIN
ANALYZE executes the query and adds instrumentation overhead; its wall time is
not the same metric as Rails request latency.

pg_stat_statements requires shared_preload_libraries at PostgreSQL startup AND
CREATE EXTENSION in the database. Compose and the baseline migration provide
both. track_io_timing is enabled. calls and total/mean_exec_time cover PostgreSQL
execution, not Rails serialization, connection pool waiting or network overhead.
shared_blks_read/hit and temp blocks help explain work, rather than just latency.
Entries are normalized and accumulated; reset before a measured window on this
isolated lab only. Resetting statistics does **not** flush caches. A server restart
does not reliably flush the host OS cache either.

## Controlled before/after procedure

1. Stop unrelated load. Record source revision/dirty state, dataset counts,
   machine, Docker/cgroup support, image versions, CPU/memory limits, shared
   buffers, Rails workers/threads/pool, k6 VUs/duration and request limit.
2. Run `script/experiment baseline results/pair-1-before` with fixed exported
   workload settings. It drops only the optional index, ANALYZEs orders, warms
   the API workload (10 seconds by default), records a representative EXPLAIN,
   resets pg_stat_statements, then measures the configured duration (30 seconds
   by default). It records live activity and CPU/memory samples during the run.
3. Run `script/experiment optimized results/pair-1-after` with the **same** settings
   and dataset. Index construction is concurrent and outside the timed window.
   It verifies index validity, ANALYZEs, and repeats the same warmup and capture.
4. Compare k6 p50/median, p95, p99 (if emitted), throughput and errors, query
   calls/mean/total execution time, buffers, plans, wait events and resource use.
   Inspect failed checks/timeouts rather than excluding them from the report.
5. Repeat at least three pairs, alternating baseline/optimized ordering. Use new
   output paths every time. Summarize dispersion, not just the fastest sample.
   Do not reseed or alter CPU/Rails/k6 settings between members of a pair.
6. Restore the baseline with `bin/lab run --rm web bin/rails lab:index:disable`.
   Stop services with `bin/lab down`. Data remains available for the next run.

```sh
K6_VUS=10 K6_DURATION=30s WARMUP_DURATION=10s \
  script/experiment baseline results/pair-1-before
K6_VUS=10 K6_DURATION=30s WARMUP_DURATION=10s \
  script/experiment optimized results/pair-1-after
```

`results/` is ignored. Each run stores metadata.txt, warmup.txt, plan.json,
k6-summary.json, k6.txt, resources.jsonl, activity.csv and statements.csv. Sampling
includes container startup/teardown intervals; align timestamps with the k6 window.
Index build time is deliberately excluded. Source changes are recorded as dirty;
commit reviewed source before publishing benchmark results. Only publish artifacts
you actually generated, with their machine/configuration and limitations.

This protocol compares **warm steady-state** behavior. Both sides warm the same
workload, but baseline scans and index access naturally populate different cache
pages. Do not claim identical physical cache contents or cold-cache results.
Increase warmup and duration if samples are unstable. ANALYZE may change estimates;
compare the observed plans each time. Tiny tables may not benefit from indexing.

## Manual k6 and concurrency sweeps

```sh
# Make sure the actual dataset has this many customer IDs:
K6_VUS=10 K6_DURATION=30s CUSTOMER_COUNT=10000 \
  bin/lab --profile tools run --rm k6 run /scripts/k6.js
```

Each VU uses a deterministic customer-ID sequence, checks JSON ownership, bounded
size, ordering and HTTP success, and reuses HTTP connections. Closed-loop VUs send
the next request after the previous completes; faster responses therefore increase
request rate. This measures capacity at fixed concurrency, **not** identical
arrival-rate traffic. Iteration counts/customer sequences naturally differ after
optimization; the distribution rule and bounds are fixed. Sweep 1, 5, 10, 20 VUs
as separate pairs, keeping concurrency equal within each pair. Do not silently
increase concurrency only for the optimized side. k6 error thresholds check
correctness, not a made-up latency target.

## Attribute the bottleneck

| Evidence | What to investigate |
| --- | --- |
| Large scan/buffer work and SQL execution time, DB CPU near an enforced quota | PostgreSQL query/index problem is plausible |
| Low DB utilization, Rails CPU high, fast direct SQL but slow HTTP | Ruby, middleware, JSON or Puma capacity |
| Requests queue while pg_stat_activity shows few active queries | Rails threads or connection checkout; inspect logs/pool behavior |
| Low Rails/DB CPU but high HTTP blocked/connecting duration | Client, Docker network or connection establishment |
| k6 CPU saturated, generator cannot increase throughput | Load-generator ceiling; isolate generator before claiming DB capacity |
| wait_event_type=Lock or IO, long transactions | Locking/storage issues, not automatically missing indexes |

Docker stats reports container CPU relative to CPUs, not directly percent of the
configured quota: roughly 200% may represent two fully used cores. Verify actual
cgroup quota enforcement. The sampler collects DB, web and k6 containers; sampling
itself consumes resources. With no cgroup controller, the wrapper marks resource
sampling unavailable instead of reporting misleading host-level values. Sampling
errors (including a k6-container exit race) are retained in resource-errors.log
and resources.jsonl without masking the underlying k6 exit status. For serious capacity results put k6 on another machine
and record network latency and generator utilization. The shared cloud host has
no usable CPU/memory enforcement or trustworthy per-container cgroup statistics; its validation results must not be presented as
controlled CPU-limited database benchmarks.

The optimized API can become Rails-bound; that does not mean PostgreSQL failed
to improve. Conversely, faster HTTP alone does not prove a database bottleneck.
Keep a separate table for SQL execution vs end-to-end latency and report errors.

## Costs and limits of the fix

The index uses disk and cache, adds insert/update work and takes time to build.
CREATE INDEX CONCURRENTLY avoids blocking normal writes for the entire build but
still waits for transactions and consumes CPU/I/O. Stop experiment load before
switching states for comparability. If interrupted, an invalid index can remain;
disable then re-enable it. Normal setup does not change optimization state after
a user enables it; disable explicitly before returning to a baseline. Future
write-load experiments should measure the maintenance cost independently.

## Recorded validation

See [the actual cloud validation pair](validation/2026-11-08/README.md) for raw
outputs and explicit limitations. To generate a table from your own pair:

```sh
bin/lab run --rm --no-deps web ruby script/compare-results.rb \
  results/pair-1-before results/pair-1-after
```
