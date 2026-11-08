class CreateLabCounters < ActiveRecord::Migration[8.1]
  def change
    create_table :lab_counters do |t|
      t.bigint :value, null: false, default: 0
    end
    add_check_constraint :lab_counters, "value >= 0", name: "lab_counter_nonnegative"
  end
end
