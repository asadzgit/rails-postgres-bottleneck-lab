require "json"
abort "Usage: ruby script/summarize-advanced.rb RESULTS_DIR ..." if ARGV.empty?
puts "Scenario | Requests | HTTP failures | HTTP p95 ms | Cache hit fraction"
puts "--- | ---: | ---: | ---: | ---:"
ARGV.each do |directory|
  metrics = JSON.parse(File.read(File.join(directory, "k6-summary.json"))).fetch("metrics")
  failed = metrics.fetch("http_req_failed").fetch("passes")
  puts "#{File.basename(directory)} | #{metrics.fetch('http_reqs').fetch('count')} | #{failed} | #{format('%.3f', metrics.fetch('http_req_duration').fetch('p(95)'))} | #{format('%.4f', metrics.fetch('cache_hits').fetch('value'))}"
end
puts "Read metadata, database execution statistics and resource limitations; HTTP latency alone is not diagnosis."
