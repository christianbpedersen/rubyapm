module Oauth
  # Token endpoint: trades an authorization code (with its PKCE verifier) or
  # a refresh token for a one-hour access token plus a new refresh token.
  # Refresh tokens rotate: each one works once.
  class TokensController < Base
    rate_limit to: 60, within: 1.minute, with: -> { oauth_error("too_many_requests", status: :too_many_requests) }

    def create
      client = OauthClient.find_by(client_id: params[:client_id].to_s)
      return oauth_error("invalid_client", "unknown client_id", status: :unauthorized) unless client

      case params[:grant_type]
      when "authorization_code"
        grant = OauthCode.redeem(params[:code].to_s, client: client, redirect_uri: params[:redirect_uri].to_s, verifier: params[:code_verifier])
        return oauth_error("invalid_grant", "code is invalid, expired, used, or does not match") unless grant
        issue(grant.user, client)
      when "refresh_token"
        old = ApiToken.live.find_by(kind: "refresh", oauth_client: client, token_digest: ApiToken.digest(params[:refresh_token]))
        return oauth_error("invalid_grant", "refresh token is invalid or expired") unless old
        ApiToken.transaction do
          old.destroy!
          issue(old.user, client)
        end
      else
        oauth_error("unsupported_grant_type")
      end
    end

    # RFC 7009: always 200, whether or not the token existed.
    def revoke
      token = ApiToken.find_by(token_digest: ApiToken.digest(params[:token]), kind: %w[access refresh])
      token&.destroy
      head :ok
    end

    private

    def issue(user, client)
      ApiToken.where(user: user, oauth_client: client, kind: "access").where(expires_at: ...Time.current).delete_all
      access = ApiToken.issue!(kind: "access", user: user, oauth_client: client, expires_at: ApiToken::ACCESS_TTL.from_now)
      refresh = ApiToken.issue!(kind: "refresh", user: user, oauth_client: client, expires_at: ApiToken::REFRESH_TTL.from_now)
      render json: { access_token: access.token, token_type: "Bearer", expires_in: ApiToken::ACCESS_TTL.to_i,
                     refresh_token: refresh.token, scope: "mcp" }
    end
  end
end
