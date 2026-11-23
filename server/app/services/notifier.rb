require "net/http"

# Posts incident open/resolve events to the policy's webhook. The payload's
# `text` field makes it work as a Slack (or Mattermost/Discord-compatible)
# incoming webhook; the other fields are for custom receivers.
class Notifier
  def self.base_url
    ENV.fetch("RUBY_APM_BASE_URL", "http://localhost:4400")
  end

  def self.deliver(incident, event)
    new(incident, event).deliver
  end

  def initialize(incident, event)
    @incident = incident
    @event = event
    @policy = incident.alert_policy
  end

  def payload
    app = @incident.app
    value = @event == :opened ? @incident.opened_value : @incident.last_value
    verb = @event == :opened ? "🔴 Opened" : "✅ Resolved"
    {
      text: "#{verb}: #{app.name} · #{@policy.name} — #{@policy.metric_label} is #{@policy.format_value(value)} " \
            "(threshold #{@policy.comparison} #{@policy.format_value(@incident.threshold)}). #{url}",
      event: @event.to_s, app: app.name, policy: @policy.name, metric: @policy.metric,
      value: value, threshold: @incident.threshold, comparison: @policy.comparison,
      transaction: @policy.tx_name, opened_at: @incident.opened_at.iso8601, closed_at: @incident.closed_at&.iso8601, url: url
    }
  end

  # RUBY_APM_BASE_URL may carry a path prefix (https://host/apm).
  def url
    base = URI(self.class.base_url)
    Rails.application.routes.url_helpers.app_alerts_url(
      @incident.app, incident: @incident.id, protocol: base.scheme, host: base.host,
      port: (base.port unless base.port == base.default_port), script_name: base.path.chomp("/")
    )
  end

  def deliver
    return if @policy.webhook_url.blank?

    uri = URI.parse(@policy.webhook_url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == "https"
    http.open_timeout = 3
    http.read_timeout = 5
    response = http.post(uri.request_uri, payload.to_json, "Content-Type" => "application/json", "User-Agent" => "RubyAPM")
    @incident.update_columns(notify_error: response.is_a?(Net::HTTPSuccess) ? nil : "HTTP #{response.code}")
  rescue StandardError => e
    @incident.update_columns(notify_error: "#{e.class}: #{e.message}".first(250))
  end
end
