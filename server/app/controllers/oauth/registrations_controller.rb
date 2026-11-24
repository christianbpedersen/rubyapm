module Oauth
  # Dynamic client registration (RFC 7591). Registering grants nothing by
  # itself: a signed-in user still has to approve the client.
  class RegistrationsController < Base
    rate_limit to: 20, within: 1.hour, with: -> { oauth_error("too_many_requests", status: :too_many_requests) }

    def create
      body = request.request_parameters.presence || (JSON.parse(request.raw_post) rescue {})
      uris = Array(body["redirect_uris"]).map(&:to_s)
      client = OauthClient.new(name: body["client_name"].to_s.strip.presence || "MCP client", redirect_uris: uris)
      return oauth_error("invalid_redirect_uri", client.errors.full_messages.to_sentence) unless client.save

      render status: :created, json: {
        client_id: client.client_id, client_id_issued_at: client.created_at.to_i, client_name: client.name,
        redirect_uris: client.redirect_uris, grant_types: %w[authorization_code refresh_token],
        response_types: ["code"], token_endpoint_auth_method: "none", scope: "mcp"
      }
    end
  end
end
