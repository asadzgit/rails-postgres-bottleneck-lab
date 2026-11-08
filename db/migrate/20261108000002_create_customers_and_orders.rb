class CreateCustomersAndOrders < ActiveRecord::Migration[8.1]
  def change
    create_table :customers do |t|
      t.string :name, null: false
      t.string :email, null: false
      t.timestamps
    end

    create_table :orders do |t|
      # Deliberately omit even the single-column index in the baseline.
      t.references :customer, null: false, foreign_key: true, index: false
      t.string :status, null: false
      t.bigint :total_cents, null: false
      t.timestamps
    end
    add_check_constraint :orders, "total_cents >= 0", name: "orders_nonnegative_total"
    add_check_constraint :orders, "status IN ('pending', 'paid', 'shipped', 'cancelled')", name: "orders_valid_status"
  end
end
