# Phase 3 — PgBouncer transaction pooling

The goal is to share a bounded number of PostgreSQL backend sessions across more
Rails client connections. Pooling can avoid connection refusal; it does not make
active queries run infinitely in parallel or repair expensive SQL, Rails pool
starvation, or long-held locks. Waiting moves to a new queue that must be observed.

## Build and run the equivalent-condition pair

```sh
script/setup-dev
K6_VUS=12 K6_DURATION=15s script/experiment-next db-exhausted results/direct
K6_VUS=12 K6_DURATION=15s script/experiment-next pooled results/pooled
```

Both scenarios use 12 threads, 12 Active Record leases, a 2-second Rails checkout
timeout, identical 100-ms pg_sleep work, and the same PostgreSQL non-superuser
role limit of 4. The direct case can open too many server sessions and receives
refusals. The pooled case changes the connection path to PgBouncer on internal
port 6432, using transaction pooling, default_pool_size=4, max_db_connections=4,
no reserve pool, and max_client_conn=200. No host PgBouncer port is published.

The runner stops/recreates client services before changing state. Do not run two
scenarios simultaneously: they share the same web service and lab_client role.
Keep K6_VUS/HOLD_MS/duration/resources identical, and investigate errors as well as
successful request latency. More accepted work can have higher latency than a
small set of direct successes because queued clients now complete rather than
being rejected. Report throughput, success fraction and queue waits together.

The image is built from the pinned PostgreSQL base and the signed PostgreSQL APT
package pgbouncer=1.26.1-1.pgdg12+1. TLS CA trust is supplied through a BuildKit
secret; APT signatures remain enabled. This package and its dependencies still
require network access for an uncached build. The PgBouncer version/package and
SHOW CONFIG are recorded in each pooled run. If a repository eventually retires
that package version, update the explicit version after review; do not bypass
package signatures or TLS checks to make a build pass. The base image is pinned,
but transitive OS package versions are not a complete immutable OS lockfile.

## Rails compatibility is explicit

LAB_DB_HOST/LAB_DB_PORT/LAB_DB_USER select the route; PGBOUNCER=1 disables Rails
server-side prepared statements and advisory migration locks. The PgBouncer config
also explicitly sets max_prepared_statements=0. Newer PgBouncer versions can support
protocol-level prepared statements with suitable configuration; this lab chooses
the simpler portable disabled configuration, rather than claiming all transaction
poolers are incompatible with prepared statements.

Never run schema migrations through the restricted transaction-pooling endpoint.
Use the direct rails admin connection instead. Active Record's normal initialization
uses consistent settings across these clients. Per-session state does not belong
to a stable backend in transaction mode: avoid session advisory locks, temporary
tables requiring session affinity, LISTEN, and arbitrary persistent SET state.
When PGBOUNCER=1, the normal session-level statement_timeout setting is intentionally
not sent. Use role/database defaults established by an admin, or SET LOCAL inside
an explicit transaction when a request requires specific timeouts. Phase 4's lock
service demonstrates SET LOCAL; its recorded comparison uses the direct route.
query_wait_timeout=10 seconds bounds PgBouncer's server-pool wait, and k6 has a
15-second HTTP timeout. Failures are still recorded if queues exceed those bounds.

## Inspect both sides of the pool

```sh
bin/lab --profile pooling exec -T pgbouncer psql -X -h 127.0.0.1 -p 6432 -U rails -d pgbouncer \
  -c 'SHOW POOLS;' -c 'SHOW STATS;' -c 'SHOW CLIENTS;' -c 'SHOW SERVERS;'
bin/lab exec -T db psql -X -U rails -d rails_postgres_bottleneck_lab_development \
  < experiments/02-connection-exhaustion/activity.sql
```

cl_active/cl_waiting describe clients; sv_active/sv_idle describe PostgreSQL
servers. SHOW STATS includes wait/time counters (check the installed version's
column names and units). PostgreSQL should show no more than four lab_client
sessions from this pool. An app client may be connected to PgBouncer without
occupying a backend at that instant. Samples are observations, not continuous
proof of a maximum; the configured server/role caps provide the enforcement.
The runner records these views during load, not only once after it ends.

This local configuration deliberately uses trust authentication with a user list
containing only lab_client and the admin identity rails. There are no passwords
in userlist.txt. Neither this authentication nor the shared database administrator
is a production deployment recommendation. Admin console access is internal-only.

The automated post-load protocol check runs uncached SQL to verify transaction
backend affinity, an Active Record bound predicate, and SET LOCAL cleanup. This
matters: Rails query caching can return an earlier SHOW/pg_backend_pid result and
create a false appearance of leaked state or stable backend identity. Use uncached
queries or a direct psql connection for these observations.

## Restore and troubleshoot

```sh
bin/lab --profile pooling down
# Recreate without the runner's child-process overrides: default direct connection.
bin/lab up -d --wait web
bin/lab down
```

- Connection refused: inspect pooler health/logs and internal port 6432.
- Too many connections persists: stop old direct clients, inspect role budget,
  SHOW SERVERS and whether a different app process bypasses the pooler.
- Rails pool timeout persists: PgBouncer does not enlarge the app's pool or threads.
- Query wait timeout: backend work/transactions are too slow for the chosen pool;
  inspect wait queues and latency, not just backend count.
- Prepared/session-state errors: confirm both PGBOUNCER=1 and pooler config; do not
  enable a feature without testing the transaction-pooling compatibility contract.
- Permission denied reading config: configs have public read permissions because
  they contain no secrets and the pooler runs as the non-root postgres user.

Cloud CPU/memory enforcement remains unavailable on the current rootless daemon.
Real role limits, protocol pooling, queues and SQL waits can be validated there;
capacity claims and isolated resource benchmarks require a suitable laptop/host.

## Actual validation

[Cloud validation, raw artifacts and limitations](../validation/phases-2-4-2026-11-08/README.md).
