require "test_helper"
require "ruby_apm"

# Drives real agent payloads through the ingest API and renders every page.
class IngestAndDashboardTest < ActionDispatch::IntegrationTest
  include AgentHelpers
  setup do
    RubyAPM.reset!
    RubyAPM.config.app_name = "Shop"
    RubyAPM.config.trace_threshold = 0
    RubyAPM.config.slow_query_threshold = 50
    RubyAPM.config.revision = "abc1234"
    @shop = App.create!(name: "Shop", api_key: "nf_test")
    sign_in
  end

  test "ingests and renders every page" do
    20.times do |i|
      fake_request("OrdersController#index", duration_ms: 100 + i,
                   sql: [["SELECT * FROM orders WHERE id = #{i}", 2, 12], ["SELECT * FROM orders WHERE status = 'open'", 80, 1]],
                   http: "api.stripe.com", custom: "Custom/PricingService#quote")
    end
    fake_request("GraphQL/query/ProductList", duration_ms: 40)
    fake_request("OrdersController#show", duration_ms: 20, error: ArgumentError.new("bad id 7"))
    result = flush!
    assert_equal 3, result["rows"]["tx_rollups"]
    # A second flush for the same minute is merged, not duplicated.
    fake_request("OrdersController#index", duration_ms: 90)
    flush!

    rollup = TxRollup.find_by(app_id: @shop.id, name: "OrdersController#index")
    assert_equal 21, rollup.count
    assert_equal 21, rollup.hist.sum
    assert_operator rollup.t_database, :>, 0
    assert_operator rollup.t_external, :>, 0
    assert_equal 1, ErrorGroup.count
    # App-level totals stay in step with the per-transaction rollups.
    assert_equal TxRollup.where(app_id: @shop.id).sum(:count), AppRollup.where(app_id: @shop.id).sum(:count)
    assert_equal TxRollup.where(app_id: @shop.id).pluck(:hist).transpose.map(&:sum),
                 AppRollup.where(app_id: @shop.id).pluck(:hist).transpose.map(&:sum)
    assert_equal 1, Deployment.where(app_id: @shop.id).count
    assert RuntimeRollup.where(app_id: @shop.id).exists?, "second flush carries a runtime sample"
    assert SlowQuery.exists?
    assert SqlRollup.where("max_per_tx >= 12").exists?

    m = Metrics.new(@shop, range: "1h")
    s = m.summary(m.tx_scope(type: "web"))
    assert_equal 23, s[:count]
    assert s[:p95] > 90, s.inspect

    key = SqlStatement.find_by(table_name: "orders", sql: "SELECT * FROM orders WHERE status = ?").key
    sample = SlowQuery.first
    trace = Trace.first
    fp = ErrorGroup.first.fingerprint
    pages = [
      "/", "/apps/#{@shop.id}", "/apps/#{@shop.id}?type=job", "/apps/#{@shop.id}/transactions",
      "/apps/#{@shop.id}/transactions?sort=p95&q=Orders", "/apps/#{@shop.id}/transaction?type=web&name=OrdersController%23index",
      "/apps/#{@shop.id}/traces/#{trace.id}", "/apps/#{@shop.id}/database", "/apps/#{@shop.id}/database?table=orders&sort=avg",
      "/apps/#{@shop.id}/sql/#{key}", "/apps/#{@shop.id}/slow-queries", "/apps/#{@shop.id}/slow-queries/#{sample.id}",
      "/apps/#{@shop.id}/code", "/apps/#{@shop.id}/code?cat=all", "/apps/#{@shop.id}/segment?name=Custom/PricingService%23quote",
      "/apps/#{@shop.id}/external", "/apps/#{@shop.id}/external/api.stripe.com", "/apps/#{@shop.id}/graphql",
      "/apps/#{@shop.id}/errors", "/apps/#{@shop.id}/errors/#{fp}", "/apps/#{@shop.id}/hosts", "/apps/#{@shop.id}/settings",
      "/apps/#{@shop.id}/search?q=orders", "/apps/#{@shop.id}/search?q=zzz-nothing", "/apps/#{@shop.id}/search",
      "/apps/#{@shop.id}/deployments", "/apps/#{@shop.id}/deployments/#{Deployment.find_by!(app_id: @shop.id).id}?minutes=15",
      "/apps/#{@shop.id}?range=7d", "/apps/#{@shop.id}?from=#{1.hour.ago.to_i}&to=#{Time.now.to_i}", "/apps/new"
    ]
    pages.each do |path|
      get path, headers: { "User-Agent" => "Mozilla/5.0 (Macintosh) AppleWebKit/605 Chrome/130.0 Safari/605" }
      assert_response :success, "#{path} failed"
    end
    get "/apps/#{@shop.id}/sql/#{key}"
    assert_includes response.body, "Sequential scan on orders"
    assert_operator m.sql_percentiles(key)[:p95], :<=, 80.0
    id_key = SqlStatement.find_by(sql: "SELECT * FROM orders WHERE id = ?").key
    get "/apps/#{@shop.id}/sql/#{id_key}"
    assert_includes response.body, "N+1" # ran 12× per request
    get "/apps/#{@shop.id}/database"
    assert_includes response.body, "12× in one request"
    get "/apps/#{@shop.id}/search?q=orderscontroller%23index"
    assert_redirected_to %r{/transaction\?}
  end

  test "dashboard pages require a signed-in user" do
    reset! # drop the setup's sign-in
    get "/apps/#{@shop.id}"
    assert_redirected_to "/login"
    sign_in
    assert_redirected_to "http://www.example.com/apps/#{@shop.id}"
    get "/apps/#{@shop.id}"
    assert_response :success
  end

  test "rejects unknown keys when auto registration is off" do
    Rails.configuration.x.auto_register_apps = false
    post "/api/v1/ingest", params: { v: 1 }.to_json, headers: { "Content-Type" => "application/json", "Authorization" => "Bearer nope" }
    assert_response :unauthorized
  end
end
