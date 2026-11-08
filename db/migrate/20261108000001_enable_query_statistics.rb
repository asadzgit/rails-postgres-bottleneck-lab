class EnableQueryStatistics < ActiveRecord::Migration[8.1]
  def change
    enable_extension "pg_stat_statements"
  end
end
