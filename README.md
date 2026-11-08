# Rails PostgreSQL Bottleneck Lab

A hands-on Rails 8 **API-only** laboratory for learning practical PostgreSQL
scaling. Intentionally reproduce a bottleneck, observe it, explain the cause, and
measure one fix at a time. This is a local educational system, not a production
SaaS. All eight educational phases are implemented: missing indexes, connection
exhaustion, PgBouncer, locks, Redis caching, physical replicas, partition pruning
and customer-owned database shards. Optional Prometheus/Grafana monitoring is included.

## Ubuntu quick start

Install Git and Docker Engine with Compose v2 using the official Docker Ubuntu
instructions: https://docs.docker.com/engine/install/ubuntu/. Verify `docker info`
and `docker compose version` work for your user. Allow several GB for images,
gems and one million orders; keep disk space available for index construction.
The workload is configurable; start with lower concurrency on small laptops.

```sh
git clone https://github.com/asadzgit/rails-postgres-bottleneck-lab.git
cd rails-postgres-bottleneck-lab
cp .env.example .env
script/setup-dev
# This has NOT added the optional customer-order index.
bin/lab run --rm web bin/rails db:seed
# Default: 10,000 customers and 1,000,000 orders.
bin/lab up -d --wait web
curl -fsS http://127.0.0.1:3000/customers/1/orders?limit=20
```

Benchmark mode creates an ephemeral signing key at boot and needs no master key;
this API does not use signed sessions or tokens. It is not production configuration.

The new application source must be committed/pushed before cloning it from GitHub;
the implementation may initially exist only in your working checkout. Source archives
also work without Git metadata: experiments record that fact plus source checksums.
No host Ruby, PostgreSQL or Node installation is required. Images are pinned by
digest; gems are locked in Gemfile.lock and installed in frozen mode. The wrapper
uses your UID/GID and mounts the trusted system CA bundle for Ruby and Git.
Set LAB_CA_BUNDLE if your system bundle is at another path. Preserve the managed
Docker proxy defaults and TLS verification in cloud environments.

PostgreSQL has no host port; Rails binds host port 3000 to loopback. Database trust
authentication and the unauthenticated API are for this local isolated lab only.

## API and data

| Route | Behavior |
| --- | --- |
| `GET /` | API and experiment description |
| `GET /up` | Rails process health (does not assert database health) |
| `GET /customers?limit=20&after_id=100` | Bounded customer keyset pagination |
| `GET /customers/:id` | Customer details |
| `GET /customers/:customer_id/orders?limit=20` | Recent orders; default 20, maximum 100 |

Recent orders sort by `created_at DESC, id DESC`, including stable timestamp ties.
Unknown customers return JSON 404; malformed/oversized IDs or limits return JSON
400. Order amounts are integer cents; statuses and foreign keys have database
constraints. These read-only endpoints focus load on the experiment, not CRUD.

The seed uses fixed UTC timestamps, explicit IDs, evenly distributed customer
ownership and SQL generate_series batches (50,000 by default). There is no Faker
or time-dependent randomness. It avoids one million Ruby objects/callbacks and
runs ANALYZE after loading. Email addresses use the reserved example.test domain.
Existing rows are not overwritten without LAB_RESET=1. Do not run a seed while
load or other writes are active: it takes exclusive table locks and is not atomic
across the full dataset. If interrupted, rerun explicitly with reset.

```sh
# Smaller validation dataset, or deliberately regenerate a controlled dataset:
bin/lab run --rm -e LAB_RESET=1 -e CUSTOMER_COUNT=1000 -e ORDER_COUNT=100000 \
  -e SEED_BATCH_SIZE=10000 web bin/rails db:seed
# Restore the default million-order dataset (explicitly destroys only lab rows):
bin/lab run --rm -e LAB_RESET=1 web bin/rails db:seed
```

Bounds: 1..1,000,000 customers, 1..20,000,000 orders, 1..100,000 per batch. IDs,
timestamps and values for a given configuration are identical on rerun. Changing
a count intentionally changes the dataset. The lab seed is rejected in production.

## Experiment 1: missing index

Read the full [investigation and comparison guide](experiments/01-missing-index/README.md).
The baseline has primary keys and a customer foreign key, but **no orders customer
lookup index**. Ordinary setup/migrations leave it unoptimized. The optional
concurrent migration is in `db/optimizations/`, outside the normal migration path.

```sh
# Same dataset, Rails settings, resource limits and workload for both runs:
K6_VUS=10 K6_DURATION=30s WARMUP_DURATION=10s \
  script/experiment baseline results/pair-1-before
K6_VUS=10 K6_DURATION=30s WARMUP_DURATION=10s \
  script/experiment optimized results/pair-1-after
# Return to the deliberately slow baseline without removing data:
bin/lab run --rm web bin/rails lab:index:disable
```

