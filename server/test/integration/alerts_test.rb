require "test_helper"
require "socket"

class AlertsTest < ActionDispatch::IntegrationTest
  setup { sign_in }

  # Minimal HTTP server that records webhook bodies.
  def with_webhook_receiver
    server = TCPServer.new("127.0.0.1", 0)
    bodies = Queue.new
    thread = Thread.new do
      loop do
        client = server.accept
        headers = {}
        while (line = client.gets) && line != "\r\n"
          k, v = line.split(":", 2)
          headers[k.downcase] = v.to_s.strip if v
        end
        bodies << JSON.parse(client.read(headers["content-length"].to_i))
        client.write "HTTP/1.1 200 OK\r\nContent-Length: 2\r\nConnection: close\r\n\r\nok"
        client.close
      end
    end
    yield "http://127.0.0.1:#{server.addr[1]}/hook", bodies
  ensure
    thread&.kill
    server&.close
  end

  def minute_rows(app, now, minutes, duration:, errors: 0)
    last = Time.at(((now.to_i - 15) / 60 - 1) * 60).utc
    minutes.times do |i|
      ts = last - i.minutes
      hist = Array.new(56, 0)
      hist[Histogram.index(duration)] = 20
      attrs = { app_id: app.id, ts: ts, tx_type: "web", count: 20, total: duration * 20, min: duration, max: duration,
                errors_count: errors, apdex_s: duration <= 500 ? 20 : 0, apdex_f: duration > 2000 ? 20 : 0,
                apdex_t: duration.between?(501, 2000) ? 20 : 0, hist: hist }
      AppRollup.upsert(attrs, unique_by: %i[app_id ts tx_type])
      TxRollup.upsert(attrs.merge(name: "OrdersController#create"), unique_by: %i[app_id ts tx_type name])
    end
  end

  Histogram = Struct.new(:x) do
    def self.index(ms) = ms <= 1 ? 0 : [(Math.log(ms) / Math.log(1.25)).ceil, 55].min
  end

  test "opens, updates and resolves an incident and notifies the webhook" do
    app = App.create!(name: "AlertApp", api_key: "nf_alert")
    assert_equal 3, app.alert_policies.count, "default policies"
    with_webhook_receiver do |url, bodies|
      policy = app.alert_policies.create!(name: "Checkout slow", metric: "p95", tx_name: "OrdersController#create",
                                          comparison: "above", threshold: 1000, window_minutes: 3, min_samples: 10,
                                          webhook_url: url)
      now = Time.current
      minute_rows(app, now, 3, duration: 3000)
      AlertEvaluator.new(policy, now: now).evaluate

      incident = policy.reload.open_incident
      assert incident, "incident opened"
      assert_operator incident.opened_value, :>, 1000
      opened = bodies.pop
      assert_equal "opened", opened["event"]
      assert_includes opened["text"], "Checkout slow"
      assert_includes opened["url"], "incident=#{incident.id}"

      # Still bad: no second notification, the same incident stays open.
      AlertEvaluator.new(policy, now: now + 30).evaluate
      assert_equal 1, policy.incidents.count
      assert bodies.empty?

      later = now + 10.minutes
      minute_rows(app, later, 3, duration: 100)
      AlertEvaluator.new(policy, now: later).evaluate
      assert_nil policy.reload.open_incident
      resolved = bodies.pop
      assert_equal "resolved", resolved["event"]
      assert_nil incident.reload.notify_error
    end
  end

  test "alert links keep the path prefix of the base URL" do
    app = App.create!(name: "Prefixed", api_key: "nf_prefixed")
    policy = app.alert_policies.first
    incident = Incident.create!(app: app, alert_policy: policy, opened_at: Time.current, threshold: 1, opened_value: 2)
    ENV["RUBY_APM_BASE_URL"] = "https://apm.example.com/apm"
    assert_equal "https://apm.example.com/apm/apps/#{app.to_param}/alerts?incident=#{incident.id}",
                 Notifier.new(incident, :opened).url
  ensure
    ENV.delete("RUBY_APM_BASE_URL")
  end

  test "too few samples do not trigger, apdex below and error rate above" do
    app = App.create!(name: "Quiet", api_key: "nf_quiet")
    now = Time.current
    minute_rows(app, now, 5, duration: 3000, errors: 5)
    apdex, errors, p95 = app.alert_policies.order(:name).to_a.values_at(0, 1, 2)
    [apdex, errors, p95].each { |p| AlertEvaluator.new(p, now: now).evaluate }
    assert apdex.reload.open_incident, "apdex 0 < 0.85"
    assert errors.reload.open_incident, "25% errors > 5%"
    assert p95.reload.open_incident

    p95.update!(min_samples: 1_000)
    p95.open_incident.update!(closed_at: now)
    AlertEvaluator.new(p95, now: now + 1).evaluate
    assert_nil p95.reload.open_incident, "below min_samples"
  end

  test "regenerate key and delete app with its data" do
    app = App.create!(name: "Doomed", api_key: "nf_doomed")
    TxRollup.create!(app_id: app.id, ts: Time.current, tx_type: "web", name: "A#b", count: 1, total: 1, hist: [])
    post "/apps/#{app.id}/regenerate_key"
    refute_equal "nf_doomed", app.reload.api_key
    delete "/apps/#{app.id}", params: { confirm_name: "wrong" }
    assert App.exists?(app.id)
    delete "/apps/#{app.id}", params: { confirm_name: "Doomed" }
    assert_redirected_to "/apps"
    refute App.exists?(app.id)
    refute TxRollup.exists?(app_id: app.id)
    refute AlertPolicy.exists?(app_id: app.id)
  end

  test "alerts pages render and policies can be created" do
    app = App.create!(name: "UI", api_key: "nf_ui")
    get "/apps/#{app.id}/alerts"
    assert_response :success
    get "/apps/#{app.id}/alerts/new?tx_name=OrdersController%23create"
    assert_response :success
    post "/apps/#{app.id}/alerts", params: { alert_policy: { name: "Payments slow", metric: "external_avg", target: "payments.localhost",
                                                             comparison: "above", threshold: 800, window_minutes: 2, tx_type: "web",
                                                             min_samples: 5, webhook_url: "ftp://nope" } }
    assert_response :unprocessable_entity
    post "/apps/#{app.id}/alerts", params: { alert_policy: { name: "Payments slow", metric: "external_avg", target: "payments.localhost",
                                                             comparison: "above", threshold: 800, window_minutes: 2, tx_type: "web", min_samples: 5 } }
    assert_redirected_to "/apps/#{app.to_param}/alerts"
    policy = app.alert_policies.find_by!(name: "Payments slow")
    get "/apps/#{app.id}/alerts/#{policy.id}/edit"
    assert_response :success
    Incident.create!(app: app, alert_policy: policy, opened_at: 5.minutes.ago, threshold: 800, opened_value: 1200, peak_value: 1500)
    get "/apps/#{app.id}/alerts"
    assert_includes response.body, "payments.localhost"
    get "/apps/#{app.id}"
    assert_includes response.body, "Payments slow"
  end
end
