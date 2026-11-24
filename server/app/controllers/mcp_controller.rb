# MCP Streamable HTTP endpoint (POST /mcp). Callers authenticate with a
# bearer token: an OAuth access token (claude.ai and other clients that sign
# in through /oauth/authorize) or a personal token from the account page.
# Without one, the 401 points clients at the OAuth discovery document.
class McpController < ActionController::API
  MAX_BODY = 1.megabyte

  before_action :reject_foreign_origin
  before_action :authenticate_token

  def create
    body = request.raw_post.to_s
    return render_error(nil, -32600, "request too large", :content_too_large) if body.bytesize > MAX_BODY

    message = JSON.parse(body)
    response = McpServer.new.handle(message)
    response ? render(json: response) : head(:accepted)
  rescue JSON::ParserError
    render_error(nil, -32700, "parse error", :bad_request)
  end

  # Stateless server: no SSE stream to open and no session to end.
  def unsupported
    response.set_header("Allow", "POST")
    head :method_not_allowed
  end

  private

  def base_url = "#{request.base_url}#{request.script_name}"

  def authenticate_token
    @token = ApiToken.authenticate(request.authorization.to_s[/\ABearer (.+)\z/, 1])
    return if @token

    response.set_header("WWW-Authenticate",
                        %(Bearer realm="RubyAPM", resource_metadata="#{base_url}/.well-known/oauth-protected-resource", scope="mcp"))
    render json: { error: "unauthorized", error_description: "Sign in with OAuth or send a RubyAPM API token" }, status: :unauthorized
  end

  # DNS-rebinding guard from the MCP spec: browsers send Origin, and only
  # this server's own origin may call it from a page.
  def reject_foreign_origin
    origin = request.headers["Origin"].presence
    head :forbidden if origin && origin != request.base_url
  end

  def render_error(id, code, message, status)
    render json: { jsonrpc: "2.0", id: id, error: { code: code, message: message } }, status: status
  end
end
