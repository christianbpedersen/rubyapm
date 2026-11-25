require "ipaddr"
require "socket"

# Where alert webhooks may go: public internet addresses on ports 80/443.
# Resolves the host once and returns the address to connect to, so a DNS
# answer cannot switch to an internal address between the check and the
# request (rebinding). Tests and local development may allow private
# addresses with config.x.webhooks_allow_private.
module WebhookTarget
  class Blocked < StandardError; end

  BLOCKED_RANGES = %w[
    0.0.0.0/8 10.0.0.0/8 100.64.0.0/10 127.0.0.0/8 169.254.0.0/16 172.16.0.0/12 192.0.0.0/24
    192.0.2.0/24 192.168.0.0/16 198.18.0.0/15 198.51.100.0/24 203.0.113.0/24 224.0.0.0/4 240.0.0.0/4
    ::/128 ::1/128 fc00::/7 fe80::/10 ff00::/8 64:ff9b::/96 2001:db8::/32
  ].map { |r| IPAddr.new(r) }.freeze
  PORTS = [80, 443].freeze

  module_function

  def allow_private? = Rails.configuration.x.webhooks_allow_private == true

  # Returns the IP to connect to, or raises Blocked with a user-facing reason.
  def resolve!(uri)
    return nil if allow_private?
    raise Blocked, "webhooks must use port 80 or 443" unless PORTS.include?(uri.port)

    addresses = Addrinfo.getaddrinfo(uri.host, nil, nil, :STREAM).map(&:ip_address).uniq
    raise Blocked, "the webhook host does not resolve" if addresses.empty?
    if addresses.any? { |a| blocked?(a) }
      raise Blocked, "webhooks must point at a public internet address"
    end
    addresses.first
  rescue SocketError
    raise Blocked, "the webhook host does not resolve"
  end

  def blocked?(address)
    ip = IPAddr.new(address)
    ip = ip.native if ip.ipv4_mapped? || ip.ipv4_compat?
    BLOCKED_RANGES.any? { |range| range.family == ip.family && range.include?(ip) }
  rescue IPAddr::InvalidAddressError
    true
  end
end
