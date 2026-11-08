class CreateAdvancedLabItems < ActiveRecord::Migration[8.1]
  def change
    %i[lab_cache_items lab_replica_items].each do |name|
      create_table name do |t|
        t.bigint :value, null: false, default: 0
        t.bigint :version, null: false, default: 0
      end
    end
  end
end
