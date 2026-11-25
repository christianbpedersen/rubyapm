require "test_helper"

# Regressions for the November 2026 security review.
class SecurityTest < ActionDispatch::IntegrationTest
  setup do
    @watched = App.create!(name: "Sec", api_key: "nf_sec")
  end

  test "links never take host, protocol or other url_for options from the query" do
    sign_in
    get "/apps/#{@watched.id}?protocol=javascript&host=%250aalert(document.domain)%252f%252f&type=web"
    hrefs = css_select("a").map { |a| a["href"].to_s }
    assert hrefs.none? { |h| h.start_with?("javascript") || h.include?("document.domain") }, hrefs.grep(/javascript|document/).inspect
    assert_includes hrefs, "/apps/#{@watched.to_param}?range=1h&type=web"
    get "/apps/#{@watched.id}/transactions?host=evil.example&sort=avg"
    assert css_select("a").none? { |a| a["href"].to_s.include?("evil.example") }
  end

  test "pages send a CSP with a nonce for inline scripts, and refuse framing" do
    get "/login"
    csp = response.headers["Content-Security-Policy"]
    assert_match "script-src 'self' 'nonce-", csp
    assert_match "frame-ancestors 'none'", csp
    assert_match "object-src 'none'", csp
    assert_equal "DENY", response.headers["X-Frame-Options"]
    nonce = csp[/'nonce-([^']+)'/, 1]
    assert_select "script[nonce='#{nonce}']"
  end

  test "members can't see keys, add, rotate or delete apps" do
    sign_in(email: "m@example.com", role: "member")
    [[:get, "/apps/#{@watched.id}/settings"], [:get, "/apps/new"], [:post, "/apps", { app: { name: "x" } }],
     [:post, "/apps/#{@watched.id}/regenerate_key"], [:delete, "/apps/#{@watched.id}", { confirm_name: "Sec" }]].each do |verb, path, params|
      send(verb, path, params: params || {})
      assert_response :forbidden, "#{verb} #{path}"
    end
    assert_equal "nf_sec", @watched.reload.api_key
    get "/apps/#{@watched.id}"
    assert_select "a", text: "Settings", count: 0
  end

  test "alert webhooks may only target public addresses" do
    Rails.configuration.x.webhooks_allow_private = false
    policy = @watched.alert_policies.first
    %w[http://127.0.0.1/hook http://10.0.0.5/x http://[::1]/x http://169.254.169.254/latest https://example.com:8443/x].each do |url|
      policy.webhook_url = url
      refute policy.valid?, url
    end
    assert_raises(WebhookTarget::Blocked) { WebhookTarget.resolve!(URI("http://localhost/hook")) }
    assert WebhookTarget.blocked?("::ffff:192.168.1.10")
    refute WebhookTarget.blocked?("93.184.216.34")

    incident = Incident.create!(app: @watched, alert_policy: policy, opened_at: Time.current, threshold: 1, opened_value: 2)
    policy.update_column(:webhook_url, "http://localhost:9/hook")
    Notifier.deliver(incident, :opened)
    assert_match "not sent:", incident.reload.notify_error
  ensure
    Rails.configuration.x.webhooks_allow_private = true
  end

  test "ingest rejects oversized or unauthenticated bodies before reading them" do
    post "/api/v1/ingest", params: "x", headers: { "Content-Type" => "application/msgpack", "Authorization" => "Bearer nf_sec",
                                                   "Content-Length" => (30 * 1024 * 1024).to_s }
    assert_response :content_too_large
    Rails.configuration.x.auto_register_apps = false
    post "/api/v1/ingest", params: "x", headers: { "Content-Type" => "application/msgpack", "Authorization" => "Bearer nope" }
    assert_response :unauthorized
  ensure
    Rails.configuration.x.auto_register_apps = true
  end

  test "a password change revokes API tokens; members can't change their email" do
    user = sign_in(email: "mo@example.com", role: "member")
    token = ApiToken.issue!(kind: "personal", user: user, name: "laptop")
    patch "/account", params: { user: { name: "Mo", email: "ceo@example.com" } }
    assert_equal ["Mo", "mo@example.com"], [user.reload.name, user.email]
    patch "/account/password", params: { current_password: AuthHelpers::PASSWORD, password: "a whole new password", password_confirmation: "a whole new password" }
    assert_nil ApiToken.authenticate(token.token)
  end

  test "a setup link can't get a member around SSO-only sign-in" do
    member = User.create!(email: "sso@example.com", role: "member")
    SsoConfig.current.update!(enabled: true, idp_metadata_xml: FakeSamlIdp.new.metadata, password_login: "admins")
    get "/password/#{member.generate_token_for(:password_setup)}"
    follow_redirect!
    assert_redirected_to "/login"
    refute member.reload.activated?
  end

  test "OAuth codes, verifiers, SAML responses and webhook URLs are filtered from logs" do
    filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)
    out = filter.filter("code" => "c", "code_verifier" => "v", "SAMLResponse" => "s", "webhook_url" => "w", "code_challenge" => "ok")
    assert_equal %w[[FILTERED]] * 4 + ["ok"], out.values_at("code", "code_verifier", "SAMLResponse", "webhook_url", "code_challenge")
  end
end
