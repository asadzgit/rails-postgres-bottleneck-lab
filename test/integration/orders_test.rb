require "test_helper"

class OrdersTest < ActionDispatch::IntegrationTest
  setup do
    @customer = Customer.create!(name: "Ada", email: "ada@example.test")
    @other = Customer.create!(name: "Grace", email: "grace@example.test")
    time = Time.utc(2024, 6, 1)
    @older = @customer.orders.create!(status: "paid", total_cents: 200, created_at: time - 1.day)
    @first = @customer.orders.create!(status: "paid", total_cents: 300, created_at: time)
    @latest = @customer.orders.create!(status: "shipped", total_cents: 400, created_at: time)
    @other.orders.create!(status: "paid", total_cents: 500, created_at: time + 1.day)
  end

  test "recent orders belong only to the requested customer and ties use descending id" do
    get customer_orders_url(@customer), params: { limit: 2 }
    assert_response :success
    orders = response.parsed_body.fetch("orders")
    assert_equal [ @latest.id, @first.id ], orders.pluck("id")
    assert_equal [ @customer.id ], orders.pluck("customer_id").uniq
    assert_equal [ "created_at", "customer_id", "id", "status", "total_cents" ], orders.first.keys.sort
  end

  test "empty order history returns an empty array" do
    empty = Customer.create!(name: "Empty", email: "empty@example.test")
    get customer_orders_url(empty)
    assert_response :success
    assert_equal [], response.parsed_body["orders"]
  end

  test "missing customer returns JSON 404" do
    get customer_orders_url(9_223_372_036_854_775_807)
    assert_response :not_found
    assert_equal "not_found", response.parsed_body["error"]
  end

  test "limits reject invalid values rather than silently coercing them" do
    [ "0", "-1", "101", "abc", "2.5", "999999999999999999999999" ].each do |limit|
      get customer_orders_url(@customer), params: { limit: limit }
      assert_response :bad_request
    end
  end

  test "customer id overflow is rejected before querying PostgreSQL" do
    get customer_orders_url("999999999999999999999999")
    assert_response :bad_request
  end

  test "customer list supports bounded keyset pagination" do
    get customers_url, params: { after_id: @customer.id, limit: 1 }
    assert_response :success
    assert_equal [ @other.id ], response.parsed_body.fetch("customers").pluck("id")
  end

  test "customer details are returned as JSON" do
    get customer_url(@customer)
    assert_response :success
    assert_equal "Ada", response.parsed_body.fetch("customer")["name"]
  end
end
