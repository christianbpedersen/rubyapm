# The tools RubyAPM exposes over MCP. All are read-only views of the same
# data the dashboard shows, trimmed to what a model needs to reason about
# performance: summaries, rankings and the few samples worth reading.
# Every result carries dashboard links so answers can point at the evidence.
class McpTools
  class ToolError < StandardError; end

  RANGE = { type: "string", enum: Metrics::RANGES.keys, description: "Time window ending now (default 1h)" }.freeze
  FROM = { type: "string", description: "Window start, ISO 8601; use with `to` instead of `range`" }.freeze
  TO = { type: "string", description: "Window end, ISO 8601" }.freeze
  APP = { type: "string", description: "App name or id, from apm_list_apps" }.freeze
  TYPE = { type: "string", enum: %w[web job], description: "web requests or background jobs (default web)" }.freeze
  LIMIT = { type: "integer", minimum: 1, maximum: 100, description: "Maximum rows (default 20)" }.freeze
  WINDOW = { range: RANGE, from: FROM, to: TO }.freeze

  TOOLS = {
    "apm_list_apps" => {
      title: "List apps",
      description: "Monitored apps with their last hour at a glance: throughput, average and p95 response time, " \
                   "error rate, Apdex and open incidents. Call first to get app names.",
      properties: {}
    },
    "apm_app_overview" => {
      title: "App overview",
      description: "Health of one app over a window: web and job summaries, where time goes per layer of the stack, " \
                   "the transactions consuming the most time, open incidents and deployments in the window.",
      properties: { app: APP, **WINDOW },
      required: %w[app]
    },
    "apm_timeseries" => {
      title: "Time series",
      description: "Per-bin throughput, average, p95 and p99 response time, error rate and Apdex for an app or one " \
                   "transaction, with deployment times. Use to see when something changed.",
      properties: { app: APP, type: TYPE, transaction: { type: "string", description: "Transaction name; omit for the whole app" }, **WINDOW },
      required: %w[app]
    },
    "apm_transactions" => {
      title: "Transactions",
      description: "Controller actions, GraphQL operations and jobs ranked by total time consumed (or another sort), " \
                   "with rpm, avg, p95, max, error rate, Apdex and per-layer ms per request.",
      properties: {
        app: APP, type: TYPE, **WINDOW, limit: LIMIT,
        query: { type: "string", description: "Substring filter on the transaction name" },
        sort: { type: "string", enum: %w[total avg p95 rpm errors apdex], description: "Ranking (default total time)" }
      },
      required: %w[app]
    },
    "apm_transaction_detail" => {
      title: "Transaction detail",
      description: "Drill into one transaction: summary and percentiles, per-layer breakdown, the segments " \
                   "(classes, views, external calls) and SQL statements costing it the most, its errors and slowest traces.",
      properties: { app: APP, name: { type: "string", description: "Exact transaction name, e.g. ProductsController#show" }, type: TYPE, **WINDOW },
      required: %w[app name]
    },
    "apm_trace" => {
      title: "Trace",
      description: "One sampled slow request as a call tree: each segment's start, duration and exclusive time, " \
                   "with SQL and external call details. Get trace ids from apm_transaction_detail.",
      properties: { app: APP, trace_id: { type: "integer" }, max_segments: { type: "integer", minimum: 10, maximum: 1000, description: "Default 200" } },
      required: %w[app trace_id]
    },
    "apm_sql" => {
      title: "SQL statements",
      description: "Obfuscated SQL statements ranked by total time, with calls per request, max executions per " \
                   "request (N+1 flag), avg/max time and calling code location. Filter by transaction, table or text.",
      properties: {
        app: APP, **WINDOW, limit: LIMIT, transaction: { type: "string" }, type: TYPE,
        table: { type: "string" }, query: { type: "string", description: "Substring of the SQL" },
        sort: { type: "string", enum: %w[total avg count max max_per_tx], description: "Default total" }
      },
      required: %w[app]
    },
    "apm_slow_queries" => {
      title: "Slow queries",
      description: "Statements that crossed the slow-query threshold, ranked by slow executions, with p50/p95/p99 " \
                   "and whether an EXPLAIN plan was captured. Follow up with apm_sql_statement.",
      properties: { app: APP, **WINDOW, limit: LIMIT },
      required: %w[app]
    },
    "apm_sql_statement" => {
      title: "SQL statement",
      description: "One statement in depth: full obfuscated SQL, percentiles, the latest EXPLAIN plan with plan " \
                   "findings, the transactions that run it, and recent slow samples with backtraces.",
      properties: { app: APP, key: { type: "string", description: "Statement key from apm_sql or apm_slow_queries" }, **WINDOW },
      required: %w[app key]
    },
    "apm_errors" => {
      title: "Errors",
      description: "Error groups in a window by occurrences, with class, message, last transaction and first/last seen. " \
                   "Pass a fingerprint for the backtrace and per-transaction counts.",
      properties: { app: APP, **WINDOW, transaction: { type: "string" }, fingerprint: { type: "string" }, limit: LIMIT },
      required: %w[app]
    },
    "apm_external_services" => {
      title: "External services",
      description: "Outbound HTTP calls grouped by host: calls per minute, avg/max time, share of response time, " \
                   "and the busiest endpoints per host.",
      properties: { app: APP, **WINDOW },
      required: %w[app]
    },
    "apm_deployments" => {
      title: "Deployments",
      description: "Recent deployments (revisions as first reported by the agent). Pass a deployment id or revision " \
                   "for a before/after comparison: summary changes and the transactions that changed most.",
      properties: {
        app: APP, limit: LIMIT,
        deployment: { type: "string", description: "Deployment id or revision prefix to compare" },
        minutes: { type: "integer", minimum: 5, maximum: 240, description: "Comparison window either side (default 30)" }
      },
      required: %w[app]
    },
    "apm_incidents" => {
      title: "Incidents",
      description: "Alert policies with their conditions, and incidents (open first) with when they opened, peak " \
                   "and latest value.",
      properties: { app: APP, limit: LIMIT },
      required: %w[app]
    }
  }.freeze

  def self.definitions
    TOOLS.map do |name, t|
      {
        name: name, title: t[:title], description: t[:description],
        inputSchema: { type: "object", properties: t[:properties], required: t[:required] || [], additionalProperties: false },
        annotations: { readOnlyHint: true, openWorldHint: false }
      }
    end
  end

  def self.tool?(name) = TOOLS.key?(name)

  def initialize(args)
    @args = args
  end

  def call(name)
    send(name.delete_prefix("apm_"))
  end

  # --- tools --------------------------------------------------------------

  def list_apps
    App.order(:name).map do |app|
      m = Metrics.new(app, range: "1h")
      s = m.summary(m.app_scope(type: "web"))
      { id: app.id, name: app.name, last_seen_at: app.last_seen_at&.iso8601, web_last_hour: brief(s),
        open_incidents: app.incidents.where(closed_at: nil).count, url: link(:app_url, app) }
    end
  end

  def app_overview
    m = metrics
    web = m.summary(m.app_scope(type: "web"))
    job = m.summary(m.app_scope(type: "job"))
    {
      app: app.name, window: window(m),
      web: brief(web).merge(layers_ms_per_request: layers(web)),
      jobs: job[:count].positive? ? brief(job).merge(layers_ms_per_request: layers(job)) : nil,
      top_transactions: m.transactions(limit: 10).map { |t| tx_row(t, m) },
      open_incidents: app.incidents.includes(:alert_policy).where(closed_at: nil).map { |i| incident_row(i) },
      deployments: m.deployments.map { |d| deployment_row(d) },
      url: link(:app_url, app, **window_params)
    }
  end

  def timeseries
    m = metrics
    name = @args["transaction"].presence
    scope = name ? m.tx_scope(type: type, name: name) : m.app_scope(type: type)
    series = m.timeseries(scope)
    pct = m.percentile_series(scope)
    {
      app: app.name, transaction: name, type: type, window: window(m), step_seconds: m.step,
      points: m.bins.each_with_index.map do |b, i|
        { t: Time.at(b).utc.iso8601, rpm: series[:throughput][i], avg: series[:avg][i], p95: num(pct[:p95][i]),
          p99: num(pct[:p99][i]), error_pct: series[:error_rate][i], apdex: series[:apdex][i] }
      end,
      deployments: m.deployments.map { |d| deployment_row(d) }
    }
  end

  TX_SORTS = TransactionsController::SORTS

  def transactions
    m = metrics
    sort = TX_SORTS.key?(@args["sort"]) && @args["sort"] != "name" ? @args["sort"] : "total"
    rows = m.transactions(type: type, query: @args["query"]).sort_by(&TX_SORTS[sort]).first(limit)
    { app: app.name, type: type, window: window(m), sort: sort, transactions: rows.map { |t| tx_row(t, m) } }
  end

  def transaction_detail
    m = metrics
    name = required("name")
    scope = m.tx_scope(type: type, name: name)
    s = m.summary(scope)
    raise ToolError, "No #{type} transaction named #{name.inspect} in #{window(m)[:from]}..#{window(m)[:to]}; check apm_transactions." if s[:count].zero?

    {
      app: app.name, name: name, type: type, window: window(m),
      summary: brief(s).merge(layers_ms_per_request: layers(s)),
      segments: m.segments(tx_type: type, tx_name: name, limit: 15).map do |seg|
        { name: seg[:name], category: seg[:category], calls_per_request: num(seg[:calls_per_tx]),
          ms_per_request: num(seg[:ms_per_tx]), share_pct: pct(seg[:share]), avg: num(seg[:avg]), max: num(seg[:max]) }
      end,
      sql: m.sql_statements(tx_type: type, tx_name: name, limit: 10).map { |st| sql_row(st) },
      errors: m.error_groups(tx_type: type, tx_name: name).first(5).map { |e| error_row(e) },
      slowest_traces: m.traces(tx_type: type, tx_name: name, limit: 5).map do |t|
        { trace_id: t.id, at: t.ts.iso8601, duration: num(t.duration), uri: t.uri, status: t.status,
          error: t.error_class, segments: t.segment_count, host: t.hostname }
      end,
      url: link(:app_transaction_url, app, type: type, name: name, **window_params)
    }
  end

  def trace
    t = Trace.find_by!(app_id: app.id, id: required("trace_id"))
    max = (@args["max_segments"] || 200).to_i.clamp(10, 1000)
    rows = []
    flatten(t.tree, 0, rows)
    kept = rows.size > max ? rows.sort_by { |r| -r[:exclusive] }.first(max).sort_by { |r| r[:i] } : rows
    {
      app: app.name, trace_id: t.id, transaction: t.tx_name, type: t.tx_type, at: t.ts.iso8601, duration: num(t.duration),
      uri: t.uri, status: t.status, error: t.error_class, host: t.hostname, attributes: t.attrs.presence,
      layers_ms: t.breakdown.transform_values { |v| num(v) }, segment_count: rows.size,
      note: (rows.size > max ? "Showing the #{max} segments with the most exclusive time of #{rows.size}." : nil),
      segments: kept.map { |r| r.except(:i).transform_values { |v| v.is_a?(Float) ? num(v) : v }.compact },
      url: link(:app_trace_url, app, t)
    }
  end

  SQL_SORTS = DatabaseController::SORTS

  def sql
    m = metrics
    sort = SQL_SORTS.fetch(@args["sort"], :total)
    tx = @args["transaction"].presence
    rows = m.sql_statements(tx_type: tx && type, tx_name: tx, table: @args["table"], query: @args["query"], limit: 200)
            .sort_by { |st| -st[sort].to_f }.first(limit)
    { app: app.name, window: window(m), transaction: tx, statements: rows.map { |st| sql_row(st) } }
  end

  def slow_queries
    m = metrics
    rows = m.slow_statements(limit: limit).map do |st|
      sql_row(st).merge(slow_executions: st[:slow], slow_pct: pct(st[:slow_rate]), p50: num(st[:p50]), p95: num(st[:p95]),
                        p99: num(st[:p99]), samples: st[:samples], explain_captured: st[:explained])
    end
    { app: app.name, window: window(m), threshold_ms_note: "slow = a single execution above the agent's slow_query_threshold (100 ms by default)",
      statements: rows }
  end

  def sql_statement
    m = metrics
    st = SqlStatement.find_by!(app_id: app.id, key: required("key"))
    stats = m.sql_statements(key: st.key, limit: 1).first
    samples = SlowQuery.where(app_id: app.id, key: st.key, ts: m.ts_range).order(duration: :desc).limit(5)
    {
      app: app.name, key: st.key, sql: st.sql, operation: st.operation, table: st.table_name, location: st.location,
      first_seen_at: st.first_seen_at&.iso8601, window: window(m),
      stats: stats && sql_row(stats).except(:sql, :key, :location).merge(m.sql_percentiles(st.key).transform_values { |v| num(v) }),
      explain: st.last_explain.presence && { captured_at: st.last_explain_at&.iso8601, plan: st.last_explain,
                                             findings: plan_findings(st.last_explain) },
      callers: m.sql_callers(st.key).first(10).map do |c|
        { type: c[:type], transaction: c[:name], calls_per_request: num(c[:calls_per_tx]), max_per_request: c[:max_per_tx],
          avg: num(c[:avg]), total: num(c[:total]) }
      end,
      slow_samples: samples.map do |q|
        { at: q.ts.iso8601, duration: num(q.duration), transaction: q.tx_name, uri: q.uri, host: q.hostname,
          location: q.location, backtrace: q.backtrace.first(8), explain: q.explain.presence && q.explain.truncate(4000) }
      end,
      url: link(:app_sql_url, app, st.key, **window_params)
    }
  end

  def errors
    m = metrics
    if (fp = @args["fingerprint"].presence)
      g = ErrorGroup.find_by!(app_id: app.id, fingerprint: fp)
      by_tx = ErrorRollup.where(app_id: app.id, fingerprint: fp, ts: m.ts_range).group(:tx_type, :tx_name)
                         .order(Arel.sql("sum(count) DESC")).limit(20).pluck(:tx_type, :tx_name, Arel.sql("sum(count)"))
      return {
        app: app.name, window: window(m), fingerprint: fp, error_class: g.error_class, message: g.message,
        total_count: g.total_count, first_seen_at: g.first_seen_at&.iso8601, last_seen_at: g.last_seen_at&.iso8601,
        last_uri: g.last_uri, backtrace: g.backtrace.first(30),
        transactions: by_tx.map { |t, n, c| { type: t, transaction: n, count: c.to_i } },
        url: link(:app_error_url, app, fp, **window_params)
      }
    end

    tx = @args["transaction"].presence
    { app: app.name, window: window(m), errors: m.error_groups(tx_type: tx && type, tx_name: tx).first(limit).map { |e| error_row(e) } }
  end

  def external_services
    m = metrics
    {
      app: app.name, window: window(m),
      hosts: m.external_hosts.map do |h|
        { host: h[:host], rpm: num(h[:rpm]), avg: num(h[:avg]), max: num(h[:max]), share_of_response_time_pct: pct(h[:share]),
          endpoints: h[:segments].first(5).map { |s| { name: s[:name], rpm: num(s[:rpm]), avg: num(s[:avg]), max: num(s[:max]) } } }
      end,
      url: link(:app_external_url, app, **window_params)
    }
  end

  def deployments
    scope = Deployment.where(app_id: app.id)
    if (ref = @args["deployment"].presence)
      d = scope.find_by(id: ref.to_i.to_s == ref ? ref.to_i : nil) ||
          scope.where("revision LIKE ?", "#{ActiveRecord::Base.sanitize_sql_like(ref)}%").order(deployed_at: :desc).first or
        raise ToolError, "No deployment #{ref.inspect}; list them with apm_deployments."
      return comparison(d)
    end

    { app: app.name, deployments: scope.order(deployed_at: :desc).limit(limit).map { |dep| deployment_row(dep) } }
  end

  def incidents
    {
      app: app.name,
      policies: app.alert_policies.order(:name).map do |p|
        { id: p.id, name: p.name, enabled: p.enabled, condition: p.condition_text }
      end,
      incidents: app.incidents.includes(:alert_policy).order(Arel.sql("closed_at IS NULL DESC, opened_at DESC")).limit(limit)
                    .map { |i| incident_row(i) }
    }
  end

  private

  def app
    @app ||= begin
      ref = required("app").to_s.strip
      App.find_by(id: ref.to_i.to_s == ref ? ref.to_i : nil) || App.where("lower(name) = ?", ref.downcase).first ||
        App.where("name ILIKE ?", "%#{ActiveRecord::Base.sanitize_sql_like(ref)}%").order(:id).first or
        raise ToolError, "No app #{ref.inspect}. Apps: #{App.order(:name).pluck(:name).join(', ')}"
    end
  end

  def metrics
    @metrics ||= if @args["from"].present? && @args["to"].present?
                   Metrics.new(app, from: parse_time("from"), to: parse_time("to"))
                 else
                   range = @args["range"].presence || "1h"
                   raise ToolError, "range must be one of #{Metrics::RANGES.keys.join(', ')}" unless Metrics::RANGES.key?(range)
                   Metrics.new(app, range: range)
                 end
  end

  def parse_time(key)
    Time.iso8601(@args[key]).to_i
  rescue ArgumentError
    raise ToolError, "#{key} must be an ISO 8601 time, e.g. 2026-11-20T14:00:00Z"
  end

  def required(key)
    value = @args[key]
    raise ToolError, "Missing required argument: #{key}" if value.blank?
    value
  end

  def type = @args["type"] == "job" ? "job" : "web"
  def limit = (@args["limit"] || 20).to_i.clamp(1, 100)

  def window(m)
    { from: m.from.iso8601, to: m.to.iso8601, range: m.range }.compact
  end

  def window_params
    @args["from"].present? && @args["to"].present? ? { from: metrics.from.to_i, to: metrics.to.to_i } : { range: metrics.range }
  end

  def num(v) = v&.to_f&.round(2)
  def pct(v) = v && (v.to_f * 100).round(1)

  def brief(s)
    { requests: s[:count], rpm: num(s[:rpm]), avg: num(s[:avg]), p50: num(s[:p50]), p95: num(s[:p95]), p99: num(s[:p99]),
      max: num(s[:max]), error_pct: pct(s[:error_rate]), apdex: s[:apdex]&.round(3), queue_avg: num(s[:queue_avg]) }
  end

  def layers(s)
    s[:layers].sort_by { |_, v| -v }.to_h { |k, v| [k, num(v)] }.reject { |_, v| v.zero? }
  end

  def tx_row(t, m)
    { type: t[:type], name: t[:name], rpm: num(t[:rpm]), avg: num(t[:avg]), p95: num(t[:p95]), max: num(t[:max]),
      error_pct: pct(t[:error_rate]), apdex: t[:apdex]&.round(3), share_of_time_pct: pct(t[:share]),
      layers_ms_per_request: t[:layers].select { |_, v| v.positive? }.sort_by { |_, v| -v }.first(4).to_h { |k, v| [k, num(v)] } }
  end

  def sql_row(st)
    { key: st[:key], sql: st[:sql].to_s.truncate(600), operation: st[:operation], table: st[:table], location: st[:location],
      rpm: num(st[:rpm]), avg: num(st[:avg]), max: num(st[:max]), total: num(st[:total]),
      calls_per_request: st[:calls_per_tx] && num(st[:calls_per_tx]), max_per_request: st[:max_per_tx],
      ms_per_request: st[:ms_per_tx] && num(st[:ms_per_tx]), n_plus_one: st[:n_plus_one] }.compact
  end

  def error_row(e)
    g = e[:group]
    { fingerprint: g.fingerprint, error_class: g.error_class, message: g.message.to_s.truncate(300), count: e[:count],
      transactions: e[:transactions], last_transaction: g.last_tx_name, last_seen_at: g.last_seen_at&.iso8601 }
  end

  def deployment_row(d)
    { id: d.id, revision: d.revision, deployed_at: d.deployed_at.iso8601, host: d.hostname }
  end

  def incident_row(i)
    p = i.alert_policy
    { id: i.id, policy: p&.name, condition: p&.condition_text, open: i.closed_at.nil?, opened_at: i.opened_at.iso8601,
      closed_at: i.closed_at&.iso8601, threshold: i.threshold, opened_value: num(i.opened_value),
      peak_value: num(i.peak_value), last_value: num(i.last_value) }
  end

  def comparison(d)
    c = DeployComparison.new(d, minutes: (@args["minutes"] || 30).to_i.clamp(5, 240))
    side = ->(s) { { from: s.from.iso8601, to: s.to.iso8601 }.merge(brief(s.summary)) }
    {
      app: app.name, deployment: deployment_row(d), ready: c.ready?, coarse_hourly_data: c.coarse?,
      before: side.(c.before), after: side.(c.after),
      transaction_changes: c.transaction_changes(limit: 15).map do |t|
        { name: t[:name], avg_before: num(t[:before][:avg]), avg_after: num(t[:after][:avg]),
          avg_change_pct: pct(t[:avg_change]), p95_change_pct: pct(t[:p95_change]),
          error_pct_change: pct(t[:error_change]), extra_ms_per_minute: num(t[:impact]) }
      end,
      overlapping_incidents: c.overlapping_incidents.map { |i| incident_row(i) },
      url: link(:app_deployment_url, app, d)
    }
  end

  def plan_findings(plan)
    PlanAnalyzer.new(plan).findings.map { |f| { severity: f.severity, title: f.title, detail: f.detail } }
  rescue StandardError
    nil
  end

  # Trace tree nodes are [name, category, start_ms, duration_ms, children, attrs?].
  def flatten(node, depth, rows)
    return unless node.is_a?(Array) && node.size >= 5

    children = node[4] || []
    exclusive = [node[3].to_f - children.sum { |c| c[3].to_f }, 0].max
    rows << { i: rows.size, depth: depth, name: node[0], category: node[1], start: node[2].to_f, duration: node[3].to_f,
              exclusive: exclusive, detail: node[5].presence }
    children.each { |c| flatten(c, depth + 1, rows) }
  end

  # Dashboard links, rooted at RUBY_APM_BASE_URL (which may carry /apm).
  def link(helper, *args, **params)
    base = URI(Notifier.base_url)
    Rails.application.routes.url_helpers.public_send(
      helper, *args, **params, protocol: base.scheme, host: base.host,
      port: (base.port unless base.port == base.default_port), script_name: base.path.chomp("/")
    )
  end
end
