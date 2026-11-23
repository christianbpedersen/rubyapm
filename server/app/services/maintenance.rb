module Maintenance
  RETENTION_DAYS = Integer(ENV.fetch("RETENTION_DAYS", 8))
  COMPACT_AFTER_HOURS = Integer(ENV.fetch("COMPACT_AFTER_HOURS", 24))

  module_function

  TRACES_PER_HOUR = Integer(ENV.fetch("TRACES_PER_TX_PER_HOUR", 5))

  def run
    Compactor.run(older_than: COMPACT_AFTER_HOURS.hours.ago)
    thin_traces(COMPACT_AFTER_HOURS.hours.ago)
    prune(RETENTION_DAYS.days.ago)
  end

  # Recent traces are all kept; older ones only the slowest few per
  # transaction per hour (plus every trace that ended in an error).
  def thin_traces(before)
    deleted = ActiveRecord::Base.connection.exec_delete(<<~SQL, "thin traces", [])
      DELETE FROM traces WHERE id IN (
        SELECT id FROM (
          SELECT id, error_class, row_number() OVER (
            PARTITION BY app_id, tx_type, tx_name, date_trunc('hour', ts) ORDER BY duration DESC) AS rank
          FROM traces WHERE ts < #{ActiveRecord::Base.connection.quote(before)}
        ) ranked
        WHERE rank > #{TRACES_PER_HOUR} AND error_class IS NULL
      )
    SQL
    Rails.logger.info("[maintenance] traces: thinned #{deleted}") if deleted.positive?
    deleted
  end

  def prune(cutoff)
    [TxRollup, AppRollup, RuntimeRollup, SegmentRollup, SqlRollup, ErrorRollup, Trace, SlowQuery].each do |model|
      n = 0
      loop do
        deleted = model.where(id: model.where(ts: ...cutoff).limit(50_000).select(:id)).delete_all
        n += deleted
        break if deleted.zero?
      end
      Rails.logger.info("[maintenance] #{model.table_name}: pruned #{n}") if n.positive?
    end
    SqlStatement.where(last_seen_at: ...cutoff).delete_all
    IngestedBucket.where(received_at: ...1.day.ago).in_batches(of: 50_000).delete_all
    Host.where(last_seen_at: ...cutoff).delete_all
  end
end
