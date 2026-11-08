# Kept outside db/migrate so ordinary setup preserves the unoptimized experiment.
class AddRecentOrdersIndex < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    add_index :orders, [ :customer_id, :created_at, :id ],
      order: { created_at: :desc, id: :desc },
      name: "index_orders_on_customer_recent", algorithm: :concurrently, if_not_exists: true
  end

  def down
    remove_index :orders, name: "index_orders_on_customer_recent", algorithm: :concurrently, if_exists: true
  end
end
