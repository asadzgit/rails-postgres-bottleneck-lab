require "test_helper"

class LabErrorsTest < ActionController::TestCase
  tests LabController

  setup do
    @controller.set_request!(@request)
    @controller.set_response!(@response)
  end

  test "pool checkout timeouts are distinguished from their connection-error superclass" do
    @controller.rescue_with_handler(ActiveRecord::ConnectionTimeoutError.new("checkout timeout"))
    assert_response :service_unavailable
    assert_equal "rails_pool_timeout", JSON.parse(@response.body)["error"]
  end

  test "connection establishment failure is reported separately" do
    @controller.rescue_with_handler(ActiveRecord::ConnectionNotEstablished.new("connection refused"))
    assert_response :service_unavailable
    assert_equal "database_connection_unavailable", JSON.parse(@response.body)["error"]
  end

  test "lock waits have a distinct error and status" do
    @controller.rescue_with_handler(ActiveRecord::LockWaitTimeout.new("lock timeout"))
    assert_response :locked
    assert_equal "lock_timeout", JSON.parse(@response.body)["error"]
  end
  test "SQL cancellations stay distinct from lock timeouts" do
    @controller.rescue_with_handler(ActiveRecord::QueryCanceled.new("canceled"))
    assert_response :service_unavailable
    assert_equal "query_canceled", JSON.parse(@response.body)["error"]
  end

  test "unrecognized SQL failures are not hidden as overload" do
    assert_raises(ActiveRecord::StatementInvalid) do
      @controller.rescue_with_handler(ActiveRecord::StatementInvalid.new("invalid SQL"))
    end
  end
end
