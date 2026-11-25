# Content Security Policy: scripts only from this origin (plus the nonce'd
# inline theme script and import map), no plugins, no framing, no <base>
# hijacking. style-src allows inline styles: charts and bars size themselves
# with style attributes.
Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src :self
    policy.script_src :self
    policy.style_src :self, :unsafe_inline
    policy.img_src :self, :data
    policy.font_src :self, :data
    policy.connect_src :self
    policy.object_src :none
    policy.base_uri :none
    policy.frame_ancestors :none
  end
  config.content_security_policy_nonce_generator = ->(_request) { SecureRandom.base64(16) }
  config.content_security_policy_nonce_directives = %w[script-src]

  config.action_dispatch.default_headers.merge!(
    "X-Frame-Options" => "DENY",
    "Referrer-Policy" => "strict-origin-when-cross-origin"
  )
  # Browsers stick to HTTPS for this host for a year. chirpbin.com is HTTPS
  # only (Cloudflare); subdomains are not included.
  if Rails.env.production?
    config.action_dispatch.default_headers["Strict-Transport-Security"] = "max-age=31536000"
  end
end
