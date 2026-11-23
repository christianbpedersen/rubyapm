require "test_helper"

# The MCP endpoint end to end: protocol handshake, every tool against real
# ingested data, and the guard that keeps it off the public proxy.
class McpTest < ActionDispatch::IntegrationTest
  include AgentHelpers

  setup do
    RubyAPM.reset!
    RubyAPM.config.app_name = "Shop"
    RubyAPM.config.trace_threshold = 0
    RubyAPM.config.slow_query_threshold = 50
    RubyAPM.config.revision = "abc1234"
    @shop = App.create!(name: "Shop", api_key: "nf_test")
  end

  def rpc(method, params = {}, id: 1, headers: {})
    post "/mcp", params: { jsonrpc: "2.0", id: id, method: method, params: params }.to_json,
                 headers: { "Content-Type" => "application/json", "Accept" => "application/json, text/event-stream" }.merge(headers)
    response.body.present? ? JSON.parse(response.body) : nil
  end

  def tool(name, args = {})
    result = rpc("tools/call", { name: name, arguments: args })
    assert_response :success
    content = result.dig("result", "content", 0, "text")
    [result.dig("result", "isError"), result["result"]["isError"] ? content : JSON.parse(content)]
  end

  test "handshake and tool listing" do
    init = rpc("initialize", { protocolVersion: "2025-06-18", capabilities: {}, clientInfo: { name: "t", version: "1" } })
    assert_equal "2025-06-18", init.dig("result", "protocolVersion")
    assert_equal "rubyapm", init.dig("result", "serverInfo", "name")
    assert init.dig("result", "capabilities", "tools")

    post "/mcp", params: { jsonrpc: "2.0", method: "notifications/initialized" }.to_json, headers: { "Content-Type" => "application/json" }
    assert_response :accepted
    assert_empty response.body

    tools = rpc("tools/list")["result"]["tools"]
    assert_equal McpTools::TOOLS.keys.sort, tools.map { |t| t["name"] }.sort
    assert tools.all? { |t| t["inputSchema"]["type"] == "object" && t["description"].present? }

    assert_equal(-32601, rpc("nope")["error"]["code"])
    assert_equal(-32602, rpc("tools/call", { name: "apm_nope" })["error"]["code"])
    post "/mcp", params: "{not json", headers: { "Content-Type" => "application/json" }
    assert_equal(-32700, JSON.parse(response.body)["error"]["code"])
    get "/mcp"
    assert_response :method_not_allowed
  end

  test "refuses proxied and browser requests" do
    rpc("tools/list", {}, headers: { "X-Forwarded-For" => "203.0.113.9" })
    assert_response :forbidden
    rpc("tools/list", {}, headers: { "CF-Connecting-IP" => "203.0.113.9" })
    assert_response :forbidden
    rpc("tools/list", {}, headers: { "Origin" => "https://evil.example" })
    assert_response :forbidden
  end

  test "every tool answers from ingested data" do
    20.times do |i|
      fake_request("OrdersController#index", duration_ms: 100 + i,
                   sql: [["SELECT * FROM orders WHERE id = #{i}", 2, 12], ["SELECT * FROM orders WHERE status = 'open'", 80, 1]],
                   http: "api.stripe.com", custom: "Custom/PricingService#quote")
    end
    fake_request("OrdersController#show", duration_ms: 20, error: ArgumentError.new("bad id 7"))
    flush!
    # Rollups for the current minute only count once the bin has closed.
    travel 3.minutes

    error, apps = tool("apm_list_apps")
    refute error
    assert_equal ["Shop"], apps.map { |a| a["name"] }
    assert_match %r{/apps/#{@shop.id}-shop\z}, apps.first["url"]

    _, overview = tool("apm_app_overview", app: "shop")
    assert_equal 21, overview["web"]["requests"]
    assert_equal "OrdersController#index", overview["top_transactions"].first["name"]
    assert overview["web"]["layers_ms_per_request"].key?("database")

    _, series = tool("apm_timeseries", app: @shop.id.to_s, transaction: "OrdersController#index")
    assert_equal 20, series["points"].sum { |p| p["rpm"].to_f * (series["step_seconds"] / 60.0) }.round

    _, txs = tool("apm_transactions", app: "Shop", sort: "errors", limit: 1)
    assert_equal ["OrdersController#show"], txs["transactions"].map { |t| t["name"] }

    _, detail = tool("apm_transaction_detail", app: "Shop", name: "OrdersController#index")
    assert_equal 20, detail["summary"]["requests"]
    assert detail["sql"].any? { |s| s["n_plus_one"] }
    assert detail["segments"].any? { |s| s["name"] == "External/api.stripe.com/GET" }
    trace_id = detail["slowest_traces"].first["trace_id"]

    _, trace = tool("apm_trace", app: "Shop", trace_id: trace_id, max_segments: 10)
    assert_equal "OrdersController#index", trace["transaction"]
    assert_operator trace["segments"].size, :<=, 10
    assert trace["note"].present?

    _, sql = tool("apm_sql", app: "Shop", table: "orders", sort: "max")
    assert_equal "SELECT * FROM orders WHERE status = ?", sql["statements"].first["sql"]

    _, slow = tool("apm_slow_queries", app: "Shop")
    key = slow["statements"].first["key"]
    assert slow["statements"].first["explain_captured"]

    _, st = tool("apm_sql_statement", app: "Shop", key: key)
    assert_equal "Sequential scan on orders", st["explain"]["findings"].first["title"]
    assert_equal "OrdersController#index", st["callers"].first["transaction"]
    assert st["slow_samples"].any?

    _, errors = tool("apm_errors", app: "Shop")
    assert_equal "ArgumentError", errors["errors"].first["error_class"]
    _, err = tool("apm_errors", app: "Shop", fingerprint: errors["errors"].first["fingerprint"])
    assert_equal [{ "type" => "web", "transaction" => "OrdersController#show", "count" => 1 }], err["transactions"]

    _, ext = tool("apm_external_services", app: "Shop")
    assert_equal "api.stripe.com", ext["hosts"].first["host"]

    _, deps = tool("apm_deployments", app: "Shop")
    assert_equal "abc1234", deps["deployments"].first["revision"]
    _, cmp = tool("apm_deployments", app: "Shop", deployment: "abc")
    assert_equal "abc1234", cmp["deployment"]["revision"]
    assert cmp.key?("transaction_changes")

    _, inc = tool("apm_incidents", app: "Shop")
    assert_equal @shop.alert_policies.count, inc["policies"].size
    assert inc["policies"].first["condition"].present?

    error, message = tool("apm_app_overview", app: "nothing-like-it")
    assert error
    assert_match "Apps: Shop", message
    error, message = tool("apm_app_overview", app: "Shop", range: "2w")
    assert error
    assert_match "range must be one of", message
  end
end
