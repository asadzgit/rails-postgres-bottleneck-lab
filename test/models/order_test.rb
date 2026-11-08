require "test_helper"

class OrderTest < ActiveSupport::TestCase
  test "orders require a customer, valid status and nonnegative integer cents" do
    order = Order.new(status: "unknown", total_cents: -1)
    assert_not order.valid?
    assert order.errors[:customer].any?
    assert order.errors[:status].any?
    assert order.errors[:total_cents].any?
  end

  test "baseline schema has no customer lookup index" do
    indexes = ActiveRecord::Base.connection.indexes(:orders)
    assert_not indexes.any? { |index| index.columns.first == "customer_id" }
    assert ActiveRecord::Base.connection.extension_enabled?("pg_stat_statements")
  end
end
