require "test_helper"

class MaintenanceTest < ActiveSupport::TestCase
  test "old traces are thinned to the slowest per hour, errors kept, recent untouched" do
    app = App.create!(name: "Traces", api_key: "nf_traces")
    hour = 3.days.ago.beginning_of_hour
    base = { app_id: app.id, tx_type: "web", tx_name: "A#b", tree: [], breakdown: {}, attrs: {} }
    10.times { |i| Trace.create!(base.merge(ts: hour + i.minutes, duration: 100 + i)) }
    Trace.create!(base.merge(ts: hour + 30.minutes, duration: 1, error_class: "Boom"))
    3.times { |i| Trace.create!(base.merge(ts: 10.minutes.ago, duration: i)) }

    Maintenance.thin_traces(24.hours.ago)

    old = Trace.where(app_id: app.id, ts: hour..hour + 1.hour)
    assert_equal [109, 108, 107, 106, 105, 1], old.order(duration: :desc).pluck(:duration).map(&:to_i)
    assert_equal 3, Trace.where(app_id: app.id, ts: 1.hour.ago..).count
  end

  test "a full maintenance run prunes buckets, hosts and expired auth rows" do
    app = App.create!(name: "Prune", api_key: "nf_prune")
    IngestedBucket.create!(app_id: app.id, bucket_id: SecureRandom.uuid, received_at: 2.days.ago)
    IngestedBucket.create!(app_id: app.id, bucket_id: SecureRandom.uuid, received_at: 1.hour.ago)
    user = User.create!(email: "p@example.com", role: "member")
    ApiToken.issue!(kind: "access", user: user, expires_at: 1.minute.ago)
    live = ApiToken.issue!(kind: "personal", user: user, name: "keep")
    user.sessions.create!(last_seen_at: 40.days.ago)

    Maintenance.run

    assert_equal 1, IngestedBucket.where(app_id: app.id).count
    assert_equal [live.id], ApiToken.pluck(:id)
    assert_equal 0, user.sessions.count
  end
end
