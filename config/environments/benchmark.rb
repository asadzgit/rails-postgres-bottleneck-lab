# Production-like execution without production credentials or deployment concerns.
# Use only on the private local laboratory network.
Rails.application.configure do
  # Fresh clones have no master.key. This local API has no signed sessions/tokens;
  # an ephemeral boot-time key avoids borrowing production credentials.
  config.secret_key_base = SecureRandom.hex(64)
  config.enable_reloading = false
  config.eager_load = true
  config.consider_all_requests_local = false
  config.log_level = :warn
  config.logger = ActiveSupport::Logger.new($stdout)
  config.active_record.verbose_query_logs = false
  config.active_support.report_deprecations = false
  config.hosts = [ "web", "localhost", "127.0.0.1" ]
end
