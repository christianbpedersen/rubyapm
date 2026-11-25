# chirpbin.com is served through Cloudflare, so the request's peer is a
# Cloudflare edge. Trust Cloudflare's published ranges (plus the usual private
# ones for Caddy and Docker) so request.remote_ip is the real client: rate
# limits and session records are per person, not per Cloudflare data center.
# Caddy only passes on an X-Forwarded-For it received from Cloudflare.
# https://www.cloudflare.com/ips/
CLOUDFLARE_RANGES = %w[
  173.245.48.0/20 103.21.244.0/22 103.22.200.0/22 103.31.4.0/22 141.101.64.0/18 108.162.192.0/18
  190.93.240.0/20 188.114.96.0/20 197.234.240.0/22 198.41.128.0/17 162.158.0.0/15 104.16.0.0/13
  104.24.0.0/14 172.64.0.0/13 131.0.72.0/22
  2400:cb00::/32 2606:4700::/32 2803:f800::/32 2405:b500::/32 2405:8100::/32 2a06:98c0::/29 2c0f:f248::/32
].map { |range| IPAddr.new(range) }.freeze

Rails.application.config.action_dispatch.trusted_proxies =
  ActionDispatch::RemoteIp::TRUSTED_PROXIES + (ENV["RUBY_APM_TRUST_CLOUDFLARE"] == "0" ? [] : CLOUDFLARE_RANGES)
