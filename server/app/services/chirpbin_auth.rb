require "net/http"
require "json"
require "digest"

# Optional sign-in through the shared chirpbin.com auth service (auth.chirpbin.com).
# Enabled when AUTH_INTERNAL_URL is set (as on nuc2).
#
# The auth service sets an opaque token in the `chirpbin_session` cookie on
# .chirpbin.com. It is verified server-to-server over the internal Docker
# network and a positive answer is cached briefly, so a page view is not an
# HTTP round trip; a sign-out can take up to CACHE_FOR to land here.
class ChirpbinAuth
  COOKIE = "chirpbin_session"
  CACHE_FOR = 60.seconds

  # The auth service is down or misbehaving, as opposed to "not signed in".
  Unavailable = Class.new(StandardError)
  # Signed in, but not granted this app at auth.chirpbin.com/admin.
  FORBIDDEN = :forbidden

  # This app's slug in the auth service (its /admin/apps list).
  def self.app_slug
    ENV.fetch("CHIRPBIN_APP_SLUG", "apm")
  end

  def self.enabled?
    ENV["AUTH_INTERNAL_URL"].present?
  end

  def self.current_user(token)
    return nil if token.blank?

    Rails.cache.fetch("chirpbin_auth:#{app_slug}:#{Digest::SHA256.hexdigest(token)}", expires_in: CACHE_FOR, skip_nil: true) do
      verify(token)
    end
  end

  def self.login_url(return_to:)
    "#{public_url}/login?#{{ return_to: return_to }.to_query}"
  end

  def self.logout_url
    "#{public_url}/logout"
  end

  def self.public_url
    ENV.fetch("AUTH_URL", "https://auth.chirpbin.com")
  end

  # The user hash, FORBIDDEN when signed in without access to this app, or
  # nil when not signed in.
  def self.verify(token)
    uri = URI.join(ENV.fetch("AUTH_INTERNAL_URL"), "/api/session")
    uri.query = URI.encode_www_form(app: app_slug)
    request = Net::HTTP::Get.new(uri)
    request["Authorization"] = "Bearer #{token}"

    response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 2, read_timeout: 3) do |http|
      http.request(request)
    end

    case response
    when Net::HTTPSuccess then JSON.parse(response.body).fetch("user")
    when Net::HTTPUnauthorized then nil
    when Net::HTTPForbidden then FORBIDDEN
    else raise Unavailable, "auth service returned #{response.code}"
    end
  rescue SocketError, SystemCallError, Net::OpenTimeout, Net::ReadTimeout, JSON::ParserError => e
    raise Unavailable, "#{e.class}: #{e.message}"
  end
end
