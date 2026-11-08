source "https://rubygems.org"

gem "rails", "~> 8.1.4", ">= 8.1.4.1"
gem "pg", "~> 1.1"
gem "puma", ">= 5.0"
gem "bootsnap", require: false
gem "csv", require: false
gem "redis", "~> 6.0"
gem "connection_pool", "~> 3.0"
gem "tzinfo-data", platforms: %i[ windows jruby ]

group :development, :test do
  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"
  gem "bundler-audit", require: false
  gem "brakeman", require: false
  gem "rubocop-rails-omakase", require: false
end
