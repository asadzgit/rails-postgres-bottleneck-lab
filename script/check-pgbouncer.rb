# Run via rails runner with PGBOUNCER=1 after the measured workload.
# Uncached is essential: cached SHOW/PID results cannot prove server state.
ActiveRecord::Base.uncached do
  connection = ActiveRecord::Base.connection
  raise "Prepared statements must be disabled" if connection.prepared_statements
  raise "Advisory migration locks must be disabled" unless ActiveRecord::Base.connection_db_config.configuration_hash[:advisory_locks] == false
  connection.transaction do
    first = connection.select_value("SELECT pg_backend_pid()")
    connection.execute("SET LOCAL lock_timeout = '20ms'")
    raise "SET LOCAL missing" unless connection.select_value("SHOW lock_timeout") == "20ms"
    LabCounter.where(id: 1).pick(:value)
    second = connection.select_value("SELECT pg_backend_pid()")
    raise "Backend changed inside a transaction" unless first == second
    puts "Transaction stayed on one backend; Active Record predicate executed."
  end
  raise "Transaction-local timeout leaked" unless connection.select_value("SHOW lock_timeout") == "0"
  puts "Prepared statements/advisory locks disabled; transaction-local timeout restored."
end
