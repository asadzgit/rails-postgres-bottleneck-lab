require "test_helper"

class AdvancedRoutingTest < ActiveSupport::TestCase
  test "shard ownership is stable and customer based" do
    assert_equal :b, Lab::Shards.owner(1, mode: "sharded")
    assert_equal :a, Lab::Shards.owner(2, mode: "sharded")
    assert_equal :b, Lab::Shards.owner(9999, mode: "sharded")
    assert_equal :single, Lab::Shards.owner(2, mode: "single")
    assert_raises(ArgumentError) { Lab::Shards.owner(0, mode: "sharded") }
    assert_raises(ArgumentError) { Lab::Shards.owner(1, mode: "invalid") }
  end

  test "partition ranges are half-open and bounded to the prepared year" do
    assert_equal [ Date.new(2024, 6, 1), Date.new(2024, 7, 1) ], Lab::Partitions.bounds("2024-06-01", "2024-07-01")
    assert_raises(ArgumentError) { Lab::Partitions.bounds("2023-01-01", "2024-01-01") }
    assert_raises(ArgumentError) { Lab::Partitions.bounds("2024-01-01", "2024-01-01") }
    assert_raises(Date::Error) { Lab::Partitions.bounds("nonsense", "2024-07-01") }
  end
end
