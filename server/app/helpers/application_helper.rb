module ApplicationHelper
  def fmt_ms(ms)
    Metrics.format_ms(ms)
  end

  def fmt_rpm(rpm)
    return "0" if rpm.nil? || rpm.zero?
    if rpm >= 1000 then "#{number_with_delimiter(rpm.round)} rpm"
    elsif rpm >= 10 then "#{rpm.round} rpm"
    else "#{rpm.round(2)} rpm"
    end
  end

  def fmt_pct(fraction, digits = 1)
    return "–" if fraction.nil?
    "#{(fraction * 100).round(digits)}%"
  end

  def fmt_count(n)
    number_with_delimiter(n.to_i)
  end

  def fmt_num(n, digits = 1)
    return "–" if n.nil?
    n >= 100 ? number_with_delimiter(n.round) : n.round(digits).to_s
  end

  def fmt_bytes(b)
    number_to_human_size(b)
  end

  def apdex_badge(score)
    return tag.span("–", class: "badge") if score.nil?
    klass = if score >= 0.94 then "good" elsif score >= 0.85 then "ok" elsif score >= 0.7 then "warn" else "bad" end
    tag.span(format("%.2f", score), class: "badge #{klass}", title: "Apdex")
  end

  def layer_meta(key)
    Metrics::LAYERS.find { |l| l[:key] == key.to_s } || { key: key.to_s, label: key.to_s.titleize, color: "#64748b" }
  end

  def layer_dot(key)
    tag.span(class: "dot", style: "background: #{layer_meta(key)[:color]}")
  end

  # Proportional bar with its percentage beside it, used in tables.
  def share_bar(fraction, color = "var(--accent)")
    pct = (fraction.to_f * 100).clamp(0, 100)
    label = pct >= 10 ? pct.round.to_s : pct.round(1).to_s
    tag.span(class: "share") do
      tag.span(class: "share-track") { tag.span(class: "share-fill", style: "width: #{pct.round(2)}%; background: #{color}") } +
        tag.span("#{label}%", class: "share-label")
    end
  end

  # Stacked bar of per-layer time for a single row.
  def layer_bar(layers)
    total = layers.values.sum
    return "" if total <= 0
    tag.span(class: "layerbar", title: layers.select { |_, v| v.positive? }.map { |k, v| "#{layer_meta(k)[:label]}: #{fmt_ms(v)}" }.join("\n")) do
      safe_join(Metrics::LAYER_KEYS.filter_map do |k|
        v = layers[k].to_f
        next if v <= 0
        tag.span(style: "width: #{(v / total * 100).round(2)}%; background: #{layer_meta(k)[:color]}")
      end)
    end
  end

  def tx_display_name(name)
    name.to_s
  end

  def tx_link(type, name, text = nil)
    link_to(text || tx_display_name(name), app_transaction_path(current_app, type: type, name: name, **range_params), class: "mono")
  end

  def segment_link(name, text = nil, **extra)
    link_to(text || name, app_segment_path(current_app, name: name, **extra, **range_params), class: "mono")
  end

  def type_badge(type)
    tag.span(type == "job" ? "job" : "web", class: "badge type-#{type}")
  end

  def category_label(cat)
    layer_meta(cat)[:label]
  end

  # JSON for the Stimulus chart controller.
  # Durations over time get a logarithmic Y axis by default (log: false opts out).
  def chart(type:, series:, unit: "ms", stacked: false, height: 200, labels: nil, zoom: true, title: nil, x: "time", m: metrics, legend: true, log: nil)
    log = unit == "ms" && x == "time" && type != "bar" if log.nil?
    config = {
      type: type, unit: unit, stacked: stacked, zoom: zoom && x == "time", x: x, legend: legend, log: log,
      labels: labels || m.bins, step: m.step,
      markers: x == "time" ? m.deployments.map { |d| { x: d.deployed_at.to_i, label: "deploy #{d.revision.first(8)}" } } : [],
      datasets: series.map { |s| { label: s[:label], data: s[:data], color: s[:color] } }
    }
    tag.div(class: "chart-wrap", style: "height: #{height}px") do
      tag.canvas(data: { controller: "chart", chart_config_value: config.to_json, chart_title_value: title.to_s })
    end
  end

  # Layers that never reach 0.5% of the total are left out to keep legends short.
  def layer_series(layers_hash, keys = Metrics::LAYER_KEYS)
    grand = keys.sum { |k| Array(layers_hash[k]).sum(&:to_f) }
    keys.filter_map do |k|
      data = layers_hash[k]
      next if data.nil? || data.sum(&:to_f) <= grand * 0.005
      { label: layer_meta(k)[:label], data: data, color: layer_meta(k)[:color] }
    end
  end

  def sortable(label, key, default: nil)
    current = params[:sort].presence || default
    dir = current == key ? " ▾" : ""
    link_to("#{label}#{dir}", request.query_parameters.merge(sort: key), class: "sort")
  end

  def sql_snippet(sql, length = 140)
    tag.code(truncate(sql.to_s, length: length), class: "sql", title: sql)
  end

  # Where to look when an incident fires: the transaction it watches (or
  # the overview), zoomed to the incident window.
  def incident_drilldown_path(incident)
    policy = incident.alert_policy
    zoom = incident.zoom_range
    if policy.metric == "external_avg" && policy.target.present?
      app_external_host_path(incident.app, policy.target, **zoom)
    elsif policy.metric == "slow_queries"
      app_slow_queries_path(incident.app, **zoom)
    elsif policy.tx_name.present?
      app_transaction_path(incident.app, type: policy.tx_type, name: policy.tx_name, **zoom)
    else
      app_path(incident.app, type: policy.tx_type, **zoom)
    end
  end

  def time_ago(t)
    return "never" unless t
    "#{time_ago_in_words(t)} ago"
  end
end
