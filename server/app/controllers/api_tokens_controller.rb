# Personal API tokens (for Claude Code, scripts) and revoking OAuth apps.
class ApiTokensController < ApplicationController
  EXPIRY = { "30" => 30.days, "90" => 90.days, "365" => 365.days, "never" => nil }.freeze

  def create
    name = params[:name].to_s.strip.presence || "API token"
    ttl = EXPIRY.fetch(params[:expires].to_s, 90.days)
    @token = ApiToken.issue!(kind: "personal", user: current_user, name: name.truncate(100), expires_at: ttl&.from_now)
    @mcp_url = "#{request.base_url}#{request.script_name}/mcp"
    render :created, status: :created
  end

  def destroy
    current_user.api_tokens.personal.find(params[:id]).destroy!
    redirect_to account_path, notice: "Token revoked."
  end

  # Disconnects an OAuth app: all of this user's tokens for it stop working.
  def revoke_client
    client = OauthClient.find(params[:client_id])
    current_user.api_tokens.where(oauth_client: client).delete_all
    redirect_to account_path, notice: "Disconnected #{client.name}."
  end
end
