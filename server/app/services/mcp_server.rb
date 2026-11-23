# Model Context Protocol over JSON-RPC 2.0, stateless (no sessions, no
# server-initiated messages): exactly what the Streamable HTTP transport
# needs when every response is a plain JSON body. McpController does HTTP;
# this does protocol; McpTools does the work.
class McpServer
  PROTOCOL_VERSIONS = %w[2025-11-25 2025-06-18 2025-03-26 2024-11-05].freeze

  INSTRUCTIONS = <<~TEXT.freeze
    RubyAPM monitors Rails apps: per-minute rollups of transactions (web requests and jobs), the time
    each spends per layer (Ruby, views, ActiveRecord, database, GraphQL, external APIs, cache), SQL
    statements, slow queries with EXPLAIN plans, errors, external services, deployments and alert incidents.
    Start with apm_list_apps, then pass the app's name or id to the other tools. Times are milliseconds,
    rpm is calls per minute, ranges are 30m, 1h, 3h, 6h, 12h, 24h, 3d or 7d (default 1h).
  TEXT

  class RpcError < StandardError
    attr_reader :code

    def initialize(code, message)
      @code = code
      super(message)
    end
  end

  # Returns the response document (Hash or Array), or nil when the message
  # was only notifications and the transport should answer 202.
  def handle(message)
    if message.is_a?(Array)
      return error_response(nil, -32600, "empty batch") if message.empty?
      responses = message.filter_map { |m| handle_one(m) }
      responses.presence
    else
      handle_one(message)
    end
  end

  private

  def handle_one(msg)
    return error_response(nil, -32600, "invalid request") unless msg.is_a?(Hash) && msg["jsonrpc"] == "2.0" && msg["method"].is_a?(String)

    notification = !msg.key?("id")
    result = dispatch(msg["method"], msg["params"].is_a?(Hash) ? msg["params"] : {})
    notification ? nil : { jsonrpc: "2.0", id: msg["id"], result: result }
  rescue RpcError => e
    notification ? nil : error_response(msg["id"], e.code, e.message)
  end

  def dispatch(method, params)
    case method
    when "initialize" then initialize_result(params)
    when "ping" then {}
    when "tools/list" then { tools: McpTools.definitions }
    when "tools/call" then call_tool(params)
    when %r{\Anotifications/} then nil
    else raise RpcError.new(-32601, "method not found: #{method}")
    end
  end

  def initialize_result(params)
    requested = params["protocolVersion"]
    {
      protocolVersion: PROTOCOL_VERSIONS.include?(requested) ? requested : PROTOCOL_VERSIONS.first,
      capabilities: { tools: { listChanged: false } },
      serverInfo: { name: "rubyapm", title: "RubyAPM", version: RubyAPM::VERSION },
      instructions: INSTRUCTIONS
    }
  end

  def call_tool(params)
    name = params["name"]
    raise RpcError.new(-32602, "unknown tool: #{name}") unless McpTools.tool?(name)

    args = params["arguments"].is_a?(Hash) ? params["arguments"] : {}
    data = McpTools.new(args).call(name)
    { content: [{ type: "text", text: JSON.pretty_generate(data) }], isError: false }
  rescue McpTools::ToolError, ActiveRecord::RecordNotFound => e
    # Tool failures go back to the model as results it can read and correct.
    { content: [{ type: "text", text: e.message }], isError: true }
  end

  def error_response(id, code, message)
    { jsonrpc: "2.0", id: id, error: { code: code, message: message } }
  end
end
