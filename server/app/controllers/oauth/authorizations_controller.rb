module Oauth
  # The consent step: a signed-in user approves (or denies) an MCP client's
  # request for read access, and is sent back to the client with a code.
  class AuthorizationsController < ApplicationController
    layout "auth"
    before_action :load_request

    def new; end

    def create
      return redirect_back_to_client(error: "access_denied") unless params[:decision] == "approve"

      code = OauthCode.issue!(user: current_user, oauth_client: @client, redirect_uri: @redirect_uri,
                              code_challenge: @challenge, resource: params[:resource].presence)
      redirect_back_to_client(code: code.code)
    end

    private

    # Problems with the client or its redirect URI are shown here, never
    # redirected (RFC 6749 §4.1.2.1); the rest go back to the client.
    def load_request
      @client = OauthClient.find_by(client_id: params[:client_id].to_s)
      @redirect_uri = params[:redirect_uri].to_s
      @redirect_uri = @client.redirect_uris.first if @client && @redirect_uri.empty? && @client.redirect_uris.one?
      unless @client&.redirect_uri?(@redirect_uri)
        return render :invalid, status: :bad_request, locals: { reason: @client ? "The redirect URI isn't registered for this app." : "Unknown app (client_id)." }
      end

      @challenge = params[:code_challenge].to_s
      if params[:response_type] != "code"
        redirect_back_to_client(error: "unsupported_response_type")
      elsif params[:code_challenge_method] != "S256" || !@challenge.match?(/\A[A-Za-z0-9_-]{43}\z/)
        redirect_back_to_client(error: "invalid_request", error_description: "PKCE with S256 is required")
      end
    end

    def redirect_back_to_client(**query)
      uri = URI.parse(@redirect_uri)
      params_out = URI.decode_www_form(uri.query.to_s) + query.merge(state: params[:state].presence, iss: issuer).compact.to_a
      uri.query = URI.encode_www_form(params_out)
      redirect_to uri.to_s, allow_other_host: true
    end

    def issuer = "#{request.base_url}#{request.script_name}"
  end
end
