# Phase 8 — real database shards, routing and ownership

Two independent PostgreSQL servers (shard-a and shard-b) hold customer-owned data.
This is database sharding, not two Rails workers or a replica mislabeled as a
shard. The single-node reference database lab_single lives on shard-a; lab_shard
holds the even-customer rows on shard-a and odd-customer rows on shard-b.

```sh
script/setup-dev
script/experiment-advanced shard-single results/single-node
script/experiment-advanced shard-sharded results/two-shards
```

Both modes expose the same logical default dataset: one million deterministic
orders across 10,000 customers. The routed mode stores half the logical rows on
each node, not duplicated full copies. Both layouts have the same customer/recent
composite index, so this is not accidentally rerunning the missing-index phase.
The runner never alters the primary application's orders. Shard setup uses fixed
lab hosts/database names, validates deterministic contents and records seed
parameters in each database. Unexpected configuration/data requires an explicit
LAB_RESET_SHARDS=1 reset of only the dedicated shard tables; no hidden resharding.

GET /lab/shards/customers/:id/orders?mode=single|sharded uses Rails native
connected_to shard contexts, scoped to the request/thread. The stable owner rule
is customer_id parity: even -> a, odd -> b. The response identifies the owner.
GET /lab/shards/summary performs a fanout aggregate; it never presents an
incomplete total as a successful complete result when a node fails.

```sh
script/advanced-checks results/shard-correctness
```

Checks compare exact recent-order payloads on both layouts, verify equal complete
counts/sums, stop shard-b, require an even customer's read on a to keep working,
require odd-owner reads to report 503 shard_unavailable, and require the fanout
aggregate to fail explicitly. The stopped node is restored by the wrapper's trap.
There is no automatic fallback that would return empty/wrong-owner data from a.

## Scaling claims and constraints

Both nodes stay up during both modes; the single case directs all traffic to a,
while sharded mode can use both servers. By default each shard has one CPU and
512 MB on supported Ubuntu cgroups; SHARD_CPUS/SHARD_MEMORY configure those caps.
The sharded case has more *active* compute available. Report that resource
increase; do not call this a same-active-CPU comparison or promise linear scaling.
On the current cloud daemon both caps are explicitly disabled and isolated
container resource measurements are unavailable. These runs validate routing and
failure behavior, not controlled horizontal capacity scaling.

Changing customer ownership is an application/data migration, not simply changing
modulo 2 to modulo 3. A real system needs a directory/consistent-hash strategy,
backfill, validation, cutover and handling of in-flight writes. This lab does not
implement online rebalancing, distributed transactions, automatic failover or a
production write allocator. Seed IDs are globally assigned deterministically;
local independent sequences would not provide that guarantee for new writes.
The read-only shard API is explicit about this limit.

Cross-shard joins and global constraints do not become free. Fanout queries add
latency, connections and partial-failure decisions; a cross-shard aggregate is
not one consistent snapshot during concurrent writes. This lab's comparison uses
a fixed read-only dataset. Data ownership and transaction boundaries, rather
than a magical transparent shard abstraction, are the learning objectives.

## Actual validation

[Raw measurements, correctness/fault results and limitations](../validation/phases-5-8-2026-11-08/README.md).
