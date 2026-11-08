class ReplicaRecord < ActiveRecord::Base
  self.abstract_class = true
  establish_connection :lab_replica
end
