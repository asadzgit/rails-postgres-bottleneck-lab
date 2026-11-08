SELECT clock_timestamp() AS sampled_at, a.pid, a.usename, a.state,
       a.wait_event_type, a.wait_event, now() - a.xact_start AS transaction_age,
       pg_blocking_pids(a.pid) AS blocking_pids, left(a.query, 250) AS query
FROM pg_stat_activity a
WHERE a.datname = current_database() AND a.pid <> pg_backend_pid()
ORDER BY a.xact_start NULLS LAST;
SELECT pid, locktype, mode, granted, relation::regclass
FROM pg_locks WHERE pid IN (
  SELECT pid FROM pg_stat_activity WHERE datname = current_database()
) ORDER BY granted, pid;
