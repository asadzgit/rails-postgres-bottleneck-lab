Rails.application.configure do
  config.enable_reloading = false
  config.eager_load = true
  config.consider_all_requests_local = false
  config.force_ssl = true
  config.log_level = :info
  config.logger = ActiveSupport::Logger.new($stdout)
  config.active_record.dump_schema_after_migration = false
end