The script switches to the non-reloading `benchmark` Rails environment, warms the
workload, captures EXPLAIN (ANALYZE, BUFFERS), resets statement statistics, runs k6,
samples containers and active queries, and retains summaries/metadata. It derives
the customer count from the seeded database. Existing output directories are never
overwritten. It does not reseed or change resource limits between the pair.
It leaves services running for investigation; stop them when done.

```sh
# Manual optimization controls (never automatic in db:prepare):
bin/lab run --rm web bin/rails lab:index:enable
bin/lab run --rm web bin/rails lab:index:disable
# Inspect database directly:
bin/lab exec db psql -U rails -d rails_postgres_bottleneck_lab_development
# Stop services, retain data:
bin/lab down
```

## Resource controls

`.env` is ignored. The default example limits PostgreSQL to 2 CPUs and 1 GiB;
shared_buffers is 128 MB and shared memory is 256 MB. Change PG_CPUS, PG_MEMORY,
PG_SHARED_BUFFERS and PG_SHM_SIZE, then recreate the DB service. Verify Docker's
reported limits **and** host cgroup enforcement before interpreting results.
With 1 GiB memory the OS page cache and working set also matter.

```sh
bin/lab up -d --force-recreate --wait db
bin/lab exec -T db psql -U rails -d rails_postgres_bottleneck_lab_development \
  -c 'SHOW shared_preload_libraries; SHOW track_io_timing; SHOW shared_buffers;'
docker inspect "$(bin/lab ps -q db)" --format '{{.HostConfig.NanoCpus}} {{.HostConfig.Memory}}'
docker stats
```

Some rootless/cloud Docker daemons have no usable cgroup controller. Explicitly
set PG_CPUS=0 and PG_MEMORY=0 on those hosts; limits are then **disabled**, not
simulated. Docker stats may be unavailable/zero there. Such runs validate the
workflow but are not CPU-limited scaling evidence. Do not compare them with
laptop runs or claim controlled PostgreSQL saturation from them.

Rails defaults to one process, five threads and five database connections.
RAILS_MAX_THREADS, DB_POOL, DB_CHECKOUT_TIMEOUT and WEB_CONCURRENCY are configurable; each worker has its own
pool. Keep these fixed within a pair. Too few Rails threads can dominate latency;
too many workers/connections are a separate future experiment.

## Phases 2–4

Apply the new counter migration once with `script/setup-dev`. These experiments do
not require the million-order seed, alter orders, or toggle the Phase 1 index.
Run scenarios sequentially (a checkout-wide file lock rejects overlap); each restarts the web client to set a known connection
budget. Default duration is 15 seconds and default concurrency is 12 VUs.

```sh
# Phase 2: same database budget, fix only the undersized Rails pool:
script/experiment-next pool-starved results/pool-before
script/experiment-next pool-balanced results/pool-after
# Phase 3: same constrained DB role budget, add a bounded transaction pool:
script/experiment-next db-exhausted results/direct
script/experiment-next pooled results/pooled
# Phase 4: same non-DB work and counter update, shorten transaction/lock scope:
script/experiment-next locks-long results/locks-before
script/experiment-next locks-short results/locks-after
bin/lab run --rm --no-deps web ruby script/summarize-next.rb \
  results/pool-before results/pool-after results/direct results/pooled \
  results/locks-before results/locks-after
bin/lab --profile pooling down
```

Read the detailed guides for [connection exhaustion](experiments/02-connection-exhaustion/README.md),
[PgBouncer](experiments/03-pgbouncer/README.md), and [locks](experiments/04-lock-contention/README.md).
HOLD_MS, WORK_MS, LOCK_TIMEOUT_MS, K6_VUS and K6_DURATION are configurable; keep
applicable values identical within a pair. Do not compare a deliberately failing
baseline's mixed success/error latency with successful-only optimized latency.

Runs retain time-scoped PostgreSQL/Rails logs, live pool/lock snapshots, actual
k6 results, and metadata. The lock runs additionally verify the counter; pooled
runs perform an uncached transaction/protocol check after measurement.

The lab API adds GET /lab/connections, GET /lab/pool, and POST /lab/locks/increment.
They require LAB_EXPERIMENT_ENDPOINTS=1 (set by the runner), reject unbounded
parameters, and always return 404 in production. Ordinary startup leaves them
disabled. The PgBouncer profile exposes no host port. It builds from a signed
pinned package using the system CA; an uncached build requires network access.
New phases preserve customer/order data; the lock runner explicitly resets only
its dedicated counter with traffic stopped. Expected overload failures are
recorded separately from successful requests, not hidden by passing checks.

## Phases 5–8 and monitoring

New fixtures/schemas are separate from original customers/orders. The physical
standby and two real shard servers use independent volumes and private ports.
A full validation setup needs disk for a primary copy, standby, two event layouts,
and the single/sharded reference datasets. Defaults are one million logical rows
per bulk experiment; no million-row Active Record object loops are used.

