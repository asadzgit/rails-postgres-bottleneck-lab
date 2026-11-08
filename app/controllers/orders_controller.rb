class OrdersController < ApplicationController
  def index
    limit = positive_integer(params[:limit], default: 20, maximum: 100)
    customer = Customer.find(positive_integer(params[:customer_id]))
    # Intentionally slow before Experiment 1's optional composite index is enabled.
    orders = customer.orders.recent.limit(limit)
    render json: { orders: orders.as_json(only: [ :id, :customer_id, :status, :total_cents, :created_at ]) }
  end
end
