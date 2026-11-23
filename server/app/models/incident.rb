class Incident < ApplicationRecord
  belongs_to :app
  belongs_to :alert_policy

  scope :open, -> { where(closed_at: nil) }

  def open? = closed_at.nil?

  def duration
    (closed_at || Time.current) - opened_at
  end

  # Window to show when drilling into the incident: a little context either side.
  def zoom_range
    pad = [alert_policy.window_minutes.minutes, 5.minutes].max
    { from: (opened_at - alert_policy.window_minutes.minutes - pad).to_i, to: ((closed_at || Time.current) + pad).to_i }
  end
end
