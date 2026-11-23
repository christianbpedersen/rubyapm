require "test_helper"

class ChirpbinAuthTest < ActionDispatch::IntegrationTest
  setup do
    ENV["AUTH_INTERNAL_URL"] = "http://chirpbin-auth-web:3000"
    Rails.cache.clear
  end

  teardown { ENV.delete("AUTH_INTERNAL_URL") }

  def stub_verify(result)
    ChirpbinAuth.singleton_class.alias_method(:__verify, :verify)
    ChirpbinAuth.define_singleton_method(:verify) { |_token| result.is_a?(Exception) ? raise(result) : result }
    yield
  ensure
    ChirpbinAuth.singleton_class.alias_method(:verify, :__verify)
    ChirpbinAuth.singleton_class.remove_method(:__verify)
  end

  test "signed-out visitors are sent to the shared login with a return address" do
    get "/apps"
    assert_response :redirect
    assert_match %r{\Ahttps://auth\.chirpbin\.com/login\?return_to=http%3A%2F%2Fwww\.example\.com%2Fapps\z}, response.location
  end

  test "a valid chirpbin session gets in" do
    stub_verify({ "email" => "me@chirpbin.com" }) do
      cookies[ChirpbinAuth::COOKIE] = "token-1"
      get "/apps"
      assert_response :success
    end
  end

  test "signed in without access to this app is a 403 with guidance" do
    stub_verify(ChirpbinAuth::FORBIDDEN) do
      cookies[ChirpbinAuth::COOKIE] = "token-3"
      get "/apps"
      assert_response :forbidden
      assert_includes response.body, "/admin/users"
    end
  end

  test "the session check names this app" do
    captured = nil
    Net::HTTP.singleton_class.alias_method(:__start, :start)
    Net::HTTP.define_singleton_method(:start) do |*_args, **_kw, &blk|
      http = Object.new
      http.define_singleton_method(:request) do |req|
        captured = req.path
        Net::HTTPForbidden.new("1.1", "403", "Forbidden")
      end
      blk.call(http)
    end
    assert_equal ChirpbinAuth::FORBIDDEN, ChirpbinAuth.verify("t")
    assert_equal "/api/session?app=apm", captured
  ensure
    Net::HTTP.singleton_class.alias_method(:start, :__start)
    Net::HTTP.singleton_class.remove_method(:__start)
  end

  test "an unavailable auth service is a 503, not a login loop" do
    stub_verify(ChirpbinAuth::Unavailable.new("down")) do
      cookies[ChirpbinAuth::COOKIE] = "token-2"
      get "/apps"
      assert_response :service_unavailable
    end
  end

  test "agent ingest never requires the dashboard login" do
    App.create!(name: "Ingest", api_key: "nf_ingest")
    post "/api/v1/ingest", params: { v: 1, buckets: [] }.to_json,
                           headers: { "Content-Type" => "application/json", "Authorization" => "Bearer nf_ingest" }
    assert_response :accepted
  end
end
