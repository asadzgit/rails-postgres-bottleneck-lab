namespace :lab do
  namespace :advanced do
    desc "Prepare small independent cache/replica fixtures and a replication login"
    task prepare: :environment do
      raise "Disabled in production" if Rails.env.production?
      LabCacheItem.insert_all((1..100).map { |id| { id: id, value: id * 100, version: 0 } })
      LabReplicaItem.insert_all([ { id: 1, value: 0, version: 0 } ])
      connection = ActiveRecord::Base.connection
      unless connection.select_value("SELECT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='lab_replicator')")
        connection.execute("CREATE ROLE lab_replicator LOGIN REPLICATION NOSUPERUSER NOCREATEDB NOCREATEROLE")
      end
      safe = connection.select_value("SELECT rolreplication AND rolcanlogin AND NOT rolsuper FROM pg_roles WHERE rolname='lab_replicator'")
      raise "Existing replication role is not a lab replication login" unless safe
      puts "Independent advanced fixtures and replication role are ready"
    end
  end

  namespace :cache do
    desc "Invalidate only the 100 known lab cache keys, never FLUSHALL"
    task clear: :environment do
      Lab::Cache::POOL.with { |redis| redis.del(*(1..100).map { |id| Lab::Cache.key(id) }) }
    end
  end

  namespace :partitions do
    desc "Build and deterministically seed heap and partitioned experiment copies"
    task prepare: :environment do
      Lab::PartitionSetup.prepare(count: ENV.fetch("EVENT_COUNT", 1_000_000), reset: ENV["LAB_RESET_EVENTS"] == "1")
      puts "Partitioning experiment data prepared"
    end
  end

  namespace :shards do
    desc "Prepare equal logical datasets on a single database and two shards"
    task prepare: :environment do
      Lab::ShardSetup.prepare(customers: ENV.fetch("SHARD_CUSTOMERS", 10_000), orders: ENV.fetch("SHARD_ORDERS", 1_000_000), reset: ENV["LAB_RESET_SHARDS"] == "1")
      puts "Single and sharded logical datasets prepared"
    end
  end
end
