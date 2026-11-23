# MCP Streamable HTTP endpoint (POST /mcp), for the chirpbin MCP gateway.
# The gateway calls the container directly on the internal Docker network;
# requests that came through a reverse proxy or from a browser are refused,
# so the dashboard's public URL never exposes it (Caddy also blocks /apm/mcp).
class McpController < ActionController::API
  MAX_BODY = 1.megabyte

  before_action :require_direct_request

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

  FORWARDED_HEADERS = %w[X-Forwarded-For X-Forwarded-Host Forwarded CF-Connecting-IP X-Real-IP].freeze

  def require_direct_request
    proxied = FORWARDED_HEADERS.any? { |h| request.headers[h].present? }
    # Browsers always send Origin on cross-site POSTs; MCP clients don't.
    head :forbidden if proxied || request.headers["Origin"].present?
  end

  def render_error(id, code, message, status)
    render json: { jsonrpc: "2.0", id: id, error: { code: code, message: message } }, status: status
  end
end
