# A signed-in browser. The signed cookie holds only this row's id, so
# deleting the row signs that browser out.
class Session < ApplicationRecord
  IDLE_TIMEOUT = 30.days

  belongs_to :user

  scope :active, -> { where(last_seen_at: IDLE_TIMEOUT.ago..) }

  def expired? = last_seen_at < IDLE_TIMEOUT.ago

  # Writes at most once a minute, not on every request.
  def touch_seen!
    update_column(:last_seen_at, Time.current) if last_seen_at < 1.minute.ago
  end
end
