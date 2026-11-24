# Signs in through the real login form, so tests exercise the cookie flow.
module AuthHelpers
  PASSWORD = "correct horse battery staple"

  def sign_in(email: "admin@example.com", role: "admin")
    user = User.find_by(email: email) || User.create!(email: email, role: role, password: PASSWORD)
    post "/login", params: { email: email, password: PASSWORD }
    user
  end
end

ActionDispatch::IntegrationTest.include AuthHelpers
