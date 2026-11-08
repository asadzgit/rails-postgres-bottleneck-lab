require "test_helper"

class SeedGeneratorTest < ActiveSupport::TestCase
  test "bulk seed is deterministic, balanced, batched and leaves sequences usable" do
    generator = Lab::SeedGenerator.new(customers: 7, orders: 23, batch_size: 5, reset: true)
    generator.call
    assert_equal 7, Customer.count
    assert_equal 23, Order.count
    assert_equal [ 3, 4 ], Order.group(:customer_id).count.values.uniq.sort
    snapshot = Order.order(:id).pluck(:id, :customer_id, :status, :total_cents, :created_at)
    generator.call
    assert_equal snapshot, Order.order(:id).pluck(:id, :customer_id, :status, :total_cents, :created_at)
    added = Order.create!(customer: Customer.first, status: "paid", total_cents: 100)
    assert_equal 24, added.id
  end

  test "existing rows require explicit reset and are preserved on refusal" do
    customer = Customer.create!(name: "Preserved", email: "keep@example.test")
    assert_raises(RuntimeError) { Lab::SeedGenerator.new(customers: 2, orders: 3).call }
    assert_equal customer, Customer.first
  end

  test "counts reject malformed and unbounded inputs" do
    [ "0", "-1", "1.5", "oops", "20000001" ].each do |count|
      assert_raises(ArgumentError) { Lab::SeedGenerator.new(orders: count) }
    end
  end
end
