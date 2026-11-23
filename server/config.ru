# This file is used by Rack-based servers to start the application.

require_relative "config/environment"

# Served under a path prefix behind a shared load balancer (e.g. /apm) when
# RAILS_RELATIVE_URL_ROOT is set; Rails then generates prefixed URLs.
prefix = ENV.fetch("RAILS_RELATIVE_URL_ROOT", "").chomp("/")
if prefix.empty?
  run Rails.application
else
  map(prefix) { run Rails.application }
end
Rails.application.load_server
