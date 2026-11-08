module Lab
  class Partitions
    TABLES = { "heap" => "lab_partitioning.events_heap", "partitioned" => "lab_partitioning.events_partitioned" }.freeze

    def self.bounds(from, to)
      first = Date.iso8601(from)
      last = Date.iso8601(to)
      raise ArgumentError unless first >= Date.new(2024, 1, 1) && last <= Date.new(2025, 1, 1) && first < last
      [ first, last ]
    end

    def self.sql(connection, layout, from, to)
      table = TABLES.fetch(layout)
      first, last = bounds(from, to)
      "SELECT count(*) AS count, coalesce(sum(amount_cents),0)::bigint AS total_cents FROM #{connection.quote_table_name(table)} WHERE occurred_at >= #{connection.quote(first)} AND occurred_at < #{connection.quote(last)}"
    end

    def self.summary(layout:, pruning:, from:, to:, explain: false)
      raise ArgumentError unless TABLES.key?(layout)
      ActiveRecord::Base.connection_pool.with_connection do |connection|
        connection.transaction do
          connection.execute(pruning ? "SET LOCAL enable_partition_pruning=on" : "SET LOCAL enable_partition_pruning=off")
          query = sql(connection, layout, from, to)
          if explain
            connection.exec_query("EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) #{query}").first["QUERY PLAN"]
          else
            connection.exec_query(query).first.merge("layout" => layout, "pruning" => pruning)
          end
        end
      end
    end
  end
end
