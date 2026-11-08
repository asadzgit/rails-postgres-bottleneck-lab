require "net/http"
require "json"

mode = ARGV.fetch(0)
output = ARGV.fetch(1)
FileUtils.mkdir_p(output)
def request(path, post: false)
  uri = URI("http://127.0.0.1:3000#{path}")
  http = Net::HTTP.new(uri.host, uri.port, nil) # Explicitly local container traffic.
  http.read_timeout = 15
  response = http.request(post ? Net::HTTP::Post.new(uri) : Net::HTTP::Get.new(uri))
  [ response.code.to_i, JSON.parse(response.body) ]
end
def read_ok(path)
  status, body = request(path)
  raise "#{path}: #{status} #{body}" unless status == 200
  body
end
result = { mode: mode, observed_at: Time.now.utc.iso8601 }
case mode
when "cache"
  Lab::Cache::POOL.with { |redis| redis.del(Lab::Cache.key(1)) }
  first = read_ok("/lab/cache/items/1?ttl=2&work_ms=1")
  second = read_ok("/lab/cache/items/1?ttl=2&work_ms=1")
  raise "No cache miss/hit sequence" unless first["cache_status"] == "miss" && second["cache_status"] == "hit"
  status, write = request("/lab/cache/items/1/increment", post: true)
  raise "Invalidation failed" unless status == 200 && write["cache_invalidated"]
  fresh = read_ok("/lab/cache/items/1?ttl=2&work_ms=1")
  raise "Serial write stale" unless fresh["version"] == write["version"] && fresh["value"] == write["value"]
  LabCacheItem.where(id: 1).update_all("value=value+1, version=version+1")
  stale = read_ok("/lab/cache/items/1?ttl=2&work_ms=1")
  result[:stale_window_observed] = stale["version"] == fresh["version"]
  sleep 2.1
  expired = read_ok("/lab/cache/items/1?ttl=2&work_ms=1")
  raise "TTL did not refresh" unless expired["version"] == fresh["version"] + 1
  result.merge!(miss: first, hit: second, write: write, stale: stale, after_ttl: expired)
when "cache-outage"
  body = read_ok("/lab/cache/items/1?work_ms=1")
  raise "Redis failure hidden" unless body["cache_status"] == "unavailable" && body["value"] == LabCacheItem.find(1).value
  result[:fallback] = body
when "replica"
  replica = ReplicaRecord.connection
  begin
    replica.exec_query("SELECT pg_wal_replay_pause()::text")
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 5
    until replica.exec_query("SELECT pg_get_wal_replay_pause_state() AS state").first["state"] == "paused"
      raise "Replay did not pause" if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
      sleep 0.02
    end
    before = read_ok("/lab/replica/items/1?source=replica")
    status, write = request("/lab/replica/items/1/increment", post: true)
    raise "Primary write failed" unless status == 200
    stale = read_ok("/lab/replica/items/1?source=replica")
    fenced_status, fenced = request("/lab/replica/items/1?source=replica&min_lsn=#{write.fetch('min_lsn')}&wait_ms=50")
    raise "Did not reproduce stale read" unless stale["version"] == before["version"] && stale["version"] < write["version"]
    raise "Fence failed" unless fenced_status == 409 && fenced["error"] == "replica_lag"
    result.merge!(before: before, write: write, stale: stale, fenced_status: fenced_status)
  ensure
    replica.exec_query("SELECT pg_wal_replay_resume()::text")
  end
  caught_up = read_ok("/lab/replica/items/1?source=replica&min_lsn=#{result[:write]['min_lsn']}&wait_ms=2000")
  raise "Replica failed to catch up" unless caught_up["version"] >= result[:write]["version"] && caught_up["in_recovery"]
  result[:caught_up] = caught_up
  raw = PG.connect(host: "replica", user: "rails", dbname: "rails_postgres_bottleneck_lab_development")
  begin
    begin
      raw.exec("UPDATE lab_replica_items SET value=value WHERE id=1")
      raise "Replica accepted a write"
    rescue PG::ReadOnlySqlTransaction
      result[:server_rejected_write] = true
    end
  ensure
    raw.close
  end
when "partition"
  values = []
  plans = {}
  [ [ "heap", true ], [ "partitioned", false ], [ "partitioned", true ] ].each do |layout, pruning|
    values << Lab::Partitions.summary(layout: layout, pruning: pruning, from: "2024-06-01", to: "2024-07-01")
    plan = Lab::Partitions.summary(layout: layout, pruning: pruning, from: "2024-06-01", to: "2024-07-01", explain: true)
    plan = JSON.parse(plan) if plan.is_a?(String)
    name = "#{layout}-#{pruning}"
    plans[name] = plan
    File.write(File.join(output, "plan-#{name}.json"), JSON.pretty_generate(plan))
  end
  raise "Partition query differs" unless values.map { |v| v.slice("count", "total_cents") }.uniq.length == 1
  walk = lambda { |node| [ node["Relation Name"], *node.fetch("Plans", []).flat_map { |child| walk.call(child) } ].compact }
  on = walk.call(plans.fetch("partitioned-true").first.fetch("Plan")).uniq
  off = walk.call(plans.fetch("partitioned-false").first.fetch("Plan")).uniq
  raise "Pruning not observed: #{on} / #{off}" unless on == [ "events_2024_06" ] && off.length == 12
  result.merge!(values: values, pruned_relations: on, unpruned_relations: off)
when "shards"
  [ 1, 2, 9999, 10000 ].each do |id|
    single = read_ok("/lab/shards/customers/#{id}/orders?mode=single")
    sharded = read_ok("/lab/shards/customers/#{id}/orders?mode=sharded")
    raise "Shard routing/data mismatch" unless single["orders"] == sharded["orders"] && sharded["shard"] == (id.even? ? "a" : "b")
  end
  single = read_ok("/lab/shards/summary?mode=single")
  sharded = read_ok("/lab/shards/summary?mode=sharded")
  raise "Fanout aggregate mismatch" unless single.slice("count", "total_cents") == sharded.slice("count", "total_cents")
  result.merge!(single: single, sharded: sharded)
when "shard-outage"
  a = read_ok("/lab/shards/customers/2/orders?mode=sharded")
  b_status, b = request("/lab/shards/customers/1/orders?mode=sharded")
  all_status, all = request("/lab/shards/summary?mode=sharded")
  raise "Shard failure was hidden or leaked" unless a["shard"] == "a" && b_status == 503 && b["error"] == "shard_unavailable" && all_status == 503 && all["partial_result"] == false
  result.merge!(healthy_owner: a["shard"], failed_owner: b, aggregate_status: all_status)
else
  raise "Unknown check #{mode}"
end
File.write(File.join(output, "#{mode}.json"), JSON.pretty_generate(result))
puts JSON.generate(result)
