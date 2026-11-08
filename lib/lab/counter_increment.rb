module Lab
  class CounterIncrement
    def initialize(mode:, work_ms:, lock_timeout_ms:)
      raise ArgumentError, "Invalid lock mode" unless %w[long short].include?(mode)
      @mode = mode
      @work_ms = bounded(work_ms, 1..2000)
      @lock_timeout_ms = bounded(lock_timeout_ms, 1..5000)
    end

    def call
      started = monotonic
      sleep(@work_ms / 1000.0) if @mode == "short"
      result = ActiveRecord::Base.connection_pool.with_connection do |connection|
        connection.transaction do
          connection.execute("SET LOCAL lock_timeout = #{connection.quote("#{@lock_timeout_ms}ms")}")
          lock_started = monotonic
          if @mode == "long"
            value = connection.exec_query("SELECT value FROM lab_counters WHERE id = 1 FOR UPDATE").rows.first&.first
            raise ActiveRecord::RecordNotFound if value.nil?
            lock_acquired = monotonic
            # Simulated external work: no need to hold a database lock while doing it.
            sleep(@work_ms / 1000.0)
          end
          value = connection.exec_query("UPDATE lab_counters SET value = value + 1 WHERE id = 1 RETURNING value").rows.first&.first
          raise ActiveRecord::RecordNotFound if value.nil?
          { value: value, lock_round_trip_ms: ((lock_acquired || monotonic) - lock_started) * 1000 }
        end
      end
      result.merge(mode: @mode, work_ms: @work_ms, elapsed_ms: (monotonic - started) * 1000)
    end

    private

    def monotonic
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    def bounded(value, range)
      number = Integer(value.to_s, 10)
      raise ArgumentError, "Value out of range" unless range.cover?(number)
      number
    end
  end
end
