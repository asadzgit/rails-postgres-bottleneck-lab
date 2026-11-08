# Optional Prometheus and Grafana

The profile provides actual PostgreSQL/Redis/process-pool metrics, not fabricated
chart data. Images are pinned by digest; the validated versions are recorded in
results. The dashboard has connections, active sessions, lock waiters, transaction
and buffer counters, Redis hits/misses, pool waiters and backend availability.

```sh
script/monitoring results/monitoring-check
```

On an Ubuntu laptop, Prometheus is bound to loopback port 9090 and Grafana to
loopback port 3001. Open the provisioned Rails PostgreSQL Bottleneck Lab dashboard
in Grafana. There is no admin login to configure: anonymous access is Viewer only,
initial admin creation/basic auth/login form are disabled, and datasource/dashboard
provisioning files are read-only. This is a local teaching viewer, not production
authentication or a multi-tenant monitoring deployment. No host database/Redis
ports are opened.

/lab/metrics is gated by the same explicit lab flag and always disabled in
production. lab_pg_up and lab_redis_up report backend availability separately from
Prometheus scrape success. PostgreSQL counters are per database, not per SQL
statement; use pg_stat_statements/EXPLAIN for query diagnosis. Pool measurements
belong to the process serving the scrape. With multiple Rails workers the samples
can alternate processes, so do not interpret them as an aggregated pool. Metrics
queries themselves create a small amount of observed load. Redis can be absent;
its availability gauge then reports zero without inventing hit counters.

Scraping has a cost. Automated comparison runners stop this profile so the
baseline and optimized runs do not accidentally differ in observer overhead.
To watch a workload live, start this profile and run the documented k6 invocation
manually with consistent settings; label monitoring overhead in reports. The
current collector is a lightweight teaching collector, not a full postgres_exporter
or production alerting/SLO stack. Prometheus retains two days of local samples.
The Grafana datasource queries the real Prometheus service over the private Docker
network. Repository validation checks scrape results, provisioning, and an actual
datasource query through Grafana's API.

Stop all optional services with `bin/lab --profile '*' down` (quote the wildcard).
Named volumes retain samples and data; do not remove volumes unless you intend to
discard their contents. Original PostgreSQL data remains in rails-lab-pgdata.
