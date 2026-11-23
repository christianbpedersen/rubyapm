require "net/http"
require "json"

# Thin client for the fake third-party services (payments, inventory,
# shipping, email) served by fake_services/ on port 4501.
class ExternalApi
  class Error < StandardError; end
  class PaymentDeclined < Error; end

  PORT = Integer(ENV.fetch("FAKE_SERVICES_PORT", 4501))

  def self.get(service, path)
    request(service, Net::HTTP::Get.new(path))
  end

  def self.post(service, path, body = {})
    req = Net::HTTP::Post.new(path, "Content-Type" => "application/json")
    req.body = body.to_json
    request(service, req)
  end

  def self.request(service, req)
    http = Net::HTTP.new("#{service}.localhost", PORT)
    http.open_timeout = 1
    http.read_timeout = 3
    response = http.start { |h| h.request(req) }
    raise Error, "#{service} responded #{response.code}" unless response.is_a?(Net::HTTPSuccess)
    JSON.parse(response.body)
  end
end
