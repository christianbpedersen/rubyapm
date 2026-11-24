require "test_helper"

# The OAuth 2.1 flow an MCP client such as claude.ai goes through:
# discovery, dynamic registration, consent, code + PKCE, refresh rotation.
class OauthTest < ActionDispatch::IntegrationTest
  REDIRECT = "https://claude.ai/api/mcp/auth_callback".freeze

  def pkce
    verifier = SecureRandom.urlsafe_base64(48)
    [verifier, Base64.urlsafe_encode64(Digest::SHA256.digest(verifier), padding: false)]
  end

  def register(redirect_uris = [REDIRECT])
    post "/oauth/register", params: { client_name: "Claude", redirect_uris: redirect_uris }.to_json,
                            headers: { "Content-Type" => "application/json" }
    JSON.parse(response.body)
  end

  def authorize_params(client_id, challenge, **extra)
    { response_type: "code", client_id: client_id, redirect_uri: REDIRECT, code_challenge: challenge,
      code_challenge_method: "S256", state: "xyz", scope: "mcp" }.merge(extra)
  end

  test "discovery documents" do
    post "/mcp"
    assert_response :unauthorized
    get "/.well-known/oauth-protected-resource"
    resource = JSON.parse(response.body)
    assert_equal "http://www.example.com/mcp", resource["resource"]
    get "/.well-known/oauth-protected-resource/mcp"
    assert_equal resource, JSON.parse(response.body)

    get "/.well-known/oauth-authorization-server"
    meta = JSON.parse(response.body)
    assert_equal resource["authorization_servers"], [meta["issuer"]]
    assert_equal "http://www.example.com/oauth/token", meta["token_endpoint"]
    assert_equal ["S256"], meta["code_challenge_methods_supported"]
  end

  test "registration only accepts safe redirect URIs" do
    assert_equal "invalid_redirect_uri", register(["http://evil.example/cb"])["error"]
    assert_equal "invalid_redirect_uri", register([])["error"]
    assert register(["http://127.0.0.1:33418/callback"])["client_id"]
    client = register
    assert_response :created
    assert_equal "none", client["token_endpoint_auth_method"]
  end

  test "full flow: consent, code, MCP call, refresh rotation, revoke" do
    client_id = register["client_id"]
    verifier, challenge = pkce

    # Not signed in: authorize sends the user to sign in, then back.
    get "/oauth/authorize", params: authorize_params(client_id, challenge)
    assert_redirected_to "/login"
    user = sign_in
    assert_match %r{\Ahttp://www.example.com/oauth/authorize\?}, response.location
    follow_redirect!
    assert_response :success
    assert_select "h1", /Connect Claude/

    post "/oauth/authorize", params: authorize_params(client_id, challenge, decision: "approve")
    back = URI.parse(response.location)
    assert_equal "claude.ai", back.host
    query = URI.decode_www_form(back.query).to_h
    assert_equal "xyz", query["state"]
    code = query["code"]

    # Wrong verifier, then the right one; the code works only once.
    post "/oauth/token", params: { grant_type: "authorization_code", client_id: client_id, code: code, redirect_uri: REDIRECT, code_verifier: pkce.first }
    assert_equal "invalid_grant", JSON.parse(response.body)["error"]
    post "/oauth/token", params: { grant_type: "authorization_code", client_id: client_id, code: code, redirect_uri: REDIRECT, code_verifier: verifier }
    assert_response :success
    tokens = JSON.parse(response.body)
    assert_equal "Bearer", tokens["token_type"]
    assert_equal "no-store", response.headers["Cache-Control"]
    post "/oauth/token", params: { grant_type: "authorization_code", client_id: client_id, code: code, redirect_uri: REDIRECT, code_verifier: verifier }
    assert_equal "invalid_grant", JSON.parse(response.body)["error"]

    post "/mcp", params: { jsonrpc: "2.0", id: 1, method: "tools/list" }.to_json,
                 headers: { "Content-Type" => "application/json", "Authorization" => "Bearer #{tokens['access_token']}" }
    assert_response :success
    assert JSON.parse(response.body)["result"]["tools"].any?

    # Refresh rotates: the old refresh token stops working.
    post "/oauth/token", params: { grant_type: "refresh_token", client_id: client_id, refresh_token: tokens["refresh_token"] }
    fresh = JSON.parse(response.body)
    assert fresh["access_token"].present?
    post "/oauth/token", params: { grant_type: "refresh_token", client_id: client_id, refresh_token: tokens["refresh_token"] }
    assert_equal "invalid_grant", JSON.parse(response.body)["error"]

    # The account page lists the connection; disconnecting kills its tokens.
    get "/account"
    assert_select "td", text: "Claude"
    delete "/account/connections/#{OauthClient.find_by!(client_id: client_id).id}"
    assert_nil ApiToken.authenticate(fresh["access_token"])
    assert_equal 0, user.api_tokens.where(kind: "refresh").count
  end

  test "deny, bad redirect URIs and missing PKCE" do
    client_id = register["client_id"]
    _, challenge = pkce
    sign_in
    get "/oauth/authorize", params: authorize_params(client_id, challenge, redirect_uri: "https://evil.example/cb")
    assert_response :bad_request
    get "/oauth/authorize", params: authorize_params("nope", challenge)
    assert_response :bad_request
    get "/oauth/authorize", params: authorize_params(client_id, challenge, code_challenge_method: "plain")
    assert_equal "invalid_request", URI.decode_www_form(URI.parse(response.location).query).to_h["error"]
    post "/oauth/authorize", params: authorize_params(client_id, challenge, decision: "deny")
    assert_equal "access_denied", URI.decode_www_form(URI.parse(response.location).query).to_h["error"]
    assert_equal 0, OauthCode.count
  end
end
