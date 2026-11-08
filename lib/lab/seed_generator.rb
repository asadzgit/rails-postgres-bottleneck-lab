module Lab
  class SeedGenerator
    LOCK_ID = 7_301_001

    def initialize(customers: 10_000, orders: 1_000_000, batch_size: 50_000, reset: false)
      @customers = bounded_integer(customers, 1..1_000_000)
      @orders = bounded_integer(orders, 1..20_000_000)
      @batch_size = bounded_integer(batch_size, 1..100_000)
      @reset = reset
    end

    def call
      raise "Seeding is disabled in production" if Rails.env.production?

      ActiveRecord::Base.connection_pool.with_connection do |connection|
        locked = connection.select_value("SELECT pg_try_advisory_lock(#{LOCK_ID})")
        raise "Another seed generator is already running" unless locked

        begin
          if (Customer.exists? || Order.exists?) && !@reset
            raise "Data already exists. Set LAB_RESET=1 to explicitly replace customers and orders."
          end
          connection.execute("TRUNCATE orders, customers RESTART IDENTITY")
          insert_customers(connection)
          insert_orders(connection)
          %w[customers orders].each do |table|
            connection.execute("SELECT setval(pg_get_serial_sequence('#{table}', 'id'), (SELECT max(id) FROM #{table}))")
            connection.execute("ANALYZE #{table}")
          end
        ensure
          connection.execute("SELECT pg_advisory_unlock(#{LOCK_ID})")
        end
      end
    end

    private

    def bounded_integer(value, range)
      number = Integer(value.to_s, 10)
      raise ArgumentError, "Seed count out of range #{range}" unless range.cover?(number)
      number
    end

    def batches(count)
      (1..count).step(@batch_size) { |first| yield first, [ first + @batch_size - 1, count ].min }
    end

    def insert_customers(connection)
      batches(@customers) do |first, last|
        connection.execute(<<~SQL)
          INSERT INTO customers (id, name, email, created_at, updated_at)
          SELECT n, 'Customer ' || n, 'customer' || n || '@example.test',
                 timestamp '2024-01-01', timestamp '2024-01-01'
          FROM generate_series(#{first}::bigint, #{last}::bigint) AS n
        SQL
      end
    end

    def insert_orders(connection)
      batches(@orders) do |first, last|
        connection.execute(<<~SQL)
          INSERT INTO orders (id, customer_id, status, total_cents, created_at, updated_at)
          SELECT n, 1 + ((n - 1) % #{@customers}),
                 (ARRAY['pending', 'paid', 'shipped', 'cancelled'])[1 + (n % 4)::int],
                 1000 + ((n * 7919) % 100000),
                 timestamp '2024-01-01' + ((n * 37) % 31536000) * interval '1 second',
                 timestamp '2024-01-01' + ((n * 37) % 31536000) * interval '1 second'
          FROM generate_series(#{first}::bigint, #{last}::bigint) AS n
        SQL
      end
    end
  end
end
