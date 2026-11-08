class Customer < ApplicationRecord
  has_many :orders, inverse_of: :customer, dependent: :restrict_with_exception

  validates :name, :email, presence: true
end
