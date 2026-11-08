# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_11_08_000005) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "pg_stat_statements"

  create_table "customers", force: :cascade do |t|
    t.string "name", null: false
    t.string "email", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "lab_cache_items", force: :cascade do |t|
    t.bigint "value", default: 0, null: false
    t.bigint "version", default: 0, null: false
  end

  create_table "lab_counters", force: :cascade do |t|
    t.bigint "value", default: 0, null: false
    t.check_constraint "value >= 0", name: "lab_counter_nonnegative"
  end

  create_table "lab_replica_items", force: :cascade do |t|
    t.bigint "value", default: 0, null: false
    t.bigint "version", default: 0, null: false
  end

  create_table "orders", force: :cascade do |t|
    t.bigint "customer_id", null: false
    t.string "status", null: false
    t.bigint "total_cents", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying::text, 'paid'::character varying::text, 'shipped'::character varying::text, 'cancelled'::character varying::text])", name: "orders_valid_status"
    t.check_constraint "total_cents >= 0", name: "orders_nonnegative_total"
  end

  add_foreign_key "orders", "customers"
end
