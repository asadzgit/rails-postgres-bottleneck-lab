# Rails PostgreSQL Bottleneck Lab

## Purpose and current scope

This is an educational, open-source laboratory for reproducing, observing,
diagnosing and fixing PostgreSQL performance bottlenecks from Rails. It is not a
production SaaS. Build understandable experiments and measured explanations.
Foundation and Phases 1–8 are now authorized: missing indexes, connection pools,
PgBouncer, locks, Redis, physical replicas, range partitioning and database shards.
Optional Prometheus/Grafana observability is included. Keep experiments independent;
do not present the lab as a production deployment or automatic scaling platform.

## Conventions

- Rails 8 API-only, Active Record, PostgreSQL 17, Docker Compose, k6.
- Keep API responses bounded, deterministic and validated. Use integer cents and
  UTC timestamps. Do not add SaaS UI, authentication or background jobs without a request.
- The deliberately missing orders customer index is an experiment requirement,
  not an oversight. Ordinary migrations and db/schema.rb represent the baseline.
- Optional optimization migrations belong in db/optimizations, outside the normal
  migration path. Expose reversible tasks, and do not change data when toggling.
- Bulk seeds use bounded generate_series batches, explicit IDs and fixed data;
  avoid a million Active Record allocations. Require LAB_RESET=1 to replace data.
- Do not invent benchmark outcomes. Retain actual measurements and environment
  metadata. Distinguish SQL execution time, HTTP latency and generator overhead.
- Keep parameters, dataset, Ruby settings, DB limits, warmup and sampling identical
  within a before/after pair. Preserve failed runs rather than deleting errors.
- Never disable TLS verification or commit credentials, keys, caches or .env.
- Use the existing checkout. Cloud tasks are already isolated; do not create Git
  worktrees unless explicitly requested. Preserve existing local changes.

## Workflow and checks

From the repository root:

```sh
script/setup-dev
RAILS_ENV=test bin/lab run --rm web bin/rails test
bin/lab run --rm --no-deps web bin/rubocop
bin/lab run --rm --no-deps web bin/rails zeitwerk:check
bin/lab run --rm --no-deps web bin/brakeman --quiet --no-pager --exit-on-warn --exit-on-error
bin/lab run --rm --no-deps web bin/bundler-audit check --update
```

The wrapper supplies user IDs, the trusted system CA, and a frozen lockfile.
For intentional dependency changes only, use BUNDLE_FROZEN=false and review the
lockfile. Test the baseline using the separate test database. Never seed production.
The lab is local-only with trust authentication on its private Docker network.
Read README.md and experiments/01-missing-index/README.md before benchmarks.
Stop services started for validation with bin/lab down when finished unless the
user asks to leave them running. The external data volume is retained.

## Experiment structure

Each experiment directory contains the load script, SQL investigation queries,
methodology and limitations. Runtime artifacts go in ignored results/. Explicitly
select only reviewed, authentic artifacts for a published report. Keep the
unoptimized version runnable before applying an optimization.

Experiment 1 uses customers and orders, GET /customers/:id/orders, and the optional
(customer_id, created_at DESC, id DESC) index. Do not add a single-column customer
index in the baseline. Foreign keys are intentional even without that index.

## Phases 2–4 conventions

Experiment endpoints require LAB_EXPERIMENT_ENDPOINTS=1 and are always disabled in
production. Use a restricted lab_client role for real connection-budget tests;
never use the superuser to demonstrate a per-role connection limit. Distinguish
Rails pool timeout (503), PostgreSQL connection refusal (503 with a different
error code), row lock timeout (423), and SQL cancellation (503 query_canceled).
Cancellations remain failed requests and must never be labeled as lock timeouts. Rescue subclasses before broad handlers
in Rails lookup order (last registered matching handler wins).

PgBouncer is an optional Compose pooling profile built from a pinned signed
package. Keep backend pool and role budgets bounded and inspect admin views.
Transaction mode disables prepared statements and advisory migration locks in this
lab. Use direct admin connections for migrations; do not assume session SET state
survives transaction pooling. Timeouts that belong to a transaction use SET LOCAL.

Use uncached SQL for live PID/session diagnostics. SQL with side effects (including
UPDATE RETURNING and lock acquisition) uses exec_query, not cacheable select_value.
Lock experiments mutate only lab_counters, verify acknowledged increments against
the final counter, and reset only with traffic stopped. Keep unknown SQL errors
visible. Expected overload responses remain unsuccessful requests in reports.
The script/experiment-next scenarios share one web service: never run them in
parallel. Restore ordinary settings by stopping the pooling profile and starting
web without the runner's child-process overrides. Stop all services after checks.

## Phases 5–8 conventions

Use dedicated cache/replica items, lab_partitioning schema, standby volume and
independent shard databases. Never replace original orders to demonstrate a new
layout. Explicit reset flags affect only the named experiment data. Keep default
Rails migrations focused on small shared fixtures; optional bulk schemas stay
outside public. Normal setup must preserve the missing-index baseline.

Cache-aside is eventual: document stale-fill and failed invalidation windows,
stampedes and TTL tradeoffs. Redis failure is explicit fallback, not a cache hit.
Keys include environment; never FLUSHALL. A committed write is not rolled back
because invalidation fails. Do not retry non-idempotent increments blindly.

The replica is real physical WAL streaming. Pause/resume tests must resume in
ensure. A WAL fence is timeline/cluster specific, not a universal token. Replica
writes must be rejected by PostgreSQL, and unfenced reads can be stale.

Partitioning comparisons need identical logical data and actual EXPLAIN evidence.
Use half-open date bounds; distinguish pruning benefit from index benefit. Shard
ownership is customer-based and stable; changes require real data migration.
Fanout failures must not masquerade as complete aggregates. Native connected_to
contexts are request/thread scoped. Do not invent distributed transactions,
rebalancing or failover guarantees that are not implemented.

script/experiment-advanced runs nine read-load scenarios. script/advanced-checks
validates consistency, pruning and controlled Redis/shard outages with restoration.
All runners share a flock; never run experiments simultaneously. Use actual
measurements only; CPU-limited laptop results are distinct from unlimited cloud
workflow validation. Current optional monitoring is a local read-only viewer and
teaching collector, not a production exporter/alerting system.

Use `bin/lab --profile '*' down` to stop all optional services after work unless
asked otherwise. Do not delete primary, standby, shard or monitoring volumes as
routine cleanup. Source, credentials and existing user data must be preserved.

## Beyond this laboratory

Automatic failover, online resharding/rebalancing, production write-ID allocation,
distributed transactions, production cache consistency and full exporter/alerting
operations are deliberately outside the implemented educational experiments.
They require their own explicit design and validation work, not unsupported claims.
