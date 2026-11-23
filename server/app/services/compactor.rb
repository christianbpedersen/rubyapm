# Rewrites minute rollups older than `older_than` into one row per hour, so
# multi-day charts read 60× fewer rows. Charts for windows longer than 24h
# already use bins of an hour or more, so no resolution is lost where it is
# visible. Idempotent: rows already on the hour are folded into themselves.
class Compactor
  CATEGORIES = Ingestor::CATEGORIES

  TABLES = {
    "tx_rollups" => {
      key: %w[app_id tx_type name],
      sums: %w[count total sumsq errors_count apdex_s apdex_t apdex_f queue_total] + CATEGORIES.map { |c| "t_#{c}" },
      mins: %w[min], maxes: %w[max], hists: %w[hist]
    },
    "app_rollups" => {
      key: %w[app_id tx_type],
      sums: %w[count total sumsq errors_count apdex_s apdex_t apdex_f queue_total] + CATEGORIES.map { |c| "t_#{c}" },
      mins: %w[min], maxes: %w[max], hists: %w[hist]
    },
    "segment_rollups" => {
      key: %w[app_id tx_type tx_name name category], sums: %w[count txns total excl], mins: %w[min], maxes: %w[max], hists: []
    },
    "sql_rollups" => {
      key: %w[app_id tx_type tx_name key], sums: %w[count txns total slow_count], mins: %w[min], maxes: %w[max max_per_tx], hists: %w[hist]
    },
    "error_rollups" => { key: %w[app_id fingerprint tx_type tx_name], sums: %w[count], mins: [], maxes: [], hists: [] }
  }.freeze

  # Data before this time may only exist at hourly resolution.
  def self.horizon
    Integer(ENV.fetch("COMPACT_AFTER_HOURS", 24)).hours.ago.beginning_of_hour
  end

  def self.run(older_than: 24.hours.ago, logger: Rails.logger)
    cutoff = older_than.beginning_of_hour
    TABLES.each do |table, spec|
      moved = compact(table, spec, cutoff)
      logger&.info("[compactor] #{table}: folded #{moved} minute rows into hourly rows before #{cutoff}")
    end
  end

  # Only hours that still contain non-hour-aligned rows are touched.
  def self.compact(table, spec, cutoff)
    conn = ActiveRecord::Base.connection
    key = spec[:key]
    cols = key + ["ts"] + spec[:sums] + spec[:mins] + spec[:maxes] + spec[:hists]
    aggs = spec[:sums].map { |c| "sum(#{c}) AS #{c}" } + spec[:mins].map { |c| "min(#{c}) AS #{c}" } +
           spec[:maxes].map { |c| "max(#{c}) AS #{c}" } + spec[:hists].map { |c| "nf_hist_sum(#{c}) AS #{c}" }
    stale = "ts < #{conn.quote(cutoff)} AND ts <> date_trunc('hour', ts)"
    hours = "date_trunc('hour', ts) IN (SELECT DISTINCT date_trunc('hour', ts) FROM #{table} WHERE #{stale})"

    ActiveRecord::Base.transaction do
      moved = conn.select_value("SELECT count(*) FROM #{table} WHERE #{stale}").to_i
      return 0 if moved.zero?

      conn.execute("DROP TABLE IF EXISTS nf_compact")
      conn.execute(<<~SQL)
        CREATE TEMP TABLE nf_compact AS
        SELECT #{key.join(', ')}, date_trunc('hour', ts) AS ts, #{aggs.join(', ')}
        FROM #{table} WHERE #{hours}
        GROUP BY #{key.join(', ')}, date_trunc('hour', ts)
      SQL
      conn.execute("DELETE FROM #{table} WHERE #{hours}")
      conn.execute("INSERT INTO #{table} (#{cols.join(', ')}) SELECT * FROM nf_compact")
      conn.execute("DROP TABLE nf_compact")
      moved
    end
  end
end
