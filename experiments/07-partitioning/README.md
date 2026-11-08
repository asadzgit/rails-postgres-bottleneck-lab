# Phase 7 — range partitioning and actual pruning

The dedicated lab_partitioning schema contains events_heap and a twelve-month
range-partitioned events_partitioned table with identical deterministic logical
data. Both have the same (id, occurred_at) primary-key shape; there is no standalone
time index silently favoring one layout. Original orders and their optional index
are unchanged. Keeping experiment tables outside public also excludes them from
the ordinary public-schema Rails schema dump.

```sh
script/setup-dev
script/experiment-advanced partition-heap results/events-heap
script/experiment-advanced partition-fanout results/events-all-partitions
script/experiment-advanced partition-pruned results/events-pruned
```

Defaults prepare one million rows in each layout using bounded SQL batches, fixed
2024 timestamps and integer amounts, then ANALYZE both. Existing unexpected counts
cause an error rather than silent reseeding. To intentionally change size, stop
traffic and run an explicit reset of only these tables:

```sh
bin/lab run --rm -e LAB_RESET_EVENTS=1 -e EVENT_COUNT=100000 web bin/rails lab:partitions:prepare
EVENT_COUNT=100000 script/experiment-advanced partition-pruned results/events-smaller
```

The request sums/counts June events with half-open bounds >= June 1 and < July 1.
GET /lab/partitions/summary accepts layout=heap|partitioned, pruning=0|1, from and
to ISO dates bounded to the prepared year. It validates table choices and quotes
date values; arbitrary table/SQL input is not allowed. SET LOCAL toggles pruning
inside the request transaction, not a persistent global server setting.

Compare three conditions: the heap baseline; the *same partitioned table* with
pruning disabled (fanout); and with pruning enabled. The last two isolate the
planner's pruning mechanism more directly than comparing two physical layouts.
A full-year control query cannot prune most partitions, so it need not improve.
Partitioning is not a universal replacement for appropriate indexes.

```sh
script/advanced-checks results/partition-correctness
```

The check saves actual EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) plans and verifies
one June child with pruning versus twelve scanned child relations without it.
All three aggregates must be identical. Unit tests also exercise half-open month
boundaries. Inspect relations, planning/execution time, buffers and rows, not only
HTTP latency. Record actual dataset size, dates, statistics and resource settings.

A partitioned unique/primary key must contain its partition key here; globally
unique id alone is not enforced across these partitions. There is deliberately no
catch-all default partition: out-of-range inserts fail instead of silently growing
an unmaintained bucket. Real designs need lifecycle automation, partition creation
before writes, retention, index/FK tradeoffs and migration plans. Dropping an old
partition deletes its data; no automatic retention deletion is implemented.
The comparison is for read pruning, not a production online repartitioning tool.

## Actual validation

[Raw measurements, correctness/fault results and limitations](../validation/phases-5-8-2026-11-08/README.md).
