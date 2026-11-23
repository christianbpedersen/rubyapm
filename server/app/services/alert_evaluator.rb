# Checks every enabled policy against its last `window_minutes` of complete
# minutes, opens an incident when the condition is breached and closes it
# once the metric is back on the right side of the threshold.
class AlertEvaluator
  INGEST_LAG = Metrics::INGEST_LAG

  def self.run(now: Time.current)
    AlertPolicy.enabled.includes(:app).find_each { |policy| new(policy, now: now).evaluate }
  end

  attr_reader :policy, :value, :samples

  def initialize(policy, now: Time.current)
    @policy = policy
    @now = now
  end

  def evaluate
    @value, @samples = measure
    policy.update_columns(last_value: @value, last_evaluated_at: @now)
    incident = policy.open_incident
    measurable = @value && @samples >= policy.min_samples

    if measurable && policy.breached?(@value)
      if incident
        peak = worst(incident.peak_value, @value)
        incident.update!(last_value: @value, peak_value: peak)
      else
        open_incident
      end
    elsif incident && (measurable || @samples.zero?)
      incident.update!(closed_at: @now, last_value: @value)
      Notifier.deliver(incident, :resolved)
    end
  end

  # Complete minutes only: [first, last] inclusive.
  def window
    last = Time.at(((@now.to_i - INGEST_LAG) / 60 - 1) * 60).utc
    [last - (policy.window_minutes - 1).minutes, last]
  end

  def measure
    first, last = window
    case policy.metric
    when "external_avg" then external_avg(first, last)
    when "slow_queries"
      slow = SqlRollup.where(app_id: policy.app_id, ts: first..last).then { |s| tx_filter(s, :tx_name) }.sum(:slow_count)
      [slow.to_f / policy.window_minutes, Float::INFINITY]
    else tx_metric(first, last)
    end
  end

  private

  def open_incident
    incident = policy.incidents.create!(app_id: policy.app_id, opened_at: @now, threshold: policy.threshold,
                                        opened_value: @value, peak_value: @value, last_value: @value)
    Notifier.deliver(incident, :opened)
  rescue ActiveRecord::RecordNotUnique
    nil # another evaluator opened it first
  end

  def worst(a, b)
    return b if a.nil?
    policy.comparison == "above" ? [a, b].max : [a, b].min
  end

  def tx_filter(scope, column)
    scope = scope.where(tx_type: policy.tx_type)
    policy.tx_name.present? ? scope.where(column => policy.tx_name) : scope
  end

  def tx_metric(first, last)
    scope = if policy.tx_name.present?
              TxRollup.where(app_id: policy.app_id, tx_type: policy.tx_type, name: policy.tx_name, ts: first..last)
            else
              AppRollup.where(app_id: policy.app_id, tx_type: policy.tx_type, ts: first..last)
            end
    rows = scope.pluck(:count, :total, :errors_count, :apdex_s, :apdex_t, :apdex_f, :max, :hist)
    count = rows.sum { |r| r[0].to_i }
    return [policy.metric == "throughput" ? 0.0 : nil, policy.metric == "throughput" ? Float::INFINITY : 0] if count.zero?

    value = case policy.metric
            when "throughput" then count.to_f / policy.window_minutes
            when "avg" then rows.sum { |r| r[1].to_f } / count
            when "error_rate" then rows.sum { |r| r[2].to_i } * 100.0 / count
            when "apdex"
              s = rows.sum { |r| r[3].to_i }
              t = rows.sum { |r| r[4].to_i }
              f = rows.sum { |r| r[5].to_i }
              (s + t / 2.0) / [s + t + f, 1].max
            when "p95"
              hist = rows.map { |r| Metrics.hist_array(r[7]) }.transpose.map(&:sum)
              [Metrics.percentile(hist, 0.95), rows.filter_map { |r| r[6] }.max].compact.min
            end
    [value, policy.metric == "throughput" ? Float::INFINITY : count]
  end

  def external_avg(first, last)
    scope = SegmentRollup.where(app_id: policy.app_id, category: "external", ts: first..last)
    scope = tx_filter(scope, :tx_name)
    scope = scope.where("name LIKE ?", "External/#{ActiveRecord::Base.sanitize_sql_like(policy.target)}/%") if policy.target.present?
    count, total = scope.pick(Arel.sql("sum(count), sum(total)"))
    count = count.to_i
    [count.positive? ? total.to_f / count : nil, count]
  end
end
