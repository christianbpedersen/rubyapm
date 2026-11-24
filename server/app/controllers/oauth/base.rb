module Oauth
  # JSON endpoints of the OAuth server: no cookies, no CSRF, never cached.
  class Base < ActionController::API
    before_action { response.set_header("Cache-Control", "no-store") }

    private

    def issuer = "#{request.base_url}#{request.script_name}"

    # RFC 6749 §5.2 error response.
    def oauth_error(error, description = nil, status: :bad_request)
      render json: { error: error, error_description: description }.compact, status: status
    end
  end
end
