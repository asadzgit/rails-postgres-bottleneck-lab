SELECT clock_timestamp() AS sampled_at, pid, usename, application_name, state,
       wait_event_type, wait_event, now() - query_start AS query_age,
       left(query, 250) AS query
FROM pg_stat_activity
WHERE datname = current_database() AND pid <> pg_backend_pid()
ORDER BY usename, pid;
SELECT rolname, rolconnlimit FROM pg_roles WHERE rolname = 'lab_client';
SELECT usename, count(*) AS connections FROM pg_stat_activity
WHERE datname = current_database() GROUP BY usename;
