> Historical validation snapshot. Later phases are documented in the current README and the phases 5–8 report.

# Actual phases 2–4 workflow validation — 2026-11-08

These are actual short cloud smoke/reproduction runs, not controlled capacity
benchmarks. Each used 12 VUs and a nominal 5-second load window; in-flight requests
were allowed to finish. No warmup; fresh web clients for each scenario. The cloud
Docker daemon has no usable per-container cgroup controller, so PG_CPUS=0 and
PG_MEMORY=0 explicitly disabled limits and resource samples are labeled unavailable.
Do not infer CPU saturation or laptop capacity from these runs.

## Actual outcomes

Counts below come directly from each k6-summary.json. Successful p95 excludes
unsuccessful responses; expected baseline errors remain failed HTTP requests.

| Scenario | Requests | Successful | Rails checkout timeouts | DB connection errors | Lock timeouts | Query cancellations | Successful p95 ms |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| pool-starved | 877 | 96 | 781 | 0 | 0 | not recorded | 162.296 |
| pool-balanced | 536 | 536 | 0 | 0 | 0 | not recorded | 132.402 |
| db-exhausted | 506 | 180 | 0 | 326 | 0 | not recorded | 130.693 |
| pooled | 200 | 200 | 0 | 0 | 0 | not recorded | 317.723 |
| locks-long | 563 | 47 | 0 | 0 | 516 | 0 | 160.857 |
| locks-short | 555 | 555 | 0 | 0 | 0 | 0 | 131.293 |

The first four runs preceded addition of the dedicated query_cancellations metric;
that column is intentionally marked not recorded, not fabricated as zero. Their
requests reconcile exactly with recorded successes and known failure categories,
and no unrecognized responses occurred. The two lock runs record the metric
explicitly. Source checksums within each before/after pair match; artifact metadata
preserves the code/settings at measurement time, including the uncommitted state.

## Interpretation and evidence

- **Rails pool:** 12 threads and role budget 16 on both sides, checkout timeout
  0.05 s; only pool size changes from 2 to 12. Actual pool snapshots show busy=2
  and waiters in pool-starved. PostgreSQL did not reject those connections. The
  balanced pool completed without request failures.
- **PostgreSQL/PgBouncer:** both use AR pool/threads=12, checkout timeout 2 s and
  non-superuser lab_client connection budget 4. The direct run's time-scoped
  PostgreSQL log contains FATAL too many connections for role lab_client. The
  pooled run completed without refusals; sampled SHOW POOLS reports four server
  backends and waiting clients. The pgbouncer/protocol artifacts identify version
  1.26.1 and verify transaction affinity, prepared/advisory settings and SET LOCAL
  restoration using uncached SQL. PgBouncer did not remove the 100-ms server work:
  it admitted requests and queued them. Its successful latency is higher than
  direct successes; that is a real queueing tradeoff, not a universal speedup.
- **Locks:** same 100-ms external work, 50-ms lock timeout, 12 threads/leases,
  role budget 16 and dedicated counter. locks-long snapshots show Lock wait
  events and pg_blocking_pids, with an idle-in-transaction holder. locks-short
  performs the same work before the transaction and uses an atomic increment.
  Both counter-consistency checks passed; no lost or unacknowledged increments
  were hidden. The optimized short case completed without timeouts/cancellations.

Inspect raw activity, pool, pooler and lock views instead of treating HTTP latency
alone as diagnosis. pg_sleep represents connection occupancy, not CPU-heavy SQL;
Ruby sleep represents external/non-database work, not a production service call.

## Commands used

```sh
K6_VUS=12 K6_DURATION=5s script/experiment-next pool-starved results/phases2-4-release-pool-starved
K6_VUS=12 K6_DURATION=5s script/experiment-next pool-balanced results/phases2-4-release-pool-balanced
K6_VUS=12 K6_DURATION=5s script/experiment-next db-exhausted results/phases2-4-release-db-exhausted
K6_VUS=12 K6_DURATION=5s script/experiment-next pooled results/phases2-4-release-pooled
K6_VUS=12 K6_DURATION=5s script/experiment-next locks-long results/phases2-4-release-v2-locks-long
K6_VUS=12 K6_DURATION=5s script/experiment-next locks-short results/phases2-4-release-v2-locks-short
```

## Failed checks retained and limitations

An earlier lock run returned one unclassified PostgreSQL SQLSTATE 57014 cancellation
("due to user request"). Its strict recognized-outcome threshold failed (exit 99).
That complete failed run is preserved in failed-cancellation-run/, including logs
and counter consistency. Its cancellation origin was not conclusively identified;
Active Record rollback includes query cancellation cleanup, but that is not proof
of causation. The API now exposes query_canceled separately as unsuccessful HTTP
503, and the workload records its own rate. It is never relabeled lock_timeout,
retried silently, or counted as a success. Other unknown SQL errors still fail.
The final lock pair above had no cancellations. Rails/pg dependencies were not
patched or assertions disabled to hide the earlier failure.

An initial pool run also revealed superclass rescue ordering mislabeling a Rails
checkout timeout as a database connection failure. That was fixed with explicit
controller regression tests; its local ignored artifacts have FAILED.md and are
excluded from the final comparison. An early pooler diagnostic also demonstrated
that Rails can cache SHOW/PID queries; the corrected uncached check observed actual
server state and passed. These diagnosis failures are not benchmark successes.

One short pair per scenario, sequential ordering, shared host, no enforced CPU/
memory isolation, and no confidence intervals. Run longer repeated/alternating
pairs on Ubuntu with verified cgroups before publishing capacity conclusions.
An uncached pooler build needs the signed package repositories; pinned PgBouncer
and base versions do not fully lock transitive OS packages. GitHub CI was updated
but was not executed on GitHub here. Redis, replicas, partitioning and horizontal
scaling remain unimplemented. No server-global max_connections exhaustion was
claimed: the reproducible refusal uses a genuine per-role PostgreSQL budget.

## Final correctness and restoration checks

27 tests, 74 assertions passed with no failures/errors/skips, including real
concurrent row locking, rollback, no lost increments, query-cache safety and
exception classification. RuboCop inspected 45 files without offenses; Zeitwerk,
Brakeman (zero warnings) and the dependency audit passed. Compose and shell syntax
checks passed. The archive metadata fallback and overlapping-run rejection were
verified without starting an extra workload.

Normal web configuration was restored and returned 404 for disabled /lab endpoints;
the original recent-orders API still returned the expected JSON. The development
database retained 10,000 customers, 1,000,000 orders, and only orders_pkey on orders.
The only new business-data table is the separate lab counter. No customer/order
seed/reset or index optimization was performed by these phases. Services were
stopped after validation. The backend cloud draft remains uneditable; the updated
proposal is local in docs/environment-config-proposal.json, not a published
configuration. Source is local/uncommitted and has not been pushed.
