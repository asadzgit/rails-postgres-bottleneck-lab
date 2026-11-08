namespace :lab do
  namespace :connections do
    desc "Prepare a non-superuser experiment role with a real PostgreSQL connection budget"
    task prepare: :environment do
      raise "Disabled in production" if Rails.env.production?
      limit = Integer(ENV.fetch("LAB_DB_CONNECTION_LIMIT", "16"), 10)
      raise "Connection limit must be between 1 and 80" unless (1..80).cover?(limit)
      connection = ActiveRecord::Base.connection
      unless connection.select_value("SELECT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'lab_client')")
        connection.execute("CREATE ROLE lab_client LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION")
      end
      safe = connection.select_value("SELECT rolcanlogin AND NOT rolsuper AND NOT rolcreatedb AND NOT rolcreaterole AND NOT rolreplication FROM pg_roles WHERE rolname='lab_client'")
      raise "Existing lab_client role is not a restricted lab role" unless safe
      connection.execute("ALTER ROLE lab_client CONNECTION LIMIT #{limit}")
      connection.execute("GRANT CONNECT ON DATABASE #{connection.quote_table_name(connection.current_database)} TO lab_client")
      connection.execute("GRANT USAGE ON SCHEMA public TO lab_client")
      connection.execute("GRANT SELECT ON customers, orders, lab_counters TO lab_client")
      connection.execute("GRANT UPDATE ON lab_counters TO lab_client")
      puts "lab_client connection limit: #{limit} (not a superuser; migrations still use rails)"
    end
  end

  namespace :locks do
    desc "Reset only the dedicated lock counter; run with experiment traffic stopped"
    task reset: :environment do
      raise "Disabled in production" if Rails.env.production?
      LabCounter.upsert({ id: 1, value: 0 })
      puts "Lock counter reset to zero; customer/order data unchanged."
    end
  end
end