```sh
script/setup-dev
# Consistency, actual pruning, cache/replica behavior, and restored fault injection:
script/advanced-checks results/advanced-checks
# Sequential equivalent-setting read-load comparisons:
script/experiment-advanced cache-off results/cache-before
script/experiment-advanced cache-on results/cache-after
script/experiment-advanced read-primary results/reads-primary
script/experiment-advanced read-replica results/reads-replica
script/experiment-advanced partition-heap results/events-heap
script/experiment-advanced partition-fanout results/events-fanout
script/experiment-advanced partition-pruned results/events-pruned
script/experiment-advanced shard-single results/single-node
script/experiment-advanced shard-sharded results/two-shards
bin/lab --profile '*' down
```

K6_VUS, K6_DURATION and WARMUP_DURATION configure advanced comparisons (defaults
10 VUs, 15 seconds and 3 seconds). Keep them fixed within a pair. The workload
verifies actual payloads, ownership, aggregates and expected read versions; Redis
fallback is not silently counted as a cache hit. Existing result directories are
never overwritten. A source archive without Git metadata is supported and labeled.

Read the guides: [Redis](experiments/05-redis-caching/README.md),
[read replicas](experiments/06-read-replicas/README.md),
[partitioning](experiments/07-partitioning/README.md),
[horizontal scaling](experiments/08-horizontal-scaling/README.md), and
[Prometheus/Grafana](docker/monitoring/README.md). They distinguish consistency and
failure behavior from throughput, and enumerate the guarantees not implemented.
The optional monitoring profile is a loopback-only provisioned Viewer dashboard,
backed by actual Prometheus scrapes; no production authentication claim is made.

Advanced datasets are prepared idempotently. EVENT_COUNT configures both partition
copies; SHARD_CUSTOMERS (even) and SHARD_ORDERS configure shard/reference copies.
Changing existing data requires explicit LAB_RESET_EVENTS=1 or LAB_RESET_SHARDS=1
on the dedicated preparation task, with traffic stopped. Do not change settings
only on one side of a comparison or silently substitute a smaller dataset.
Physical replica initialization never overwrites an existing non-standby cluster.
All optional services are stopped by the quoted-wildcard down command above;
volumes persist and require deliberate removal if data must be discarded.

## Tests and checks

```sh
RAILS_ENV=test bin/lab run --rm web bin/rails test
bin/lab run --rm --no-deps web bin/rubocop
bin/lab run --rm --no-deps web bin/rails zeitwerk:check
bin/lab run --rm --no-deps web bin/brakeman --quiet --no-pager --exit-on-warn --exit-on-error
bin/lab run --rm --no-deps web bin/bundler-audit check --update
```

Tests cover bounded JSON API responses, customer isolation, stable ordering,
invalid inputs, model validation, the deliberately unindexed baseline, deterministic
bulk seeds and reset protection. CI uses the same Compose setup with PostgreSQL
statistics enabled. Tests use a separate database and do not require a million-row
seed. For intentional dependency updates only, set BUNDLE_FROZEN=false and review
the lockfile. `script/setup-dev` is repeatable; it never seeds or toggles the index.

## Troubleshooting

- **Missing pg_stat_statements preload:** recreate db after changing its command;
  creating the extension alone is insufficient. Run normal migrations in each DB.
- **CPU quota/cgroup error:** check `docker info`; use the explicit unlimited cloud
  override above if unsupported. Do not present unlimited runs as constrained.
- **Port 3000 busy:** stop the conflicting server; do not benchmark the wrong app.
  Inspect `bin/lab logs web` and `curl /` before load.
- **Existing seed data:** inspect it first; LAB_RESET=1 intentionally replaces only
  customers/orders. Do not seed a shared or production database.
- **Index build exceeds the request statement timeout:** use `bin/lab run --rm -e PG_STATEMENT_TIMEOUT=0 web bin/rails lab:index:enable` for that dedicated migration process; keep request timeouts unchanged.
- **Invalid index after interrupted concurrent build:** with no load, run
  lab:index:disable, then lab:index:enable. Index enable validates indisvalid.
- **Permission/CA errors:** invoke bin/lab as your regular user, check the mounted
  CA path and Docker proxy settings. Never bypass TLS verification.
- **Slow or failed HTTP requests:** inspect k6 errors, Rails logs, pool waits,
  PostgreSQL wait events/plans and container CPU; latency alone does not prove a
  database bottleneck. A statement timeout is counted as a failed request.
- **Changing dataset size:** use reset and update manual k6 CUSTOMER_COUNT to the
  actual seeded number. The experiment wrapper derives it automatically.
- **Insufficient disk/memory:** reduce ORDER_COUNT for a smoke test, label it as
  such, and record the new dataset and limits. Never silently substitute results.

The external rails-lab-pgdata volume and ignored .bundle/gems cache survive service
shutdown. `docker volume rm rails-lab-pgdata` destroys the entire lab database;
do that only when you intentionally want to discard all retained lab data.

See [AGENTS.md](AGENTS.md) for conventions and the future roadmap. Authentic
validation results, when recorded, are separate from expected plan behavior.

## License

[MIT](LICENSE).
