class LabController < ApplicationController
  before_action :require_experiment_mode

  rescue_from ActiveRecord::StatementInvalid do |exception|
    if exception.cause.is_a?(PG::ConnectionBad)
      render json: { error: "database_connection_unavailable" }, status: :service_unavailable
    else
      raise exception
    end
  end

  rescue_from ActiveRecord::ConnectionNotEstablished, PG::ConnectionBad do
    render json: { error: "database_connection_unavailable" }, status: :service_unavailable
  end
  rescue_from ActiveRecord::ConnectionTimeoutError do
    render json: { error: "rails_pool_timeout" }, status: :service_unavailable
  end
  rescue_from ActiveRecord::LockWaitTimeout do
    render json: { error: "lock_timeout" }, status: :locked
  end

  rescue_from ActiveRecord::QueryCanceled do
    render json: { error: "query_canceled" }, status: :service_unavailable
  end

  def connection_work
    hold_ms = positive_integer(params[:hold_ms], default: 100, maximum: 2000)
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    result = ActiveRecord::Base.connection_pool.with_connection do |connection|
      acquired = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      row = connection.exec_query("SELECT pg_backend_pid() AS backend_pid, pg_sleep(#{connection.quote(hold_ms / 1000.0)})::text AS work").first
      {
        hold_ms: hold_ms, backend_pid: row.fetch("backend_pid"),
        checkout_wait_ms: (acquired - started) * 1000,
        database_round_trip_ms: (Process.clock_gettime(Process::CLOCK_MONOTONIC) - acquired) * 1000
      }
    end
    render json: result
  end

  def pool
    render json: ActiveRecord::Base.connection_pool.stat
  end

  def increment
    mode = params.fetch(:mode, "long")
    raise ActionController::BadRequest unless %w[long short].include?(mode)
    work_ms = positive_integer(params[:work_ms], default: 100, maximum: 2000)
    lock_timeout_ms = positive_integer(params[:lock_timeout_ms], default: 250, maximum: 5000)
    render json: Lab::CounterIncrement.new(mode: mode, work_ms: work_ms, lock_timeout_ms: lock_timeout_ms).call
  end

  private

  def require_experiment_mode
    head :not_found if Rails.env.production? || ENV["LAB_EXPERIMENT_ENDPOINTS"] != "1"
  end
end
