# Phase 5 — Redis cache-aside, invalidation and failure tradeoffs

This phase uses 100 independent lab_cache_items, not the original customer/order
data. A database fetch does a labeled 20-ms pg_sleep to model an expensive backend
round trip. This is connection occupancy, not a claim of real CPU-heavy SQL.
Every item has a value/version; controlled writes increment both atomically.

```sh
script/setup-dev
K6_VUS=10 K6_DURATION=15s script/experiment-advanced cache-off results/cache-before
K6_VUS=10 K6_DURATION=15s script/experiment-advanced cache-on results/cache-after
```

Both cases run Redis and the same Rails/data/workload settings. Both warm the
same deterministic distribution of 100 keys; the cached run uses a 30-second TTL.
The default workload checks actual payload invariants, not just HTTP 200. Record
cache_hits, cache_backend_unavailable, HTTP errors/latency, Redis INFO deltas, and
primary-statements.csv. If a cache backend is unavailable, a correct response can
still come from PostgreSQL; the explicit unavailable metric prevents presenting
fail-open responses as cache hits. The strict load check fails on that condition.

The API is GET /lab/cache/items/:id?cache=0|1&ttl=5&work_ms=20, enabled only by the
lab flag. POST /lab/cache/items/:id/increment commits PostgreSQL first, then deletes
the known Redis key. Serial write/read validation confirms that invalidation
exposes the new version. Keys include the Rails environment, preventing test data
from poisoning benchmark cache keys. lab:cache:clear deletes only the 100 known
namespaced keys; it never runs FLUSHALL. Redis is ephemeral, bounded to 128 MB,
uses allkeys-lru, and exposes no host port. It is not the source of truth.

## Consistency contract: eventual, not linearizable

TTL bounds normal stale entries, but delete-after-write is not a distributed
transaction. A reader can fetch the old database value, a writer can commit and
delete, then that reader can refill the old value until expiry. Out-of-band writes
can similarly remain invisible until TTL. No stampede protection, durable cache
outbox, distributed lock or strong consistency claim is made. Cold/expired keys
may cause concurrent backend reads. Those are explicit tradeoffs to investigate,
not hidden guarantees. Longer TTL improves reuse but extends possible staleness.

Redis commands have bounded connection/read/write timeouts. Errors fall back to
the database with cache_status=unavailable; invalidation failure after a committed
write is returned as cache_invalidated=false, not a rolled-back database write.
Never blindly retry that non-idempotent increment. A real system might add an
outbox, version-based invalidation, admission control or a circuit breaker after
measuring the relevant failure mode.

## Inspect and reproduce failure behavior

```sh
bin/lab --profile cache exec -T redis redis-cli INFO stats
bin/lab --profile cache exec -T redis redis-cli INFO memory
# Full correctness suite includes a controlled stop/restart of Redis:
script/advanced-checks results/advanced-checks
```

The correctness suite shows a miss then a hit, immediate serial invalidation,
an actual stale window after an out-of-band database update, TTL refresh, and a
Redis outage that preserves the returned business value while reporting fallback.
It does not modify Phase 1 orders. Restore services with the commands in the main
README; delete neither PostgreSQL data nor unrelated keys for a cache experiment.

## Actual validation

[Raw measurements, correctness/fault results and limitations](../validation/phases-5-8-2026-11-08/README.md).
