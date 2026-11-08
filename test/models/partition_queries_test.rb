require "test_helper"

class PartitionQueriesTest < ActiveSupport::TestCase
  test "heap, fanout and pruned queries preserve aggregates and half-open boundaries" do
    Lab::PartitionSetup.prepare(count: 366, reset: true)
    heap = Lab::Partitions.summary(layout: "heap", pruning: true, from: "2024-06-01", to: "2024-07-01")
    pruned = Lab::Partitions.summary(layout: "partitioned", pruning: true, from: "2024-06-01", to: "2024-07-01")
    fanout = Lab::Partitions.summary(layout: "partitioned", pruning: false, from: "2024-06-01", to: "2024-07-01")
    assert_equal 30, heap["count"]
    assert_equal heap.slice("count", "total_cents"), pruned.slice("count", "total_cents")
    assert_equal heap.slice("count", "total_cents"), fanout.slice("count", "total_cents")
    combined = Lab::Partitions.summary(layout: "partitioned", pruning: true, from: "2024-06-01", to: "2024-08-01")
    july = Lab::Partitions.summary(layout: "partitioned", pruning: true, from: "2024-07-01", to: "2024-08-01")
    assert_equal heap["count"] + july["count"], combined["count"]
    assert_equal heap["total_cents"] + july["total_cents"], combined["total_cents"]
  end
end
