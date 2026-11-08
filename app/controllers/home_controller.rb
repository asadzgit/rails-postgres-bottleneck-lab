class HomeController < ApplicationController
  def index
    render json: {
      name: "Rails PostgreSQL Bottleneck Lab",
      experiment: "01-missing-index",
      customers: "/customers",
      recent_orders: "/customers/:customer_id/orders?limit=20"
    }
  end
end
