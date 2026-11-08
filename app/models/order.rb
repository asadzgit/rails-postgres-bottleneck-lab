class Order < ApplicationRecord
  belongs_to :customer, inverse_of: :orders

  STATUSES = %w[pending paid shipped cancelled].freeze
  scope :recent, -> { order(created_at: :desc, id: :desc) }

  validates :status, inclusion: { in: STATUSES }
  validates :total_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
end
