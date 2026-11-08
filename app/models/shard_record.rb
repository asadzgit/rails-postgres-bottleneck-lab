class ShardRecord < ActiveRecord::Base
  self.abstract_class = true
  connects_to shards: {
    single: { writing: :lab_single },
    a: { writing: :lab_shard_a },
    b: { writing: :lab_shard_b }
  }
end
