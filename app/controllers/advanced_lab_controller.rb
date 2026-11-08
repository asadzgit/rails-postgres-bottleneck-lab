class AdvancedLabController < LabController
  rescue_from ArgumentError, Date::Error, KeyError do
    render json: { error: "invalid_parameters" }, status: :bad_request
  end
  rescue_from Lab::Replica::Lagging do
    render json: { error: "replica_lag", retryable: true }, status: :conflict
  end
  rescue_from Lab::Shards::Unavailable do |exception|
    render json: { error: "shard_unavailable", shard: exception.shard, partial_result: false }, status: :service_unavailable
  end

  def cache_read
    enabled = params.fetch(:cache, "1")
    raise ArgumentError unless %w[0 1].include?(enabled)
    render json: Lab::Cache.read(positive_integer(params[:id]), enabled: enabled == "1",
      ttl: positive_integer(params[:ttl], default: 5, maximum: 60),
      work_ms: positive_integer(params[:work_ms], default: 20, maximum: 100))
  end

  def cache_write
    render json: Lab::Cache.increment(positive_integer(params[:id]))
  end

  def replica_read
    wait_ms = params.fetch(:wait_ms, "0")
    wait_ms = wait_ms == "0" ? 0 : positive_integer(wait_ms, maximum: 2000)
    render json: Lab::Replica.read(positive_integer(params[:id]), source: params.fetch(:source, "primary"),
      min_lsn: params[:min_lsn], wait_ms: wait_ms)
  end

  def replica_write
    render json: Lab::Replica.increment(positive_integer(params[:id]))
  end

  def partition_summary
    pruning = params.fetch(:pruning, "1")
    raise ArgumentError unless %w[0 1].include?(pruning)
    render json: Lab::Partitions.summary(layout: params.fetch(:layout, "partitioned"), pruning: pruning == "1",
      from: params.fetch(:from, "2024-06-01"), to: params.fetch(:to, "2024-07-01"))
  end

  def shard_orders
    render json: Lab::Shards.orders(positive_integer(params[:id]), mode: params.fetch(:mode, "sharded"),
      limit: positive_integer(params[:limit], default: 20, maximum: 100))
  end

  def shard_summary
    render json: Lab::Shards.summary(mode: params.fetch(:mode, "sharded"))
  end
end
