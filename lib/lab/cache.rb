module Lab
  class Cache
    POOL = ConnectionPool.new(size: 5, timeout: 0.2) do
      Redis.new(url: ENV.fetch("REDIS_URL", "redis://redis:6379/0"),
        connect_timeout: 0.2, read_timeout: 0.2, write_timeout: 0.2)
    end
    TTL = 5

    def self.key(id)
      "rails-bottleneck-lab:v1:#{Rails.env}:item:#{id}"
    end

    def self.read(id, enabled:, ttl: TTL, work_ms: 20)
      raise ArgumentError unless (1..60).cover?(ttl) && (0..100).cover?(work_ms)
      if enabled
        begin
          cached = POOL.with { |redis| redis.get(key(id)) }
          return JSON.parse(cached).merge("cache_status" => "hit") if cached
        rescue Redis::BaseError, ConnectionPool::TimeoutError, JSON::ParserError
          return fetch(id, work_ms).merge("cache_status" => "unavailable")
        end
      end
      payload = fetch(id, work_ms)
      status = enabled ? "miss" : "disabled"
      if enabled
        begin
          POOL.with { |redis| redis.set(key(id), JSON.generate(payload), ex: ttl) }
        rescue Redis::BaseError, ConnectionPool::TimeoutError
          status = "unavailable"
        end
      end
      payload.merge("cache_status" => status)
    end

    def self.increment(id)
      # Autocommit is complete before invalidation. This is eventual, not a
      # distributed transaction: a concurrent stale fill can survive until TTL.
      row = ActiveRecord::Base.connection.exec_query(<<~SQL).first
        UPDATE lab_cache_items SET value=value+1, version=version+1
        WHERE id=#{ActiveRecord::Base.connection.quote(Integer(id))} RETURNING id, value, version
      SQL
      raise ActiveRecord::RecordNotFound unless row
      invalidated = true
      begin
        POOL.with { |redis| redis.del(key(id)) }
      rescue Redis::BaseError, ConnectionPool::TimeoutError
        invalidated = false
      end
      row.merge("cache_invalidated" => invalidated)
    end

    def self.fetch(id, work_ms)
      connection = ActiveRecord::Base.connection
      row = connection.exec_query(<<~SQL).first
        SELECT id, value, version, pg_sleep(#{connection.quote(work_ms / 1000.0)})::text AS simulated_work
        FROM lab_cache_items WHERE id=#{ActiveRecord::Base.connection.quote(Integer(id))} /* lab_cache_load */
      SQL
      raise ActiveRecord::RecordNotFound unless row
      row.except("simulated_work")
    end
    private_class_method :fetch
  end
end
