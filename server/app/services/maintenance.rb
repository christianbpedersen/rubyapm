module Maintenance
  RETENTION_DAYS = Integer(ENV.fetch("RETENTION_DAYS", 8))
  COMPACT_AFTER_HOURS = Integer(ENV.fetch("COMPACT_AFTER_HOURS", 24))

  module_function

  TRACES_PER_HOUR = Integer(ENV.fetch("TRACES_PER_TX_PER_HOUR", 5))

  def run
    Compactor.run(older_than: COMPACT_AFTER_HOURS.hours.ago)
    thin_traces(COMPACT_AFTER_HOURS.hours.ago)
    prune(RETENTION_DAYS.days.ago)
    prune_auth
  end

  # Expired tokens, used or stale authorization codes, idle sessions, and
  # OAuth clients nobody ever approved.
  def prune_auth
    ApiToken.where(expires_at: ...Time.current).delete_all
    OauthCode.where(expires_at: ...1.hour.ago).delete_all
    Session.where(last_seen_at: ...Session::IDLE_TIMEOUT.ago).delete_all
    OauthClient.where(created_at: ...1.day.ago).where.missing(:api_tokens).where.not(id: OauthCode.select(:oauth_client_id)).delete_all
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
    # No primary key (only a unique index), so no in_batches; a day of
    # bucket IDs is small enough for one statement.
    IngestedBucket.where(received_at: ...1.day.ago).delete_all
    Host.where(last_seen_at: ...cutoff).delete_all
  end
end
