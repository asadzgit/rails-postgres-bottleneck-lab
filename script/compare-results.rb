#!/usr/bin/env ruby
require "json"
require "csv"

abort "Usage: ruby script/compare-results.rb BEFORE_DIR AFTER_DIR" unless ARGV.length == 2

runs = ARGV.map do |directory|
  summary = JSON.parse(File.read(File.join(directory, "k6-summary.json"))).fetch("metrics")
  plan = JSON.parse(File.read(File.join(directory, "plan.json"))).first
  statements = CSV.read(File.join(directory, "statements.csv"), headers: true)
  orders = statements.find { |row| row["query"].include?('SELECT "orders".*') }
  abort "No measured order query in #{directory}" unless orders
  {
    "Requests" => summary.fetch("http_reqs").fetch("count"),
    "Requests/sec" => summary.fetch("http_reqs").fetch("rate"),
    "HTTP median ms" => summary.fetch("http_req_duration").fetch("med"),
    "HTTP p95 ms" => summary.fetch("http_req_duration").fetch("p(95)"),
    "HTTP failure fraction" => summary.fetch("http_req_failed").fetch("value"),
    "Failed checks" => summary.fetch("checks").fetch("fails"),
    "Order SQL mean ms under load" => Float(orders["mean_exec_ms"]),
    "Representative EXPLAIN execution ms" => plan.fetch("Execution Time"),
    "Representative EXPLAIN shared hits" => plan.fetch("Plan").fetch("Shared Hit Blocks")
  }
end
puts "Metric | Baseline | Optimized"
puts "--- | ---: | ---:"
runs.first.each_key do |metric|
  values = runs.map { |run| run.fetch(metric) }.map { |value| value.is_a?(Float) ? format("%.3f", value) : value }
  puts "#{metric} | #{values.join(' | ')}"
end
puts "\nSQL execution time and end-to-end HTTP latency are different measurements."
puts "Inspect both metadata files and resource-sampling limitations before drawing conclusions."
