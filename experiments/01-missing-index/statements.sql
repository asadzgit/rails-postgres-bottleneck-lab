SELECT queryid, calls, round(total_exec_time::numeric, 3) AS total_exec_ms,
       round(mean_exec_time::numeric, 3) AS mean_exec_ms,
       round(stddev_exec_time::numeric, 3) AS stddev_exec_ms,
       rows, shared_blks_hit, shared_blks_read, temp_blks_read, temp_blks_written,
       query
FROM pg_stat_statements
WHERE dbid = (SELECT oid FROM pg_database WHERE datname = current_database())
ORDER BY total_exec_time DESC LIMIT 20;
