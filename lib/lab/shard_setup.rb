module Lab
  class ShardSetup
    def self.prepare(customers:, orders:, reset: false)
      raise "Disabled in production" if Rails.env.production?
      customers = Integer(customers.to_s, 10)
      orders = Integer(orders.to_s, 10)
      raise ArgumentError unless (2..100_000).cover?(customers) && customers.even? && (customers..2_000_000).cover?(orders)
      # Database names and hosts are fixed laboratory destinations, never user input.
      admin = PG.connect(host: "shard-a", user: "rails", dbname: "postgres")
      begin
        exists = admin.exec("SELECT 1 FROM pg_database WHERE datname='lab_single'").ntuples.positive?
        admin.exec("CREATE DATABASE lab_single OWNER rails") unless exists
      ensure
        admin.close
      end
      [ :single, :a, :b ].each do |shard|
        ShardRecord.connected_to(shard: shard) do
          connection = ShardRecord.connection
          connection.execute("CREATE EXTENSION IF NOT EXISTS pg_stat_statements")
          if reset
            connection.execute("DROP TABLE IF EXISTS orders")
            connection.execute("DROP TABLE IF EXISTS lab_seed_manifest")
          end
          connection.execute("CREATE TABLE IF NOT EXISTS lab_seed_manifest (id integer PRIMARY KEY, customers bigint NOT NULL, orders bigint NOT NULL, seed_version integer NOT NULL)")
          manifest = connection.select_one("SELECT * FROM lab_seed_manifest WHERE id=1")
          if manifest && (manifest["customers"] != customers || manifest["orders"] != orders || manifest["seed_version"] != 1)
            raise "Shard seed parameters changed; explicitly reset only the lab shard tables"
          end
          connection.execute("CREATE TABLE IF NOT EXISTS orders (id bigint PRIMARY KEY, customer_id bigint NOT NULL, amount_cents bigint NOT NULL CHECK(amount_cents>=0), created_at timestamp NOT NULL)")
          existing = connection.select_value("SELECT count(*) FROM orders")
          expected = shard == :single ? orders : (shard == :a ? orders / 2 : (orders + 1) / 2)
          if existing.zero?
            (1..orders).step(50_000) do |first|
              last = [ first + 49_999, orders ].min
              lane = shard == :single ? 2 : (shard == :a ? 0 : 1)
              connection.execute(<<~SQL)
                INSERT INTO orders
                SELECT n, 1+((n-1)%#{connection.quote(customers)}), 100+((n*7919)%100000),
                       timestamp '2024-01-01' + ((n*37)%31536000)*interval '1 second'
                FROM generate_series(#{connection.quote(first)}::bigint,#{connection.quote(last)}::bigint) n WHERE #{connection.quote(lane)} = 2 OR (1+((n-1)%#{connection.quote(customers)})) % 2 = #{connection.quote(lane)}
              SQL
            end
          elsif existing != expected
            raise "Shard #{shard} has unexpected row count; LAB_RESET_SHARDS=1 explicitly replaces only lab shard tables"
          end
          invalid = connection.select_value(<<~SQL)
            SELECT count(*) FROM orders
            WHERE id < 1 OR id > #{connection.quote(orders)} OR customer_id <> 1+((id-1)%#{connection.quote(customers)})
              OR amount_cents <> 100+((id*7919)%100000)
              OR created_at <> timestamp '2024-01-01' + ((id*37)%31536000)*interval '1 second'
          SQL
          raise "Shard data no longer matches deterministic seed; explicit reset required" unless invalid.zero?
          connection.execute("INSERT INTO lab_seed_manifest VALUES(1,#{connection.quote(customers)},#{connection.quote(orders)},1) ON CONFLICT(id) DO NOTHING")
          connection.execute("CREATE INDEX IF NOT EXISTS orders_customer_recent ON orders(customer_id, created_at DESC, id DESC)")
          connection.execute("ANALYZE orders")
        end
      end
    end
  end
end
