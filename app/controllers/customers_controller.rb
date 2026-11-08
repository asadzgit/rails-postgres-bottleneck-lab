class CustomersController < ApplicationController
  def index
    limit = positive_integer(params[:limit], default: 20, maximum: 100)
    customers = Customer.order(:id)
    customers = customers.where("id > ?", positive_integer(params[:after_id])) if params[:after_id]
    render json: { customers: customers.limit(limit).as_json(only: [ :id, :name, :email ]) }
  end

  def show
    customer = Customer.find(positive_integer(params[:id]))
    render json: { customer: customer.as_json(only: [ :id, :name, :email ]) }
  end
end
