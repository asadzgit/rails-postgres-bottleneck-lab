# Actual cloud workflow validation — 2026-11-08

This is one short **workflow validation pair**, not a repeatable CPU-limited
capacity benchmark. Raw outputs from the actual commands are included in before/
and after/. No values below are estimated or invented.

## Conditions and commands

- Dataset: 10,000 customers, 1,000,000 orders from the default deterministic seed.
- Ruby 3.4.12 / Rails 8.1.4.1 / PostgreSQL 17.11 / k6 1.0.0; pinned image references
  and source checksums are recorded in metadata.txt. Source was uncommitted.
- Rails benchmark environment, one process, 5 threads, 5 connections.
- PG shared_buffers 128 MB; max_parallel_workers_per_gather 2, work_mem 4 MB,
  effective_cache_size 4 GB, max_connections 100. No settings changed within pair.
- 5 closed-loop VUs, 10-second measured window, 5-second warmup, limit 20.
- This shared cloud Docker daemon has cgroup driver `none`. PG_CPUS=0 and
  PG_MEMORY=0 explicitly disabled resource limits. Per-container cgroup metrics
  were unavailable/untrustworthy and were not used to infer CPU saturation.

```sh
K6_VUS=5 K6_DURATION=10s WARMUP_DURATION=5s \
  script/experiment baseline results/cloud-validation-v2-before
K6_VUS=5 K6_DURATION=10s WARMUP_DURATION=5s \
  script/experiment optimized results/cloud-validation-v2-after
```

Both wrapper commands exited successfully. The orders query call count in
pg_stat_statements matched the number of measured HTTP requests on each side.
All three checks per request passed (HTTP success, ownership/bounds and order).

| Actual metric | Baseline | Composite index |
| --- | ---: | ---: |
| HTTP requests | 552 | 4,861 |
| HTTP requests/second | 54.698 | 485.719 |
| HTTP median (ms) | 88.481 | 9.394 |
| HTTP p95 (ms) | 136.568 | 15.538 |
| HTTP failures / failed checks | 0 / 0 | 0 / 0 |
| Order query mean execution under load (ms) | 76.065 | 0.079 |
| Representative EXPLAIN execution, outside load (ms) | 23.086 | 0.133 |
| Representative EXPLAIN shared buffer hits | 9,702 | 23 |
| Representative EXPLAIN shared buffer reads | 0 | 0 |

The baseline plan was Limit → Gather Merge → Sort → parallel-aware Seq Scan.
The optimized plan was Limit → Index Scan using index_orders_on_customer_recent.
The representative EXPLAIN ran after warmup and before resetting statement stats.
Its instrumented single-query latency is distinct from mean SQL execution under
concurrent load and from end-to-end HTTP latency.

The evidence shows less PostgreSQL scan/sort work and faster order-query execution
with the index in this run. Because caches were warm, the baseline was not a
physical-disk read bottleneck. Without reliable CPU quota/utilization evidence we
cannot claim PostgreSQL CPU saturation. The optimized HTTP latency remains much
larger than SQL execution time; these measurements do not separately identify
Ruby, Puma queueing, network and k6 overhead.

## Limitations and failed attempt

One short pair, fixed order, shared host, no enforced resource isolation, no
multiple-run confidence estimate. Closed-loop throughput increases as responses
get faster; this is not a same-arrival-rate experiment. The customer distribution
rule was identical, but faster execution naturally completed more iterations.
Follow the main experiment guide for longer, repeated/alternating laptop runs.
Do not quote these values as a universal speedup or publish them as CPU-constrained
benchmark results.

An earlier attempt passed all k6 checks but its wrapper stopped on Docker stats
EOF when the short-lived k6 container exited. That incomplete run remains in the
local ignored results/cloud-validation-before directory with FAILED.md; it is not
included in this valid comparison. The wrapper now records resource sampling
errors without hiding k6 failures and explicitly detects unavailable cgroups.

Correctness checks separately passed: 14 tests, 41 assertions, no failures/errors/
skips; RuboCop (34 files), Zeitwerk, Brakeman (zero warnings) and gem audit passed.
The full million-order seed succeeded. GitHub Actions was configured but not run
on GitHub during this local validation. Long-duration laptop resource saturation
and later roadmap experiments have not been validated.

Follow-up portability checks found that a fresh source checkout without master.key
needed an explicit benchmark signing key. Benchmark mode now generates an ephemeral
key at boot; no signing tokens/sessions are exposed. The report above retains the
original actual artifacts from before that boot-only fix and the subsequent CSV
comparison-helper dependency. Neither change modifies the order SQL, seed data or
k6 workload. Index enable/disable idempotency and equality of the exact API response
were also checked after the pair, then the missing-index baseline was restored.

Final checks after the portability fix and helper addition: 14 tests/41 assertions
passed again, RuboCop inspected 35 files without offenses, Zeitwerk and Brakeman
passed, and the updated dependency audit reported no known vulnerabilities. A
read-only clean-source copy with no master.key served the database-backed API
request successfully. Repeating setup preserved Gemfile.lock and db/schema.rb;
the database still had 1,000,000 orders and only orders_pkey after index disable.
All services started for validation were stopped afterward.
