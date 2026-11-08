module Lab
  class PartitionSetup
    def self.prepare(count:, reset: false)
      raise "Disabled in production" if Rails.env.production?
      count = Integer(count.to_s, 10)
      raise ArgumentError unless (1..2_000_000).cover?(count)
      connection = ActiveRecord::Base.connection
      connection.execute("CREATE SCHEMA IF NOT EXISTS lab_partitioning")
      if reset
        connection.execute("DROP TABLE IF EXISTS lab_partitioning.events_partitioned CASCADE")
        connection.execute("DROP TABLE IF EXISTS lab_partitioning.events_heap")
      end
      connection.execute("CREATE TABLE IF NOT EXISTS lab_partitioning.events_heap (id bigint NOT NULL, occurred_at timestamp NOT NULL, amount_cents bigint NOT NULL, PRIMARY KEY(id, occurred_at))")
      connection.execute("CREATE TABLE IF NOT EXISTS lab_partitioning.events_partitioned (id bigint NOT NULL, occurred_at timestamp NOT NULL, amount_cents bigint NOT NULL, PRIMARY KEY(id, occurred_at)) PARTITION BY RANGE(occurred_at)")
      12.times do |index|
        first = Date.new(2024, index + 1, 1)
        last = first.next_month
        table = connection.quote_table_name("lab_partitioning.events_#{first.strftime('%Y_%m')}")
        connection.execute("CREATE TABLE IF NOT EXISTS #{table} PARTITION OF lab_partitioning.events_partitioned FOR VALUES FROM (#{connection.quote(first)}) TO (#{connection.quote(last)})")
      end
      %w[events_heap events_partitioned].each do |name|
        table = connection.quote_table_name("lab_partitioning.#{name}")
        existing = connection.select_value("SELECT count(*) FROM #{table}")
        if existing.zero?
          (1..count).step(50_000) do |first|
            last = [ first + 49_999, count ].min
            connection.execute(<<~SQL)
              INSERT INTO #{table} (id, occurred_at, amount_cents)
              SELECT n, timestamp '2024-01-01' + ((n-1)%366)*interval '1 day' + ((n*37)%86400)*interval '1 second',
                     100 + ((n*7919)%100000)
              FROM generate_series(#{connection.quote(first)}::bigint,#{connection.quote(last)}::bigint) n
            SQL
          end
        elsif existing != count
          raise "Existing #{name} has #{existing} rows; use LAB_RESET_EVENTS=1 explicitly to replace experiment tables"
        end
        connection.execute("ANALYZE #{table}")
      end
    end
  end
end
