# This file is used by Rack-based servers to start the application.

require_relative "config/environment"

# Served under a path prefix behind a shared load balancer (e.g. /apm) when
# RAILS_RELATIVE_URL_ROOT is set; Rails then generates prefixed URLs.
prefix = ENV.fetch("RAILS_RELATIVE_URL_ROOT", "").chomp("/")
if prefix.empty?
  run Rails.application
else
  # OAuth discovery for an issuer with a path (RFC 8414, RFC 9728) lives at
  # the host root with the path appended, e.g.
  # /.well-known/oauth-authorization-server/apm. The proxy forwards those
  # here too; hand them to the app as its own /.well-known routes.
  %w[oauth-authorization-server oauth-protected-resource].each do |doc|
    map("/.well-known/#{doc}#{prefix}") do
      run ->(env) { Rails.application.call(env.merge("SCRIPT_NAME" => prefix, "PATH_INFO" => "/.well-known/#{doc}")) }
    end
  end
  map(prefix) { run Rails.application }
end
Rails.application.load_server
