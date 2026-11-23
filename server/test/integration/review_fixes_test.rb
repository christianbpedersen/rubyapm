require "test_helper"

# Regression tests for issues found in code review.
class ReviewFixesTest < ActionDispatch::IntegrationTest
  setup do
    @nf = App.create!(name: "Fixes", api_key: "nf_fixes")
    Rails.configuration.x.auto_register_apps = false
  end

  teardown { Rails.configuration.x.auto_register_apps = true }

  def payload(bucket_id: SecureRandom.uuid, ts: 2.minutes.ago.to_i / 60 * 60)
    { "v" => 1, "app" => "Fixes", "host" => "h", "pid" => 1, "sent_at" => Time.now.to_f,
      "buckets" => [{ "id" => bucket_id, "ts" => ts,
                      "transactions" => [{ "type" => "web", "name" => "A#b", "count" => 3, "total" => 30, "min" => 5,
                                           "max" => 15, "sumsq" => 1, "errors" => 0, "apdex" => [3, 0, 0], "hist" => { "10" => 3 },
                                           "breakdown" => { "controller" => 30 }, "segments" => [] }],
                      "sql" => [], "errors" => [] }] }
  end

  def post_doc(doc, key: "nf_fixes", gzip: false)
    body = doc.to_json
    headers = { "Content-Type" => "application/json", "Authorization" => "Bearer #{key}" }
    if gzip
      body = Zlib.gzip(body)
      headers["Content-Encoding"] = "gzip"
    end
    post "/api/v1/ingest", params: body, headers: headers
  end

  test "a retried bucket is not counted twice" do
    doc = payload
    post_doc(doc)
    assert_response :accepted
    post_doc(doc)
    assert_response :accepted
    assert_equal 3, TxRollup.where(app_id: @nf.id).sum(:count)
    assert_equal 3, AppRollup.where(app_id: @nf.id).sum(:count)
    post_doc(payload) # a new bucket for the same minute still adds up
    assert_equal 6, TxRollup.where(app_id: @nf.id).sum(:count)
  end

  test "unknown keys are rejected before decompressing, bombs are refused" do
    bomb = Zlib.gzip("\0" * 120.megabytes)
    post "/api/v1/ingest", params: bomb, headers: { "Content-Type" => "application/msgpack", "Content-Encoding" => "gzip", "Authorization" => "Bearer nope" }
    assert_response :unauthorized
    post "/api/v1/ingest", params: bomb, headers: { "Content-Type" => "application/msgpack", "Content-Encoding" => "gzip", "Authorization" => "Bearer nf_fixes" }
    assert_response :payload_too_large
  end

  test "histogram sums do not overflow 32 bits" do
    big = Array.new(56, 0).tap { |h| h[10] = 2_000_000_000 }
    2.times { |i| AppRollup.create!(app_id: @nf.id, ts: (i + 2).minutes.ago.beginning_of_minute, tx_type: "web", count: 1, total: 1, hist: big) }
    m = Metrics.new(@nf, range: "1h")
    assert_equal 4_000_000_000, m.histogram(m.app_scope)[10]
  end

  test "custom ranges are clamped" do
    m = Metrics.new(@nf, from: 0, to: 6_000_000_000_000)
    assert_operator m.to, :<=, 2.hours.from_now
    assert_operator m.to - m.from, :<=, Metrics::MAX_SPAN + m.step # plus bin alignment
    assert_operator m.bins.size, :<=, 200
  end

  test "windows reaching compacted data use hour bins" do
    m = Metrics.new(@nf, from: 3.days.ago.to_i, to: (3.days.ago + 30.minutes).to_i)
    assert_equal 3600, m.step
  end

  test "deploy comparison sides never share the deploy minute" do
    at = Time.current.utc.change(sec: 30) - 20.minutes
    dep = Deployment.create!(app_id: @nf.id, revision: "r1", deployed_at: at)
    cmp = DeployComparison.new(dep, minutes: 10)
    assert_equal at.beginning_of_minute, cmp.before.to
    assert_equal at.beginning_of_minute + 1.minute, cmp.after.from
    assert cmp.before.metrics.exact?
    deploy_minute = AppRollup.create!(app_id: @nf.id, ts: at.beginning_of_minute, tx_type: "web", count: 100, total: 1, hist: [])
    assert_equal 0, cmp.before.metrics.app_scope.where(id: deploy_minute.id).count
    assert_equal 0, DeployComparison.new(dep, minutes: 10).after.metrics.app_scope.where(id: deploy_minute.id).count
  end

  test "old deploys compare whole hours" do
    dep = Deployment.create!(app_id: @nf.id, revision: "old", deployed_at: 3.days.ago.change(min: 20))
    cmp = DeployComparison.new(dep, minutes: 30)
    assert cmp.coarse?
    assert_equal dep.deployed_at.beginning_of_hour, cmp.before.to
    assert_equal dep.deployed_at.beginning_of_hour + 1.hour, cmp.after.from
    get "/apps/#{@nf.id}/deployments/#{dep.id}"
    assert_response :success
  end
end
