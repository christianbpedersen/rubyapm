class AlertPolicy < ApplicationRecord
  METRICS = {
    "apdex" => { label: "Apdex", unit: "apdex", default: ["below", 0.85] },
    "error_rate" => { label: "Error rate (%)", unit: "%", default: ["above", 5] },
    "p95" => { label: "p95 response time (ms)", unit: "ms", default: ["above", 2000] },
    "avg" => { label: "Average response time (ms)", unit: "ms", default: ["above", 1000] },
    "throughput" => { label: "Throughput (rpm)", unit: "rpm", default: ["below", 1] },
    "external_avg" => { label: "External API avg (ms)", unit: "ms", default: ["above", 1000] },
    "slow_queries" => { label: "Slow queries per minute", unit: "rpm", default: ["above", 10] }
  }.freeze

  belongs_to :app
  has_many :incidents, dependent: :delete_all

  validates :name, presence: true
  validates :metric, inclusion: { in: METRICS.keys }
  validates :comparison, inclusion: { in: %w[above below] }
  validates :tx_type, inclusion: { in: %w[web job] }
  validates :threshold, numericality: true
  validates :window_minutes, numericality: { only_integer: true, greater_than_or_equal_to: 1, less_than_or_equal_to: 60 }
  validates :min_samples, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :webhook_url_is_http

  scope :enabled, -> { where(enabled: true) }

  def self.defaults_for(app)
    [
      { name: "Web Apdex low", metric: "apdex", comparison: "below", threshold: 0.85 },
      { name: "Web error rate high", metric: "error_rate", comparison: "above", threshold: 5 },
      { name: "Web p95 slow", metric: "p95", comparison: "above", threshold: 2000 }
    ].map { |attrs| app.alert_policies.new(attrs) }
  end

  def open_incident
    incidents.find_by(closed_at: nil)
  end

  def breached?(value)
    return false if value.nil?
    comparison == "above" ? value > threshold : value < threshold
  end

  def unit = METRICS.dig(metric, :unit)
  def metric_label = METRICS.dig(metric, :label)

  def condition_text
    scope = tx_name.presence || (tx_type == "job" ? "all jobs" : "all web requests")
    scope = "#{target} (#{scope})" if metric == "external_avg" && target.present?
    "#{metric_label} #{comparison} #{format_value(threshold)} over #{window_minutes} min · #{scope}"
  end

  def format_value(v)
    return "–" if v.nil?
    case unit
    when "apdex" then format("%.2f", v)
    when "%" then "#{v.round(2)}%"
    when "ms" then Metrics.format_ms(v)
    else "#{v.round(2)} rpm"
    end
  end

  private

  def webhook_url_is_http
    return if webhook_url.blank?
    uri = URI.parse(webhook_url)
    errors.add(:webhook_url, "must be an http(s) URL") unless uri.is_a?(URI::HTTP) && uri.host.present?
  rescue URI::InvalidURIError
    errors.add(:webhook_url, "is not a valid URL")
  end
end
