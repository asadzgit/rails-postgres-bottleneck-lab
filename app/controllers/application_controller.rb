class ApplicationController < ActionController::API
  rescue_from ActiveRecord::RecordNotFound do
    render json: { error: "not_found" }, status: :not_found
  end

  rescue_from ActionController::BadRequest do
    render json: { error: "invalid_parameters" }, status: :bad_request
  end

  private

  def positive_integer(value, default: nil, maximum: 9_223_372_036_854_775_807)
    return default if value.nil? && !default.nil?
    raise ActionController::BadRequest unless value.to_s.match?(/\A[1-9][0-9]*\z/)

    number = Integer(value, 10)
    raise ActionController::BadRequest if number > maximum
    number
  end
end
