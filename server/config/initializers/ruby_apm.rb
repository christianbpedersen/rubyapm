# RubyAPM monitoring itself: reports as the "APM" app when RUBY_APM_API_KEY
# is set (production on nuc2). Without a key (development, tests) the agent
# stays off and its middleware passes requests straight through.
#
# It reports to this same server over the container's loopback. The upload
# runs on the agent's background thread, outside any request, so it is not
# traced; the ingest request it causes is one more transaction every 10 s.
RubyAPM.configure do |c|
  c.app_name = ENV.fetch("RUBY_APM_APP_NAME", "APM")
  c.api_key = ENV["RUBY_APM_API_KEY"]
  c.endpoint = ENV.fetch("RUBY_APM_ENDPOINT", "http://127.0.0.1:3000#{ENV.fetch('RAILS_RELATIVE_URL_ROOT', '').chomp('/')}")
  c.environment = Rails.env
end
