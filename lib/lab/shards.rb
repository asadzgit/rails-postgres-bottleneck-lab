module Lab
  class Shards
    class Unavailable < StandardError
      attr_reader :shard
      def initialize(shard)
        @shard = shard
        super("Shard #{shard} is unavailable")
      end
    end

    def self.owner(customer_id, mode:)
      raise ArgumentError unless %w[single sharded].include?(mode) && customer_id.positive?
      mode == "single" ? :single : (customer_id.even? ? :a : :b)
    end

    def self.on(shard)
      ShardRecord.connected_to(shard: shard) { yield }
    rescue ActiveRecord::ConnectionNotEstablished, PG::ConnectionBad
      raise Unavailable, shard
    end

    def self.orders(customer_id, mode:, limit:)
      shard = owner(customer_id, mode: mode)
      records = on(shard) do
        ShardOrder.where(customer_id: customer_id).order(created_at: :desc, id: :desc).limit(limit)
          .pluck(:id, :customer_id, :amount_cents, :created_at)
      end
      { shard: shard, orders: records.map { |id, customer, amount, time| { id: id, customer_id: customer, amount_cents: amount, created_at: time } } }
    end

    def self.summary(mode:)
      raise ArgumentError unless %w[single sharded].include?(mode)
      shards = mode == "single" ? [ :single ] : [ :a, :b ]
      totals = shards.map do |shard|
        on(shard) { ShardOrder.connection.exec_query("SELECT count(*) AS count, coalesce(sum(amount_cents),0)::bigint AS total_cents FROM orders").first }
      end
      { count: totals.sum { |r| r["count"] }, total_cents: totals.sum { |r| r["total_cents"] }, shards: shards }
    end
  end
end
