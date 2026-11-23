# Read side: turns minute rollups into the time series, summaries and
# breakdown tables the dashboard renders. Every query is bounded by app and
# time window and grouped into `step`-second bins chosen for ~100 points.
class Metrics
  RANGES = {
    "30m" => 30.minutes, "1h" => 1.hour, "3h" => 3.hours, "6h" => 6.hours,
    "12h" => 12.hours, "24h" => 24.hours, "3d" => 3.days, "7d" => 7.days
  }.freeze
  STEPS = [60, 120, 300, 600, 900, 1800, 3600, 7200, 10_800, 21_600, 43_200, 86_400].freeze
  TARGET_POINTS = 90

  # Layers of the stack, in the order they are stacked in charts. "Ruby" is
  # the controller's own time; custom code and jobs are their own layers.
  LAYERS = [
    { key: "controller", label: "Ruby (controller)", color: "#6366f1" },
    { key: "custom", label: "Custom code", color: "#a855f7" },
    { key: "view", label: "View", color: "#14b8a6" },
    { key: "activerecord", label: "ActiveRecord", color: "#f59e0b" },
    { key: "database", label: "Database", color: "#ef4444" },
    { key: "graphql", label: "GraphQL resolvers", color: "#e879f9" },
    { key: "external", label: "External APIs", color: "#3b82f6" },
    { key: "cache", label: "Cache", color: "#84cc16" },
    { key: "job", label: "Job", color: "#ec4899" },
    { key: "middleware", label: "Middleware", color: "#94a3b8" }
  ].freeze
  LAYER_KEYS = LAYERS.map { |l| l[:key] }.freeze

  attr_reader :app, :from, :to, :step, :range

  MAX_SPAN = 31.days

  # +exact+: use [from, to) as given (minute-aligned), no bin alignment.
  # Deploy comparisons need this so the two sides never share a minute.
  def initialize(app, range: nil, from: nil, to: nil, exact: false)
    @app = app
    @exact = exact
    now = Time.current.utc
    if from.present? && to.present?
      # Clamp arbitrary URLs to something sane: within a month, not in the future.
      @to = Time.at(to.to_i.clamp(0, now.to_i + 3600)).utc
      @from = Time.at(from.to_i).utc.clamp(@to - MAX_SPAN, @to)
      @to = @from + 1.minute if @to <= @from
      @range = nil
    else
      @range = RANGES.key?(range) ? range : "1h"
      @to = now
      @from = @to - RANGES[@range]
    end
    span = @to - @from
    @step = STEPS.find { |s| span / s <= TARGET_POINTS } || STEPS.last
    # Minute rows older than the compaction horizon were folded into hourly
    # rows; finer bins there would show one spike per hour.
    if @from < Compactor.horizon && @step < 3600
      @step = 3600
      @from = @from.beginning_of_hour
      @to = @to.end_of_hour if @to < Compactor.horizon
    end
    # Align window to bins so the first and last points are full buckets.
    @from = Time.at((@from.to_i / @step) * @step).utc unless @exact
    @to_bin = if @range
                # Live windows end at the last bin that has closed and had
                # time to arrive (agents flush every ~10 s); a half-filled
                # current bin would look like a sudden drop.
                ((@to.to_i - INGEST_LAG - @step) / @step) * @step
              else
                ((@to.to_i - (@exact ? 1 : 0)) / @step) * @step
              end
  end

  def exact? = @exact

  # Inclusive for dashboard windows, half-open for exact comparisons.
  def ts_range
    @exact ? (@from...@to) : (@from..@to)
  end

  INGEST_LAG = 15

  def span_minutes
    [(@to - @from) / 60.0, 1.0].max
  end

  def bins
    @bins ||= (@from.to_i..@to_bin).step(@step).to_a
  end

  def bin_expr(column = "ts")
    "(floor(extract(epoch from #{column}) / #{@step}) * #{@step})::bigint"
  end

  # --- scopes -------------------------------------------------------------

  def tx_scope(type: nil, name: nil)
    s = TxRollup.where(app_id: app.id, ts: ts_range)
    s = s.where(tx_type: type) if type.present?
    s = s.where(name: name) if name.present?
    s
  end

  # App-wide totals (all transaction names) for overview charts; same
  # columns as tx_rollups, ~20x fewer rows.
  def app_scope(type: nil)
    s = AppRollup.where(app_id: app.id, ts: ts_range)
    s = s.where(tx_type: type) if type.present?
    s
  end

  def segment_scope(tx_type: nil, tx_name: nil)
    s = SegmentRollup.where(app_id: app.id, ts: ts_range)
    s = s.where(tx_type: tx_type) if tx_type.present?
    s = s.where(tx_name: tx_name) if tx_name.present?
    s
  end

  def sql_scope(tx_type: nil, tx_name: nil)
    s = SqlRollup.where(app_id: app.id, ts: ts_range)
    s = s.where(tx_type: tx_type) if tx_type.present?
    s = s.where(tx_name: tx_name) if tx_name.present?
    s
  end

  # --- transactions -------------------------------------------------------

  LAYER_SUMS = LAYER_KEYS.map { |k| "sum(t_#{k}) AS t_#{k}" }.join(", ")

  def summary(scope)
    row = scope.select("sum(count) AS count, sum(total) AS total, max(max) AS max, sum(errors_count) AS errors_sum, " \
                       "sum(apdex_s) AS s, sum(apdex_t) AS t, sum(apdex_f) AS f, sum(queue_total) AS queue, #{LAYER_SUMS}")
               .take
    count = row&.count.to_i
    hist = histogram(scope)
    total = row&.total.to_f
    {
      count: count,
      rpm: count / span_minutes,
      total: total,
      avg: count.positive? ? total / count : 0.0,
      max: row&.max.to_f,
      errors: row&.errors_sum.to_i,
      error_rate: count.positive? ? row.errors_sum.to_f / count : 0.0,
      apdex: apdex(row&.s, row&.t, row&.f),
      queue_avg: count.positive? ? row.queue.to_f / count : 0.0,
      p50: clamp(self.class.percentile(hist, 0.50), row&.max),
      p95: clamp(self.class.percentile(hist, 0.95), row&.max),
      p99: clamp(self.class.percentile(hist, 0.99), row&.max),
      layers: LAYER_KEYS.to_h { |k| [k, count.positive? ? row.public_send("t_#{k}").to_f / count : 0.0] },
      layer_totals: LAYER_KEYS.to_h { |k| [k, row&.public_send("t_#{k}").to_f] }
    }
  end

  # Throughput, mean latency, error rate, apdex and per-layer mean time per bin.
  def timeseries(scope)
    rows = scope.group(Arel.sql(bin_expr))
                .pluck(Arel.sql("#{bin_expr}, sum(count), sum(total), sum(errors_count), sum(apdex_s), sum(apdex_t), " \
                                "sum(apdex_f), #{LAYER_KEYS.map { |k| "sum(t_#{k})" }.join(', ')}"))
                .index_by(&:first)
    per_min = @step / 60.0
    series = { throughput: [], avg: [], error_rate: [], apdex: [], errors: [], layers: LAYER_KEYS.to_h { |k| [k, []] } }
    bins.each do |b|
      r = rows[b]
      count = r ? r[1].to_i : 0
      series[:throughput] << (count / per_min).round(2)
      series[:avg] << (count.positive? ? (r[2].to_f / count).round(2) : nil)
      series[:errors] << (r ? r[3].to_i : 0)
      series[:error_rate] << (count.positive? ? (r[3].to_f * 100 / count).round(2) : nil)
      series[:apdex] << (count.positive? ? apdex(r[4], r[5], r[6])&.round(3) : nil)
      LAYER_KEYS.each_with_index do |k, i|
        series[:layers][k] << (count.positive? ? (r[7 + i].to_f / count).round(2) : 0)
      end
    end
    series
  end

  # p50/p95/p99 per bin from the merged latency histograms.
  # Histograms are summed in Postgres with the nf_hist_sum aggregate, which
  # is ~50x faster than unnesting them and grouping by bucket.
  def percentile_series(scope)
    rows = scope.group(Arel.sql(bin_expr)).pluck(Arel.sql("#{bin_expr}, nf_hist_sum(hist), max(max)"))
    hists = rows.to_h { |bin, hist, _| [bin.to_i, self.class.hist_array(hist)] }
    maxes = rows.to_h { |bin, _, max| [bin.to_i, max] }
    percentiles_from(hists, maxes)
  end

  def histogram(scope)
    self.class.hist_array(scope.pick(Arel.sql("nf_hist_sum(hist)")))
  end

  # Latency distribution trimmed to the populated range, for a bar chart.
  def histogram_chart(scope)
    hist_chart(histogram(scope))
  end

  def hist_chart(hist)
    first = hist.index(&:positive?)
    return { labels: [], counts: [] } unless first

    last = hist.rindex(&:positive?)
    labels = (first..last).map { |i| self.class.format_ms(self.class.bucket_upper(i)) }
    { labels: labels, counts: hist[first..last] }
  end

  # The transactions table: everything needed to rank by time consumed,
  # slowness, throughput or errors. Percentiles are computed in one pass.
  def transactions(type: nil, query: nil, limit: 500)
    s = tx_scope(type: type)
    s = s.where("name ILIKE ?", "%#{ActiveRecord::Base.sanitize_sql_like(query)}%") if query.present?
    rows = s.group(:tx_type, :name)
            .order(Arel.sql("sum(total) DESC"))
            .limit(limit)
            .pluck(:tx_type, :name, Arel.sql("sum(count), sum(total), max(max), sum(errors_count), sum(apdex_s), sum(apdex_t), sum(apdex_f), " +
                                             LAYER_KEYS.map { |k| "sum(t_#{k})" }.join(", ")))
    grand_total = rows.sum { |r| r[3].to_f }
    p95s = percentiles_by_name(s, rows.map { |r| r[1] })
    rows.map do |r|
      count = r[2].to_i
      {
        type: r[0], name: r[1], count: count, total: r[3].to_f, rpm: count / span_minutes,
        avg: count.positive? ? r[3].to_f / count : 0, max: r[4].to_f, errors: r[5].to_i,
        error_rate: count.positive? ? r[5].to_f / count : 0, apdex: apdex(r[6], r[7], r[8]),
        share: grand_total.positive? ? r[3].to_f / grand_total : 0, p95: p95s[[r[0], r[1]]],
        layers: LAYER_KEYS.each_with_index.to_h { |k, i| [k, count.positive? ? r[9 + i].to_f / count : 0] }
      }
    end
  end

  # --- segments: layers, classes, external services -----------------------

  # Breakdown of a transaction (or the whole app) by segment, with time per
  # request so "calls per request" and "ms per request" are comparable.
  def segments(tx_type: nil, tx_name: nil, categories: nil, query: nil, limit: 200, with_callers: false)
    s = segment_scope(tx_type: tx_type, tx_name: tx_name)
    s = s.where(category: categories) if categories.present?
    s = s.where("name ILIKE ?", "%#{ActiveRecord::Base.sanitize_sql_like(query)}%") if query.present?
    totals = tx_name ? tx_scope(type: tx_type, name: tx_name) : app_scope(type: tx_type)
    tx_count, tx_total = totals.pick(Arel.sql("sum(count), sum(total)"))
    tx_count = tx_count.to_i
    tx_total = tx_total.to_f
    rows = s.group(:name, :category).order(Arel.sql("sum(excl) DESC")).limit(limit)
            .pluck(:name, :category, Arel.sql("sum(count), sum(txns), sum(total), sum(excl), max(max)"))
    callers = tx_name ? Hash.new(1) : (with_callers ? distinct_callers(segment_scope(tx_type: tx_type), :name, rows.map(&:first)) : {})
    rows.map do |name, cat, count, txns, total, excl, max|
      count = count.to_i
      {
        name: name, category: cat, count: count, txns: txns.to_i, total: total.to_f, excl: excl.to_f, max: max.to_f,
        avg: count.positive? ? total.to_f / count : 0, calls_per_tx: tx_count.positive? ? count.to_f / tx_count : 0,
        ms_per_tx: tx_count.positive? ? excl.to_f / tx_count : 0, share: tx_total.positive? ? excl.to_f / tx_total : 0,
        rpm: count / span_minutes, callers: callers[name]
      }
    end
  end

  # How many distinct transactions use each of +values+ (a column of
  # +scope+). Counted only for the rows being shown: DISTINCT over the whole
  # window is the most expensive part of these queries.
  def distinct_callers(scope, column, values)
    return {} if values.empty?
    scope.where(column => values).group(column).distinct.count(:tx_name)
  end

  def segment_summary(name, tx_type: nil, tx_name: nil)
    s = segment_scope(tx_type: tx_type, tx_name: tx_name).where(name: name)
    count, total, excl, max, cat = s.pick(Arel.sql("sum(count), sum(total), sum(excl), max(max), max(category)"))
    count = count.to_i
    { name: name, category: cat, count: count, total: total.to_f, excl: excl.to_f, max: max.to_f,
      avg: count.positive? ? total.to_f / count : 0, rpm: count / span_minutes }
  end

  def segment_timeseries(name, tx_type: nil, tx_name: nil)
    rows = segment_scope(tx_type: tx_type, tx_name: tx_name).where(name: name)
             .group(Arel.sql(bin_expr)).pluck(Arel.sql("#{bin_expr}, sum(count), sum(total), max(max)")).index_by(&:first)
    per_min = @step / 60.0
    out = { calls: [], avg: [], max: [] }
    bins.each do |b|
      r = rows[b]
      c = r ? r[1].to_i : 0
      out[:calls] << (c / per_min).round(2)
      out[:avg] << (c.positive? ? (r[2].to_f / c).round(2) : nil)
      out[:max] << (r ? r[3].to_f.round(2) : nil)
    end
    out
  end

  # Which transactions call a segment, and how much it costs each of them.
  def segment_callers(name)
    segment_scope.where(name: name).group(:tx_type, :tx_name).order(Arel.sql("sum(total) DESC")).limit(100)
                 .pluck(:tx_type, :tx_name, Arel.sql("sum(count), sum(txns), sum(total), max(max)"))
                 .map do |type, tx, count, txns, total, max|
      { type: type, name: tx, count: count.to_i, txns: txns.to_i, total: total.to_f, max: max.to_f,
        avg: count.to_i.positive? ? total.to_f / count.to_i : 0,
        calls_per_tx: txns.to_i.positive? ? count.to_f / txns.to_i : 0 }
    end
  end

  # Time series per segment name (top N), e.g. one line per external host.
  # Use metric: :excl for stacked charts so nested segments are not counted twice.
  def stacked_segments(names, metric: :total, tx_type: nil, tx_name: nil)
    return {} if names.empty?

    rows = segment_scope(tx_type: tx_type, tx_name: tx_name).where(name: names)
             .group(:name, Arel.sql(bin_expr)).pluck(:name, Arel.sql("#{bin_expr}, sum(count), sum(total), sum(excl)"))
    per_min = @step / 60.0
    grouped = rows.group_by(&:first).transform_values { |rs| rs.index_by { |r| r[1] } }
    names.to_h do |n|
      by_bin = grouped[n] || {}
      [n, bins.map do |b|
        r = by_bin[b]
        next 0 unless r
        case metric
        when :calls then (r[2].to_f / per_min).round(2)
        when :avg then r[2].to_i.positive? ? (r[3].to_f / r[2].to_i).round(2) : nil
        when :excl then (r[4].to_f / per_min).round(2) # exclusive ms per minute; safe to stack
        else (r[3].to_f / per_min).round(2) # inclusive ms of wall time per minute
        end
      end]
    end
  end

  # External APIs grouped by host (segment names are External/<host>/<verb>).
  def external_hosts
    segments(categories: ["external"], limit: 500).group_by { |s| s[:name].split("/")[1] }.map do |host, segs|
      count = segs.sum { |s| s[:count] }
      total = segs.sum { |s| s[:total] }
      { host: host, count: count, total: total, avg: count.positive? ? total / count : 0, rpm: count / span_minutes,
        max: segs.map { |s| s[:max] }.max, segments: segs, share: segs.sum { |s| s[:share] } }
    end.sort_by { |h| -h[:total] }
  end

  # --- SQL ----------------------------------------------------------------

  def sql_statements(tx_type: nil, tx_name: nil, table: nil, operation: nil, query: nil, key: nil, limit: 200, with_callers: false)
    s = sql_scope(tx_type: tx_type, tx_name: tx_name)
    s = s.where(key: key) if key
    if table.present? || operation.present? || query.present?
      st = SqlStatement.where(app_id: app.id)
      st = st.where(table_name: table) if table.present?
      st = st.where(operation: operation) if operation.present?
      st = st.where("sql ILIKE ?", "%#{ActiveRecord::Base.sanitize_sql_like(query)}%") if query.present?
      s = s.where(key: st.select(:key))
    end
    tx_count = (tx_name ? tx_scope(type: tx_type, name: tx_name) : app_scope(type: tx_type)).sum(:count).to_i
    # Aggregate by key first; statement text is joined only for the top rows.
    rows = s.group(:key).order(Arel.sql("sum(total) DESC")).limit(limit)
            .pluck(:key, Arel.sql("sum(count), sum(txns), sum(total), max(max), max(max_per_tx), sum(slow_count)"))
    keys = rows.map(&:first)
    statements = SqlStatement.where(app_id: app.id, key: keys).index_by(&:key)
    callers = tx_name ? Hash.new(1) : (with_callers ? distinct_callers(sql_scope(tx_type: tx_type), :key, keys) : {})
    rows.filter_map do |k, count, txns, total, max, max_per_tx, slow|
      st = statements[k] or next
      count = count.to_i
      {
        key: k, sql: st.sql, operation: st.operation, table: st.table_name, location: st.location, count: count, txns: txns.to_i,
        total: total.to_f, max: max.to_f, avg: count.positive? ? total.to_f / count : 0,
        max_per_tx: max_per_tx.to_i, callers: callers[k], rpm: count / span_minutes,
        calls_per_tx: txns.to_i.positive? ? count.to_f / txns.to_i : 0,
        ms_per_tx: tx_count.positive? && tx_name ? total.to_f / tx_count : nil,
        n_plus_one: max_per_tx.to_i >= 10, slow: slow.to_i
      }
    end
  end

  def sql_by_table
    sql_scope.joins("JOIN sql_statements st ON st.app_id = sql_rollups.app_id AND st.key = sql_rollups.key")
             .group("st.table_name", "st.operation").order(Arel.sql("sum(sql_rollups.total) DESC")).limit(100)
             .pluck(Arel.sql("coalesce(st.table_name, '(none)'), st.operation, sum(sql_rollups.count), sum(sql_rollups.total), max(sql_rollups.max)"))
             .map do |table, op, count, total, max|
      { table: table, operation: op, count: count.to_i, total: total.to_f, max: max.to_f,
        avg: count.to_i.positive? ? total.to_f / count.to_i : 0, rpm: count.to_i / span_minutes }
    end
  end

  def sql_timeseries(key)
    rows = sql_scope.where(key: key).group(Arel.sql(bin_expr))
                    .pluck(Arel.sql("#{bin_expr}, sum(count), sum(total), max(max), max(max_per_tx)")).index_by(&:first)
    per_min = @step / 60.0
    out = { calls: [], avg: [], max: [], max_per_tx: [] }
    bins.each do |b|
      r = rows[b]
      c = r ? r[1].to_i : 0
      out[:calls] << (c / per_min).round(2)
      out[:avg] << (c.positive? ? (r[2].to_f / c).round(3) : nil)
      out[:max] << (r ? r[3].to_f.round(2) : nil)
      out[:max_per_tx] << (r ? r[4].to_i : nil)
    end
    out
  end

  def sql_callers(key)
    sql_scope.where(key: key).group(:tx_type, :tx_name).order(Arel.sql("sum(total) DESC")).limit(100)
             .pluck(:tx_type, :tx_name, Arel.sql("sum(count), sum(txns), sum(total), max(max), max(max_per_tx)"))
             .map do |type, name, count, txns, total, max, mpt|
      { type: type, name: name, count: count.to_i, txns: txns.to_i, total: total.to_f, max: max.to_f,
        avg: count.to_i.positive? ? total.to_f / count.to_i : 0, max_per_tx: mpt.to_i,
        calls_per_tx: txns.to_i.positive? ? count.to_f / txns.to_i : 0 }
    end
  end

  def sql_histogram(key)
    self.class.hist_array(sql_scope.where(key: key).pick(Arel.sql("nf_hist_sum(hist)")))
  end

  def sql_percentiles(key)
    h = sql_histogram(key)
    max = sql_scope.where(key: key).maximum(:max)
    { p50: clamp(self.class.percentile(h, 0.5), max), p95: clamp(self.class.percentile(h, 0.95), max),
      p99: clamp(self.class.percentile(h, 0.99), max) }
  end

  def sql_histogram_chart(key)
    hist_chart(sql_histogram(key))
  end

  def sql_percentile_series(key)
    rows = sql_scope.where(key: key).group(Arel.sql(bin_expr)).pluck(Arel.sql("#{bin_expr}, nf_hist_sum(hist), max(max)"))
    percentiles_from(rows.to_h { |b, h, _| [b.to_i, self.class.hist_array(h)] }, rows.to_h { |b, _, m| [b.to_i, m] })
  end

  # Statements ranked for slow-query analysis: per-statement percentiles from
  # their histograms plus how often a single execution crossed the threshold.
  def slow_statements(limit: 100)
    rows = sql_scope.group(:key)
                    .having("sum(slow_count) > 0 OR max(max) >= 50")
                    .order(Arel.sql("sum(slow_count) DESC, max(max) DESC")).limit(limit)
                    .pluck(:key, Arel.sql("sum(count), sum(total), max(max), sum(slow_count)"))
    keys = rows.map(&:first)
    hists = keys.empty? ? {} : sql_scope.where(key: keys).group(:key).pluck(:key, Arel.sql("nf_hist_sum(hist)"))
                                        .to_h { |k, h| [k, self.class.hist_array(h)] }
    samples = SlowQuery.where(app_id: app.id, key: keys, ts: ts_range).group(:key).count
    statements = SqlStatement.where(app_id: app.id, key: keys).index_by(&:key)
    rows.filter_map do |key, count, total, max, slow|
      st = statements[key] or next
      h = hists[key] || Array.new(Ingestor::HIST_SIZE, 0)
      count = count.to_i
      max = max.to_f
      {
        key: key, sql: st.sql, operation: st.operation, table: st.table_name, location: st.location,
        explained: st.last_explain.present?, count: count,
        total: total.to_f, avg: count.positive? ? total.to_f / count : 0, max: max.to_f, slow: slow.to_i,
        slow_rate: count.positive? ? slow.to_f / count : 0, samples: samples[key].to_i,
        p50: clamp(self.class.percentile(h, 0.5), max), p95: clamp(self.class.percentile(h, 0.95), max),
        p99: clamp(self.class.percentile(h, 0.99), max)
      }
    end
  end

  def slow_query_series
    rows = sql_scope.group(Arel.sql(bin_expr)).pluck(Arel.sql("#{bin_expr}, sum(slow_count), sum(count)")).index_by(&:first)
    per_min = @step / 60.0
    { slow: bins.map { |b| ((rows[b]&.[](1)).to_f / per_min).round(2) },
      all: bins.map { |b| ((rows[b]&.[](2)).to_f / per_min).round(2) } }
  end

  # Time series of several transactions side by side.
  # metric: :avg (ms per request), :rpm, or :total (ms of wall time per minute).
  def tx_series_by_name(type, names, metric: :avg)
    return {} if names.empty?

    s = tx_scope(type: type).where(name: names)
    rows = s.group(:name, Arel.sql(bin_expr)).pluck(:name, Arel.sql("#{bin_expr}, sum(count), sum(total)"))
    per_min = @step / 60.0
    grouped = rows.group_by(&:first).transform_values { |rs| rs.index_by { |r| r[1] } }
    names.to_h do |n|
      by_bin = grouped[n] || {}
      [n, bins.map do |b|
        r = by_bin[b]
        case metric
        when :rpm then r ? (r[2].to_f / per_min).round(2) : 0
        when :total then r ? (r[3].to_f / per_min).round(2) : 0
        else r && r[2].to_i.positive? ? (r[3].to_f / r[2].to_i).round(2) : nil
        end
      end]
    end
  end

  # ms spent in each segment per request of a transaction, per bin.
  def segments_per_tx_series(names, tx_type:, tx_name:)
    return {} if names.empty?

    tx_counts = tx_scope(type: tx_type, name: tx_name).group(Arel.sql(bin_expr)).pluck(Arel.sql("#{bin_expr}, sum(count)")).to_h
    rows = segment_scope(tx_type: tx_type, tx_name: tx_name).where(name: names)
             .group(:name, Arel.sql(bin_expr)).pluck(:name, Arel.sql("#{bin_expr}, sum(excl)"))
    grouped = rows.group_by(&:first).transform_values { |rs| rs.to_h { |r| [r[1], r[2].to_f] } }
    names.to_h do |n|
      by_bin = grouped[n] || {}
      [n, bins.map { |b| tx_counts[b].to_i.positive? ? (by_bin[b].to_f / tx_counts[b].to_i).round(2) : 0 }]
    end
  end

  # --- errors -------------------------------------------------------------

  def error_groups(tx_type: nil, tx_name: nil)
    s = ErrorRollup.where(app_id: app.id, ts: ts_range)
    s = s.where(tx_type: tx_type) if tx_type.present?
    s = s.where(tx_name: tx_name) if tx_name.present?
    counts = s.group(:fingerprint).order(Arel.sql("sum(count) DESC")).limit(200).pluck(:fingerprint, Arel.sql("sum(count), count(DISTINCT tx_name)"))
    groups = ErrorGroup.where(app_id: app.id, fingerprint: counts.map(&:first)).index_by(&:fingerprint)
    counts.filter_map do |fp, count, txs|
      g = groups[fp] or next
      { group: g, count: count.to_i, transactions: txs.to_i }
    end
  end

  def error_series(fingerprint: nil, tx_type: nil, tx_name: nil)
    s = ErrorRollup.where(app_id: app.id, ts: ts_range)
    s = s.where(fingerprint: fingerprint) if fingerprint
    s = s.where(tx_type: tx_type) if tx_type.present?
    s = s.where(tx_name: tx_name) if tx_name.present?
    rows = s.group(Arel.sql(bin_expr)).pluck(Arel.sql("#{bin_expr}, sum(count)")).to_h
    bins.map { |b| rows[b].to_i }
  end

  def traces(tx_type: nil, tx_name: nil, limit: 50)
    s = Trace.where(app_id: app.id, ts: ts_range)
    s = s.where(tx_type: tx_type) if tx_type.present?
    s = s.where(tx_name: tx_name) if tx_name.present?
    s.order(duration: :desc).limit(limit).select(:id, :ts, :tx_type, :tx_name, :duration, :uri, :status, :error_class, :segment_count, :hostname, :breakdown)
  end

  # Per process: memory, CPU %, GC time and allocations per minute, DB pool.
  def runtime_series
    rows = RuntimeRollup.where(app_id: app.id, ts: ts_range)
                        .group(:hostname, :pid, Arel.sql(bin_expr))
                        .pluck(:hostname, :pid, Arel.sql("#{bin_expr}, sum(elapsed_ms), sum(cpu_ms), sum(gc_time_ms), sum(allocations), " \
                                                        "max(rss_mb), max(db_pool_busy), max(db_pool_size), max(threads), sum(gc_major)"))
    per_min = @step / 60.0
    rows.group_by { |h, pid, *| "#{h}:#{pid}" }.transform_values do |rs|
      by_bin = rs.index_by { |r| r[2] }
      series = { cpu: [], gc_time: [], allocations: [], rss: [], db_busy: [], db_size: [], threads: [], gc_major: [] }
      bins.each do |b|
        r = by_bin[b]
        elapsed = r ? r[3].to_f : 0
        series[:cpu] << (elapsed.positive? ? (r[4].to_f / elapsed * 100).round(1) : nil)
        series[:gc_time] << (r ? (r[5].to_f / per_min).round(1) : nil)
        series[:allocations] << (r ? (r[6].to_f / per_min).round : nil)
        series[:rss] << r&.[](7)
        series[:db_busy] << r&.[](8)
        series[:db_size] << r&.[](9)
        series[:threads] << r&.[](10)
        series[:gc_major] << (r ? (r[11].to_f / per_min).round(2) : nil)
      end
      series
    end
  end

  def deployments
    @deployments ||= Deployment.where(app_id: app.id, deployed_at: @from..@to).order(:deployed_at).to_a
  end

  # --- helpers ------------------------------------------------------------

  def apdex(s, t, f)
    total = s.to_i + t.to_i + f.to_i
    return nil if total.zero?
    (s.to_i + t.to_i / 2.0) / total
  end

  def labels
    bins
  end

  # Fixed-size histogram from a Postgres integer[] (Array or "{1,2}" text).
  def self.hist_array(value)
    values = value.is_a?(String) ? value.delete("{}").split(",").map(&:to_i) : Array(value).map(&:to_i)
    values.fill(0, values.size...Ingestor::HIST_SIZE).first(Ingestor::HIST_SIZE)
  end

  def self.bucket_upper(i) = 1.25**i
  def self.bucket_lower(i) = i.zero? ? 0.0 : 1.25**(i - 1)

  # Interpolates within the histogram bucket that holds the q-th sample.
  def self.percentile(hist, q)
    total = hist.sum
    return nil if total.zero?

    target = q * total
    cumulative = 0
    hist.each_with_index do |c, i|
      next if c.zero?
      if cumulative + c >= target
        lo = bucket_lower(i)
        hi = bucket_upper(i)
        return lo + (hi - lo) * ((target - cumulative) / c.to_f)
      end
      cumulative += c
    end
    bucket_upper(hist.size - 1)
  end

  def self.format_ms(ms)
    return "–" if ms.nil?
    if ms >= 10_000 then "#{(ms / 1000.0).round(0)} s"
    elsif ms >= 1000 then "#{(ms / 1000.0).round(1)} s"
    elsif ms >= 10 then "#{ms.round(0)} ms"
    else "#{ms.round(1)} ms"
    end
  end

  private

  def percentiles_by_name(scope, names)
    return {} if names.empty?

    scope.where(name: names).group(:tx_type, :name).pluck(:tx_type, :name, Arel.sql("nf_hist_sum(hist), max(max)"))
         .to_h { |type, name, h, max| [[type, name], clamp(self.class.percentile(self.class.hist_array(h), 0.95), max)] }
  end

  # Histogram interpolation can overshoot the slowest sample in a bucket.
  def clamp(value, max)
    return value if value.nil? || max.nil? || max.to_f <= 0
    [value, max.to_f].min
  end

  def percentiles_from(hists, maxes)
    out = { p50: [], p95: [], p99: [] }
    bins.each do |b|
      h = hists.key?(b) ? hists[b] : nil
      { p50: 0.5, p95: 0.95, p99: 0.99 }.each do |k, q|
        out[k] << (h && clamp(self.class.percentile(h, q), maxes[b])&.round(2))
      end
    end
    out
  end
end
