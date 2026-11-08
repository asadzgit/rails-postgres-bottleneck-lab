#!/usr/bin/env ruby
require "json"

abort "Usage: ruby script/summarize-next.rb RESULTS_DIR [RESULTS_DIR ...]" if ARGV.empty?
puts "Run | Requests | Successes | Rails pool timeouts | DB connection errors | Lock timeouts | Query cancellations | Successful p95 ms"
puts "--- | ---: | ---: | ---: | ---: | ---: | ---: | ---:"
ARGV.each do |directory|
  metrics = JSON.parse(File.read(File.join(directory, "k6-summary.json"))).fetch("metrics")
  names = %w[successful_requests rails_pool_timeouts database_connection_errors lock_timeouts]
  counts = names.map { |name| metrics.fetch(name).fetch("passes") }
  cancelled = metrics.key?("query_cancellations") ? metrics.fetch("query_cancellations").fetch("passes") : "not recorded"
  latency = metrics["successful_latency"]
  p95 = latency ? format("%.3f", latency.fetch("p(95)")) : "no successful requests"
  puts "#{File.basename(directory)} | #{metrics.fetch('http_reqs').fetch('count')} | #{counts.join(' | ')} | #{cancelled} | #{p95}"
end
puts "\nRecognized experiment errors are still unsuccessful requests; do not compare mixed success/failure latency as a speedup."
