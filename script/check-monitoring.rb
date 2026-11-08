require "net/http"
require "json"
require "fileutils"

def fetch_monitor(url)
  uri = URI(url)
  http = Net::HTTP.new(uri.host, uri.port, nil) # Private Docker services only.
  http.open_timeout = 3
  http.read_timeout = 3
  response = http.get(uri.request_uri)
  raise "Monitoring HTTP #{response.code}" unless response.code == "200"
  JSON.parse(response.body)
end

deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 40
loop do
  begin
    query = fetch_monitor("http://prometheus:9090/api/v1/query?query=lab_pg_up")
    fetch_monitor("http://grafana:3000/api/health")
    fetch_monitor("http://grafana:3000/api/dashboards/uid/rails-pg-lab")
    break if query.fetch("data").fetch("result").any? { |row| row["value"][1] == "1" }
  rescue StandardError => exception
    last_error = exception.message
  end
  raise "Prometheus did not scrape PostgreSQL: #{last_error}" if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
  sleep 1
end
health = fetch_monitor("http://grafana:3000/api/health")
dashboard = fetch_monitor("http://grafana:3000/api/dashboards/uid/rails-pg-lab")
proxy = fetch_monitor("http://grafana:3000/api/datasources/proxy/uid/lab-prometheus/api/v1/query?query=lab_pg_up")
raise "Dashboard datasource not working" unless proxy["data"]["result"].any? { |row| row["value"][1] == "1" }
raise "Dashboard provisioning missing" unless dashboard["dashboard"]["panels"].length == 10
output = ARGV.fetch(0)
FileUtils.mkdir_p(output)
File.write(File.join(output, "monitoring.json"), JSON.pretty_generate({ observed_at: Time.now.utc.iso8601,
  prometheus_build: fetch_monitor("http://prometheus:9090/api/v1/status/buildinfo"),
  grafana_health: health, datasource_query: proxy, dashboard_uid: dashboard["dashboard"]["uid"], panels: 10 }))
puts "Actual Prometheus scrape, Grafana provisioning and datasource query passed."
