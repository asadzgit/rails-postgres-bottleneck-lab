# Actual phases 5–8 and monitoring validation — 2026-11-08

These are real short cloud workflow validations, not controlled laptop capacity
benchmarks. Each read-load run used 5 VUs, a nominal 5-second measured window,
2-second warmup, one Rails process/10 threads/10 connections. All raw artifacts
are retained here. Primary and shard CPU/memory caps were explicitly disabled
because the cloud daemon lacks usable cgroup enforcement. Services share one
host; do not infer production scaling ratios or resource-isolated throughput.

## Actual load observations

| Scenario | Requests | HTTP failures | HTTP p95 ms | Cache hit fraction |
| --- | ---: | ---: | ---: | ---: |
| cache-off | 1042 | 0 | 29.151 | 0.0000 |
| cache-on | 5528 | 0 | 7.187 | 1.0000 |
| shard-single | 3618 | 0 | 11.423 | 0.0000 |
| shard-sharded | 2359 | 0 | 23.640 | 0.0000 |
| read-primary | 5110 | 0 | 8.406 | 0.0000 |
| read-replica | 4878 | 0 | 8.362 | 0.0000 |
| partition-heap | 269 | 0 | 173.221 | 0.0000 |
| partition-fanout | 268 | 0 | 148.098 | 0.0000 |
| partition-pruned | 1452 | 0 | 27.034 | 0.0000 |

No request failed its payload/route/aggregate checks. Paired source checksums
match. Cache runs use 100 keys, 30-second TTL and a deliberately labeled 20-ms
PostgreSQL pg_sleep miss cost. The hit fraction applies only to cache cases;
zero for non-cache cases means not a cache workload, not a failed cache.
Metadata records actual source/dirty state, settings, image IDs and resources.

### Interpret what actually happened

- Cache-on bypassed the simulated backend work and had lower HTTP latency in
  this run. The 100% measured hit fraction followed warmup; it is not a promise
  about cold caches, expiry, stampedes, eviction or writes in production.
- Read traffic really moved: primary mode recorded 5,110 item-read statements on
  the primary and none on the replica; replica mode recorded 4,878 on the standby
  and none on the primary. HTTP latency was essentially unchanged. The tiny query
  averaged roughly 0.010–0.011 ms in PostgreSQL, so these HTTP results are not
  evidence of a PostgreSQL CPU bottleneck or a replica speedup.
- The same partitioned dataset with pruning off scanned twelve child relations;
  pruning on selected only June. All layouts returned exactly 81,960 June rows
  totaling 4,106,342,220 cents. Actual instrumented plans are in correctness/.
  The heap and fanout comparisons had higher HTTP latency than pruning in this
  short run; inspect buffers/actual plans rather than inferring from HTTP alone.
- Sharded routing was **slower**, not faster, in this short shared-host indexed
  lookup test. The single database executed 3,618 reads; sharded mode executed
  1,180 on a and 1,179 on b (2,359 total). Both expose the same logical million
  rows; the two shard copies have 500,000 each. This validates real ownership and
  traffic distribution, not a performance win. Do not rename it a universal
  optimization or hide the result. More active nodes, driver connections and
  fanout add costs; hardware/cache/Rails limits require separate diagnosis.

## Consistency and actual fault injection

The complete saved script/advanced-checks procedure ran successfully:

- Cache miss/hit, committed serial write plus invalidation, actual stale data
  after an out-of-band write, then TTL refresh. Stopping Redis returned correct
  PostgreSQL data with explicit unavailable status. Redis was restarted.
- An actual physical standby was paused. A primary write advanced the row from
  version 1 to 2; the paused replica still returned version 1. A minimum-LSN read
  returned HTTP 409, replay was resumed in ensure, then the fence returned the
  updated row. A raw standby write was rejected by PostgreSQL read-only mode.
- Real EXPLAIN plans and matching aggregates demonstrated one-versus-twelve
  relations. Unit tests separately cover half-open boundaries.
- Exact recent-order payloads and complete aggregates matched single versus
  sharded layout: 1,000,000 rows and 50,099,500,000 cents. Stopping b left a's
  customer available, returned 503 for b's customer, and rejected an incomplete
  fanout aggregate. The stopped shard was restarted.

These are deliberately bounded local tests on separate fixtures, schemas and
servers. No customer/order data in the original application was replaced.
Cache-aside remains eventual, and the shard API is read-only: no distributed
transaction, online rebalancing, production write allocator or automatic failover
was claimed or implemented.

## Monitoring

script/monitoring passed its complete startup/readiness procedure. Real metrics
were scraped by Prometheus 3.16.0; Grafana 13.3.0 provisioned ten Viewer panels and
successfully queried the actual datasource through its API. Images are pinned to
resolved official digests. The proof is in monitoring/monitoring.json. This is a
local teaching collector/dashboard, not a complete production exporter/SLO stack.
Automated read comparisons stopped the observer profile to avoid unequal scrape
overhead. No container CPU measurements were fabricated when cgroups were absent.

## Reproduction and exclusions

```sh
K6_VUS=5 K6_DURATION=5s WARMUP_DURATION=2s script/experiment-advanced cache-off results/advanced-final-cache-off
K6_VUS=5 K6_DURATION=5s WARMUP_DURATION=2s script/experiment-advanced cache-on results/advanced-final-cache-on
# The seven other names are read-primary, read-replica, partition-heap,
# partition-fanout, partition-pruned, shard-single and shard-sharded.
script/advanced-checks results/advanced-final-correctness
script/monitoring results/advanced-final-monitoring
```

Existing output directories are never overwritten. Change paths for another run.
For credible capacity work use longer repeated/alternating pairs on a suitable
Ubuntu host, verify cgroup caps and generator utilization, and report all errors.
The shard case uses extra active compute, not an undisclosed identical-CPU budget.
An initial cache pair crossed a SQL-quoting refactor; its checks passed but source
checksums differed, so it was excluded and both cache runs were repeated. Security
warnings were corrected through explicit SQL quoting, not suppressed. The earlier
individual smoke runs are not substituted for the complete recorded procedure.
GitHub CI was updated but not executed on GitHub. No new environment publication,
fresh-task snapshot restoration, public release or remote push was performed.

## Final checks and cleanup

36 tests and 110 assertions passed, with no failures/errors/skips. RuboCop checked
66 Ruby files without offenses; Zeitwerk, Brakeman (zero warnings) and the updated
dependency audit passed. The complete saved correctness/fault and monitoring
startup scripts executed successfully, not merely their helper commands.

Ordinary startup was restored: original recent-order JSON still worked, all lab
advanced/metrics routes returned 404, and primary data retained 10,000 customers,
1,000,000 orders and only orders_pkey on orders. The standby was in recovery and
not paused. Repeating setup preserved Gemfile.lock and db/schema.rb; experimental
partition tables did not leak into the baseline public schema. All application,
cache, standby, shard and monitoring services were then stopped; volumes retained.

The source remains local/uncommitted/not pushed. The cloud startup proposal was
updated locally in docs/environment-config-proposal.json, but the backend draft
remains locked; no publication or new-task restoration claim is made.
