RubyAPM.configure do |c|
  c.app_name = "Shopwell"
  c.api_key = ENV.fetch("RUBY_APM_API_KEY", "nf_dev_shopwell")
  c.endpoint = ENV.fetch("RUBY_APM_ENDPOINT", "http://localhost:4400")
  c.flush_interval = Float(ENV.fetch("RUBY_APM_FLUSH_INTERVAL", 10))
  c.apdex_t = 300
  c.trace_threshold = 400
  c.slow_query_threshold = 40
end
