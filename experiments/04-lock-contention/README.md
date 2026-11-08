# Phase 4 — row locks and transaction duration

This phase uses a separate lab_counters table, not customer/order mutations.
Every successful POST increments row 1 exactly once. The value is reset before
each run with traffic stopped, and the runner verifies the final value equals the
number of acknowledged successful k6 requests. There are no automatic retries.

## Compare identical work under different lock scope

```sh
script/setup-dev
K6_VUS=12 K6_DURATION=15s WORK_MS=100 LOCK_TIMEOUT_MS=50 \
  script/experiment-next locks-long results/locks-before
K6_VUS=12 K6_DURATION=15s WORK_MS=100 LOCK_TIMEOUT_MS=50 \
  script/experiment-next locks-short results/locks-after
```

Both have one process, 12 threads/leases, the same restricted role budget of 16,
identical simulated 100-ms non-database work, a 50-ms lock timeout and the same
counter/traffic distribution. Only the transaction pattern changes:

- **long:** BEGIN; SET LOCAL lock_timeout; SELECT row FOR UPDATE; do simulated
  external work while holding the row lock; atomic increment; COMMIT.
- **short:** do the same external work before checkout/transaction; BEGIN;
  SET LOCAL lock_timeout; atomic UPDATE value=value+1 RETURNING value; COMMIT.

The first pattern serializes unrelated waiting/work behind a hot row. The second
keeps only the data change inside the transaction. It preserves atomic increments
rather than performing a read-modify-write in Ruby that would lose updates.
Moving work out of a transaction is correct only if that work does not depend on
locked state: this synthetic counter example deliberately satisfies that condition.
Do not apply this rewrite blindly to a real multi-row business invariant.

## Find blockers and the transaction holding the lock

In a second terminal while load is active:

```sh
bin/lab exec -T db psql -X -U rails -d rails_postgres_bottleneck_lab_development \
  < experiments/04-lock-contention/blockers.sql
```

Inspect pg_blocking_pids, wait_event_type=Lock, transaction age, and pg_locks.
Row conflicts can be represented as waits on transaction IDs, not just visible
tuple locks. A blocker can be idle in transaction while Ruby is sleeping: low
PostgreSQL CPU does not imply an idle database with no bottleneck. Ordinary idle
connections without a transaction are different. The runner samples this evidence
into locks.txt while k6 is active and retains PostgreSQL/Rails logs.

Lock timeouts return HTTP 423 with error=lock_timeout. They roll back the entire
increment; no partial write is considered successful. Other SQL failures are not
silently relabeled as lock contention. Baseline errors remain failures in the k6
metrics, even when recognized outcome checks pass. The optimized scenario also
enforces <1% HTTP failures. Compare successful latency, failed counts, actual
counter value, blockers and transaction duration rather than aggregate latency
that mixes fast errors with successful operations.

## Correctness, reset and cleanup

Tests use real concurrent PostgreSQL sessions to block a row, verify the waiter's
timeout and rollback, then verify a successful retry after the blocker releases.
Concurrent short increments are tested for lost updates. Controller regression
tests distinguish lock, connection-establishment and Rails-checkout exceptions.

```sh
# Stop traffic before an explicit counter reset:
bin/lab stop web
bin/lab run --rm web bin/rails lab:locks:reset
# This never resets customer/order data or changes the missing-index optimization.
bin/lab --profile pooling down
```

The work/lock parameters are bounded by the API (work 1..2000 ms, lock timeout
1..5000 ms). SET LOCAL makes the lock timeout transaction-scoped; after commit or
rollback it does not leak into another transaction/backend. The response's
lock_round_trip_ms includes SQL/driver time and lock acquisition, not a pure lock
wait measurement; use PostgreSQL wait evidence to diagnose its cause. The
artificial work is Ruby sleep that releases the GVL, not CPU-intensive application
work, disk I/O or an external HTTP service.

Repeated, alternating-order runs with fixed settings are required for stronger
performance claims. This phase teaches a genuine lock mechanism and an applicable
transaction-design principle; it does not model deadlocks, distributed locking,
all transaction isolation anomalies, or full production business workflows.

PostgreSQL lock_timeout applies to an individual lock acquisition, not total
transaction or request duration. Repeated waits/rechecks can exceed that duration
in aggregate without an error. The runner's 50-ms default is shorter than the
100-ms held work to make timeout reproduction likely. It is not an end-to-end
latency deadline. Always report actual timeout counts instead of assuming them.

SQL cancellation (SQLSTATE 57014) is not lock_timeout (55P03). If PostgreSQL or the
driver cancels a query, the API returns 503 query_canceled and k6 records it in
query_cancellations as an unsuccessful request. It is never reclassified as a
lock timeout or retried silently. Inspect the server message and request/driver
context; a cancellation message alone does not establish its origin. Unknown SQL
errors still fail the recognized-outcome check. A validation run caught one such
cancellation and retained its failed artifacts before the explicit mapping was
added. Optimized runs still enforce the HTTP success threshold.

## Actual validation

[Cloud validation, raw artifacts and limitations](../validation/phases-2-4-2026-11-08/README.md).
