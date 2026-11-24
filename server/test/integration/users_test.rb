require "test_helper"

# Sign-in, setup links and user management.
class UsersTest < ActionDispatch::IntegrationTest
  test "sign in and out" do
    User.create!(email: "ana@example.com", role: "member", password: AuthHelpers::PASSWORD)
    get "/"
    assert_redirected_to "/login"
    post "/login", params: { email: "ana@example.com", password: "wrong password!" }
    assert_response :unprocessable_entity
    post "/login", params: { email: "ANA@example.com ", password: AuthHelpers::PASSWORD }
    assert_redirected_to "http://www.example.com/"
    assert_match "rapm_session", response.headers["Set-Cookie"].to_s
    get "/"
    assert_response :success
    assert_select ".user-menu a", text: "ana@example.com"
    assert_select ".user-menu a", text: "Users", count: 0

    delete "/logout"
    get "/"
    assert_redirected_to "/login"
  end

  test "login page explains how to create the first admin" do
    get "/login"
    assert_select ".callout", /rubyapm:create_user/
  end

  test "admins add users, who set their own password from the link" do
    sign_in
    get "/users"
    assert_response :success
    post "/users", params: { user: { email: "bo@example.com", name: "Bo", role: "member" } }
    assert_response :created
    link = css_select("input[aria-label='Setup link']").first["value"]
    token = link[%r{/password/(.+)\z}, 1]
    assert User.find_by(email: "bo@example.com").then { |u| !u.activated? }

    reset!
    post "/login", params: { email: "bo@example.com", password: "" }
    assert_response :unprocessable_entity
    get "/password/#{token}"
    assert_response :success
    patch "/password/#{token}", params: { password: "short", password_confirmation: "short" }
    assert_response :unprocessable_entity
    patch "/password/#{token}", params: { password: "a long enough password", password_confirmation: "different one here" }
    assert_response :unprocessable_entity
    patch "/password/#{token}", params: { password: "a long enough password", password_confirmation: "a long enough password" }
    assert_redirected_to "/"
    get "/"
    assert_response :success
    # Members can't manage users.
    get "/users"
    assert_response :forbidden
    # The link works once.
    get "/password/#{token}"
    assert_response :not_found
  end

  test "setup links never carry the password hash" do
    user = User.create!(email: "dee@example.com", role: "member", password: AuthHelpers::PASSWORD)
    token = user.generate_token_for(:password_setup)
    payload = Base64.decode64(token.split("--").first)
    refute_includes payload, user.password_digest
    refute_includes payload, user.password_digest[7, 22] # the salt
    assert_equal user, User.find_by_token_for(:password_setup, token)
    user.update!(password: "another long password")
    assert_nil User.find_by_token_for(:password_setup, token)
  end

  test "the last admin can't be demoted or removed, and nobody removes themselves" do
    admin = sign_in
    patch "/users/#{admin.id}", params: { user: { role: "member" } }
    assert_response :unprocessable_entity
    assert admin.reload.admin?
    delete "/users/#{admin.id}"
    assert admin.reload

    other = User.create!(email: "cy@example.com", role: "admin", password: AuthHelpers::PASSWORD)
    patch "/users/#{admin.id}", params: { user: { role: "member" } }
    assert_redirected_to "/users"
    refute admin.reload.admin?
    sign_in(email: "cy@example.com")
    ApiToken.issue!(kind: "personal", user: admin, name: "x")
    delete "/users/#{admin.id}"
    assert_redirected_to "/users"
    refute User.exists?(admin.id)
    assert_equal 0, ApiToken.where(user_id: admin.id).count
    assert other.reload.admin?
  end

  test "account: password change signs out other browsers; tokens shown once" do
    user = sign_in
    other_browser = open_session
    other_browser.post "/login", params: { email: user.email, password: AuthHelpers::PASSWORD }
    assert_equal 2, user.sessions.count

    patch "/account/password", params: { current_password: "nope", password: "new password 123", password_confirmation: "new password 123" }
    assert_response :unprocessable_entity
    patch "/account/password", params: { current_password: AuthHelpers::PASSWORD, password: "new password 123", password_confirmation: "new password 123" }
    assert_redirected_to "/account"
    assert_equal 1, user.sessions.count
    other_browser.get "/"
    assert_equal 302, other_browser.response.status

    post "/account/tokens", params: { name: "Claude Code", expires: "30" }
    assert_response :created
    plaintext = css_select("input[aria-label='API token']").first["value"]
    assert plaintext.start_with?("rapm_pat_")
    token = ApiToken.authenticate(plaintext)
    assert_equal user, token.user
    assert_in_delta 30.days.from_now, token.expires_at, 5
    refute_includes ApiToken.pluck(:token_digest), plaintext

    get "/account"
    assert_response :success
    assert_no_match plaintext, response.body
    delete "/account/tokens/#{token.id}"
    assert_nil ApiToken.authenticate(plaintext)
  end
end
