require "test_helper"

class CompactorTest < ActiveSupport::TestCase
  test "folds old minute rows into hourly rows preserving totals and histograms" do
    app = App.create!(name: "Old", api_key: "nf_old")
    hour = 3.days.ago.beginning_of_hour
    hist_a = Array.new(56, 0).tap { |h| h[10] = 2 }
    hist_b = Array.new(56, 0).tap { |h| h[10] = 1; h[20] = 4 }
    [[hour + 1.minute, 2, 10.0, 5.0, hist_a], [hour + 30.minutes, 5, 50.0, 30.0, hist_b]].each do |ts, count, total, max, hist|
      TxRollup.create!(app_id: app.id, ts: ts, tx_type: "web", name: "A#b", count: count, total: total, min: 1, max: max,
                       sumsq: 1, hist: hist, t_database: total / 2)
      SegmentRollup.create!(app_id: app.id, ts: ts, tx_type: "web", tx_name: "A#b", name: "Database/x/select",
                            category: "database", count: count, txns: count, total: total, excl: total, min: 1, max: max)
    end
    recent = TxRollup.create!(app_id: app.id, ts: 1.hour.ago, tx_type: "web", name: "A#b", count: 1, total: 1, hist: [])

    Compactor.run(older_than: 24.hours.ago, logger: nil)

    rows = TxRollup.where(app_id: app.id, ts: hour)
    assert_equal 1, rows.count
    row = rows.first
    assert_equal 7, row.count
    assert_equal 60.0, row.total
    assert_equal 30.0, row.max
    assert_equal 30.0, row.t_database
    assert_equal 3, row.hist[10]
    assert_equal 4, row.hist[20]
    assert_equal 1, SegmentRollup.where(app_id: app.id).count
    assert TxRollup.exists?(recent.id), "recent rows are untouched"

    Compactor.run(older_than: 24.hours.ago, logger: nil) # idempotent
    assert_equal 7, TxRollup.where(app_id: app.id, ts: hour).sum(:count)
  end
end
