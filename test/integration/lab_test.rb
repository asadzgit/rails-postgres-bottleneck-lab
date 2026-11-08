require "test_helper"

class LabTest < ActionDispatch::IntegrationTest
  setup do
    @old_flag = ENV["LAB_EXPERIMENT_ENDPOINTS"]
    ENV["LAB_EXPERIMENT_ENDPOINTS"] = "1"
    LabCounter.upsert({ id: 1, value: 0 })
  end

  teardown do
    ENV["LAB_EXPERIMENT_ENDPOINTS"] = @old_flag
  end

  test "experiment endpoints are disabled by default" do
    ENV["LAB_EXPERIMENT_ENDPOINTS"] = "0"
    get "/lab/connections"
    assert_response :not_found
    post "/lab/locks/increment"
    assert_response :not_found
    get "/lab/pool"
    assert_response :not_found
  end

  test "connection probe executes on PostgreSQL and reports actual timing" do
    get "/lab/connections", params: { hold_ms: 1 }
    assert_response :success
    body = response.parsed_body
    assert_kind_of Integer, body["backend_pid"]
    assert_equal 1, body["hold_ms"]
    assert_operator body["checkout_wait_ms"], :>=, 0
    assert_operator body["database_round_trip_ms"], :>=, 0
  end

  test "pool diagnostics do not require checking out a connection" do
    get "/lab/pool"
    assert_response :success
    assert response.parsed_body.key?("waiting")
    assert response.parsed_body.key?("busy")
  end

  test "long and short transactions produce the same atomic increments" do
    %w[long short].each do |mode|
      post "/lab/locks/increment", params: { mode: mode, work_ms: 1 }
      assert_response :success
    end
    assert_equal 2, LabCounter.find(1).value
  end

  test "unbounded work and invalid modes are rejected" do
    get "/lab/connections", params: { hold_ms: 2001 }
    assert_response :bad_request
    post "/lab/locks/increment", params: { mode: "unknown" }
    assert_response :bad_request
    post "/lab/locks/increment", params: { work_ms: -1 }
    assert_response :bad_request
  end
end
