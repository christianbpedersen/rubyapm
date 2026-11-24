require "test_helper"

# SAML single sign-on against a fake OneLogin: setup, SP- and IdP-initiated
# sign-in, provisioning rules, the password policy, and responses that must
# be refused (tampered, wrong signer, expired, wrong audience, replayed).
class SamlTest < ActionDispatch::IntegrationTest
  setup do
    @idp = FakeSamlIdp.new
    @sso = SsoConfig.current
    @sso.update!(enabled: true, idp_metadata_xml: @idp.metadata, button_label: "OneLogin")
  end

  def acs(saml_response)
    post "/saml/acs", params: { SAMLResponse: saml_response }
  end

  def signed_in_as?(email)
    get "/account"
    response.successful? && response.body.include?(email)
  end

  test "SP metadata and the admin settings page" do
    get "/saml/metadata"
    assert_response :success
    assert_match %r{entityID=['"]http://www.example.com/saml/metadata['"]}, response.body
    assert_includes response.body, "http://www.example.com/saml/acs"

    sign_in(email: "member@example.com", role: "member")
    get "/sso"
    assert_response :forbidden
    sign_in
    get "/sso"
    assert_response :success
    assert_select "dd", text: "https://idp.test/metadata"

    patch "/sso", params: { sso_config: { idp_metadata_xml: "<nope/>", enabled: "1" } }
    assert_response :unprocessable_entity
    patch "/sso", params: { sso_config: { idp_metadata_xml: @idp.metadata, allowed_domains: "Bunny.com, @example.com", auto_provision: "1" } }
    assert_redirected_to "/sso"
    assert_equal %w[bunny.com example.com], @sso.reload.allowed_domains
  end

  test "SP-initiated sign-in returns to the page that asked for it" do
    User.create!(email: "ana@example.com", role: "member")
    get "/account"
    assert_redirected_to "/login"
    get "/login"
    assert_select "button", text: "Sign in with OneLogin"

    get "/saml/login"
    idp_url = URI.parse(response.location)
    assert_equal "idp.test", idp_url.host
    request_xml = Zlib::Inflate.new(-Zlib::MAX_WBITS).inflate(Base64.decode64(Rack::Utils.parse_query(idp_url.query)["SAMLRequest"]))
    request_id = request_xml[/ID=['"]([^'"]+)/, 1]

    acs(@idp.response(email: "ANA@example.com", in_response_to: request_id, attributes: { firstName: "Ana", lastName: "Silva" }))
    assert_redirected_to "http://www.example.com/account"
    assert signed_in_as?("ana@example.com")
    user = User.find_by(email: "ana@example.com")
    assert_equal "Ana Silva", user.name
    assert_equal "saml", user.last_sign_in_via
    refute user.activated?, "SSO users need no password"
  end

  test "IdP-initiated sign-in (OneLogin app tile)" do
    User.create!(email: "bo@example.com", role: "member")
    acs(@idp.response(email: "bo@example.com"))
    assert_redirected_to "http://www.example.com/"
    assert signed_in_as?("bo@example.com")
  end

  test "unknown people: refused unless provisioning allows their domain" do
    acs(@idp.response(email: "new@bunny.com"))
    assert_redirected_to "/login"
    assert_match "no RubyAPM account", flash[:alert]
    refute User.exists?(email: "new@bunny.com")

    @sso.update!(auto_provision: true, allowed_domains: ["bunny.com"])
    acs(@idp.response(email: "new@elsewhere.com"))
    assert_match "isn't an allowed domain", flash[:alert]
    acs(@idp.response(email: "new@bunny.com", attributes: { "User.FirstName" => "Nu" }))
    assert_redirected_to "http://www.example.com/"
    created = User.find_by!(email: "new@bunny.com")
    assert_equal "member", created.role
    assert_equal "Nu", created.name
  end

  test "refuses forged, foreign, expired, misdirected and replayed responses" do
    User.create!(email: "ana@example.com", role: "admin")
    User.create!(email: "eve@example.com", role: "member")
    refusals = {
      "unsigned" => @idp.response(email: "ana@example.com", signed: false),
      "signed by someone else" => @idp.response(email: "ana@example.com", sign_with: FakeSamlIdp.new),
      "email changed after signing" => @idp.response(email: "eve@example.com", tamper: ->(x) { x.sub("eve@example.com", "ana@example.com") }),
      "expired" => @idp.response(email: "ana@example.com", not_on_or_after: 10.minutes.ago),
      "for another service" => @idp.response(email: "ana@example.com", audience: "https://other.example/saml/metadata"),
      "garbage" => Base64.strict_encode64("<xml/>")
    }
    refusals.each do |label, saml|
      reset!
      acs(saml)
      assert_redirected_to "/login", label
      refute signed_in_as?("ana@example.com"), "#{label} must not sign in"
    end

    # A response answering a different request than the one this browser made.
    get "/saml/login"
    acs(@idp.response(email: "ana@example.com", in_response_to: "_someone_elses_request"))
    assert_redirected_to "/login"

    # The same assertion can't be used twice.
    original = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    saml = @idp.response(email: "ana@example.com")
    reset!
    acs(saml)
    assert_redirected_to "http://www.example.com/"
    reset!
    acs(saml)
    assert_redirected_to "/login"
    assert_match "already used", flash[:alert]
  ensure
    Rails.cache = original if original
  end

  test "SSO switched off: no button, no sign-in" do
    @sso.update!(enabled: false)
    User.create!(email: "ana@example.com", role: "member")
    get "/login"
    assert_select "button", text: /Sign in with/, count: 0
    acs(@idp.response(email: "ana@example.com"))
    assert_redirected_to "/login"
    refute signed_in_as?("ana@example.com")
  end

  test "password sign-in can be limited to admins" do
    member = User.create!(email: "mo@example.com", role: "member", password: AuthHelpers::PASSWORD)
    @sso.update!(password_login: "admins")
    post "/login", params: { email: member.email, password: AuthHelpers::PASSWORD }
    assert_response :unprocessable_entity
    assert_match "Sign in with OneLogin instead", response.body
    sign_in
    assert_redirected_to "http://www.example.com/"
  end
end
