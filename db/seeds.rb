# Bulk SQL avoids allocating one million Active Record objects or running callbacks.
Lab::SeedGenerator.new(
  customers: ENV.fetch("CUSTOMER_COUNT", 10_000),
  orders: ENV.fetch("ORDER_COUNT", 1_000_000),
  batch_size: ENV.fetch("SEED_BATCH_SIZE", 50_000),
  reset: ENV["LAB_RESET"] == "1"
).call
puts "Seeded #{Customer.count} customers and #{Order.count} orders."
