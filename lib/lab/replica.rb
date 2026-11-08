module Lab
  class Replica
    class Lagging < StandardError; end

    def self.read(id, source:, min_lsn: nil, wait_ms: 0)
      raise ArgumentError unless %w[primary replica].include?(source)
      raise ArgumentError unless (0..2000).cover?(wait_ms)
      if min_lsn && !min_lsn.match?(/\A[0-9a-f]{1,8}\/[0-9a-f]{1,8}\z/i)
        raise ArgumentError, "Invalid WAL LSN"
      end
      pool = source == "primary" ? ActiveRecord::Base.connection_pool : ReplicaRecord.connection_pool
      pool.with_connection do |connection|
        if source == "replica" && min_lsn
          deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + wait_ms / 1000.0
          loop do
            ready = connection.exec_query("SELECT pg_last_wal_replay_lsn() >= #{connection.quote(min_lsn)}::pg_lsn AS ready").first["ready"]
            break if ready
            raise Lagging if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
            sleep 0.01
          end
        end
        row = connection.exec_query("SELECT id, value, version, pg_is_in_recovery() AS in_recovery FROM lab_replica_items WHERE id=#{connection.quote(Integer(id))}").first
        raise ActiveRecord::RecordNotFound unless row
        row.merge("source" => source)
      end
    end

    def self.increment(id)
      connection = ActiveRecord::Base.connection
      row = connection.exec_query("UPDATE lab_replica_items SET value=value+1, version=version+1 WHERE id=#{connection.quote(Integer(id))} RETURNING id, value, version").first
      raise ActiveRecord::RecordNotFound unless row
      row.merge("min_lsn" => connection.exec_query("SELECT pg_current_wal_lsn()::text AS lsn").first["lsn"])
    end
  end
end
