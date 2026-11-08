namespace :lab do
  namespace :index do
    desc "Enable Experiment 1's optional recent-orders index (outside normal migrations)"
    task enable: :environment do
      raise "Experiment changes are disabled in production" if Rails.env.production?
      load Rails.root.join("db/optimizations/20261108000003_add_recent_orders_index.rb")
      AddRecentOrdersIndex.new.migrate(:up)
      valid = ActiveRecord::Base.connection.select_value(<<~SQL)
        SELECT indisvalid FROM pg_index
        WHERE indexrelid = to_regclass('index_orders_on_customer_recent')
      SQL
      raise "Index is invalid; disable it and retry with no active load" unless valid
      ActiveRecord::Base.connection.execute("ANALYZE orders")
    end

    desc "Restore the missing-index baseline without deleting data"
    task disable: :environment do
      raise "Experiment changes are disabled in production" if Rails.env.production?
      load Rails.root.join("db/optimizations/20261108000003_add_recent_orders_index.rb")
      AddRecentOrdersIndex.new.migrate(:down)
      ActiveRecord::Base.connection.execute("ANALYZE orders")
    end
  end
end
