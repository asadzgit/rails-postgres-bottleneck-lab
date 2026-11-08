require "test_helper"

class AdvancedLabTest < ActionDispatch::IntegrationTest
  setup do
    @flag = ENV["LAB_EXPERIMENT_ENDPOINTS"]
    ENV["LAB_EXPERIMENT_ENDPOINTS"] = "1"
    LabCacheItem.create!(id: 500, value: 123, version: 2)
    LabReplicaItem.create!(id: 500, value: 22, version: 1)
  end

  teardown do
    ENV["LAB_EXPERIMENT_ENDPOINTS"] = @flag
  end

  test "advanced APIs stay disabled without the explicit flag" do
    ENV["LAB_EXPERIMENT_ENDPOINTS"] = "0"
    %w[/lab/metrics /lab/cache/items/500 /lab/replica/items/500 /lab/partitions/summary /lab/shards/summary].each do |path|
      get path
      assert_response :not_found
    end
  end

  test "uncached read returns actual database values without Redis" do
    get "/lab/cache/items/500", params: { cache: 0, work_ms: 1 }
    assert_response :success
    assert_equal 123, response.parsed_body["value"]
    assert_equal 2, response.parsed_body["version"]
    assert_equal "disabled", response.parsed_body["cache_status"]
  end

  test "primary read is identified as primary" do
    get "/lab/replica/items/500", params: { source: "primary" }
    assert_response :success
    assert_equal false, response.parsed_body["in_recovery"]
    assert_equal 22, response.parsed_body["value"]
  end

  test "malformed replication fences are rejected" do
    get "/lab/replica/items/500", params: { source: "replica", min_lsn: "not-an-lsn" }
    assert_response :bad_request
  end

  test "API bounds and enum values are validated" do
    get "/lab/cache/items/500", params: { ttl: 61 }
    assert_response :bad_request
    get "/lab/partitions/summary", params: { from: "2024-07-01", to: "2024-06-01" }
    assert_response :bad_request
    get "/lab/shards/summary", params: { mode: "arbitrary_database" }
    assert_response :bad_request
  end
  test "Prometheus endpoint exports real database and process-pool measurements" do
    get "/lab/metrics"
    assert_response :success
    assert_match(/^lab_pg_up 1$/, response.body)
    assert_match(/^lab_rails_pool_busy [0-9]+$/, response.body)
  end
end
