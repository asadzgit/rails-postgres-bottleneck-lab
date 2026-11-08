class LabMetricsController < LabController
  def show
    lines = []
    begin
      connection = ActiveRecord::Base.connection
      values = connection.exec_query(<<~SQL).first
        SELECT numbackends, xact_commit, xact_rollback, blks_read, blks_hit, deadlocks
        FROM pg_stat_database WHERE datname=current_database()
      SQL
      lines << "lab_pg_up 1"
      values.each { |key, value| lines << "lab_pg_#{key} #{value}" }
      waits = connection.exec_query(<<~SQL).first
        SELECT count(*) FILTER (WHERE state='active') AS active,
               count(*) FILTER (WHERE wait_event_type='Lock') AS lock_waiters
        FROM pg_stat_activity WHERE datname=current_database()
      SQL
      waits.each { |key, value| lines << "lab_pg_#{key} #{value}" }
    rescue ActiveRecord::ActiveRecordError
      lines << "lab_pg_up 0"
    end
    ActiveRecord::Base.connection_pool.stat.slice(:busy, :idle, :waiting).each do |key, value|
      lines << "lab_rails_pool_#{key} #{value}"
    end
    begin
      info = Lab::Cache::POOL.with { |redis| redis.info("stats") }
      lines << "lab_redis_up 1"
      %w[keyspace_hits keyspace_misses evicted_keys].each { |key| lines << "lab_redis_#{key} #{Integer(info.fetch(key))}" }
    rescue Redis::BaseError, ConnectionPool::TimeoutError
      lines << "lab_redis_up 0"
    end
    render plain: lines.join("\n") + "\n", content_type: "text/plain; version=0.0.4"
  end
end
